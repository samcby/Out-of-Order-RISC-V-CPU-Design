`timescale 1ns/1ps

module tb_fetch_packet_adapter;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    pip_if #(fetch_decode_t)        in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(fetch_decode_packet_t) out_if (.clk(clk), .rst_n(rst_n));

    fetch_packet_adapter dut (
        .in_if (in_if.consumer),
        .out_if(out_if.producer)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

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
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b1;

        in_if.valid = 1'b1;
        in_if.data.pc = 32'h0000_0040;
        in_if.data.instr = 32'h0050_0093;
        in_if.data.pred_taken = 1'b1;
        in_if.data.pred_target = 32'h0000_0100;
        out_if.ready = 1'b0;
        #1;

        check_ok(in_if.ready == 1'b0, "backpressure propagates to input");
        check_ok(out_if.valid == 1'b1, "packet valid follows input valid");
        check_ok(out_if.data.lane0.valid == 1'b1, "lane0 carries valid instruction");
        check_ok(out_if.data.lane0.data.pc == 32'h0000_0040, "lane0 pc preserved");
        check_ok(out_if.data.lane0.data.instr == 32'h0050_0093, "lane0 instruction preserved");
        check_ok(out_if.data.lane0.data.pred_taken == 1'b1, "lane0 prediction bit preserved");
        check_ok(out_if.data.lane0.data.pred_target == 32'h0000_0100, "lane0 prediction target preserved");
        check_ok(out_if.data.lane1.valid == 1'b0, "lane1 is disabled in compatibility mode");

        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready == 1'b1, "ready propagates from packet consumer");

        in_if.valid = 1'b0;
        #1;
        check_ok(out_if.valid == 1'b0, "packet valid deasserts with input valid");
        check_ok(out_if.data.lane0.valid == 1'b0, "lane0 valid deasserts with input valid");

        $display("==== tb_fetch_packet_adapter PASS ====");
        $finish;
    end

endmodule
