module dispatch_stage (
    input  logic                           src1_ready,
    input  logic                           src2_ready,
    input  logic [defines_pkg::WIDTH-1:0]  src1_value,
    input  logic [defines_pkg::WIDTH-1:0]  src2_value,

    input  logic                           wb_valid,
    input  defines_pkg::preg_t             wb_preg,
    input  defines_pkg::rob_tag_t          wb_tag,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           complete_valid,
    input  defines_pkg::rob_tag_t          complete_tag,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result,
    input  logic                           branch_complete_valid,
    input  defines_pkg::rob_tag_t          branch_complete_tag,
    input  logic [defines_pkg::WIDTH-1:0]  branch_complete_result,

    input  logic                           commit_en,
    input  logic                           flush,
    input  logic                           branch_pending,
    input  logic [defines_pkg::CHECKPOINT_NUM-1:0] active_checkpoint_mask,
    input  logic                           squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic                           resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    pip_if.consumer in_if,
    pip_if.producer issue_if,

    output defines_pkg::rob_t              rob_head,
    output logic                           rob_head_valid,
    output logic                           rob_head_complete
);
    import defines_pkg::*;

    pip_if #(rob_t)       rob_if        (.clk(in_if.clk), .rst_n(in_if.rst_n));

    pip_if #(alu_rs_t)    alu_in_if     (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_in_if     (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(branch_rs_t) branch_in_if  (.clk(in_if.clk), .rst_n(in_if.rst_n));

    pip_if #(alu_rs_t)    alu_out_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(lsu_rs_t)    lsu_out_if    (.clk(in_if.clk), .rst_n(in_if.rst_n));
    pip_if #(branch_rs_t) branch_out_if (.clk(in_if.clk), .rst_n(in_if.rst_n));

    logic [1:0] fu_sel;

    dispatch_logic u_dispatch_logic (
        .in_if         (in_if),
        .src1_ready    (src1_ready),
        .src2_ready    (src2_ready),
        .src1_value    (src1_value),
        .src2_value    (src2_value),
        .branch_pending(branch_pending),
        .active_checkpoint_mask(active_checkpoint_mask),
        .rob_if        (rob_if.producer),
        .alu_if        (alu_in_if.producer),
        .lsu_if        (lsu_in_if.producer),
        .branch_if     (branch_in_if.producer)
    );

    rs #(
        .T(alu_rs_t),
        .OPERATION(FU_ALU)
    ) u_rs_alu (
        .wb_valid (wb_valid),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .fu_sel   (fu_sel),
        .flush    (flush),        
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if    (alu_in_if.consumer),
        .out_if   (alu_out_if.producer)
    );

    rs #(
        .T(lsu_rs_t),
        .OPERATION(FU_MEM)
    ) u_rs_lsu (
        .wb_valid (wb_valid),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .fu_sel   (fu_sel),
        .flush    (flush), 
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if    (lsu_in_if.consumer),
        .out_if   (lsu_out_if.producer)
    );

    rs #(
        .T(branch_rs_t),
        .OPERATION(FU_BRANCH)
    ) u_rs_branch (
        .wb_valid (wb_valid),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .fu_sel   (fu_sel),
        .flush    (flush), 
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if    (branch_in_if.consumer),
        .out_if   (branch_out_if.producer)
    );

    issue_arbiter u_issue_arbiter (
        .alu_if    (alu_out_if.consumer),
        .lsu_if    (lsu_out_if.consumer),
        .branch_if (branch_out_if.consumer),
        .issue_if  (issue_if),
        .fu_sel    (fu_sel)
    );

    rob u_rob (
        .rob_if_in       (rob_if.consumer),
        .complete_en0    (complete_valid),
        .complete_tag0   (complete_tag),
        .complete_result0(complete_result),
        .complete_en1    (branch_complete_valid),
        .complete_tag1   (branch_complete_tag),
        .complete_result1(branch_complete_result),
        .commit_en       (commit_en),
        .head_entry      (rob_head),
        .head_valid      (rob_head_valid),
        .head_complete   (rob_head_complete),
        .flush           (flush),        
        .squash_en       (squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en      (resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .full            (),
        .empty           ()
    );

endmodule
