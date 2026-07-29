`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for decode packet lane0 adapter.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_decode_packet_lane0_adapter;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic flush;

    pip_if #(decode_rat_packet_t) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_t)        out_if (.clk(clk), .rst_n(rst_n));

    decode_packet_lane0_adapter dut (
        .flush (flush),
        .in_if (in_if.consumer),
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

    task automatic check_ok;
        input logic cond;
        input string msg;
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        flush = 1'b0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        step_clk;
        rst_n = 1'b1;

        in_if.valid = 1'b1;
        in_if.data = '0;
        in_if.data.lane0.valid = 1'b1;
        in_if.data.lane0.data.datapath.pc = 32'h0000_0040;
        in_if.data.lane0.data.datapath.instr = 32'h0050_0093;
        out_if.ready = 1'b0;
        #1;

        check_ok(out_if.valid == 1'b1, "single-lane packet produces output valid");
        check_ok(out_if.data.datapath.pc == 32'h0000_0040, "single-lane packet forwards lane0");
        check_ok(in_if.ready == 1'b0, "single-lane packet observes downstream backpressure");

        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready == 1'b1, "single-lane packet ready follows downstream ready");

        in_if.data.lane1.valid = 1'b1;
        in_if.data.lane1.data.datapath.pc = 32'h0000_0044;
        in_if.data.lane1.data.datapath.instr = 32'h0060_0113;
        #1;
        check_ok(out_if.valid == 1'b1, "two-lane packet produces lane0 first");
        check_ok(out_if.data.datapath.pc == 32'h0000_0040, "two-lane packet lane0 appears first");
        check_ok(in_if.ready == 1'b1, "two-lane packet can be consumed when downstream ready");

        step_clk;
        in_if.valid = 1'b0;
        in_if.data = '0;
        #1;
        check_ok(out_if.valid == 1'b1, "serializer replays held lane1");
        check_ok(out_if.data.datapath.pc == 32'h0000_0044, "serializer outputs lane1 after lane0");
        check_ok(in_if.ready == 1'b0, "serializer blocks new packets while replaying lane1");

        step_clk;
        #1;
        check_ok(out_if.valid == 1'b0, "serializer becomes empty after lane1 handshake");
        check_ok(in_if.ready == 1'b1, "serializer accepts new packet when empty");

        in_if.valid = 1'b1;
        in_if.data = '0;
        in_if.data.lane0.valid = 1'b1;
        in_if.data.lane0.data.datapath.pc = 32'h0000_0080;
        in_if.data.lane1.valid = 1'b1;
        in_if.data.lane1.data.datapath.pc = 32'h0000_0084;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.datapath.pc == 32'h0000_0080, "flush test emits lane0 before storing lane1");

        flush = 1'b1;
        #1;
        check_ok(out_if.valid == 1'b0, "flush immediately suppresses output valid");
        check_ok(in_if.ready == 1'b0, "flush immediately blocks new packet consumption");

        in_if.valid = 1'b0;
        in_if.data = '0;
        step_clk;
        #1;
        check_ok(out_if.valid == 1'b0, "flush clears held lane1");

        flush = 1'b0;
        #1;
        check_ok(in_if.ready == 1'b1, "serializer accepts new packet after flush");

        in_if.valid = 1'b1;
        in_if.data = '0;
        out_if.ready = 1'b0;
        #1;
        check_ok(out_if.valid == 1'b0, "empty packet does not assert output valid");
        check_ok(in_if.ready == 1'b1, "empty packet can be consumed");

        in_if.valid = 1'b0;
        in_if.data.lane0.valid = 1'b1;
        #1;
        check_ok(out_if.valid == 1'b0, "invalid packet does not assert output valid");
        check_ok(in_if.ready == 1'b1, "invalid packet never backpressures upstream");

        $display("==== tb_decode_packet_lane0_adapter PASS ====");
        $finish;
    end

endmodule
