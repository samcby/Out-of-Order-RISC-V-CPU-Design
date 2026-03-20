module top (
    input  logic clk,
    input  logic rst_n,

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

    pip_if #(fetch_decode_t) pipe_fd       (.clk(clk), .rst_n(rst_n));
    pip_if #(fetch_decode_t) pipe_fd_s     (.clk(clk), .rst_n(rst_n));

    pip_if #(decode_rat_t)   pipe_dr       (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_t)   pipe_dr_s     (.clk(clk), .rst_n(rst_n));

    pip_if #(rat_dis_t)      pipe_rd       (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_t)      pipe_rd_s     (.clk(clk), .rst_n(rst_n));

    pip_if #(issue_exe_t)    issue_if      (.clk(clk), .rst_n(rst_n));

    logic src1_ready;
    logic src2_ready;

    logic [WIDTH-1:0] prf_rdata0;
    logic [WIDTH-1:0] prf_rdata1;

    rob_t rob_head;

    logic           wb_valid;
    preg_t          wb_preg;
    rob_tag_t       wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic           complete_valid;
    rob_tag_t       complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic           branch_complete_valid;
    rob_tag_t       branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;

    logic           retire_valid;
    preg_t          retire_preg;
    logic           commit_en;

    logic           pc_src_exe;
    logic [WIDTH-1:0] pc_branch_exe;

    logic flush_exe;

    logic flush_front;
    logic branch_pending_q;
    logic branch_resolve_exe;
    logic [CHECKPOINT_W-1:0] resolve_checkpoint_id_exe;
    logic [CHECKPOINT_NUM-1:0] active_checkpoint_mask_q;
    logic branch_dispatch_fire;
    logic branch_rename_fire;
    logic bp_update_valid_exe;
    logic [WIDTH-1:0] bp_update_pc_exe;
    logic bp_update_taken_exe;
    logic bp_update_is_jalr_exe;
    logic [WIDTH-1:0] bp_update_target_exe;
    
    assign flush_exe = pc_src_exe;    
    
    assign flush_front = pc_src_exe;

    assign branch_dispatch_fire =
        pipe_rd_s.valid && pipe_rd_s.ready &&
        (pipe_rd_s.data.rs_entry.control_signal.fu_type == FU_BRANCH);

    assign branch_rename_fire =
        pipe_rd.valid && pipe_rd.ready &&
        (pipe_rd.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    

    assign commit_en    = rob_head_valid && rob_head_complete;
    assign retire_valid = commit_en &&
                          (rob_head.datapath.new_des_preg != '0) &&
                          (rob_head.datapath.rd != '0);
    assign retire_preg  = rob_head.datapath.old_des_preg;


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_checkpoint_mask_q <= '0;
        end else begin
            if (branch_resolve_exe) begin
                active_checkpoint_mask_q[resolve_checkpoint_id_exe] <= 1'b0;
            end

            if (branch_rename_fire) begin
                active_checkpoint_mask_q[pipe_rd.data.rs_entry.datapath.checkpoint_id] <= 1'b1;
            end
        end
    end

    assign branch_pending_q = |active_checkpoint_mask_q;


    fetch_stage u_fetch (
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        // Phase 4 再正式把恢复/flush 接完整，这里先不驱动 fetch redirect
        .pc_src         (pc_src_exe),
        .pc_branch      (pc_branch_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc   (bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .out_if         (pipe_fd.producer)
    );

    skid_buffer_pipe #(
        .T(fetch_decode_t)
    ) u_skid_fd (
        .flush (flush_exe),
        .in_if (pipe_fd.consumer),
        .out_if(pipe_fd_s.producer)
    );

    decode_stage u_decode (
        .in_if (pipe_fd_s.consumer),
        .out_if(pipe_dr.producer)
    );

    skid_buffer_pipe #(
        .T(decode_rat_t)
    ) u_skid_dr (
        .flush (flush_exe),
        .in_if (pipe_dr.consumer),
        .out_if(pipe_dr_s.producer)
    );

    rename_stage u_rename (
        .flush               (1'b0),
        .restore_rat         (pc_src_exe),
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
        .squash_en        (pc_src_exe),
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
        .rob_head_valid   (rob_head_valid),
        .rob_head_complete(rob_head_complete)
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
        .wb_valid       (wb_valid),
        .wb_preg        (wb_preg),
        .wb_tag         (wb_tag),
        .wb_result      (wb_result),
        .complete_valid (complete_valid),
        .complete_tag   (complete_tag),
        .complete_result(complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .resolve_checkpoint_id(resolve_checkpoint_id_exe),
        .bp_update_valid(bp_update_valid_exe),
        .bp_update_pc   (bp_update_pc_exe),
        .bp_update_taken(bp_update_taken_exe),
        .bp_update_is_jalr(bp_update_is_jalr_exe),
        .bp_update_target(bp_update_target_exe),
        .pc_src         (pc_src_exe),
        .pc_branch      (pc_branch_exe),
        .branch_resolve (branch_resolve_exe)
    );

    assign issue_valid   = issue_if.valid;
    assign issue_fu_type = issue_if.data.fu_sel;
    assign issue_pc      = issue_if.data.datapath.pc;
    assign issue_imm     = issue_if.data.datapath.imm;

    assign rob_head_rd   = rob_head.datapath.rd;

endmodule

