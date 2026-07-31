`timescale 1ns / 1ps

// Stateful two-wide dispatch coordinator.
//
// Wraps dispatch_packet_logic with the ROB, ALU/FP reservation station, branch
// reservation station, memory-order queue, and issue arbiter. Its ready signal
// represents an atomic promise: once a packet transfers, all required entries
// are allocated in the same cycle, so no instruction can exist in a queue
// without a matching ROB entry.
//
// Writeback broadcasts update queue readiness, while branch recovery squashes
// younger entries using their speculation masks. CSR-pending tracking limits
// side-effecting CSR/system instructions to a safe serialized path.
module dispatch_packet_stage #(
    parameter bit ENABLE_2WIDE = 1'b1,
    parameter bit ENABLE_DUAL_MEM = 1'b0
)(
    input  logic                           halt,
    input  logic                           lane0_src1_ready,
    input  logic                           lane0_src2_ready,
    input  logic                           lane0_src3_ready,
    input  logic [defines_pkg::WIDTH-1:0]  lane0_src1_value,
    input  logic [defines_pkg::WIDTH-1:0]  lane0_src2_value,
    input  logic [defines_pkg::WIDTH-1:0]  lane0_src3_value,
    input  logic                           lane1_src1_ready,
    input  logic                           lane1_src2_ready,
    input  logic                           lane1_src3_ready,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_src1_value,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_src2_value,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_src3_value,

    input  logic                           wb_valid,
    input  logic                           wb_is_fp,
    input  defines_pkg::preg_t             wb_preg,
    input  defines_pkg::rob_tag_t          wb_tag,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           wb1_valid,
    input  logic                           wb1_is_fp,
    input  defines_pkg::preg_t             wb1_preg,
    input  defines_pkg::rob_tag_t          wb1_tag,
    input  logic [defines_pkg::WIDTH-1:0]  wb1_result,
    input  logic                           complete_valid,
    input  defines_pkg::rob_tag_t          complete_tag,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result,
    input  logic [4:0]                     complete_fp_flags,
    input  logic                           complete_exception_valid,
    input  logic [defines_pkg::WIDTH-1:0]  complete_exception_cause,
    input  logic [defines_pkg::WIDTH-1:0]  complete_exception_tval,
    input  logic                           branch_complete_valid,
    input  defines_pkg::rob_tag_t          branch_complete_tag,
    input  logic [defines_pkg::WIDTH-1:0]  branch_complete_result,
    input  logic                           branch_complete_exception_valid,
    input  logic [defines_pkg::WIDTH-1:0]  branch_complete_exception_cause,
    input  logic [defines_pkg::WIDTH-1:0]  branch_complete_exception_tval,
    input  logic                           lane1_complete_valid,
    input  defines_pkg::rob_tag_t          lane1_complete_tag,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_complete_result,
    input  logic [4:0]                     lane1_complete_fp_flags,
    input  logic                           lane1_complete_exception_valid,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_complete_exception_cause,
    input  logic [defines_pkg::WIDTH-1:0]  lane1_complete_exception_tval,

    input  logic                           commit_en0,
    input  logic                           commit_en1,
    input  logic                           flush,
    input  logic                           squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic                           resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    pip_if.consumer in_if,
    pip_if.producer issue_if,
    pip_if.producer issue1_if,

    output defines_pkg::rob_t              rob_head,
    output logic                           rob_head_valid,
    output logic                           rob_head_complete,
    output defines_pkg::rob_t              rob_head1,
    output logic                           rob_head1_valid,
    output logic                           rob_head1_complete,
    output logic                           rob_empty,
    output logic                           memory_replay_valid,
    output defines_pkg::rob_tag_t          memory_replay_tag,
    output logic [defines_pkg::WIDTH-1:0]  memory_replay_pc,
    output defines_pkg::cp_mask_t          memory_replay_speculation_mask
);
    import defines_pkg::*;

    pip_if #(rat_dis_packet_t) rob_packet_if (.clk(in_if.clk), .rst_n(in_if.rst_n));

    pip_if #(alu_rs_t)    alu_in_if     (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(alu_rs_t)    alu_in1_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_in_if     (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_in1_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(branch_rs_t) branch_in_if  (.clk(in_if.clk), .rst_n(in_if.rst_n));

    pip_if #(alu_rs_t)    alu_out_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(alu_rs_t)    alu_out1_if   (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_out_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_out1_if   (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(branch_rs_t) branch_out_if (.clk(in_if.clk), .rst_n(in_if.rst_n));

    logic [1:0] fu_sel;
    logic [1:0] issue1_fu_sel;
    logic csr_pending_q;
    rob_tag_t csr_pending_tag_q;
    cp_mask_t csr_pending_mask_q;
    logic csr_dispatch_fire;
    logic csr_commit_fire;

    assign csr_dispatch_fire = alu_in_if.valid && alu_in_if.ready &&
                               (alu_in_if.data.control_signal.csr_en ||
                                alu_in_if.data.control_signal.sys_en);
    assign csr_commit_fire = csr_pending_q &&
                             ((commit_en0 &&
                               rob_head_valid &&
                               (rob_head.datapath.rob_tag == csr_pending_tag_q)) ||
                              (commit_en1 &&
                               rob_head1_valid &&
                               (rob_head1.datapath.rob_tag == csr_pending_tag_q)));

    dispatch_packet_logic u_dispatch_packet_logic (
        .in_if(in_if),
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
        .halt(halt),
        .csr_pending(csr_pending_q),
        .rob_empty(rob_empty),
        .rob_packet_if(rob_packet_if.producer),
        .alu_if(alu_in_if.producer),
        .alu1_if(alu_in1_if.producer),
        .lsu_if(lsu_in_if.producer),
        .lsu1_if(lsu_in1_if.producer),
        .branch_if(branch_in_if.producer)
    );

    rs_2issue #(
        .T(alu_rs_t)
    ) u_rs_alu (
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if(alu_in_if.consumer),
        .in1_if(alu_in1_if.consumer),
        .out0_if(alu_out_if.producer),
        .out1_if(alu_out1_if.producer)
    );

    load_store_queue u_load_store_queue (
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .complete_valid0(complete_valid),
        .complete_tag0(complete_tag),
        .complete_valid1(lane1_complete_valid),
        .complete_tag1(lane1_complete_tag),
        .commit_valid0(commit_en0),
        .commit_tag0(rob_head.datapath.rob_tag),
        .commit_valid1(commit_en1),
        .commit_tag1(rob_head1.datapath.rob_tag),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in0_if(lsu_in_if.consumer),
        .in1_if(lsu_in1_if.consumer),
        .out0_if(lsu_out_if.producer),
        .out1_if(lsu_out1_if.producer),
        .replay_valid(memory_replay_valid),
        .replay_tag(memory_replay_tag),
        .replay_pc(memory_replay_pc),
        .replay_speculation_mask(memory_replay_speculation_mask)
    );

    rs #(
        .T(branch_rs_t),
        .OPERATION(FU_BRANCH)
    ) u_rs_branch (
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .fu_sel(fu_sel),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if(branch_in_if.consumer),
        .out_if(branch_out_if.producer)
    );

    issue_packet_arbiter #(
        .ENABLE_2WIDE(ENABLE_2WIDE),
        .ENABLE_DUAL_MEM(ENABLE_DUAL_MEM)
    ) u_issue_packet_arbiter (
        .alu_if(alu_out_if.consumer),
        .alu1_if(alu_out1_if.consumer),
        .lsu_if(lsu_out_if.consumer),
        .lsu1_if(lsu_out1_if.consumer),
        .branch_if(branch_out_if.consumer),
        .issue0_if(issue_if),
        .issue1_if(issue1_if),
        .rob_head_valid(rob_head_valid),
        .rob_head_tag(rob_head.datapath.rob_tag),
        .issue0_fu_sel(fu_sel),
        .issue1_fu_sel(issue1_fu_sel)
    );

    rob_2w u_rob_2w (
        .rob_packet_if(rob_packet_if.consumer),
        .complete_en0(complete_valid),
        .complete_tag0(complete_tag),
        .complete_result0(complete_result),
        .complete_fp_flags0(complete_fp_flags),
        .complete_exception_valid0(complete_exception_valid),
        .complete_exception_cause0(complete_exception_cause),
        .complete_exception_tval0(complete_exception_tval),
        .complete_en1(branch_complete_valid),
        .complete_tag1(branch_complete_tag),
        .complete_result1(branch_complete_result),
        .complete_fp_flags1('0),
        .complete_exception_valid1(branch_complete_exception_valid),
        .complete_exception_cause1(branch_complete_exception_cause),
        .complete_exception_tval1(branch_complete_exception_tval),
        .complete_en2(lane1_complete_valid),
        .complete_tag2(lane1_complete_tag),
        .complete_result2(lane1_complete_result),
        .complete_fp_flags2(lane1_complete_fp_flags),
        .complete_exception_valid2(lane1_complete_exception_valid),
        .complete_exception_cause2(lane1_complete_exception_cause),
        .complete_exception_tval2(lane1_complete_exception_tval),
        .commit_en0(commit_en0),
        .commit_en1(commit_en1),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .head_entry(rob_head),
        .head_valid(rob_head_valid),
        .head_complete(rob_head_complete),
        .head1_entry(rob_head1),
        .head1_valid(rob_head1_valid),
        .head1_complete(rob_head1_complete),
        .full(),
        .empty(rob_empty)
    );

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            csr_pending_q <= 1'b0;
            csr_pending_tag_q <= '0;
            csr_pending_mask_q <= '0;
        end else begin
            if (squash_en && csr_pending_mask_q[squash_checkpoint_id]) begin
                csr_pending_q <= 1'b0;
                csr_pending_tag_q <= '0;
                csr_pending_mask_q <= '0;
            end else if (csr_commit_fire) begin
                csr_pending_q <= 1'b0;
                csr_pending_tag_q <= '0;
                csr_pending_mask_q <= '0;
            end

            if (resolve_en) begin
                csr_pending_mask_q[resolve_checkpoint_id] <= 1'b0;
            end

            if (csr_dispatch_fire) begin
                csr_pending_q <= 1'b1;
                csr_pending_tag_q <= alu_in_if.data.datapath.rob_tag;
                csr_pending_mask_q <= alu_in_if.data.datapath.speculation_mask;
            end
        end
    end

endmodule
