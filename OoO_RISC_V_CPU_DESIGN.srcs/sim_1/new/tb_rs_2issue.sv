`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for rs 2issue.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_rs_2issue;

    import defines_pkg::*;

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

    pip_if #(alu_rs_t) in_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) in1_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) out0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) out1_if (.clk(clk), .rst_n(rst_n));

    rs_2issue #(
        .T(alu_rs_t)
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
        .in1_if(in1_if.consumer),
        .out0_if(out0_if.producer),
        .out1_if(out1_if.producer)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic make_ready(
        output alu_rs_t entry,
        input rob_tag_t tag,
        input preg_t dest,
        input logic [WIDTH-1:0] src1,
        input logic [WIDTH-1:0] src2
    );
    begin
        entry = '0;
        entry.control_signal.reg_write = 1'b1;
        entry.control_signal.alu_op = ALU_ADD;
        entry.datapath.rob_tag = tag;
        entry.datapath.new_des_preg = dest;
        entry.datapath.src1_value = src1;
        entry.datapath.src2_value = src2;
        entry.src1_ready = 1'b1;
        entry.src2_ready = 1'b1;
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

    task automatic push_ready(input rob_tag_t tag, input preg_t dest, input logic [WIDTH-1:0] src1, input logic [WIDTH-1:0] src2);
    begin
        in_if.valid = 1'b1;
        in_if.data = '0;
        in_if.data.control_signal.reg_write = 1'b1;
        in_if.data.control_signal.alu_op = ALU_ADD;
        in_if.data.datapath.rob_tag = tag;
        in_if.data.datapath.new_des_preg = dest;
        in_if.data.datapath.src1_value = src1;
        in_if.data.datapath.src2_value = src2;
        in_if.data.src1_ready = 1'b1;
        in_if.data.src2_ready = 1'b1;
        #1;
        check_ok(in_if.ready, "RS accepts ready ALU entry");
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
        in1_if.valid = 1'b0;
        in1_if.data = '0;
        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        in_if.valid = 1'b1;
        in1_if.valid = 1'b1;
        make_ready(in_if.data, rob_tag_t'(8'd9), preg_t'(8'd44), 32'd9, 32'd1);
        make_ready(in1_if.data, rob_tag_t'(8'd10), preg_t'(8'd45), 32'd10, 32'd2);
        #1;
        check_ok(in_if.ready && in1_if.ready, "RS accepts two ready ALU entries in one cycle");
        step_clk;
        in_if.valid = 1'b0;
        in_if.data = '0;
        in1_if.valid = 1'b0;
        in1_if.data = '0;
        #1;
        check_ok(out0_if.valid && out1_if.valid, "dual-enqueued entries appear on both issue slots");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd9), "dual enqueue first tag preserved");
        check_ok(out1_if.data.datapath.rob_tag == rob_tag_t'(8'd10), "dual enqueue second tag preserved");
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b1;
        step_clk;
        check_ok(!out0_if.valid && !out1_if.valid, "dual-enqueued entries retire together");

        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        push_ready(rob_tag_t'(8'd1), preg_t'(8'd40), 32'd1, 32'd2);
        push_ready(rob_tag_t'(8'd2), preg_t'(8'd41), 32'd3, 32'd4);

        #1;
        check_ok(out0_if.valid, "first ALU issue slot is valid");
        check_ok(out1_if.valid, "second ALU issue slot is valid");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd1), "first issue preserves older tag");
        check_ok(out1_if.data.datapath.rob_tag == rob_tag_t'(8'd2), "second issue preserves next tag");
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b1;
        step_clk;

        check_ok(!out0_if.valid && !out1_if.valid, "both ALU entries retired after dual issue");

        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        push_ready(rob_tag_t'(8'd3), preg_t'(8'd42), 32'd5, 32'd6);
        push_ready(rob_tag_t'(8'd4), preg_t'(8'd43), 32'd7, 32'd8);
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b0;
        #1;
        check_ok(out0_if.valid && out1_if.valid, "both outputs remain visible under lane1 backpressure");
        step_clk;
        check_ok(out0_if.valid, "second entry slides to first output after lane0 consumed");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd4), "lane1-backpressured entry is preserved");

        out1_if.ready = 1'b1;
        step_clk;
        check_ok(!out0_if.valid && !out1_if.valid, "remaining entry retires after backpressure clears");

        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            push_ready(rob_tag_t'(20 + i), preg_t'(48 + i), 20 + i, 32'd1);
        end
        #1;
        check_ok(out0_if.valid && out1_if.valid, "full RS exposes two oldest ready entries");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd20), "oldest ready entry issues first before index reuse");
        check_ok(out1_if.data.datapath.rob_tag == rob_tag_t'(8'd21), "second-oldest ready entry issues second before index reuse");
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b0;
        step_clk;

        out0_if.ready = 1'b0;
        push_ready(rob_tag_t'(8'd99), preg_t'(8'd63), 32'd99, 32'd1);
        #1;
        check_ok(out0_if.valid && out1_if.valid, "RS still exposes two ready entries after low-index reuse");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd21), "age priority keeps older high-index entry ahead of reused low-index entry");
        check_ok(out1_if.data.datapath.rob_tag == rob_tag_t'(8'd22), "age priority selects next older entry for second issue slot");
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b1;
        repeat (4) step_clk;

        $display("==== tb_rs_2issue PASS ====");
        $finish;
    end

endmodule
