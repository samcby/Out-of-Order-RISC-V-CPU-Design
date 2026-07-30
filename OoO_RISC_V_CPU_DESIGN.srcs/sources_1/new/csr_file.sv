// Machine-mode CSR storage and trap-return state machine.
//
// Implements the subset needed by this core: mstatus, mie, mtvec, mepc,
// mcause, mtval, mip, sixteen PMP entries, and a constant mhartid. CSR reads are combinational;
// CSRRW/CSRRS/CSRRC writes occur on the clock edge. Trap entry records fault
// context and updates MIE/MPIE/MPP, while MRET restores interrupt and
// privilege state. The supported privilege modes are U and M.
//
// Hardware interrupt inputs continuously drive the relevant mip bits. The FP
// path reports fp_state_dirty at commit so mstatus.FS/SD become architecturally
// dirty only for retired floating-point state changes.
module csr_file #(
    parameter bit RESET_FS_INITIAL = 1'b0
)(
    input  logic                          clk,
    input  logic                          rst_n,

    input  logic                          csr_en,
    input  logic [1:0]                    csr_op,
    input  logic [11:0]                   csr_addr,
    input  logic [defines_pkg::WIDTH-1:0] csr_wdata,

    input  logic                          trap_en,
    input  logic [defines_pkg::WIDTH-1:0] trap_mepc,
    input  logic [defines_pkg::WIDTH-1:0] trap_mcause,
    input  logic [defines_pkg::WIDTH-1:0] trap_mtval,
    input  logic                          mret_en,
    input  logic                          software_irq_pending,
    input  logic                          timer_irq_pending,
    input  logic                          external_irq_pending,
    input  logic                          fp_state_dirty,

    output logic [defines_pkg::WIDTH-1:0] csr_rdata,
    output logic [defines_pkg::WIDTH-1:0] mstatus_value,
    output logic [defines_pkg::WIDTH-1:0] mie_value,
    output logic [defines_pkg::WIDTH-1:0] mtvec_value,
    output logic [defines_pkg::WIDTH-1:0] mepc_value,
    output logic [1:0]                    current_privilege,
    output logic [defines_pkg::WIDTH-1:0] pmpcfg0_value,
    output logic [defines_pkg::WIDTH-1:0] pmpaddr0_value,
    output logic [defines_pkg::PMP_ENTRY_COUNT*8-1:0] pmpcfg_values,
    output logic [defines_pkg::PMP_ENTRY_COUNT*defines_pkg::WIDTH-1:0]
                                             pmpaddr_values
);
    import defines_pkg::*;

    localparam int MSTATUS_MIE_BIT      = 3;
    localparam int MSTATUS_MPIE_BIT     = 7;
    localparam int MSTATUS_MPP_LSB      = 11;
    localparam int MSTATUS_MPP_MSB      = 12;
    localparam int MSTATUS_FS_LSB       = 13;
    localparam int MSTATUS_FS_MSB       = 14;
    localparam int MSTATUS_SD_BIT       = 31;
    localparam logic [1:0] FS_OFF        = 2'b00;
    localparam logic [1:0] FS_INITIAL    = 2'b01;
    localparam logic [1:0] FS_DIRTY      = 2'b11;

    logic [WIDTH-1:0] mstatus_q;
    logic [WIDTH-1:0] mie_q;
    logic [WIDTH-1:0] mtvec_q;
    logic [WIDTH-1:0] mepc_q;
    logic [WIDTH-1:0] mcause_q;
    logic [WIDTH-1:0] mtval_q;
    logic [WIDTH-1:0] mip_q;
    logic [WIDTH-1:0] pmpcfg_q [0:PMP_CFG_WORD_COUNT-1];
    logic [WIDTH-1:0] pmpaddr_q [0:PMP_ENTRY_COUNT-1];
    wire [WIDTH-1:0] pmpcfg0_q = pmpcfg_q[0];
    wire [WIDTH-1:0] pmpaddr0_q = pmpaddr_q[0];
    logic [1:0] current_priv_q;
    logic [WIDTH-1:0] write_value;
    logic [WIDTH-1:0] mstatus_visible;
    integer pmp_pack_index;
    integer pmp_reset_index;
    integer pmp_cfg_byte_index;

    function automatic logic [7:0] pmpcfg_byte_warl(
        input logic [7:0] requested
    );
        logic [7:0] cfg;
    begin
        cfg = '0;
        cfg[7] = requested[7];
        cfg[4:3] = requested[4:3];
        cfg[2] = requested[2];
        cfg[1] = requested[1] && requested[0];
        cfg[0] = requested[0];
        pmpcfg_byte_warl = cfg;
    end
    endfunction

    function automatic logic pmpaddr_write_locked(
        input integer entry
    );
        logic [7:0] own_cfg;
        logic [7:0] next_cfg;
    begin
        own_cfg = pmpcfg_q[entry / 4][(entry % 4)*8 +: 8];
        next_cfg = '0;
        if (entry < (PMP_ENTRY_COUNT-1)) begin
            next_cfg = pmpcfg_q[(entry+1) / 4][((entry+1) % 4)*8 +: 8];
        end
        pmpaddr_write_locked =
            own_cfg[7] ||
            ((entry < (PMP_ENTRY_COUNT-1)) &&
             next_cfg[7] &&
             (next_cfg[4:3] == PMP_A_TOR));
    end
    endfunction

    // SD is a derived architectural summary bit: expose it whenever the FP
    // state field is Dirty even if software attempted to write an inconsistent
    // stored SD value.
    always_comb begin
        mstatus_visible = mstatus_q;
        mstatus_visible[MSTATUS_SD_BIT] =
            (mstatus_q[MSTATUS_FS_MSB:MSTATUS_FS_LSB] == FS_DIRTY);
    end

    assign mstatus_value = mstatus_visible;
    assign mie_value     = mie_q;
    assign mtvec_value   = mtvec_q;
    assign mepc_value    = mepc_q;
    assign current_privilege = current_priv_q;
    assign pmpcfg0_value = pmpcfg_q[0];
    assign pmpaddr0_value = pmpaddr_q[0];

    always_comb begin
        pmpcfg_values = '0;
        pmpaddr_values = '0;
        for (pmp_pack_index = 0;
             pmp_pack_index < PMP_CFG_WORD_COUNT;
             pmp_pack_index = pmp_pack_index + 1) begin
            pmpcfg_values[pmp_pack_index*WIDTH +: WIDTH] =
                pmpcfg_q[pmp_pack_index];
        end
        for (pmp_pack_index = 0;
             pmp_pack_index < PMP_ENTRY_COUNT;
             pmp_pack_index = pmp_pack_index + 1) begin
            pmpaddr_values[pmp_pack_index*WIDTH +: WIDTH] =
                pmpaddr_q[pmp_pack_index];
        end
    end

    // CSR reads are combinational so a CSR instruction can write its old value
    // to the integer PRF on the same execution path that updates the CSR state.
    always_comb begin
        unique case (csr_addr)
            CSR_MSTATUS: csr_rdata = mstatus_visible;
            CSR_MIE:     csr_rdata = mie_q;
            CSR_MTVEC:   csr_rdata = mtvec_q;
            CSR_MEPC:    csr_rdata = mepc_q;
            CSR_MCAUSE:  csr_rdata = mcause_q;
            CSR_MTVAL:   csr_rdata = mtval_q;
            CSR_MIP:     csr_rdata = mip_q;
            CSR_MHARTID: csr_rdata = '0;
            default: begin
                if ((csr_addr >= CSR_PMPCFG0) &&
                    (csr_addr <= CSR_PMPCFG3)) begin
                    csr_rdata = pmpcfg_q[csr_addr - CSR_PMPCFG0];
                end else if ((csr_addr >= CSR_PMPADDR0) &&
                             (csr_addr <= CSR_PMPADDR15)) begin
                    csr_rdata = pmpaddr_q[csr_addr - CSR_PMPADDR0];
                end else begin
                    csr_rdata = '0;
                end
            end
        endcase
    end

    // Compute the requested read-modify-write value before the sequential block;
    // CSRRS/CSRRC source-zero suppression is performed by execution_stage.
    always_comb begin
        unique case (csr_op)
            CSR_RW:  write_value = csr_wdata;
            CSR_RS:  write_value = csr_rdata | csr_wdata;
            CSR_RC:  write_value = csr_rdata & ~csr_wdata;
            default: write_value = csr_rdata;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_q <= '0;
            mstatus_q[MSTATUS_FS_MSB:MSTATUS_FS_LSB] <=
                RESET_FS_INITIAL ? FS_INITIAL : FS_OFF;
            mie_q     <= '0;
            mtvec_q   <= '0;
            mepc_q    <= '0;
            mcause_q  <= '0;
            mtval_q   <= '0;
            mip_q     <= '0;
            for (pmp_reset_index = 0;
                 pmp_reset_index < PMP_CFG_WORD_COUNT;
                 pmp_reset_index = pmp_reset_index + 1) begin
                pmpcfg_q[pmp_reset_index] <= '0;
            end
            for (pmp_reset_index = 0;
                 pmp_reset_index < PMP_ENTRY_COUNT;
                 pmp_reset_index = pmp_reset_index + 1) begin
                pmpaddr_q[pmp_reset_index] <= '0;
            end
            // Entry zero defaults to an unlocked full-address-space RWX TOR
            // region so existing bare-metal tests remain compatible.
            pmpcfg_q[0] <= 32'h0000000f;
            pmpaddr_q[0] <= 32'h40000000;
            current_priv_q <= PRV_M;
        end else begin
            if (csr_en) begin
                unique case (csr_addr)
                    CSR_MSTATUS: begin
                        mstatus_q <= write_value;
                        // Only U and M are implemented. Unsupported MPP
                        // encodings use the legal WARL fallback U.
                        mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <=
                            (write_value[MSTATUS_MPP_MSB:
                                         MSTATUS_MPP_LSB] == PRV_M) ?
                            PRV_M : PRV_U;
                        mstatus_q[MSTATUS_SD_BIT] <=
                            (write_value[MSTATUS_FS_MSB:MSTATUS_FS_LSB] ==
                             FS_DIRTY);
                    end
                    CSR_MIE:     mie_q     <= write_value;
                    CSR_MTVEC:   mtvec_q   <= write_value;
                    CSR_MEPC:    mepc_q    <= write_value;
                    CSR_MCAUSE:  mcause_q  <= write_value;
                    CSR_MTVAL:   mtval_q   <= write_value;
                    CSR_MIP:     mip_q     <= write_value;
                    default: begin
                        if ((csr_addr >= CSR_PMPCFG0) &&
                            (csr_addr <= CSR_PMPCFG3)) begin
                            for (pmp_cfg_byte_index = 0;
                                 pmp_cfg_byte_index < 4;
                                 pmp_cfg_byte_index =
                                     pmp_cfg_byte_index + 1) begin
                                if (!pmpcfg_q[csr_addr - CSR_PMPCFG0]
                                              [pmp_cfg_byte_index*8+7]) begin
                                    pmpcfg_q[csr_addr - CSR_PMPCFG0]
                                            [pmp_cfg_byte_index*8 +: 8] <=
                                        pmpcfg_byte_warl(
                                            write_value[
                                                pmp_cfg_byte_index*8 +: 8]);
                                end
                            end
                        end else if ((csr_addr >= CSR_PMPADDR0) &&
                                     (csr_addr <= CSR_PMPADDR15)) begin
                            if (!pmpaddr_write_locked(
                                    csr_addr - CSR_PMPADDR0)) begin
                                pmpaddr_q[csr_addr - CSR_PMPADDR0] <=
                                    write_value;
                            end
                        end
                    end
                endcase
            end

            // Trap entry has later assignments than an ordinary CSR write and
            // therefore wins for the architecturally sensitive status fields.
            if (trap_en) begin
                mepc_q   <= trap_mepc;
                mcause_q <= trap_mcause;
                mtval_q  <= trap_mtval;
                mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
                mstatus_q[MSTATUS_MIE_BIT]  <= 1'b0;
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <=
                    current_priv_q;
                current_priv_q <= PRV_M;
            end

            if (mret_en) begin
                mstatus_q[MSTATUS_MIE_BIT]  <= mstatus_q[MSTATUS_MPIE_BIT];
                mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
                current_priv_q <=
                    (mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] == PRV_M) ?
                    PRV_M : PRV_U;
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRV_U;
            end

            if (fp_state_dirty &&
                (mstatus_q[MSTATUS_FS_MSB:MSTATUS_FS_LSB] != FS_OFF)) begin
                mstatus_q[MSTATUS_FS_MSB:MSTATUS_FS_LSB] <= FS_DIRTY;
                mstatus_q[MSTATUS_SD_BIT] <= 1'b1;
            end

            mip_q[3]  <= software_irq_pending;
            mip_q[7]  <= timer_irq_pending;
            mip_q[11] <= external_irq_pending;
        end
    end

endmodule
