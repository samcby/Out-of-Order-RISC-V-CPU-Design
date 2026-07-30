// Primary integration top for the current packetized two-wide OoO backend.
//
// This is the architectural wiring diagram expressed as RTL: it connects the
// predicted frontend, decode/rename skid stages, packet splitter, dispatch and
// issue queues, global integer/FP PRFs, execution resources, ROB, and commit
// side effects. Instructions may execute and write physical registers out of
// order, but commit signals derived from the ROB head make Store visibility,
// physical-register reclamation, FP flags, and retire traces strictly ordered.
//
// Recovery signals originate in execution and flow backward to Fetch, Rename,
// queues, and storage structures. `flush_exe` clears front-end transport state;
// checkpoint restore recovers RAT/free-pool state; selective squash removes only
// younger speculative work. The legacy scalar-oriented integration remains in
// top.sv.
module top_packet_backend #(
    parameter bit ENABLE_2WIDE = 1'b1,
    parameter logic [31:0] IMEM_BASE_ADDR = 32'h00000000,
    parameter int IMEM_DEPTH_BYTES = 4096,
    parameter logic [31:0] DMEM_BASE_ADDR = 32'h00010000,
    parameter bit ENABLE_ACCESS_FAULTS = 1'b1,
    parameter bit ENABLE_PMP = 1'b1,
    parameter int DMEM_WORDS = 256,
    parameter bit RESET_FS_INITIAL = 1'b0
)(
    input  logic clk,
    input  logic rst_n,
    input  logic software_irq,
    input  logic timer_irq,
    input  logic external_irq,

    input  logic        load_en,
    input  logic [31:0] load_addr,
    input  logic [7:0]  load_instr_byte,

    output logic        issue_valid,
    output logic [1:0]  issue_fu_type,
    output logic [31:0] issue_pc,
    output logic [31:0] issue_imm,

    output logic        rob_head_valid,
    output logic        rob_head_complete,
    output logic [4:0]  rob_head_rd,

    output defines_pkg::retire_trace_t retire_trace0,
    output defines_pkg::retire_trace_t retire_trace1
);

    import defines_pkg::*;

    pip_if #(fetch_decode_packet_t) pipe_fd_pkt   (.clk(clk), .rst_n(rst_n));
    pip_if #(fetch_decode_packet_t) pipe_fd_pkt_s (.clk(clk), .rst_n(rst_n));

    pip_if #(decode_rat_packet_t) pipe_dr_pkt   (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_packet_t) pipe_dr_pkt_s (.clk(clk), .rst_n(rst_n));

    pip_if #(rat_dis_packet_t) pipe_rd_pkt   (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t) pipe_rd_pkt_s (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t) pipe_rd_pkt_d (.clk(clk), .rst_n(rst_n));

    pip_if #(issue_exe_t) issue_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue1_if (.clk(clk), .rst_n(rst_n));

    logic lane0_src1_ready;
    logic lane0_src2_ready;
    logic lane0_src3_ready;
    logic lane1_src1_ready;
    logic lane1_src2_ready;
    logic lane1_src3_ready;
    logic [WIDTH-1:0] lane0_src1_value;
    logic [WIDTH-1:0] lane0_src2_value;
    logic [WIDTH-1:0] lane0_src3_value;
    logic [WIDTH-1:0] lane1_src1_value;
    logic [WIDTH-1:0] lane1_src2_value;
    logic [WIDTH-1:0] lane1_src3_value;
    logic int_lane0_src1_ready;
    logic int_lane0_src2_ready;
    logic int_lane1_src1_ready;
    logic int_lane1_src2_ready;
    logic fp_lane0_src1_ready;
    logic fp_lane0_src2_ready;
    logic fp_lane0_src3_ready;
    logic fp_lane1_src1_ready;
    logic fp_lane1_src2_ready;
    logic fp_lane1_src3_ready;
    logic [WIDTH-1:0] int_lane0_src1_value;
    logic [WIDTH-1:0] int_lane0_src2_value;
    logic [WIDTH-1:0] int_lane1_src1_value;
    logic [WIDTH-1:0] int_lane1_src2_value;
    logic [WIDTH-1:0] fp_lane0_src1_value;
    logic [WIDTH-1:0] fp_lane0_src2_value;
    logic [WIDTH-1:0] fp_lane0_src3_value;
    logic [WIDTH-1:0] fp_lane1_src1_value;
    logic [WIDTH-1:0] fp_lane1_src2_value;
    logic [WIDTH-1:0] fp_lane1_src3_value;

    rob_t rob_head;
    rob_t rob_head1;
    logic rob_head_valid_i;
    logic rob_head_complete_i;
    logic rob_head1_valid_i;
    logic rob_head1_complete_i;
    logic rob_empty_i;

    logic           wb_valid;
    logic           wb_is_fp;
    preg_t          wb_preg;
    rob_tag_t       wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic           wb1_valid;
    logic           wb1_is_fp;
    preg_t          wb1_preg;
    rob_tag_t       wb1_tag;
    logic [WIDTH-1:0] wb1_result;
    logic           complete_valid;
    rob_tag_t       complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic [4:0]     complete_fp_flags;
    logic           complete_exception_valid;
    logic [WIDTH-1:0] complete_exception_cause;
    logic [WIDTH-1:0] complete_exception_tval;
    logic           branch_complete_valid;
    rob_tag_t       branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;
    logic           branch_complete_exception_valid;
    logic [WIDTH-1:0] branch_complete_exception_cause;
    logic [WIDTH-1:0] branch_complete_exception_tval;
    logic           lane1_complete_valid;
    rob_tag_t       lane1_complete_tag;
    logic [WIDTH-1:0] lane1_complete_result;
    logic [4:0]     lane1_complete_fp_flags;
    logic           lane1_complete_exception_valid;
    logic [WIDTH-1:0] lane1_complete_exception_cause;
    logic [WIDTH-1:0] lane1_complete_exception_tval;

    logic           retire_valid;
    logic           retire_valid1;
    logic [1:0]     retire_is_fp;
    preg_t          retire_preg;
    preg_t          retire_preg1;
    logic           commit_en;
    logic           commit_en1;
    logic           trap_commit;
    logic           architectural_flush;
    logic           mret_flush_exe;
    logic           fp_state_dirty_commit;
    logic [63:0]    retire_order_q;
    retire_trace_t  retire_trace0_next;
    retire_trace_t  retire_trace1_next;
    logic           commit_store_valid0;
    logic           commit_store_valid1;
    logic           fp_commit_flags_valid;
    logic [4:0]     fp_commit_flags;
    logic [31:0]    fp_csr_rdata;
    logic [4:0]     fp_fflags;
    logic [2:0]     fp_frm;
    logic [7:0]     fp_fcsr;
    logic           fp_csr_write_en;
    logic [11:0]    fp_csr_write_addr;
    logic [31:0]    fp_csr_write_data;
    logic           memory_quiescent;

    logic           pc_src_exe;
    logic [WIDTH-1:0] pc_branch_exe;
    logic           recover_rat_exe;
    logic           software_irq_level;
    logic           timer_irq_level;
    logic           external_irq_level;
    logic           software_irq_pending_q;
    logic           timer_irq_pending_q;
    logic           external_irq_pending_q;
    logic           software_irq_locally_enabled;
    logic           timer_irq_locally_enabled;
    logic           external_irq_locally_enabled;
    logic           software_irq_enabled;
    logic           timer_irq_enabled;
    logic           external_irq_enabled;
    logic           interrupt_request;
    logic           interrupt_take;
    logic [WIDTH-1:0] interrupt_mepc;
    logic [WIDTH-1:0] interrupt_mcause;
    logic [WIDTH-1:0] csr_mstatus_value;
    logic [WIDTH-1:0] csr_mie_value;
    logic [1:0]       csr_privilege_mode;
    logic             wfi_commit;
    logic             wfi_wake_request;
    logic             wfi_sleep_q;
    logic [WIDTH-1:0] wfi_resume_pc_q;
    logic             mret_resume_valid_q;
    logic [WIDTH-1:0] mret_resume_pc_q;
    logic [WIDTH-1:0] csr_pmpcfg0_value;
    logic [WIDTH-1:0] csr_pmpaddr0_value;
    logic [PMP_ENTRY_COUNT*8-1:0] csr_pmpcfg_values;
    logic [PMP_ENTRY_COUNT*WIDTH-1:0] csr_pmpaddr_values;
    logic             machine_interrupt_global_enable;

    localparam int MSTATUS_MIE_BIT = 3;
    localparam int MIE_MSIE_BIT    = 3;
    localparam int MIE_MTIE_BIT    = 7;
    localparam int MIE_MEIE_BIT    = 11;
    localparam logic [WIDTH-1:0] MCAUSE_MSI = 32'h80000003;
    localparam logic [WIDTH-1:0] MCAUSE_MTI = 32'h80000007;
    localparam logic [WIDTH-1:0] MCAUSE_MEI = 32'h8000000b;

    logic flush_exe;
    logic branch_pending_q;
    logic branch_resolve_exe;
    logic [CHECKPOINT_W-1:0] resolve_checkpoint_id_exe;
    logic [CHECKPOINT_NUM-1:0] active_checkpoint_mask_q;
    logic [CHECKPOINT_NUM-1:0] checkpoint_dep_mask_q [0:CHECKPOINT_NUM-1];
    logic [CHECKPOINT_NUM-1:0] checkpoint_kill_mask;
    logic [CHECKPOINT_NUM-1:0] checkpoint_alloc_dep_mask;
    logic lane0_branch_rename_fire;
    logic lane1_branch_rename_fire;
    logic branch_rename_fire;
    cp_id_t branch_rename_checkpoint_id;
    logic bp_update_valid_exe;
    logic [WIDTH-1:0] bp_update_pc_exe;
    logic bp_update_taken_exe;
    logic bp_update_is_jalr_exe;
    logic [WIDTH-1:0] bp_update_target_exe;
    logic lane0_dispatch_fire;
    logic lane1_dispatch_fire;

    logic [31:0] perf_fetch_packet_count_q;
    logic [31:0] perf_fetch_dual_count_q;
    logic [31:0] perf_decode_packet_count_q;
    logic [31:0] perf_decode_dual_count_q;
    logic [31:0] perf_rename_packet_count_q;
    logic [31:0] perf_rename_dual_count_q;
    logic [31:0] perf_dispatch_packet_count_q;
    logic [31:0] perf_dispatch_dual_count_q;
    logic [31:0] perf_issue_count_q;
    logic [31:0] perf_dual_issue_count_q;
    logic [31:0] perf_branch_alu_dual_issue_count_q;
    logic [31:0] perf_branch_mem_dual_issue_count_q;
    logic [31:0] perf_mem_alu_dual_issue_count_q;
    logic [31:0] perf_alu_alu_dual_issue_count_q;
    logic [31:0] perf_lane1_wb_count_q;
    logic [31:0] perf_dual_wb_count_q;
    logic [31:0] perf_commit_count_q;
    logic [31:0] perf_dual_commit_count_q;
    logic [31:0] perf_branch_lane1_complete_same_cycle_count_q;
    logic [31:0] perf_fetch_stall_count_q;
    logic [31:0] perf_decode_stall_count_q;
    logic [31:0] perf_rename_stall_count_q;
    logic [31:0] perf_dispatch_stall_count_q;
    logic [31:0] perf_active_cycle_count_q;

    assign architectural_flush = trap_commit || interrupt_take ||
                                  mret_flush_exe;
    assign flush_exe = pc_src_exe || architectural_flush;

    assign lane0_branch_rename_fire =
        pipe_rd_pkt.valid && pipe_rd_pkt.ready &&
        pipe_rd_pkt.data.lane0.valid &&
        (pipe_rd_pkt.data.lane0.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    assign lane1_branch_rename_fire =
        pipe_rd_pkt.valid && pipe_rd_pkt.ready &&
        pipe_rd_pkt.data.lane1.valid &&
        (pipe_rd_pkt.data.lane1.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    assign branch_rename_fire = lane0_branch_rename_fire || lane1_branch_rename_fire;
    assign branch_rename_checkpoint_id =
        lane0_branch_rename_fire ? pipe_rd_pkt.data.lane0.data.rs_entry.datapath.checkpoint_id :
        lane1_branch_rename_fire ? pipe_rd_pkt.data.lane1.data.rs_entry.datapath.checkpoint_id : '0;

    always_comb begin
        checkpoint_kill_mask = '0;

        if (branch_resolve_exe) begin
            checkpoint_kill_mask[resolve_checkpoint_id_exe] = 1'b1;

            if (recover_rat_exe) begin
                for (int i = 0; i < CHECKPOINT_NUM; i++) begin
                    if (checkpoint_dep_mask_q[i][resolve_checkpoint_id_exe]) begin
                        checkpoint_kill_mask[i] = 1'b1;
                    end
                end
            end
        end

        checkpoint_alloc_dep_mask = active_checkpoint_mask_q & ~checkpoint_kill_mask;
    end

    assign software_irq_level = (software_irq === 1'b1);
    assign timer_irq_level    = (timer_irq === 1'b1);
    assign external_irq_level = (external_irq === 1'b1);
    assign machine_interrupt_global_enable =
        (csr_privilege_mode != PRV_M) ||
        csr_mstatus_value[MSTATUS_MIE_BIT];
    assign software_irq_locally_enabled =
        csr_mie_value[MIE_MSIE_BIT] && software_irq_pending_q;
    assign timer_irq_locally_enabled =
        csr_mie_value[MIE_MTIE_BIT] && timer_irq_pending_q;
    assign external_irq_locally_enabled =
        csr_mie_value[MIE_MEIE_BIT] && external_irq_pending_q;
    assign software_irq_enabled = machine_interrupt_global_enable &&
                                  software_irq_locally_enabled;
    assign timer_irq_enabled    = machine_interrupt_global_enable &&
                                  timer_irq_locally_enabled;
    assign external_irq_enabled = machine_interrupt_global_enable &&
                                  external_irq_locally_enabled;
    assign wfi_wake_request = external_irq_locally_enabled ||
                              software_irq_locally_enabled ||
                              timer_irq_locally_enabled;
    assign interrupt_request = external_irq_enabled ||
                               software_irq_enabled ||
                               timer_irq_enabled;
    // Retire the already-complete architectural prefix before taking a pending
    // interrupt. Once the oldest entry is incomplete, flush and replay it from
    // its ROB PC instead of waiting for all younger work to finish.
    assign interrupt_take = !trap_commit &&
                            !commit_en &&
                            !mret_flush_exe &&
                            interrupt_request;
    assign interrupt_mcause = external_irq_enabled ? MCAUSE_MEI :
                              software_irq_enabled ? MCAUSE_MSI :
                              MCAUSE_MTI;
    assign interrupt_mepc = wfi_sleep_q ?
                            wfi_resume_pc_q :
                            rob_head_valid_i ?
                            rob_head.datapath.pc :
                            (pipe_rd_pkt_d.valid && pipe_rd_pkt_d.data.lane0.valid) ?
                            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.pc :
                            (pipe_rd_pkt_s.valid && pipe_rd_pkt_s.data.lane0.valid) ?
                            pipe_rd_pkt_s.data.lane0.data.rs_entry.datapath.pc :
                            (pipe_rd_pkt.valid && pipe_rd_pkt.data.lane0.valid) ?
                            pipe_rd_pkt.data.lane0.data.rs_entry.datapath.pc :
                            (pipe_dr_pkt_s.valid && pipe_dr_pkt_s.data.lane0.valid) ?
                            pipe_dr_pkt_s.data.lane0.data.datapath.pc :
                            (pipe_dr_pkt.valid && pipe_dr_pkt.data.lane0.valid) ?
                            pipe_dr_pkt.data.lane0.data.datapath.pc :
                            (pipe_fd_pkt_s.valid && pipe_fd_pkt_s.data.lane0.valid) ?
                            pipe_fd_pkt_s.data.lane0.data.pc :
                            (pipe_fd_pkt.valid && pipe_fd_pkt.data.lane0.valid) ?
                            pipe_fd_pkt.data.lane0.data.pc :
                            mret_resume_valid_q ?
                            mret_resume_pc_q :
                            32'b0;

    assign trap_commit = rob_head_valid_i &&
                         rob_head_complete_i &&
                         rob_head.datapath.exception_valid;
    assign commit_en    = rob_head_valid_i &&
                          rob_head_complete_i &&
                          !rob_head.datapath.exception_valid;
    assign wfi_commit   = commit_en &&
                          (rob_head.datapath.instr == 32'h10500073);
    assign commit_en1   = ENABLE_2WIDE && commit_en &&
                          !wfi_commit &&
                          rob_head1_valid_i &&
                          rob_head1_complete_i &&
                          !rob_head1.datapath.exception_valid;
    // Only stores create memory-visibility events. Keeping non-store retire
    // tags off this path prevents a wrapped ROB tag from poisoning a future
    // store-buffer entry.
    assign commit_store_valid0 = commit_en && rob_head.control_signal.store;
    assign commit_store_valid1 = commit_en1 && rob_head1.control_signal.store;
    assign retire_valid = commit_en &&
                          (rob_head.datapath.dest_is_fp ||
                           ((rob_head.datapath.new_des_preg != '0) &&
                            (rob_head.datapath.rd != '0)));
    assign retire_valid1 = commit_en1 &&
                           (rob_head1.datapath.dest_is_fp ||
                            ((rob_head1.datapath.new_des_preg != '0) &&
                             (rob_head1.datapath.rd != '0)));
    assign retire_is_fp = {
        rob_head1.datapath.dest_is_fp,
        rob_head.datapath.dest_is_fp
    };
    assign retire_preg  = rob_head.datapath.old_des_preg;
    assign retire_preg1 = rob_head1.datapath.old_des_preg;
    assign fp_commit_flags =
        (commit_en ? rob_head.datapath.fp_flags : 5'b0) |
        (commit_en1 ? rob_head1.datapath.fp_flags : 5'b0);
    assign fp_commit_flags_valid = |fp_commit_flags;

    function automatic logic updates_fp_state(input logic [31:0] instr);
        logic [6:0] opcode;
        logic [11:0] csr_addr;
    begin
        opcode = instr[6:0];
        csr_addr = instr[31:20];
        unique case (opcode)
            7'b0000111, // FLW
            7'b1000011, // FMADD.S
            7'b1000111, // FMSUB.S
            7'b1001011, // FNMSUB.S
            7'b1001111, // FNMADD.S
            7'b1010011: updates_fp_state = 1'b1; // OP-FP
            7'b1110011: updates_fp_state =
                (instr[14:12] != 3'b000) &&
                ((csr_addr == 12'h001) ||
                 (csr_addr == 12'h002) ||
                 (csr_addr == 12'h003));
            default: updates_fp_state = 1'b0;
        endcase
    end
    endfunction

    assign fp_state_dirty_commit =
        (commit_en && updates_fp_state(rob_head.datapath.instr)) ||
        (commit_en1 && updates_fp_state(rob_head1.datapath.instr));

    always_comb begin
        retire_trace0_next = '0;
        retire_trace1_next = '0;

        retire_trace0_next.valid = commit_en;
        retire_trace0_next.order = retire_order_q;
        retire_trace0_next.pc = rob_head.datapath.pc;
        retire_trace0_next.instr = rob_head.datapath.instr;
        retire_trace0_next.rd_wen = retire_valid;
        retire_trace0_next.rd_is_fp = rob_head.datapath.dest_is_fp;
        retire_trace0_next.rd = rob_head.datapath.rd;
        retire_trace0_next.rd_wdata = rob_head.datapath.result;
        retire_trace0_next.fp_flags = rob_head.datapath.fp_flags;
        retire_trace0_next.is_store = rob_head.control_signal.store;
        retire_trace0_next.is_branch = rob_head.control_signal.branch;
        retire_trace0_next.rob_tag = rob_head.datapath.rob_tag;

        retire_trace1_next.valid = commit_en1;
        retire_trace1_next.order = retire_order_q + 64'd1;
        retire_trace1_next.pc = rob_head1.datapath.pc;
        retire_trace1_next.instr = rob_head1.datapath.instr;
        retire_trace1_next.rd_wen = retire_valid1;
        retire_trace1_next.rd_is_fp = rob_head1.datapath.dest_is_fp;
        retire_trace1_next.rd = rob_head1.datapath.rd;
        retire_trace1_next.rd_wdata = rob_head1.datapath.result;
        retire_trace1_next.fp_flags = rob_head1.datapath.fp_flags;
        retire_trace1_next.is_store = rob_head1.control_signal.store;
        retire_trace1_next.is_branch = rob_head1.control_signal.branch;
        retire_trace1_next.rob_tag = rob_head1.datapath.rob_tag;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retire_order_q <= '0;
            retire_trace0 <= '0;
            retire_trace1 <= '0;
        end else begin
            retire_trace0 <= retire_trace0_next;
            retire_trace1 <= retire_trace1_next;
            retire_order_q <= retire_order_q +
                              64'(commit_en ? 1 : 0) +
                              64'(commit_en1 ? 1 : 0);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            perf_fetch_packet_count_q          <= '0;
            perf_fetch_dual_count_q            <= '0;
            perf_decode_packet_count_q         <= '0;
            perf_decode_dual_count_q           <= '0;
            perf_rename_packet_count_q         <= '0;
            perf_rename_dual_count_q           <= '0;
            perf_dispatch_packet_count_q       <= '0;
            perf_dispatch_dual_count_q         <= '0;
            perf_issue_count_q                 <= '0;
            perf_dual_issue_count_q            <= '0;
            perf_branch_alu_dual_issue_count_q <= '0;
            perf_branch_mem_dual_issue_count_q <= '0;
            perf_mem_alu_dual_issue_count_q    <= '0;
            perf_alu_alu_dual_issue_count_q    <= '0;
            perf_lane1_wb_count_q              <= '0;
            perf_dual_wb_count_q               <= '0;
            perf_commit_count_q                <= '0;
            perf_dual_commit_count_q           <= '0;
            perf_branch_lane1_complete_same_cycle_count_q <= '0;
            perf_fetch_stall_count_q           <= '0;
            perf_decode_stall_count_q          <= '0;
            perf_rename_stall_count_q          <= '0;
            perf_dispatch_stall_count_q        <= '0;
            perf_active_cycle_count_q          <= '0;
        end else begin
            if (!load_en && !wfi_sleep_q) begin
                perf_active_cycle_count_q <= perf_active_cycle_count_q + 1'b1;
            end

            if (pipe_fd_pkt.valid && pipe_fd_pkt.ready && pipe_fd_pkt.data.lane0.valid) begin
                perf_fetch_packet_count_q <= perf_fetch_packet_count_q + 1'b1;
                if (pipe_fd_pkt.data.lane1.valid) begin
                    perf_fetch_dual_count_q <= perf_fetch_dual_count_q + 1'b1;
                end
            end

            if (pipe_fd_pkt.valid && !pipe_fd_pkt.ready) begin
                perf_fetch_stall_count_q <= perf_fetch_stall_count_q + 1'b1;
            end

            if (pipe_dr_pkt.valid && pipe_dr_pkt.ready && pipe_dr_pkt.data.lane0.valid) begin
                perf_decode_packet_count_q <= perf_decode_packet_count_q + 1'b1;
                if (pipe_dr_pkt.data.lane1.valid) begin
                    perf_decode_dual_count_q <= perf_decode_dual_count_q + 1'b1;
                end
            end

            if (pipe_dr_pkt.valid && !pipe_dr_pkt.ready) begin
                perf_decode_stall_count_q <= perf_decode_stall_count_q + 1'b1;
            end

            if (pipe_rd_pkt.valid && pipe_rd_pkt.ready && pipe_rd_pkt.data.lane0.valid) begin
                perf_rename_packet_count_q <= perf_rename_packet_count_q + 1'b1;
                if (pipe_rd_pkt.data.lane1.valid) begin
                    perf_rename_dual_count_q <= perf_rename_dual_count_q + 1'b1;
                end
            end

            if (pipe_rd_pkt.valid && !pipe_rd_pkt.ready) begin
                perf_rename_stall_count_q <= perf_rename_stall_count_q + 1'b1;
            end

            if (pipe_rd_pkt_d.valid && pipe_rd_pkt_d.ready && pipe_rd_pkt_d.data.lane0.valid) begin
                perf_dispatch_packet_count_q <= perf_dispatch_packet_count_q + 1'b1;
                if (pipe_rd_pkt_d.data.lane1.valid) begin
                    perf_dispatch_dual_count_q <= perf_dispatch_dual_count_q + 1'b1;
                end
            end

            if (pipe_rd_pkt_d.valid && !pipe_rd_pkt_d.ready) begin
                perf_dispatch_stall_count_q <= perf_dispatch_stall_count_q + 1'b1;
            end

            if (issue_if.valid && issue_if.ready) begin
                if (issue1_if.valid && issue1_if.ready) begin
                    perf_issue_count_q      <= perf_issue_count_q + 32'd2;
                    perf_dual_issue_count_q <= perf_dual_issue_count_q + 1'b1;

                    if ((issue_if.data.fu_sel == FU_BRANCH) &&
                        (issue1_if.data.fu_sel == FU_ALU)) begin
                        perf_branch_alu_dual_issue_count_q <= perf_branch_alu_dual_issue_count_q + 1'b1;
                    end

                    if ((issue_if.data.fu_sel == FU_BRANCH) &&
                        (issue1_if.data.fu_sel == FU_MEM)) begin
                        perf_branch_mem_dual_issue_count_q <= perf_branch_mem_dual_issue_count_q + 1'b1;
                    end

                    if (((issue_if.data.fu_sel == FU_MEM) &&
                         (issue1_if.data.fu_sel == FU_ALU)) ||
                        ((issue_if.data.fu_sel == FU_ALU) &&
                         (issue1_if.data.fu_sel == FU_MEM))) begin
                        perf_mem_alu_dual_issue_count_q <= perf_mem_alu_dual_issue_count_q + 1'b1;
                    end

                    if ((issue_if.data.fu_sel == FU_ALU) &&
                        (issue1_if.data.fu_sel == FU_ALU)) begin
                        perf_alu_alu_dual_issue_count_q <= perf_alu_alu_dual_issue_count_q + 1'b1;
                    end
                end else begin
                    perf_issue_count_q <= perf_issue_count_q + 1'b1;
                end
            end else if (issue1_if.valid && issue1_if.ready) begin
                perf_issue_count_q <= perf_issue_count_q + 1'b1;
            end

            if (wb1_valid) begin
                perf_lane1_wb_count_q <= perf_lane1_wb_count_q + 1'b1;
            end

            if (wb_valid && wb1_valid) begin
                perf_dual_wb_count_q <= perf_dual_wb_count_q + 1'b1;
            end

            if (branch_complete_valid && lane1_complete_valid) begin
                perf_branch_lane1_complete_same_cycle_count_q <=
                    perf_branch_lane1_complete_same_cycle_count_q + 1'b1;
            end

            if (commit_en) begin
                if (commit_en1) begin
                    perf_commit_count_q      <= perf_commit_count_q + 32'd2;
                    perf_dual_commit_count_q <= perf_dual_commit_count_q + 1'b1;
                end else begin
                    perf_commit_count_q <= perf_commit_count_q + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || architectural_flush) begin
            active_checkpoint_mask_q <= '0;
            for (int i = 0; i < CHECKPOINT_NUM; i++) begin
                checkpoint_dep_mask_q[i] <= '0;
            end
        end else begin
            active_checkpoint_mask_q <= active_checkpoint_mask_q & ~checkpoint_kill_mask;

            for (int i = 0; i < CHECKPOINT_NUM; i++) begin
                if (checkpoint_kill_mask[i]) begin
                    checkpoint_dep_mask_q[i] <= '0;
                end else if (branch_resolve_exe) begin
                    checkpoint_dep_mask_q[i][resolve_checkpoint_id_exe] <= 1'b0;
                end
            end

            if (branch_rename_fire) begin
                active_checkpoint_mask_q[branch_rename_checkpoint_id] <= 1'b1;
                checkpoint_dep_mask_q[branch_rename_checkpoint_id] <= checkpoint_alloc_dep_mask;
            end
        end
    end

`ifndef SYNTHESIS
    logic [63:0] assert_next_retire_order_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            assert_next_retire_order_q <= '0;
        end else begin
            assert (!(lane0_branch_rename_fire && lane1_branch_rename_fire))
                else $error("CHECKPOINT: one packet allocated two branch checkpoints");
            if (branch_rename_fire) begin
                assert (!active_checkpoint_mask_q[branch_rename_checkpoint_id] ||
                        checkpoint_kill_mask[branch_rename_checkpoint_id])
                    else $error("CHECKPOINT: allocated active checkpoint id %0d",
                                branch_rename_checkpoint_id);
            end

            for (int i = 0; i < CHECKPOINT_NUM; i++) begin
                if (active_checkpoint_mask_q[i]) begin
                    assert (!checkpoint_dep_mask_q[i][i])
                        else $error("CHECKPOINT: checkpoint %0d depends on itself", i);
                    assert ((checkpoint_dep_mask_q[i] & ~active_checkpoint_mask_q) == '0)
                        else $error("CHECKPOINT: checkpoint %0d depends on an inactive checkpoint", i);
                end else begin
                    assert (checkpoint_dep_mask_q[i] == '0)
                        else $error("CHECKPOINT: inactive checkpoint %0d retains dependencies", i);
                end
            end

            assert (!commit_en1 || commit_en)
                else $error("RETIRE: lane1 retired without lane0");
            assert (!retire_trace1.valid || retire_trace0.valid)
                else $error("RETIRE: trace lane1 is valid without lane0");

            if (retire_trace0.valid) begin
                assert (retire_trace0.order == assert_next_retire_order_q)
                    else $error("RETIRE: expected order %0d, got %0d",
                                assert_next_retire_order_q, retire_trace0.order);
                assert (!retire_trace0.rd_wen || retire_trace0.rd_is_fp ||
                        (retire_trace0.rd != '0))
                    else $error("RETIRE: integer x0 write reported on lane0");
            end

            if (retire_trace1.valid) begin
                assert (retire_trace1.order == (retire_trace0.order + 64'd1))
                    else $error("RETIRE: lane1 order is not consecutive");
                assert (retire_trace1.rob_tag != retire_trace0.rob_tag)
                    else $error("RETIRE: two lanes reported the same ROB tag");
                assert (!retire_trace1.rd_wen || retire_trace1.rd_is_fp ||
                        (retire_trace1.rd != '0))
                    else $error("RETIRE: integer x0 write reported on lane1");
            end

            assert_next_retire_order_q <= assert_next_retire_order_q +
                                          64'(retire_trace0.valid ? 1 : 0) +
                                          64'(retire_trace1.valid ? 1 : 0);
        end
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            software_irq_pending_q <= 1'b0;
            timer_irq_pending_q    <= 1'b0;
            external_irq_pending_q <= 1'b0;
        end else begin
            // Platform interrupt pins are level-sensitive. A source that stays
            // asserted therefore remains visible in mip after trap entry and
            // can be selected again after MRET restores interrupt enable.
            software_irq_pending_q <= software_irq_level;
            timer_irq_pending_q    <= timer_irq_level;
            external_irq_pending_q <= external_irq_level;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wfi_sleep_q     <= 1'b0;
            wfi_resume_pc_q <= '0;
            mret_resume_valid_q <= 1'b0;
            mret_resume_pc_q    <= '0;
        end else begin
            if (wfi_commit) begin
                wfi_resume_pc_q <= rob_head.datapath.pc + 32'd4;
            end

            if (mret_flush_exe) begin
                mret_resume_valid_q <= 1'b1;
                mret_resume_pc_q    <= pc_branch_exe;
            end else if (interrupt_take ||
                         (pipe_fd_pkt.valid && pipe_fd_pkt.ready)) begin
                mret_resume_valid_q <= 1'b0;
            end

            if (wfi_sleep_q) begin
                if (wfi_wake_request) begin
                    wfi_sleep_q <= 1'b0;
                end
            end else if (wfi_commit && !wfi_wake_request) begin
                wfi_sleep_q <= 1'b1;
            end
        end
    end

    assign branch_pending_q = |active_checkpoint_mask_q;

    fetch_packet_stage #(
        .BASE_ADDR(IMEM_BASE_ADDR),
        .DEPTH_BYTES(IMEM_DEPTH_BYTES),
        .ENABLE_ACCESS_FAULTS(ENABLE_ACCESS_FAULTS),
        .ENABLE_PMP(ENABLE_PMP),
        .ENABLE_2WIDE(ENABLE_2WIDE)
    ) u_fetch (
        .load_en(load_en),
        .load_addr(load_addr),
        .load_instr_byte(load_instr_byte),
        .pc_src(pc_src_exe),
        .pc_branch(pc_branch_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc(bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .current_privilege(csr_privilege_mode),
        .pmpcfg_values(csr_pmpcfg_values),
        .pmpaddr_values(csr_pmpaddr_values),
        .out_if(pipe_fd_pkt.producer)
    );

    skid_buffer_pipe #(
        .T(fetch_decode_packet_t)
    ) u_skid_fd (
        .flush(flush_exe),
        .in_if(pipe_fd_pkt.consumer),
        .out_if(pipe_fd_pkt_s.producer)
    );

    decode_packet_stage u_decode (
        .in_if(pipe_fd_pkt_s.consumer),
        .out_if(pipe_dr_pkt.producer)
    );

    skid_buffer_pipe #(
        .T(decode_rat_packet_t)
    ) u_skid_dr (
        .flush(flush_exe),
        .in_if(pipe_dr_pkt.consumer),
        .out_if(pipe_dr_pkt_s.producer)
    );

    rename_packet_stage u_rename_packet (
        .flush(flush_exe),
        .restore_rat(recover_rat_exe),
        .restore_committed(architectural_flush),
        .restore_checkpoint_id(resolve_checkpoint_id_exe),
        .active_checkpoint_mask(active_checkpoint_mask_q),
        .in_if(pipe_dr_pkt_s.consumer),
        .out_if(pipe_rd_pkt.producer),
        .retire_valid({retire_valid1, retire_valid}),
        .retire_is_fp(retire_is_fp),
        .retire_areg0(rob_head.datapath.rd),
        .retire_areg1(rob_head1.datapath.rd),
        .retire_preg0(retire_preg),
        .retire_preg1(retire_preg1),
        .retire_new_preg0(rob_head.datapath.new_des_preg),
        .retire_new_preg1(rob_head1.datapath.new_des_preg)
    );

    skid_buffer_pipe #(
        .T(rat_dis_packet_t)
    ) u_skid_rd_packet (
        .flush(flush_exe),
        .in_if(pipe_rd_pkt.consumer),
        .out_if(pipe_rd_pkt_s.producer)
    );

    rat_dis_packet_splitter u_packet_splitter (
        .flush(flush_exe),
        .in_if(pipe_rd_pkt_s.consumer),
        .out_if(pipe_rd_pkt_d.producer)
    );

    dispatch_packet_stage #(
        .ENABLE_2WIDE(ENABLE_2WIDE)
    ) u_dispatch_packet (
        .halt(wfi_sleep_q),
        .flush(architectural_flush),
        .squash_en(recover_rat_exe),
        .squash_checkpoint_id(resolve_checkpoint_id_exe),
        .resolve_en(branch_resolve_exe),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .lane0_src1_ready(lane0_src1_ready),
        .lane0_src2_ready(lane0_src2_ready),
        .lane0_src3_ready(lane0_src3_ready),
        .lane0_src1_value(lane0_src1_value),
        .lane0_src2_value(lane0_src2_value),
        .lane0_src3_value(lane0_src3_value),
        .lane1_src1_ready(lane1_src1_ready),
        .lane1_src2_ready(lane1_src2_ready),
        .lane1_src3_ready(lane1_src3_ready),
        .lane1_src1_value(lane1_src1_value),
        .lane1_src2_value(lane1_src2_value),
        .lane1_src3_value(lane1_src3_value),
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_tag(wb_tag),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_tag(wb1_tag),
        .wb1_result(wb1_result),
        .complete_valid(complete_valid),
        .complete_tag(complete_tag),
        .complete_result(complete_result),
        .complete_fp_flags(complete_fp_flags),
        .complete_exception_valid(complete_exception_valid),
        .complete_exception_cause(complete_exception_cause),
        .complete_exception_tval(complete_exception_tval),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .branch_complete_exception_valid(branch_complete_exception_valid),
        .branch_complete_exception_cause(branch_complete_exception_cause),
        .branch_complete_exception_tval(branch_complete_exception_tval),
        .lane1_complete_valid(lane1_complete_valid),
        .lane1_complete_tag(lane1_complete_tag),
        .lane1_complete_result(lane1_complete_result),
        .lane1_complete_fp_flags(lane1_complete_fp_flags),
        .lane1_complete_exception_valid(lane1_complete_exception_valid),
        .lane1_complete_exception_cause(lane1_complete_exception_cause),
        .lane1_complete_exception_tval(lane1_complete_exception_tval),
        .commit_en0(commit_en),
        .commit_en1(commit_en1),
        .in_if(pipe_rd_pkt_d.consumer),
        .issue_if(issue_if.producer),
        .issue1_if(issue1_if.producer),
        .rob_head(rob_head),
        .rob_head_valid(rob_head_valid_i),
        .rob_head_complete(rob_head_complete_i),
        .rob_head1(rob_head1),
        .rob_head1_valid(rob_head1_valid_i),
        .rob_head1_complete(rob_head1_complete_i),
        .rob_empty(rob_empty_i)
    );

    assign lane0_dispatch_fire = pipe_rd_pkt_d.valid && pipe_rd_pkt_d.ready &&
                                 pipe_rd_pkt_d.data.lane0.valid;
    assign lane1_dispatch_fire = pipe_rd_pkt_d.valid && pipe_rd_pkt_d.ready &&
                                 pipe_rd_pkt_d.data.lane1.valid;

    assign lane0_src1_ready =
        pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src1_is_fp ?
        fp_lane0_src1_ready : int_lane0_src1_ready;
    assign lane0_src2_ready =
        pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src2_is_fp ?
        fp_lane0_src2_ready : int_lane0_src2_ready;
    assign lane0_src3_ready =
        !pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src3_is_fp ||
        fp_lane0_src3_ready;
    assign lane1_src1_ready =
        pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src1_is_fp ?
        fp_lane1_src1_ready : int_lane1_src1_ready;
    assign lane1_src2_ready =
        pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src2_is_fp ?
        fp_lane1_src2_ready : int_lane1_src2_ready;
    assign lane1_src3_ready =
        !pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src3_is_fp ||
        fp_lane1_src3_ready;
    assign lane0_src1_value =
        pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src1_is_fp ?
        fp_lane0_src1_value : int_lane0_src1_value;
    assign lane0_src2_value =
        pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src2_is_fp ?
        fp_lane0_src2_value : int_lane0_src2_value;
    assign lane0_src3_value =
        pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src3_is_fp ?
        fp_lane0_src3_value : '0;
    assign lane1_src1_value =
        pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src1_is_fp ?
        fp_lane1_src1_value : int_lane1_src1_value;
    assign lane1_src2_value =
        pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src2_is_fp ?
        fp_lane1_src2_value : int_lane1_src2_value;
    assign lane1_src3_value =
        pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src3_is_fp ?
        fp_lane1_src3_value : '0;

    reg_file_2w u_prf_2w (
        .clk(clk),
        .rst_n(rst_n),
        .w_en(wb_valid && !wb_is_fp),
        .w_addr(wb_preg),
        .w_data(wb_result),
        .w1_en(wb1_valid && !wb1_is_fp),
        .w1_addr(wb1_preg),
        .w1_data(wb1_result),
        .lane0_raddr0(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p),
        .lane0_rdata0(int_lane0_src1_value),
        .lane0_raddr1(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p),
        .lane0_rdata1(int_lane0_src2_value),
        .lane1_raddr0(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p),
        .lane1_rdata0(int_lane1_src1_value),
        .lane1_raddr1(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p),
        .lane1_rdata1(int_lane1_src2_value),
        .rename_en({
            lane1_dispatch_fire &&
            pipe_rd_pkt_d.data.lane1.data.rs_entry.control_signal.rename &&
            !pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.dest_is_fp,
            lane0_dispatch_fire &&
            pipe_rd_pkt_d.data.lane0.data.rs_entry.control_signal.rename &&
            !pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.dest_is_fp
        }),
        .lane0_src1_valid_addr(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p),
        .lane0_src2_valid_addr(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p),
        .lane0_new_des_preg(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.new_des_preg),
        .lane1_src1_valid_addr(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p),
        .lane1_src2_valid_addr(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p),
        .lane1_new_des_preg(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.new_des_preg),
        .lane0_src1_ready(int_lane0_src1_ready),
        .lane0_src2_ready(int_lane0_src2_ready),
        .lane1_src1_ready(int_lane1_src1_ready),
        .lane1_src2_ready(int_lane1_src2_ready)
    );

    fp_reg_file_2w u_fp_prf_2w (
        .clk(clk),
        .rst_n(rst_n),
        .wb0_en(wb_valid && wb_is_fp),
        .wb0_addr(fp_defines_pkg::fp_preg_t'(wb_preg)),
        .wb0_data(wb_result),
        .wb1_en(wb1_valid && wb1_is_fp),
        .wb1_addr(fp_defines_pkg::fp_preg_t'(wb1_preg)),
        .wb1_data(wb1_result),
        .lane0_raddr0(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p)),
        .lane0_rdata0(fp_lane0_src1_value),
        .lane0_raddr1(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p)),
        .lane0_rdata1(fp_lane0_src2_value),
        .lane0_raddr2(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_3p)),
        .lane0_rdata2(fp_lane0_src3_value),
        .lane1_raddr0(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p)),
        .lane1_rdata0(fp_lane1_src1_value),
        .lane1_raddr1(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p)),
        .lane1_rdata1(fp_lane1_src2_value),
        .lane1_raddr2(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_3p)),
        .lane1_rdata2(fp_lane1_src3_value),
        .rename_en({
            lane1_dispatch_fire &&
            pipe_rd_pkt_d.data.lane1.data.rs_entry.control_signal.rename &&
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.dest_is_fp,
            lane0_dispatch_fire &&
            pipe_rd_pkt_d.data.lane0.data.rs_entry.control_signal.rename &&
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.dest_is_fp
        }),
        .lane0_src1_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p)),
        .lane0_src2_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p)),
        .lane0_src3_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_3p)),
        .lane0_new_preg(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.new_des_preg)),
        .lane1_src1_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p)),
        .lane1_src2_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p)),
        .lane1_src3_addr(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_3p)),
        .lane1_new_preg(fp_defines_pkg::fp_preg_t'(
            pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.new_des_preg)),
        .lane0_src1_ready(fp_lane0_src1_ready),
        .lane0_src2_ready(fp_lane0_src2_ready),
        .lane0_src3_ready(fp_lane0_src3_ready),
        .lane1_src1_ready(fp_lane1_src1_ready),
        .lane1_src2_ready(fp_lane1_src2_ready),
        .lane1_src3_ready(fp_lane1_src3_ready)
    );

    fp_csr u_fp_csr (
        .clk        (clk),
        .rst_n      (rst_n),
        .csr_we     (fp_csr_write_en),
        .csr_addr   (fp_csr_write_addr),
        .csr_wdata  (fp_csr_write_data),
        .flags_valid(fp_commit_flags_valid),
        .flags      (fp_commit_flags),
        .csr_rdata  (fp_csr_rdata),
        .fflags     (fp_fflags),
        .frm        (fp_frm),
        .fcsr       (fp_fcsr)
    );

    execution_stage #(
        .MEM_WORDS(DMEM_WORDS),
        .DATA_BASE_ADDR(DMEM_BASE_ADDR),
        .ENABLE_DATA_ACCESS_FAULTS(ENABLE_ACCESS_FAULTS),
        .ENABLE_PMP(ENABLE_PMP),
        .PRECISE_SYSTEM_EXCEPTIONS(1'b1),
        .RESET_FS_INITIAL(RESET_FS_INITIAL)
    ) u_execution (
        .in_if(issue_if.consumer),
        .in1_if(issue1_if.consumer),
        .software_irq_pending(software_irq_pending_q),
        .timer_irq_pending(timer_irq_pending_q),
        .external_irq_pending(external_irq_pending_q),
        .interrupt_take(interrupt_take),
        .interrupt_mepc(interrupt_mepc),
        .interrupt_mcause(interrupt_mcause),
        .commit_trap_en(trap_commit),
        .commit_trap_mepc(rob_head.datapath.pc),
        .commit_trap_mcause(rob_head.datapath.exception_cause),
        .commit_trap_mtval(rob_head.datapath.exception_tval),
        .fp_frm_value(fp_frm),
        .fp_csr_rdata(fp_csr_rdata),
        .fp_state_dirty(fp_state_dirty_commit),
        .commit_store_valid0(commit_store_valid0),
        .commit_store_tag0(rob_head.datapath.rob_tag),
        .commit_store_valid1(commit_store_valid1),
        .commit_store_tag1(rob_head1.datapath.rob_tag),
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_tag(wb_tag),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_tag(wb1_tag),
        .wb1_result(wb1_result),
        .complete_valid(complete_valid),
        .complete_tag(complete_tag),
        .complete_result(complete_result),
        .complete_fp_flags(complete_fp_flags),
        .complete_exception_valid(complete_exception_valid),
        .complete_exception_cause(complete_exception_cause),
        .complete_exception_tval(complete_exception_tval),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .branch_complete_exception_valid(branch_complete_exception_valid),
        .branch_complete_exception_cause(branch_complete_exception_cause),
        .branch_complete_exception_tval(branch_complete_exception_tval),
        .lane1_complete_valid(lane1_complete_valid),
        .lane1_complete_tag(lane1_complete_tag),
        .lane1_complete_result(lane1_complete_result),
        .lane1_complete_fp_flags(lane1_complete_fp_flags),
        .lane1_complete_exception_valid(lane1_complete_exception_valid),
        .lane1_complete_exception_cause(lane1_complete_exception_cause),
        .lane1_complete_exception_tval(lane1_complete_exception_tval),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc(bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .pc_src(pc_src_exe),
        .pc_branch(pc_branch_exe),
        .recover_rat(recover_rat_exe),
        .mret_flush(mret_flush_exe),
        .csr_mstatus_value(csr_mstatus_value),
        .csr_mie_value(csr_mie_value),
        .csr_privilege_mode(csr_privilege_mode),
        .csr_pmpcfg0_value(csr_pmpcfg0_value),
        .csr_pmpaddr0_value(csr_pmpaddr0_value),
        .csr_pmpcfg_values(csr_pmpcfg_values),
        .csr_pmpaddr_values(csr_pmpaddr_values),
        .fp_csr_write_en(fp_csr_write_en),
        .fp_csr_write_addr(fp_csr_write_addr),
        .fp_csr_write_data(fp_csr_write_data),
        .memory_quiescent(memory_quiescent),
        .branch_resolve(branch_resolve_exe)
    );

    assign issue_valid   = issue_if.valid;
    assign issue_fu_type = issue_if.data.fu_sel;
    assign issue_pc      = issue_if.data.datapath.pc;
    assign issue_imm     = issue_if.data.datapath.imm;

    assign rob_head_valid    = rob_head_valid_i;
    assign rob_head_complete = rob_head_complete_i;
    assign rob_head_rd       = rob_head.datapath.rd;

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n === 1'b1) begin
            assert (!commit_en ||
                    (rob_head.control_signal.store ==
                     ((rob_head.datapath.instr[6:0] == 7'b0100011) ||
                      (rob_head.datapath.instr[6:0] == 7'b0100111))))
                else $error("[ASSERT:TOP] lane0 ROB store metadata disagrees with opcode");
            assert (!commit_en1 ||
                    (rob_head1.control_signal.store ==
                     ((rob_head1.datapath.instr[6:0] == 7'b0100011) ||
                      (rob_head1.datapath.instr[6:0] == 7'b0100111))))
                else $error("[ASSERT:TOP] lane1 ROB store metadata disagrees with opcode");
            assert (!trap_commit || !commit_en)
                else $error("[ASSERT:TOP] exceptional ROB head retired normally");
            assert (!(trap_commit && interrupt_take))
                else $error("[ASSERT:TOP] synchronous exception and interrupt taken together");
            assert (!(commit_en && interrupt_take))
                else $error("[ASSERT:TOP] normal retirement and interrupt taken together");
            assert (!interrupt_take || !rob_head_valid_i || !rob_head_complete_i)
                else $error("[ASSERT:TOP] interrupt flushed a completed ROB head");
            assert (!interrupt_take || !rob_head_valid_i ||
                    (interrupt_mepc == rob_head.datapath.pc))
                else $error("[ASSERT:TOP] non-empty ROB interrupt restart PC is not the head PC");
            assert (!commit_en1 || !rob_head1.datapath.exception_valid)
                else $error("[ASSERT:TOP] exceptional lane1 ROB entry retired normally");
            assert (!wfi_sleep_q || !commit_en)
                else $error("[ASSERT:TOP] instruction retired while WFI was asleep");
            assert (!wfi_sleep_q || !pipe_rd_pkt_d.ready)
                else $error("[ASSERT:TOP] dispatch accepted work while WFI was asleep");
        end
    end
`endif

endmodule
