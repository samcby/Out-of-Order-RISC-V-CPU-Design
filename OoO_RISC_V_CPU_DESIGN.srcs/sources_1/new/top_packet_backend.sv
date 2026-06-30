// Primary integration top for the current packetized 2-wide backend.
// The legacy scalar-oriented integration remains available as top.sv.
module top_packet_backend (
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
    output logic [4:0]  rob_head_rd
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
    logic lane1_src1_ready;
    logic lane1_src2_ready;
    logic [WIDTH-1:0] lane0_src1_value;
    logic [WIDTH-1:0] lane0_src2_value;
    logic [WIDTH-1:0] lane1_src1_value;
    logic [WIDTH-1:0] lane1_src2_value;

    rob_t rob_head;
    rob_t rob_head1;
    logic rob_head_valid_i;
    logic rob_head_complete_i;
    logic rob_head1_valid_i;
    logic rob_head1_complete_i;
    logic rob_empty_i;

    logic           wb_valid;
    preg_t          wb_preg;
    rob_tag_t       wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic           wb1_valid;
    preg_t          wb1_preg;
    rob_tag_t       wb1_tag;
    logic [WIDTH-1:0] wb1_result;
    logic           complete_valid;
    rob_tag_t       complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic           branch_complete_valid;
    rob_tag_t       branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;
    logic           lane1_complete_valid;
    rob_tag_t       lane1_complete_tag;
    logic [WIDTH-1:0] lane1_complete_result;

    logic           retire_valid;
    logic           retire_valid1;
    preg_t          retire_preg;
    preg_t          retire_preg1;
    logic           commit_en;
    logic           commit_en1;
    logic           commit_store_valid0;
    logic           commit_store_valid1;

    logic           pc_src_exe;
    logic [WIDTH-1:0] pc_branch_exe;
    logic           recover_rat_exe;
    logic           software_irq_level;
    logic           timer_irq_level;
    logic           external_irq_level;
    logic           software_irq_level_q;
    logic           timer_irq_level_q;
    logic           external_irq_level_q;
    logic           software_irq_rise;
    logic           timer_irq_rise;
    logic           external_irq_rise;
    logic           software_irq_pending_q;
    logic           timer_irq_pending_q;
    logic           external_irq_pending_q;
    logic           software_irq_enabled;
    logic           timer_irq_enabled;
    logic           external_irq_enabled;
    logic           interrupt_take;
    logic [WIDTH-1:0] interrupt_mepc;
    logic [WIDTH-1:0] interrupt_mcause;
    logic [WIDTH-1:0] csr_mstatus_value;
    logic [WIDTH-1:0] csr_mie_value;

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

    assign flush_exe = pc_src_exe || interrupt_take;

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
    assign software_irq_rise  = software_irq_level && !software_irq_level_q;
    assign timer_irq_rise     = timer_irq_level && !timer_irq_level_q;
    assign external_irq_rise  = external_irq_level && !external_irq_level_q;
    assign software_irq_enabled = csr_mstatus_value[MSTATUS_MIE_BIT] &&
                                  csr_mie_value[MIE_MSIE_BIT] &&
                                  software_irq_pending_q;
    assign timer_irq_enabled    = csr_mstatus_value[MSTATUS_MIE_BIT] &&
                                  csr_mie_value[MIE_MTIE_BIT] &&
                                  timer_irq_pending_q;
    assign external_irq_enabled = csr_mstatus_value[MSTATUS_MIE_BIT] &&
                                  csr_mie_value[MIE_MEIE_BIT] &&
                                  external_irq_pending_q;
    assign interrupt_take = rob_empty_i &&
                            (external_irq_enabled ||
                             software_irq_enabled ||
                             timer_irq_enabled);
    assign interrupt_mcause = external_irq_enabled ? MCAUSE_MEI :
                              software_irq_enabled ? MCAUSE_MSI :
                              MCAUSE_MTI;
    assign interrupt_mepc = (pipe_fd_pkt_s.valid && pipe_fd_pkt_s.data.lane0.valid) ?
                            pipe_fd_pkt_s.data.lane0.data.pc :
                            (pipe_dr_pkt_s.valid && pipe_dr_pkt_s.data.lane0.valid) ?
                            pipe_dr_pkt_s.data.lane0.data.datapath.pc :
                            (pipe_dr_pkt.valid && pipe_dr_pkt.data.lane0.valid) ?
                            pipe_dr_pkt.data.lane0.data.datapath.pc :
                            (pipe_rd_pkt_s.valid && pipe_rd_pkt_s.data.lane0.valid) ?
                            pipe_rd_pkt_s.data.lane0.data.rs_entry.datapath.pc :
                            (pipe_rd_pkt_d.valid && pipe_rd_pkt_d.data.lane0.valid) ?
                            pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.pc :
                            32'b0;

    assign commit_en    = rob_head_valid_i && rob_head_complete_i;
    assign commit_en1   = commit_en && rob_head1_valid_i && rob_head1_complete_i;
    // LSU store buffer filters by tag, so forward every committed ROB tag.
    // This avoids losing a store commit if ROB-side store metadata is stale.
    assign commit_store_valid0 = commit_en;
    assign commit_store_valid1 = commit_en1;
    assign retire_valid = commit_en &&
                          (rob_head.datapath.new_des_preg != '0) &&
                          (rob_head.datapath.rd != '0);
    assign retire_valid1 = commit_en1 &&
                           (rob_head1.datapath.new_des_preg != '0) &&
                           (rob_head1.datapath.rd != '0);
    assign retire_preg  = rob_head.datapath.old_des_preg;
    assign retire_preg1 = rob_head1.datapath.old_des_preg;

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
        end else begin
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

                    if ((issue_if.data.fu_sel == FU_MEM) &&
                        (issue1_if.data.fu_sel == FU_ALU)) begin
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
        if (!rst_n) begin
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            software_irq_level_q <= 1'b0;
            timer_irq_level_q    <= 1'b0;
            external_irq_level_q <= 1'b0;
            software_irq_pending_q <= 1'b0;
            timer_irq_pending_q    <= 1'b0;
            external_irq_pending_q <= 1'b0;
        end else begin
            software_irq_level_q <= software_irq_level;
            timer_irq_level_q    <= timer_irq_level;
            external_irq_level_q <= external_irq_level;

            if (interrupt_take && (interrupt_mcause == MCAUSE_MSI)) begin
                software_irq_pending_q <= 1'b0;
            end else if (software_irq_rise) begin
                software_irq_pending_q <= 1'b1;
            end

            if (interrupt_take && (interrupt_mcause == MCAUSE_MTI)) begin
                timer_irq_pending_q <= 1'b0;
            end else if (timer_irq_rise) begin
                timer_irq_pending_q <= 1'b1;
            end

            if (interrupt_take && (interrupt_mcause == MCAUSE_MEI)) begin
                external_irq_pending_q <= 1'b0;
            end else if (external_irq_rise) begin
                external_irq_pending_q <= 1'b1;
            end
        end
    end

    assign branch_pending_q = |active_checkpoint_mask_q;

    fetch_packet_stage u_fetch (
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
        .restore_checkpoint_id(resolve_checkpoint_id_exe),
        .active_checkpoint_mask(active_checkpoint_mask_q),
        .in_if(pipe_dr_pkt_s.consumer),
        .out_if(pipe_rd_pkt.producer),
        .retire_valid({retire_valid1, retire_valid}),
        .retire_preg0(retire_preg),
        .retire_preg1(retire_preg1)
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

    dispatch_packet_stage u_dispatch_packet (
        .flush(1'b0),
        .squash_en(recover_rat_exe),
        .squash_checkpoint_id(resolve_checkpoint_id_exe),
        .resolve_en(branch_resolve_exe),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .lane0_src1_ready(lane0_src1_ready),
        .lane0_src2_ready(lane0_src2_ready),
        .lane0_src1_value(lane0_src1_value),
        .lane0_src2_value(lane0_src2_value),
        .lane1_src1_ready(lane1_src1_ready),
        .lane1_src2_ready(lane1_src2_ready),
        .lane1_src1_value(lane1_src1_value),
        .lane1_src2_value(lane1_src2_value),
        .wb_valid(wb_valid),
        .wb_preg(wb_preg),
        .wb_tag(wb_tag),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_preg(wb1_preg),
        .wb1_tag(wb1_tag),
        .wb1_result(wb1_result),
        .complete_valid(complete_valid),
        .complete_tag(complete_tag),
        .complete_result(complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .lane1_complete_valid(lane1_complete_valid),
        .lane1_complete_tag(lane1_complete_tag),
        .lane1_complete_result(lane1_complete_result),
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

    reg_file_2w u_prf_2w (
        .clk(clk),
        .rst_n(rst_n),
        .w_en(wb_valid),
        .w_addr(wb_preg),
        .w_data(wb_result),
        .w1_en(wb1_valid),
        .w1_addr(wb1_preg),
        .w1_data(wb1_result),
        .lane0_raddr0(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p),
        .lane0_rdata0(lane0_src1_value),
        .lane0_raddr1(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p),
        .lane0_rdata1(lane0_src2_value),
        .lane1_raddr0(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p),
        .lane1_rdata0(lane1_src1_value),
        .lane1_raddr1(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p),
        .lane1_rdata1(lane1_src2_value),
        .rename_en({
            lane1_dispatch_fire &&
            pipe_rd_pkt_d.data.lane1.data.rs_entry.control_signal.rename,
            lane0_dispatch_fire &&
            pipe_rd_pkt_d.data.lane0.data.rs_entry.control_signal.rename
        }),
        .lane0_src1_valid_addr(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_1p),
        .lane0_src2_valid_addr(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.src_reg_2p),
        .lane0_new_des_preg(pipe_rd_pkt_d.data.lane0.data.rs_entry.datapath.new_des_preg),
        .lane1_src1_valid_addr(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_1p),
        .lane1_src2_valid_addr(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.src_reg_2p),
        .lane1_new_des_preg(pipe_rd_pkt_d.data.lane1.data.rs_entry.datapath.new_des_preg),
        .lane0_src1_ready(lane0_src1_ready),
        .lane0_src2_ready(lane0_src2_ready),
        .lane1_src1_ready(lane1_src1_ready),
        .lane1_src2_ready(lane1_src2_ready)
    );

    execution_stage u_execution (
        .in_if(issue_if.consumer),
        .in1_if(issue1_if.consumer),
        .software_irq_pending(software_irq_pending_q),
        .timer_irq_pending(timer_irq_pending_q),
        .external_irq_pending(external_irq_pending_q),
        .interrupt_take(interrupt_take),
        .interrupt_mepc(interrupt_mepc),
        .interrupt_mcause(interrupt_mcause),
        .commit_store_valid0(commit_store_valid0),
        .commit_store_tag0(rob_head.datapath.rob_tag),
        .commit_store_valid1(commit_store_valid1),
        .commit_store_tag1(rob_head1.datapath.rob_tag),
        .wb_valid(wb_valid),
        .wb_preg(wb_preg),
        .wb_tag(wb_tag),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_preg(wb1_preg),
        .wb1_tag(wb1_tag),
        .wb1_result(wb1_result),
        .complete_valid(complete_valid),
        .complete_tag(complete_tag),
        .complete_result(complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .lane1_complete_valid(lane1_complete_valid),
        .lane1_complete_tag(lane1_complete_tag),
        .lane1_complete_result(lane1_complete_result),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc(bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .pc_src(pc_src_exe),
        .pc_branch(pc_branch_exe),
        .recover_rat(recover_rat_exe),
        .csr_mstatus_value(csr_mstatus_value),
        .csr_mie_value(csr_mie_value),
        .branch_resolve(branch_resolve_exe)
    );

    assign issue_valid   = issue_if.valid;
    assign issue_fu_type = issue_if.data.fu_sel;
    assign issue_pc      = issue_if.data.datapath.pc;
    assign issue_imm     = issue_if.data.datapath.imm;

    assign rob_head_valid    = rob_head_valid_i;
    assign rob_head_complete = rob_head_complete_i;
    assign rob_head_rd       = rob_head.datapath.rd;

endmodule
