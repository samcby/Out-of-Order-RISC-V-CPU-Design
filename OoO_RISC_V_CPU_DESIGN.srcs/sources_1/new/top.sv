// Legacy scalar-oriented integration top.
// New development should target top_packet_backend.sv unless explicitly
// validating backward compatibility with the original scalar path.
module top (
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

    pip_if #(decode_rat_packet_t)   pipe_dr_pkt   (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_packet_t)   pipe_dr_pkt_s (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_t)          pipe_dr_s     (.clk(clk), .rst_n(rst_n));

    pip_if #(rat_dis_t)      pipe_rd       (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_t)      pipe_rd_s     (.clk(clk), .rst_n(rst_n));

    pip_if #(issue_exe_t)    issue_if      (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t)    issue1_dummy_if (.clk(clk), .rst_n(rst_n));

    logic src1_ready;
    logic src2_ready;

    logic [WIDTH-1:0] prf_rdata0;
    logic [WIDTH-1:0] prf_rdata1;

    rob_t rob_head;
    logic rob_head_valid_i;
    logic rob_head_complete_i;
    logic rob_empty_i;

    logic           wb_valid;
    preg_t          wb_preg;
    rob_tag_t       wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic           wb1_dummy_valid;
    preg_t          wb1_dummy_preg;
    rob_tag_t       wb1_dummy_tag;
    logic [WIDTH-1:0] wb1_dummy_result;
    logic           complete_valid;
    rob_tag_t       complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic           branch_complete_valid;
    rob_tag_t       branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;
    logic           lane1_dummy_complete_valid;
    rob_tag_t       lane1_dummy_complete_tag;
    logic [WIDTH-1:0] lane1_dummy_complete_result;

    logic           retire_valid;
    preg_t          retire_preg;
    logic           commit_en;

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

    logic flush_front;
    logic branch_pending_q;
    logic branch_resolve_exe;
    logic [CHECKPOINT_W-1:0] resolve_checkpoint_id_exe;
    logic [CHECKPOINT_NUM-1:0] active_checkpoint_mask_q;
    logic [CHECKPOINT_NUM-1:0] checkpoint_dep_mask_q [0:CHECKPOINT_NUM-1];
    logic [CHECKPOINT_NUM-1:0] checkpoint_kill_mask;
    logic [CHECKPOINT_NUM-1:0] checkpoint_alloc_dep_mask;
    logic branch_dispatch_fire;
    logic branch_rename_fire;
    logic bp_update_valid_exe;
    logic [WIDTH-1:0] bp_update_pc_exe;
    logic bp_update_taken_exe;
    logic bp_update_is_jalr_exe;
    logic [WIDTH-1:0] bp_update_target_exe;
    
    assign flush_exe = pc_src_exe || interrupt_take;    
    
    assign flush_front = pc_src_exe;

    assign branch_dispatch_fire =
        pipe_rd_s.valid && pipe_rd_s.ready &&
        (pipe_rd_s.data.rs_entry.control_signal.fu_type == FU_BRANCH);

    assign branch_rename_fire =
        pipe_rd.valid && pipe_rd.ready &&
        (pipe_rd.data.rs_entry.control_signal.fu_type == FU_BRANCH);

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
    assign interrupt_take     = rob_empty_i &&
                                (external_irq_enabled ||
                                 software_irq_enabled ||
                                 timer_irq_enabled);
    assign interrupt_mcause   = external_irq_enabled ? MCAUSE_MEI :
                                software_irq_enabled ? MCAUSE_MSI :
                                MCAUSE_MTI;
    assign interrupt_mepc     = (pipe_fd_pkt_s.valid && pipe_fd_pkt_s.data.lane0.valid) ?
                                pipe_fd_pkt_s.data.lane0.data.pc :
                                (pipe_dr_pkt_s.valid && pipe_dr_pkt_s.data.lane0.valid) ?
                                pipe_dr_pkt_s.data.lane0.data.datapath.pc :
                                (pipe_dr_pkt.valid && pipe_dr_pkt.data.lane0.valid) ?
                                pipe_dr_pkt.data.lane0.data.datapath.pc :
                                pipe_dr_s.valid ? pipe_dr_s.data.datapath.pc :
                                32'b0;
    

    assign commit_en    = rob_head_valid_i && rob_head_complete_i;
    assign retire_valid = commit_en &&
                          (rob_head.datapath.new_des_preg != '0) &&
                          (rob_head.datapath.rd != '0);
    assign retire_preg  = rob_head.datapath.old_des_preg;
    assign issue1_dummy_if.valid = 1'b0;
    assign issue1_dummy_if.data  = '0;


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
                active_checkpoint_mask_q[pipe_rd.data.rs_entry.datapath.checkpoint_id] <= 1'b1;
                checkpoint_dep_mask_q[pipe_rd.data.rs_entry.datapath.checkpoint_id] <= checkpoint_alloc_dep_mask;
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
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        .pc_src         (pc_src_exe),
        .pc_branch      (pc_branch_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc   (bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .out_if(pipe_fd_pkt.producer)
    );

    skid_buffer_pipe #(
        .T(fetch_decode_packet_t)
    ) u_skid_fd (
        .flush (flush_exe),
        .in_if (pipe_fd_pkt.consumer),
        .out_if(pipe_fd_pkt_s.producer)
    );

    decode_packet_stage u_decode (
        .in_if (pipe_fd_pkt_s.consumer),
        .out_if(pipe_dr_pkt.producer)
    );

    skid_buffer_pipe #(
        .T(decode_rat_packet_t)
    ) u_skid_dr (
        .flush (flush_exe),
        .in_if (pipe_dr_pkt.consumer),
        .out_if(pipe_dr_pkt_s.producer)
    );

    decode_packet_lane0_adapter u_decode_packet_lane0_adapter (
        .flush (flush_exe),
        .in_if (pipe_dr_pkt_s.consumer),
        .out_if(pipe_dr_s.producer)
    );

    rename_stage u_rename (
        .flush               (1'b0),
        .restore_rat         (recover_rat_exe),
        .restore_checkpoint_id(resolve_checkpoint_id_exe),
        .active_checkpoint_mask(active_checkpoint_mask_q),
        .in_if               (pipe_dr_s.consumer),
        .out_if              (pipe_rd.producer),
        .retire_valid        (retire_valid),
        .retire_preg         (retire_preg)
    );

    skid_buffer_pipe #(
        .T(rat_dis_t)
    ) u_skid_rd (
        .flush (flush_exe),
        .in_if (pipe_rd.consumer),
        .out_if(pipe_rd_s.producer)
    );

    dispatch_stage u_dispatch (
        .flush            (1'b0),
        .branch_pending   (branch_pending_q),
        .active_checkpoint_mask(active_checkpoint_mask_q),
        .squash_en        (recover_rat_exe),
        .squash_checkpoint_id(resolve_checkpoint_id_exe),
        .resolve_en       (branch_resolve_exe),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .src1_ready       (src1_ready),
        .src2_ready       (src2_ready),
        .src1_value       (prf_rdata0),
        .src2_value       (prf_rdata1),
        .wb_valid         (wb_valid),
        .wb_preg          (wb_preg),
        .wb_tag           (wb_tag),
        .wb_result        (wb_result),
        .complete_valid   (complete_valid),
        .complete_tag     (complete_tag),
        .complete_result  (complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .commit_en        (commit_en),
        .in_if            (pipe_rd_s.consumer),
        .issue_if         (issue_if.producer),
        .rob_head         (rob_head),
        .rob_head_valid   (rob_head_valid_i),
        .rob_head_complete(rob_head_complete_i),
        .rob_empty        (rob_empty_i)
    );

    reg_file u_prf (
        .clk            (clk),
        .rst_n          (rst_n),
        .w_en           (wb_valid),
        .w_addr         (wb_preg),
        .w_data         (wb_result),
        .raddr0         (pipe_rd_s.data.rs_entry.datapath.src_reg_1p),
        .rdata0         (prf_rdata0),
        .raddr1         (pipe_rd_s.data.rs_entry.datapath.src_reg_2p),
        .rdata1         (prf_rdata1),
        .rename_en      (pipe_rd_s.valid && pipe_rd_s.ready &&
                         pipe_rd_s.data.rs_entry.control_signal.rename),
        .src1_valid_addr(pipe_rd_s.data.rs_entry.datapath.src_reg_1p),
        .src2_valid_addr(pipe_rd_s.data.rs_entry.datapath.src_reg_2p),
        .new_des_preg   (pipe_rd_s.data.rs_entry.datapath.new_des_preg),
        .src1_ready     (src1_ready),
        .src2_ready     (src2_ready)
    );

    execution_stage u_execution (
        .in_if          (issue_if.consumer),
        .in1_if         (issue1_dummy_if.consumer),
        .software_irq_pending(software_irq_pending_q),
        .timer_irq_pending(timer_irq_pending_q),
        .external_irq_pending(external_irq_pending_q),
        .interrupt_take (interrupt_take),
        .interrupt_mepc (interrupt_mepc),
        .interrupt_mcause(interrupt_mcause),
        .wb_valid       (wb_valid),
        .wb_preg        (wb_preg),
        .wb_tag         (wb_tag),
        .wb_result      (wb_result),
        .wb1_valid      (wb1_dummy_valid),
        .wb1_preg       (wb1_dummy_preg),
        .wb1_tag        (wb1_dummy_tag),
        .wb1_result     (wb1_dummy_result),
        .complete_valid (complete_valid),
        .complete_tag   (complete_tag),
        .complete_result(complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .lane1_complete_valid(lane1_dummy_complete_valid),
        .lane1_complete_tag(lane1_dummy_complete_tag),
        .lane1_complete_result(lane1_dummy_complete_result),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc   (bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .pc_src         (pc_src_exe),
        .pc_branch      (pc_branch_exe),
        .recover_rat    (recover_rat_exe),
        .csr_mstatus_value(csr_mstatus_value),
        .csr_mie_value  (csr_mie_value),
        .branch_resolve (branch_resolve_exe)
    );

    assign issue_valid   = issue_if.valid;
    assign issue_fu_type = issue_if.data.fu_sel;
    assign issue_pc      = issue_if.data.datapath.pc;
    assign issue_imm     = issue_if.data.datapath.imm;

    assign rob_head_valid    = rob_head_valid_i;
    assign rob_head_complete = rob_head_complete_i;
    assign rob_head_rd   = rob_head.datapath.rd;

endmodule

