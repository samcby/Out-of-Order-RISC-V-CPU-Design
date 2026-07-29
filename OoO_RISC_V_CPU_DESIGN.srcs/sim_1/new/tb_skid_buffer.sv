`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for skid buffer.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_skid_buffer;

    logic clk;
    logic rst_n;

    pip_if #(.T(logic [31:0])) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(.T(logic [31:0])) out_if (.clk(clk), .rst_n(rst_n));

    skid_buffer #(
        .T(logic [31:0])
    ) dut (
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
        input bit cond;
        input string msg;
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end
        else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        in_if.valid = 1'b0;
        in_if.data  = 32'd0;
        out_if.ready = 1'b0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        out_if.ready = 1'b1;
        in_if.valid  = 1'b1;
        in_if.data   = 32'hA1A1A1A1;
        #1;
        check_ok(in_if.ready == 1'b1, "pass-through ready");
        check_ok(out_if.valid == 1'b1, "pass-through valid");
        check_ok(out_if.data  == 32'hA1A1A1A1, "pass-through data");

        out_if.ready = 1'b0;
        in_if.valid  = 1'b1;
        in_if.data   = 32'hB2B2B2B2;
        #1;
        check_ok(in_if.ready == 1'b0, "backpressure seen at input");
        step_clk;
        check_ok(out_if.valid == 1'b1, "held valid during stall");
        check_ok(out_if.data  == 32'hB2B2B2B2, "captured stalled data");

        in_if.data = 32'hC3C3C3C3;
        #1;
        check_ok(out_if.data == 32'hB2B2B2B2, "held data stable while stalled");

        in_if.valid = 1'b0;
        out_if.ready = 1'b1;
        step_clk;
        check_ok(out_if.valid == 1'b0, "buffer drained");

        $display("==== tb_skid_buffer PASS ====");
        $finish;
    end

endmodule
