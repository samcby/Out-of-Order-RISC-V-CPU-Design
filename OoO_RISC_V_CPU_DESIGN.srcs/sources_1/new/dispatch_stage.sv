// Legacy scalar dispatch stage.
//
// Drives the original scalar ROB/reservation-station interfaces and stalls
// rename when the selected backend structure is full. It remains for top.sv;
// top_packet_backend routes packetized instructions through dispatch_packet_stage.
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
    output logic                           rob_head_complete,
    output logic                           rob_empty
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
    logic csr_pending_q;
    rob_tag_t csr_pending_tag_q;
    cp_mask_t csr_pending_mask_q;
    logic csr_dispatch_fire;
    logic csr_commit_fire;

    assign csr_dispatch_fire = alu_in_if.valid && alu_in_if.ready &&
                               (alu_in_if.data.control_signal.csr_en ||
                                alu_in_if.data.control_signal.sys_en);
    assign csr_commit_fire = csr_pending_q &&
                             commit_en &&
                             rob_head_valid &&
                             (rob_head.datapath.rob_tag == csr_pending_tag_q);

    dispatch_logic u_dispatch_logic (
        .in_if         (in_if),
        .src1_ready    (src1_ready),
        .src2_ready    (src2_ready),
        .src1_value    (src1_value),
        .src2_value    (src2_value),
        .branch_pending(branch_pending),
        .csr_pending   (csr_pending_q),
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
        .wb_is_fp (1'b0),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .wb1_valid(1'b0),
        .wb1_is_fp(1'b0),
        .wb1_preg ('0),
        .wb1_result('0),
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
        .OPERATION(FU_MEM),
        .SINGLE_ENTRY(1'b1)
    ) u_rs_lsu (
        .wb_valid (wb_valid),
        .wb_is_fp (1'b0),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .wb1_valid(1'b0),
        .wb1_is_fp(1'b0),
        .wb1_preg ('0),
        .wb1_result('0),
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
        .wb_is_fp (1'b0),
        .wb_preg  (wb_preg),
        .wb_result(wb_result),
        .wb1_valid(1'b0),
        .wb1_is_fp(1'b0),
        .wb1_preg ('0),
        .wb1_result('0),
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
        .empty           (rob_empty)
    );

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            csr_pending_q     <= 1'b0;
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
