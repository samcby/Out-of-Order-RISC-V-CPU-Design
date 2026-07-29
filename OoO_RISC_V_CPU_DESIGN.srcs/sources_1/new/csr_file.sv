// Machine-mode CSR storage and trap-return state machine.
//
// Implements the subset needed by this core: mstatus, mie, mtvec, mepc,
// mcause, mtval, mip, and a constant mhartid. CSR reads are combinational;
// CSRRW/CSRRS/CSRRC writes occur on the clock edge. Trap entry records fault
// context and updates MIE/MPIE/MPP, while MRET restores interrupt state.
//
// Hardware interrupt inputs continuously drive the relevant mip bits. The FP
// path reports fp_state_dirty at commit so mstatus.FS/SD become architecturally
// dirty only for retired floating-point state changes.
module csr_file (
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
    output logic [defines_pkg::WIDTH-1:0] mepc_value
);
    import defines_pkg::*;

    localparam int MSTATUS_MIE_BIT      = 3;
    localparam int MSTATUS_MPIE_BIT     = 7;
    localparam int MSTATUS_MPP_LSB      = 11;
    localparam int MSTATUS_MPP_MSB      = 12;
    localparam int MSTATUS_FS_LSB       = 13;
    localparam int MSTATUS_FS_MSB       = 14;
    localparam int MSTATUS_SD_BIT       = 31;
    localparam logic [1:0] PRV_M         = 2'b11;
    localparam logic [1:0] FS_OFF        = 2'b00;
    localparam logic [1:0] FS_DIRTY      = 2'b11;

    logic [WIDTH-1:0] mstatus_q;
    logic [WIDTH-1:0] mie_q;
    logic [WIDTH-1:0] mtvec_q;
    logic [WIDTH-1:0] mepc_q;
    logic [WIDTH-1:0] mcause_q;
    logic [WIDTH-1:0] mtval_q;
    logic [WIDTH-1:0] mip_q;
    logic [WIDTH-1:0] write_value;
    logic [WIDTH-1:0] mstatus_visible;

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
            default:     csr_rdata = '0;
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
            mie_q     <= '0;
            mtvec_q   <= '0;
            mepc_q    <= '0;
            mcause_q  <= '0;
            mtval_q   <= '0;
            mip_q     <= '0;
        end else begin
            if (csr_en) begin
                unique case (csr_addr)
                    CSR_MSTATUS: begin
                        mstatus_q <= write_value;
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
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRV_M;
            end

            if (mret_en) begin
                mstatus_q[MSTATUS_MIE_BIT]  <= mstatus_q[MSTATUS_MPIE_BIT];
                mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= 2'b00;
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
