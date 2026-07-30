`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for dispatch packet stage.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_dispatch_packet_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic lane0_src1_ready;
    logic lane0_src2_ready;
    logic [WIDTH-1:0] lane0_src1_value;
    logic [WIDTH-1:0] lane0_src2_value;
    logic lane1_src1_ready;
    logic lane1_src2_ready;
    logic [WIDTH-1:0] lane1_src1_value;
    logic [WIDTH-1:0] lane1_src2_value;
    logic wb_valid;
    preg_t wb_preg;
    rob_tag_t wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic wb1_valid;
    preg_t wb1_preg;
    rob_tag_t wb1_tag;
    logic [WIDTH-1:0] wb1_result;
    logic complete_valid;
    rob_tag_t complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic branch_complete_valid;
    rob_tag_t branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;
    logic lane1_complete_valid;
    rob_tag_t lane1_complete_tag;
    logic [WIDTH-1:0] lane1_complete_result;
    logic commit_en;
    logic commit_en1;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    rob_t rob_head;
    rob_t rob_head1;
    logic rob_head_valid;
    logic rob_head_complete;
    logic rob_head1_valid;
    logic rob_head1_complete;
    logic rob_empty;

    pip_if #(rat_dis_packet_t) in_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue1_if (.clk(clk), .rst_n(rst_n));

    dispatch_packet_stage dut (
        .halt(1'b0),
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
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if(in_if.consumer),
        .issue_if(issue_if.producer),
        .issue1_if(issue1_if.producer),
        .rob_head(rob_head),
        .rob_head_valid(rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head1(rob_head1),
        .rob_head1_valid(rob_head1_valid),
        .rob_head1_complete(rob_head1_complete),
        .rob_empty(rob_empty)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic set_lane(
        output rat_dis_lane_t lane,
        input  logic          valid,
        input  logic [1:0]    fu_type,
        input  rob_tag_t      tag,
        input  areg_t         rd,
        input  preg_t         new_preg
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.rs_entry.control_signal.fu_type = fu_type;
        lane.data.rs_entry.datapath.rob_tag = tag;
        lane.data.rs_entry.datapath.new_des_preg = new_preg;
        lane.data.rs_entry.datapath.src_reg_1p = preg_t'(1);
        lane.data.rs_entry.datapath.src_reg_2p = preg_t'(2);
        lane.data.rob_entry.datapath.rob_tag = tag;
        lane.data.rob_entry.datapath.rd = rd;
        lane.data.rob_entry.datapath.new_des_preg = new_preg;
        lane.data.rob_entry.datapath.old_des_preg = preg_t'(rd);
    end
    endtask

    initial begin
        rst_n = 1'b0;
        lane0_src1_ready = 1'b1;
        lane0_src2_ready = 1'b1;
        lane0_src1_value = 32'h1111_0001;
        lane0_src2_value = 32'h1111_0002;
        lane1_src1_ready = 1'b1;
        lane1_src2_ready = 1'b1;
        lane1_src1_value = 32'h2222_0001;
        lane1_src2_value = 32'h2222_0002;
        wb_valid = 1'b0;
        wb_preg = '0;
        wb_tag = '0;
        wb_result = '0;
        wb1_valid = 1'b0;
        wb1_preg = '0;
        wb1_tag = '0;
        wb1_result = '0;
        complete_valid = 1'b0;
        complete_tag = '0;
        complete_result = '0;
        branch_complete_valid = 1'b0;
        branch_complete_tag = '0;
        branch_complete_result = '0;
        lane1_complete_valid = 1'b0;
        lane1_complete_tag = '0;
        lane1_complete_result = '0;
        commit_en = 1'b0;
        commit_en1 = 1'b0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        issue_if.ready = 1'b1;
        issue1_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(rob_empty, "packet dispatch stage ROB starts empty");

        in_if.valid = 1'b1;
        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(1), areg_t'(5), preg_t'(32));
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(2), areg_t'(6), preg_t'(33));
        #1;
        check_ok(in_if.ready, "stage accepts mixed ALU/MEM packet");
        step_clk;

        in_if.valid = 1'b0;
        check_ok(rob_head_valid, "ROB has head after packet dispatch");
        check_ok(rob_head.datapath.rob_tag == rob_tag_t'(1), "ROB head is older lane");

        check_ok(issue_if.valid, "first ready instruction issues");
        check_ok(issue_if.data.fu_sel == FU_ALU, "ALU issues before LSU under arbiter priority");
        check_ok(issue_if.data.datapath.rob_tag == rob_tag_t'(1), "issued ALU carries lane0 tag");
        step_clk;

        check_ok(issue_if.valid, "second ready instruction issues");
        check_ok(issue_if.data.fu_sel == FU_MEM, "LSU issues after ALU");
        check_ok(issue_if.data.datapath.rob_tag == rob_tag_t'(2), "issued LSU carries lane1 tag");
        step_clk;

        complete_valid = 1'b1;
        complete_tag = rob_tag_t'(1);
        complete_result = 32'hAAAA_0001;
        branch_complete_valid = 1'b1;
        branch_complete_tag = rob_tag_t'(2);
        branch_complete_result = 32'hBBBB_0002;
        step_clk;

        complete_valid = 1'b0;
        branch_complete_valid = 1'b0;
        check_ok(rob_head_complete, "ROB head completes after complete port writeback");
        check_ok(rob_head.datapath.result == 32'hAAAA_0001, "ROB head result is stored");

        commit_en = 1'b1;
        step_clk;
        check_ok(rob_head_valid, "second ROB entry becomes head");
        check_ok(rob_head.datapath.rob_tag == rob_tag_t'(2), "second ROB head preserves order");
        check_ok(rob_head_complete, "second ROB entry is already complete");

        step_clk;
        commit_en = 1'b0;
        check_ok(rob_empty, "packet dispatch stage ROB drains after two commits");

        in_if.valid = 1'b1;
        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(3), areg_t'(7), preg_t'(34));
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(4), areg_t'(8), preg_t'(35));
        #1;
        check_ok(in_if.ready, "stage accepts duplicate ALU packet with the two-write RS");

        $display("==== tb_dispatch_packet_stage PASS ====");
        $finish;
    end

endmodule
