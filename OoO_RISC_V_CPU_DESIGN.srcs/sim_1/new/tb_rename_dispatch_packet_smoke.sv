`timescale 1ns/1ps

module tb_rename_dispatch_packet_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic flush;
    logic restore_rat;
    cp_id_t restore_checkpoint_id;
    cp_mask_t active_checkpoint_mask;
    logic [1:0] retire_valid;
    preg_t retire_preg0;
    preg_t retire_preg1;

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

    pip_if #(decode_rat_packet_t) decode_packet_if (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t)    rename_packet_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t)         issue_if         (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t)         issue1_if        (.clk(clk), .rst_n(rst_n));

    rename_packet_stage u_rename_packet_stage (
        .flush(flush),
        .restore_rat(restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .active_checkpoint_mask(active_checkpoint_mask),
        .in_if(decode_packet_if.consumer),
        .out_if(rename_packet_if.producer),
        .retire_valid(retire_valid),
        .retire_preg0(retire_preg0),
        .retire_preg1(retire_preg1)
    );

    dispatch_packet_stage u_dispatch_packet_stage (
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
        .in_if(rename_packet_if.consumer),
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

    task automatic set_decode_lane(
        output decode_rat_lane_t lane,
        input  logic             valid,
        input  logic [1:0]       fu_type,
        input  logic [31:0]      pc,
        input  areg_t            rs1,
        input  areg_t            rs2,
        input  areg_t            rd,
        input  logic             do_rename
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.datapath.pc = pc;
        lane.data.datapath.rs1 = rs1;
        lane.data.datapath.rs2 = rs2;
        lane.data.datapath.rd = rd;
        lane.data.datapath.instr = 32'h0000_0013;
        lane.data.control_signal.rs_control_signal.fu_type = fu_type;
        lane.data.control_signal.rs_control_signal.rename = do_rename;
        lane.data.control_signal.rs_control_signal.alu_control_signal.reg_write =
            (fu_type == FU_ALU) && do_rename;
        lane.data.control_signal.rs_control_signal.alu_control_signal.alu_op = ALU_ADD;
        lane.data.control_signal.rs_control_signal.lsu_control_signal.reg_write =
            (fu_type == FU_MEM) && do_rename;
        lane.data.control_signal.rs_control_signal.lsu_control_signal.mem_read =
            (fu_type == FU_MEM);
    end
    endtask

    initial begin
        rst_n = 1'b0;
        flush = 1'b0;
        restore_rat = 1'b0;
        restore_checkpoint_id = '0;
        active_checkpoint_mask = '0;
        retire_valid = 2'b00;
        retire_preg0 = '0;
        retire_preg1 = '0;

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
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;

        decode_packet_if.valid = 1'b0;
        decode_packet_if.data = '0;
        issue_if.ready = 1'b1;
        issue1_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(rob_empty, "integrated packet backend starts with empty ROB");

        decode_packet_if.valid = 1'b1;
        set_decode_lane(decode_packet_if.data.lane0, 1'b1, FU_ALU, 32'h0000_0000,
                        areg_t'(1), areg_t'(2), areg_t'(5), 1'b1);
        set_decode_lane(decode_packet_if.data.lane1, 1'b1, FU_MEM, 32'h0000_0004,
                        areg_t'(5), areg_t'(3), areg_t'(6), 1'b1);
        #1;
        check_ok(decode_packet_if.ready, "rename-dispatch pipe accepts mixed packet");
        check_ok(rename_packet_if.valid, "rename packet is visible before handshake");
        check_ok(rename_packet_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(32),
                 "lane0 receives first physical allocation");
        check_ok(rename_packet_if.data.lane1.data.rs_entry.datapath.new_des_preg == preg_t'(33),
                 "lane1 receives second physical allocation");
        check_ok(rename_packet_if.data.lane1.data.rs_entry.datapath.src_reg_1p == preg_t'(32),
                 "lane1 source uses lane0 rename bypass");
        step_clk;

        decode_packet_if.valid = 1'b0;
        check_ok(rob_head_valid, "ROB receives renamed packet");
        check_ok(rob_head.datapath.rob_tag == rob_tag_t'(0), "ROB head gets lane0 tag");
        check_ok(rob_head.datapath.new_des_preg == preg_t'(32), "ROB head stores lane0 new preg");

        check_ok(issue_if.valid, "first renamed instruction issues");
        check_ok(issue_if.data.fu_sel == FU_ALU, "ALU lane issues first");
        check_ok(issue_if.data.datapath.rob_tag == rob_tag_t'(0), "issued ALU has lane0 tag");
        step_clk;

        check_ok(issue_if.valid, "second renamed instruction issues");
        check_ok(issue_if.data.fu_sel == FU_MEM, "MEM lane issues second");
        check_ok(issue_if.data.datapath.rob_tag == rob_tag_t'(1), "issued MEM has lane1 tag");
        step_clk;

        complete_valid = 1'b1;
        complete_tag = rob_tag_t'(0);
        complete_result = 32'hAAAA_0000;
        branch_complete_valid = 1'b1;
        branch_complete_tag = rob_tag_t'(1);
        branch_complete_result = 32'hBBBB_0001;
        step_clk;

        complete_valid = 1'b0;
        branch_complete_valid = 1'b0;
        check_ok(rob_head_complete, "ROB head completes through integrated path");
        check_ok(rob_head.datapath.result == 32'hAAAA_0000, "ROB head result stored");

        commit_en = 1'b1;
        step_clk;
        check_ok(rob_head_valid, "lane1 becomes head after lane0 commit");
        check_ok(rob_head.datapath.rob_tag == rob_tag_t'(1), "lane1 preserves program order");
        check_ok(rob_head_complete, "lane1 was completed by second complete port");

        step_clk;
        commit_en = 1'b0;
        check_ok(rob_empty, "integrated packet backend drains after both commits");

        $display("==== tb_rename_dispatch_packet_smoke PASS ====");
        $finish;
    end

endmodule
