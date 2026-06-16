`timescale 1ns/1ps

module tb_dispatch_packet_stage_dual_issue;

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
    pip_if #(issue_exe_t) issue0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue1_if (.clk(clk), .rst_n(rst_n));

    dispatch_packet_stage dut (
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
        .issue_if(issue0_if.producer),
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
        lane.data.rs_entry.control_signal.rename = (rd != '0);
        lane.data.rs_entry.datapath.rob_tag = tag;
        lane.data.rs_entry.datapath.new_des_preg = new_preg;
        lane.data.rs_entry.datapath.src_reg_1p = preg_t'(1);
        lane.data.rs_entry.datapath.src_reg_2p = preg_t'(2);
        lane.data.rs_entry.datapath.pc = {24'h0, tag};
        lane.data.rob_entry.datapath.rob_tag = tag;
        lane.data.rob_entry.datapath.rd = rd;
        lane.data.rob_entry.datapath.new_des_preg = new_preg;
        lane.data.rob_entry.datapath.old_des_preg = preg_t'(rd);
    end
    endtask

    task automatic dispatch_pair(
        input logic [1:0] fu0,
        input logic [1:0] fu1,
        input rob_tag_t tag0,
        input rob_tag_t tag1
    );
    begin
        in_if.valid = 1'b1;
        set_lane(in_if.data.lane0, 1'b1, fu0, tag0, areg_t'(5), preg_t'(32));
        set_lane(in_if.data.lane1, 1'b1, fu1, tag1, areg_t'(6), preg_t'(33));
        #1;
        check_ok(in_if.ready, "dual-issue packet is accepted by dispatch");
        step_clk;
        in_if.valid = 1'b0;
        in_if.data = '0;
    end
    endtask

    task automatic complete_and_drain_pair(
        input rob_tag_t tag0,
        input rob_tag_t tag1
    );
    begin
        step_clk;
        complete_valid = 1'b1;
        complete_tag = tag0;
        complete_result = {24'h0, tag0};
        branch_complete_valid = 1'b1;
        branch_complete_tag = tag1;
        branch_complete_result = {24'h0, tag1};
        step_clk;

        complete_valid = 1'b0;
        branch_complete_valid = 1'b0;
        commit_en = 1'b1;
        commit_en1 = 1'b0;
        step_clk;
        step_clk;
        commit_en = 1'b0;
        check_ok(rob_empty, "ROB drains after dual-issued pair commits");
    end
    endtask

    task automatic complete_and_drain_alu_pair(
        input rob_tag_t tag0,
        input rob_tag_t tag1
    );
    begin
        step_clk;
        complete_valid = 1'b1;
        complete_tag = tag0;
        complete_result = {24'h0, tag0};
        lane1_complete_valid = 1'b1;
        lane1_complete_tag = tag1;
        lane1_complete_result = {24'h0, tag1};
        step_clk;

        complete_valid = 1'b0;
        lane1_complete_valid = 1'b0;
        commit_en = 1'b1;
        commit_en1 = 1'b0;
        step_clk;
        step_clk;
        commit_en = 1'b0;
        check_ok(rob_empty, "ROB drains after dual ALU pair commits");
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
        issue0_if.ready = 1'b1;
        issue1_if.ready = 1'b1;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(rob_empty, "dual-issue dispatch stage starts empty");

        dispatch_pair(FU_ALU, FU_ALU, rob_tag_t'(5), rob_tag_t'(6));
        check_ok(issue0_if.valid, "ALU/ALU packet asserts issue lane0");
        check_ok(issue1_if.valid, "ALU/ALU packet asserts issue lane1");
        check_ok(issue0_if.data.fu_sel == FU_ALU, "ALU/ALU places first ALU on lane0");
        check_ok(issue1_if.data.fu_sel == FU_ALU, "ALU/ALU places second ALU on lane1");
        check_ok(issue0_if.data.datapath.rob_tag == rob_tag_t'(5), "ALU/ALU lane0 tag preserved");
        check_ok(issue1_if.data.datapath.rob_tag == rob_tag_t'(6), "ALU/ALU lane1 tag preserved");
        complete_and_drain_alu_pair(rob_tag_t'(5), rob_tag_t'(6));

        dispatch_pair(FU_ALU, FU_MEM, rob_tag_t'(1), rob_tag_t'(2));
        check_ok(issue0_if.valid, "ALU/MEM packet asserts issue lane0");
        check_ok(issue1_if.valid, "ALU/MEM packet asserts issue lane1");
        check_ok(issue0_if.data.fu_sel == FU_MEM, "ALU/MEM places MEM on lane0");
        check_ok(issue1_if.data.fu_sel == FU_ALU, "ALU/MEM places ALU on lane1");
        check_ok(issue0_if.data.datapath.rob_tag == rob_tag_t'(2), "ALU/MEM lane0 MEM tag preserved");
        check_ok(issue1_if.data.datapath.rob_tag == rob_tag_t'(1), "ALU/MEM lane1 ALU tag preserved");
        complete_and_drain_pair(rob_tag_t'(2), rob_tag_t'(1));

        dispatch_pair(FU_BRANCH, FU_ALU, rob_tag_t'(3), rob_tag_t'(4));
        check_ok(issue0_if.valid, "BR/ALU packet asserts issue lane0");
        check_ok(issue1_if.valid, "BR/ALU packet asserts issue lane1");
        check_ok(issue0_if.data.fu_sel == FU_BRANCH, "BR/ALU prioritizes branch on lane0");
        check_ok(issue1_if.data.fu_sel == FU_ALU, "BR/ALU pairs ALU on lane1");
        check_ok(issue0_if.data.datapath.rob_tag == rob_tag_t'(3), "BR/ALU lane0 tag preserved");
        check_ok(issue1_if.data.datapath.rob_tag == rob_tag_t'(4), "BR/ALU lane1 tag preserved");
        complete_and_drain_pair(rob_tag_t'(3), rob_tag_t'(4));

        $display("==== tb_dispatch_packet_stage_dual_issue PASS ====");
        $finish;
    end

endmodule
