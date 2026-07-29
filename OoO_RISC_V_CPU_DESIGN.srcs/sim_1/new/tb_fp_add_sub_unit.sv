`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp add sub unit.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_add_sub_unit;

    logic subtract;
    logic [2:0] rounding_mode;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_add_sub_unit u_dut (
        .subtract(subtract),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .flags(flags)
    );

    task automatic check_case(
        input logic sub,
        input logic [2:0] rm,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] expected_result,
        input logic [4:0] expected_flags,
        input string message
    );
    begin
        subtract = sub;
        rounding_mode = rm;
        operand_a = a;
        operand_b = b;
        #1;
        if ((result == expected_result) && (flags == expected_flags)) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s result=0x%08h expected=0x%08h flags=0x%02h expected_flags=0x%02h",
                     message, result, expected_result, flags, expected_flags);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        errors = 0;
        subtract = 1'b0;
        rounding_mode = 3'b000;
        operand_a = '0;
        operand_b = '0;

        check_case(1'b0, 3'b000, 32'h3fc00000, 32'h40100000,
                   32'h40700000, 5'b0, "1.5 + 2.25 = 3.75");
        check_case(1'b1, 3'b000, 32'h3fc00000, 32'h40100000,
                   32'hbf400000, 5'b0, "1.5 - 2.25 = -0.75");
        check_case(1'b0, 3'b000, 32'h3f800000, 32'hbf800000,
                   32'h00000000, 5'b0, "exact cancellation produces +0 in RNE");
        check_case(1'b0, 3'b010, 32'h3f800000, 32'hbf800000,
                   32'h80000000, 5'b0, "exact cancellation produces -0 in RDN");

        check_case(1'b0, 3'b000, 32'h3f800000, 32'h33800000,
                   32'h3f800000, 5'b00001, "RNE rounds a halfway tie to even");
        check_case(1'b0, 3'b011, 32'h3f800000, 32'h33800000,
                   32'h3f800001, 5'b00001, "RUP rounds a positive tie upward");
        check_case(1'b0, 3'b001, 32'h3f800000, 32'h33800000,
                   32'h3f800000, 5'b00001, "RTZ truncates a positive tie");
        check_case(1'b0, 3'b100, 32'h3f800000, 32'h33800000,
                   32'h3f800001, 5'b00001, "RMM rounds a tie away in magnitude");
        check_case(1'b0, 3'b010, 32'hbf800000, 32'hb3800000,
                   32'hbf800001, 5'b00001, "RDN rounds a negative tie downward");

        check_case(1'b0, 3'b000, 32'h7f7fffff, 32'h7f7fffff,
                   32'h7f800000, 5'b00101, "overflow rounds to positive infinity");
        check_case(1'b0, 3'b001, 32'h7f7fffff, 32'h7f7fffff,
                   32'h7f7fffff, 5'b00101, "RTZ overflow saturates at max finite");
        check_case(1'b0, 3'b000, 32'h7f800000, 32'hff800000,
                   32'h7fc00000, 5'b10000, "opposite infinities raise invalid");
        check_case(1'b0, 3'b000, 32'h7f800001, 32'h3f800000,
                   32'h7fc00000, 5'b10000, "signaling NaN raises invalid");
        check_case(1'b0, 3'b000, 32'h00000001, 32'h00000001,
                   32'h00000002, 5'b0, "exact subnormal addition stays exact");

        if (errors == 0) begin
            $display("==== tb_fp_add_sub_unit PASS ====");
        end else begin
            $display("==== tb_fp_add_sub_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
