`timescale 1ns/1ps

module tb_rob_2w;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic complete_en0;
    logic complete_en1;
    logic complete_en2;
    rob_tag_t complete_tag0;
    rob_tag_t complete_tag1;
    rob_tag_t complete_tag2;
    logic [WIDTH-1:0] complete_result0;
    logic [WIDTH-1:0] complete_result1;
    logic [WIDTH-1:0] complete_result2;
    logic commit_en;
    logic commit_en1;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    rob_t head_entry;
    rob_t head1_entry;
    logic head_valid;
    logic head_complete;
    logic head1_valid;
    logic head1_complete;
    logic full;
    logic empty;

    pip_if #(rat_dis_packet_t) rob_packet_if (.clk(clk), .rst_n(rst_n));

    rob_2w dut (
        .rob_packet_if(rob_packet_if.consumer),
        .complete_en0(complete_en0),
        .complete_tag0(complete_tag0),
        .complete_result0(complete_result0),
        .complete_fp_flags0('0),
        .complete_en1(complete_en1),
        .complete_tag1(complete_tag1),
        .complete_result1(complete_result1),
        .complete_fp_flags1('0),
        .complete_en2(complete_en2),
        .complete_tag2(complete_tag2),
        .complete_result2(complete_result2),
        .complete_fp_flags2('0),
        .commit_en0(commit_en),
        .commit_en1(commit_en1),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .head_entry(head_entry),
        .head_valid(head_valid),
        .head_complete(head_complete),
        .head1_entry(head1_entry),
        .head1_valid(head1_valid),
        .head1_complete(head1_complete),
        .full(full),
        .empty(empty)
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

    task automatic set_rob_lane(
        output rat_dis_lane_t lane,
        input  logic          valid,
        input  rob_tag_t      tag,
        input  areg_t         rd,
        input  preg_t         new_preg,
        input  cp_mask_t      spec_mask
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.rob_entry.datapath.rob_tag = tag;
        lane.data.rob_entry.datapath.rd = rd;
        lane.data.rob_entry.datapath.new_des_preg = new_preg;
        lane.data.rob_entry.datapath.old_des_preg = preg_t'(rd);
        lane.data.rob_entry.datapath.speculation_mask = spec_mask;
        lane.data.rob_entry.datapath.complete = 1'b0;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        complete_en0 = 1'b0;
        complete_en1 = 1'b0;
        complete_en2 = 1'b0;
        complete_tag0 = '0;
        complete_tag1 = '0;
        complete_tag2 = '0;
        complete_result0 = '0;
        complete_result1 = '0;
        complete_result2 = '0;
        commit_en = 1'b0;
        commit_en1 = 1'b0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        rob_packet_if.valid = 1'b0;
        rob_packet_if.data = '0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(empty, "ROB starts empty");

        rob_packet_if.valid = 1'b1;
        set_rob_lane(rob_packet_if.data.lane0, 1'b1, rob_tag_t'(10), areg_t'(1), preg_t'(32), '0);
        set_rob_lane(rob_packet_if.data.lane1, 1'b1, rob_tag_t'(11), areg_t'(2), preg_t'(33), '0);
        #1;
        check_ok(rob_packet_if.ready, "2-wide ROB accepts a dual enqueue");
        step_clk;

        rob_packet_if.valid = 1'b0;
        check_ok(head_valid, "head valid after enqueue");
        check_ok(head_entry.datapath.rob_tag == rob_tag_t'(10), "head is older lane0 entry");
        check_ok(!head_complete, "head starts incomplete");

        complete_en0 = 1'b1;
        complete_tag0 = rob_tag_t'(10);
        complete_result0 = 32'h1111_0000;
        complete_en1 = 1'b1;
        complete_tag1 = rob_tag_t'(11);
        complete_result1 = 32'h2222_0000;
        step_clk;

        complete_en0 = 1'b0;
        complete_en1 = 1'b0;
        check_ok(head_complete, "complete port marks oldest entry complete");
        check_ok(head_entry.datapath.result == 32'h1111_0000, "complete result stored for oldest entry");
        check_ok(head1_valid, "second head view is valid after dual enqueue");
        check_ok(head1_entry.datapath.rob_tag == rob_tag_t'(11), "second head view preserves program order");
        check_ok(head1_complete, "second head view sees second complete port");

        commit_en = 1'b1;
        commit_en1 = 1'b1;
        step_clk;
        commit_en = 1'b0;
        commit_en1 = 1'b0;
        check_ok(empty, "ROB drains after dual-committing both entries");

        rob_packet_if.valid = 1'b1;
        set_rob_lane(rob_packet_if.data.lane0, 1'b1, rob_tag_t'(20), areg_t'(3), preg_t'(34), '0);
        set_rob_lane(rob_packet_if.data.lane1, 1'b1, rob_tag_t'(21), areg_t'(4), preg_t'(35), cp_mask_t'(4'b0010));
        step_clk;

        rob_packet_if.valid = 1'b0;
        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(1);
        step_clk;

        squash_en = 1'b0;
        check_ok(head_valid, "ROB keeps non-squashed older entry");
        check_ok(head_entry.datapath.rob_tag == rob_tag_t'(20), "squash removes younger speculative entry");

        complete_en0 = 1'b1;
        complete_tag0 = rob_tag_t'(20);
        complete_result0 = 32'h3333_0000;
        step_clk;
        complete_en0 = 1'b0;
        commit_en = 1'b1;
        step_clk;
        commit_en = 1'b0;
        check_ok(empty, "ROB drains after squash survivor commits");

        rob_packet_if.valid = 1'b1;
        set_rob_lane(rob_packet_if.data.lane0, 1'b1, rob_tag_t'(30), areg_t'(5), preg_t'(36), cp_mask_t'(4'b0100));
        rob_packet_if.data.lane1 = '0;
        step_clk;

        rob_packet_if.valid = 1'b0;
        resolve_en = 1'b1;
        resolve_checkpoint_id = cp_id_t'(2);
        step_clk;
        resolve_en = 1'b0;
        check_ok(head_entry.datapath.speculation_mask[2] == 1'b0, "resolve clears checkpoint bit in ROB entry");

        flush = 1'b1;
        step_clk;
        flush = 1'b0;
        check_ok(empty, "flush clears ROB");

        // A branch recovery may coincide with retirement of older entries.
        // The squash path must preserve those pops instead of exposing the
        // same committed tags again on the following cycle.
        rob_packet_if.valid = 1'b1;
        set_rob_lane(rob_packet_if.data.lane0, 1'b1,
                     rob_tag_t'(60), areg_t'(6), preg_t'(45), '0);
        set_rob_lane(rob_packet_if.data.lane1, 1'b1,
                     rob_tag_t'(61), areg_t'(7), preg_t'(46), '0);
        step_clk;

        set_rob_lane(rob_packet_if.data.lane0, 1'b1,
                     rob_tag_t'(62), areg_t'(8), preg_t'(47),
                     cp_mask_t'(4'b0010));
        rob_packet_if.data.lane1 = '0;
        step_clk;
        rob_packet_if.valid = 1'b0;

        complete_en0 = 1'b1;
        complete_tag0 = rob_tag_t'(60);
        complete_result0 = 32'h6060_0000;
        complete_en1 = 1'b1;
        complete_tag1 = rob_tag_t'(61);
        complete_result1 = 32'h6161_0000;
        step_clk;
        complete_en0 = 1'b0;
        complete_en1 = 1'b0;
        check_ok(head_complete && head1_complete,
                 "older entries complete before simultaneous recovery");

        commit_en = 1'b1;
        commit_en1 = 1'b1;
        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(1);
        step_clk;
        commit_en = 1'b0;
        commit_en1 = 1'b0;
        squash_en = 1'b0;
        check_ok(empty,
                 "simultaneous dual commit and squash removes each entry once");

        // Fill all but one slot, then verify that a dual packet receives
        // stable backpressure without feeding valid back into ready.
        for (int i = 0; i < 7; i++) begin
            rob_packet_if.valid = 1'b1;
            set_rob_lane(rob_packet_if.data.lane0, 1'b1,
                         rob_tag_t'(40 + (i * 2)), areg_t'(1), preg_t'(40), '0);
            set_rob_lane(rob_packet_if.data.lane1, 1'b1,
                         rob_tag_t'(41 + (i * 2)), areg_t'(2), preg_t'(41), '0);
            #1;
            check_ok(rob_packet_if.ready, "ROB accepts packet while two slots remain");
            step_clk;
        end

        rob_packet_if.valid = 1'b1;
        set_rob_lane(rob_packet_if.data.lane0, 1'b1,
                     rob_tag_t'(54), areg_t'(3), preg_t'(42), '0);
        rob_packet_if.data.lane1 = '0;
        #1;
        check_ok(rob_packet_if.ready, "ROB accepts one lane into the penultimate free slot");
        step_clk;

        set_rob_lane(rob_packet_if.data.lane0, 1'b1,
                     rob_tag_t'(55), areg_t'(4), preg_t'(43), '0);
        set_rob_lane(rob_packet_if.data.lane1, 1'b1,
                     rob_tag_t'(56), areg_t'(5), preg_t'(44), '0);
        rob_packet_if.valid = 1'b0;
        #1;
        check_ok(!rob_packet_if.ready,
                 "dual packet shape requires two slots even before valid asserts");
        rob_packet_if.valid = 1'b1;
        #1;
        check_ok(!rob_packet_if.ready,
                 "dual packet is stably backpressured with one ROB slot free");

        rob_packet_if.data.lane1 = '0;
        #1;
        check_ok(rob_packet_if.ready,
                 "single-lane packet can use the final ROB slot");
        step_clk;
        check_ok(full, "ROB reports full after final single-lane enqueue");

        rob_packet_if.valid = 1'b0;
        rob_packet_if.data = '0;
        flush = 1'b1;
        step_clk;
        flush = 1'b0;
        check_ok(empty, "flush clears near-capacity ROB regression state");

        $display("==== tb_rob_2w PASS ====");
        $finish;
    end

endmodule
