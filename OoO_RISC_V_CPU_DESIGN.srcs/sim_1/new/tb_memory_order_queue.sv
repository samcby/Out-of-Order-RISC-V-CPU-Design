`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for memory order queue.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_memory_order_queue;

    import defines_pkg::*;

    localparam int TEST_DEPTH = 4;

    logic clk;
    logic rst_n;
    logic wb_valid;
    preg_t wb_preg;
    logic [WIDTH-1:0] wb_result;
    logic wb1_valid;
    preg_t wb1_preg;
    logic [WIDTH-1:0] wb1_result;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;

    pip_if #(lsu_rs_t) in_if (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t) out_if (.clk(clk), .rst_n(rst_n));

    memory_order_queue #(
        .DEPTH(TEST_DEPTH)
    ) dut (
        .wb_valid(wb_valid),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if(in_if.consumer),
        .out_if(out_if.producer)
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

    task automatic push_mem(
        input rob_tag_t tag,
        input logic is_store,
        input logic src1_ready,
        input logic src2_ready,
        input preg_t src1_preg,
        input preg_t src2_preg,
        input cp_mask_t spec_mask
    );
    begin
        in_if.valid = 1'b1;
        in_if.data = '0;
        in_if.data.control_signal.reg_write = !is_store;
        in_if.data.control_signal.mem_read = !is_store;
        in_if.data.control_signal.mem_write = is_store;
        in_if.data.control_signal.funct3 = 3'b010;
        in_if.data.datapath.rob_tag = tag;
        in_if.data.datapath.src_reg_1p = src1_preg;
        in_if.data.datapath.src_reg_2p = src2_preg;
        in_if.data.datapath.src1_value = 32'h0000_0100;
        in_if.data.datapath.src2_value = 32'h1234_5678;
        in_if.data.datapath.speculation_mask = spec_mask;
        in_if.data.src1_ready = src1_ready;
        in_if.data.src2_ready = src2_ready;
        #1;
        check_ok(in_if.ready, "memory order queue accepts entry");
        step_clk;
        in_if.valid = 1'b0;
        in_if.data = '0;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        wb_valid = 1'b0;
        wb_preg = '0;
        wb_result = '0;
        wb1_valid = 1'b0;
        wb1_preg = '0;
        wb1_result = '0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        // An older store waiting for its data must block a ready younger load.
        push_mem(rob_tag_t'(8'd10), 1'b1, 1'b1, 1'b0,
                 preg_t'(7'd32), preg_t'(7'd40), cp_mask_t'(4'b0000));
        push_mem(rob_tag_t'(8'd11), 1'b0, 1'b1, 1'b1,
                 preg_t'(7'd33), preg_t'(7'd0), cp_mask_t'(4'b0000));
        #1;
        check_ok(!out_if.valid, "younger load cannot bypass an unready older store");

        wb_valid = 1'b1;
        wb_preg = preg_t'(7'd40);
        wb_result = 32'hdead_beef;
        step_clk;
        wb_valid = 1'b0;
        wb_preg = '0;
        wb_result = '0;
        #1;
        check_ok(out_if.valid, "older store becomes issuable after writeback wakeup");
        check_ok(out_if.data.datapath.rob_tag == rob_tag_t'(8'd10),
                 "older store issues before younger load");
        check_ok(out_if.data.datapath.src2_value == 32'hdead_beef,
                 "store data captures writeback value");

        out_if.ready = 1'b1;
        step_clk;
        #1;
        check_ok(out_if.valid, "younger load becomes visible after older store issues");
        check_ok(out_if.data.datapath.rob_tag == rob_tag_t'(8'd11),
                 "younger load preserves memory program order");
        step_clk;
        out_if.ready = 1'b0;
        #1;
        check_ok(!out_if.valid, "queue drains after ordered issue");

        // Resolve clears the matching checkpoint bit before issue.
        push_mem(rob_tag_t'(8'd12), 1'b0, 1'b1, 1'b1,
                 preg_t'(7'd34), preg_t'(7'd0), cp_mask_t'(4'b0100));
        resolve_en = 1'b1;
        resolve_checkpoint_id = cp_id_t'(2'd2);
        step_clk;
        resolve_en = 1'b0;
        #1;
        check_ok(out_if.valid, "resolved memory entry remains issuable");
        check_ok(!out_if.data.datapath.speculation_mask[2],
                 "checkpoint resolve clears memory entry speculation bit");
        out_if.ready = 1'b1;
        step_clk;
        out_if.ready = 1'b0;

        // Squashing the oldest wrong-path entry exposes the next survivor.
        push_mem(rob_tag_t'(8'd13), 1'b1, 1'b1, 1'b1,
                 preg_t'(7'd35), preg_t'(7'd36), cp_mask_t'(4'b0010));
        push_mem(rob_tag_t'(8'd14), 1'b0, 1'b1, 1'b1,
                 preg_t'(7'd37), preg_t'(7'd0), cp_mask_t'(4'b0000));
        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(2'd1);
        step_clk;
        squash_en = 1'b0;
        #1;
        check_ok(out_if.valid, "surviving memory entry remains after squash");
        check_ok(out_if.data.datapath.rob_tag == rob_tag_t'(8'd14),
                 "wrong-path older memory entry is removed");
        out_if.ready = 1'b1;
        step_clk;
        out_if.ready = 1'b0;

        // Same-cycle lane1 writeback is captured during enqueue.
        wb1_valid = 1'b1;
        wb1_preg = preg_t'(7'd50);
        wb1_result = 32'hcafe_babe;
        push_mem(rob_tag_t'(8'd15), 1'b1, 1'b1, 1'b0,
                 preg_t'(7'd38), preg_t'(7'd50), cp_mask_t'(4'b0000));
        wb1_valid = 1'b0;
        wb1_preg = '0;
        wb1_result = '0;
        #1;
        check_ok(out_if.valid, "enqueue captures same-cycle lane1 writeback");
        check_ok(out_if.data.datapath.src2_value == 32'hcafe_babe,
                 "same-cycle lane1 writeback supplies store data");
        repeat (8) begin
            step_clk;
            check_ok(out_if.valid, "registered memory head holds valid under LSU backpressure");
            check_ok(out_if.data.datapath.rob_tag == rob_tag_t'(8'd15),
                     "registered memory head remains stable under LSU backpressure");
        end
        out_if.ready = 1'b1;
        step_clk;

        $display("==== tb_memory_order_queue PASS ====");
        $finish;
    end

endmodule
