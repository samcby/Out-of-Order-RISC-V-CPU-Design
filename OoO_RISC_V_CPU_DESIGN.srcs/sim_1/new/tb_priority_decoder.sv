`timescale 1ns/1ps

module tb_priority_decoder;

    localparam int WIDTH = 8;

    logic [WIDTH-1:0] in;
    logic valid;
    logic [$clog2(WIDTH)-1:0] idx;

    priority_decoder #(
        .WIDTH(WIDTH)
    ) dut (
        .in   (in),
        .valid(valid),
        .idx  (idx)
    );

    task automatic check_case(
        input logic [WIDTH-1:0] t_in,
        input logic             exp_valid,
        input logic [$clog2(WIDTH)-1:0] exp_idx,
        input string            msg
    );
        begin
            in = t_in;
            #1;
            if (valid !== exp_valid) begin
                $fatal(1, "[FAIL] %s: valid=%0b exp=%0b", msg, valid, exp_valid);
            end
            if (idx !== exp_idx) begin
                $fatal(1, "[FAIL] %s: idx=%0d exp=%0d", msg, idx, exp_idx);
            end
            $display("[PASS] %s", msg);
        end
    endtask

    initial begin
        $display("==== tb_priority_decoder start ====");

        check_case(8'b0000_0000, 1'b0, 3'd0, "all zero");
        check_case(8'b0000_0001, 1'b1, 3'd0, "bit 0");
        check_case(8'b0001_0000, 1'b1, 3'd4, "bit 4");
        check_case(8'b1000_0000, 1'b1, 3'd7, "bit 7");
        check_case(8'b1010_1000, 1'b1, 3'd3, "multiple bits, lowest index wins");
        check_case(8'b1111_1111, 1'b1, 3'd0, "all ones");

        $display("==== tb_priority_decoder PASS ====");
        $finish;
    end

endmodule
