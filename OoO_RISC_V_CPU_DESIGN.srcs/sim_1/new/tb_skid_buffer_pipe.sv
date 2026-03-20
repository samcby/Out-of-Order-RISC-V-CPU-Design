`timescale 1ns/1ps

module tb_skid_buffer_pipe;

    logic clk;
    logic rst_n;

    pip_if #(.T(logic [31:0])) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(.T(logic [31:0])) out_if (.clk(clk), .rst_n(rst_n));

    skid_buffer_pipe #(
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

        check_ok(out_if.valid == 1'b0, "reset output invalid");

        out_if.ready = 1'b1;
        in_if.valid  = 1'b1;
        in_if.data   = 32'h11111111;
        #1;
        check_ok(in_if.ready == 1'b1, "input can handshake");
        check_ok(out_if.valid == 1'b0, "one-cycle latency before register fill");

        step_clk;
        check_ok(out_if.valid == 1'b1, "output valid after one cycle");
        check_ok(out_if.data  == 32'h11111111, "output data matches first word");

        out_if.ready = 1'b0;
        in_if.valid  = 1'b1;
        in_if.data   = 32'h22222222;
        #1;
        check_ok(in_if.ready == 1'b0, "input blocked when downstream stalled");
        check_ok(out_if.data  == 32'h11111111, "old data held during stall");

        step_clk;
        check_ok(out_if.valid == 1'b1, "valid remains asserted during stall");
        check_ok(out_if.data  == 32'h11111111, "data remains stable during stall");

        in_if.valid  = 1'b0;
        out_if.ready = 1'b1;
        step_clk;
        check_ok(out_if.valid == 1'b0, "output clears after consume");

        in_if.valid = 1'b1;
        in_if.data  = 32'h33333333;
        step_clk;
        check_ok(out_if.valid == 1'b1, "second transfer valid");
        check_ok(out_if.data  == 32'h33333333, "second transfer data correct");

        $display("==== tb_skid_buffer_pipe PASS ====");
        $finish;
    end

endmodule
