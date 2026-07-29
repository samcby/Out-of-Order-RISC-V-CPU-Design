`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp mul unit.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_mul_unit;

    logic [2:0] rounding_mode;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_mul_unit u_dut (
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .flags(flags)
    );

    task automatic check_case(
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [2:0] rm,
        input logic [31:0] expected_result,
        input logic [4:0] expected_flags,
        input string message
    );
    begin
        operand_a = a;
        operand_b = b;
        rounding_mode = rm;
        #1;
        if ((result === expected_result) && (flags === expected_flags)) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s result=0x%08h flags=0x%02h",
                     message, result, flags);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        errors = 0;
        operand_a = '0;
        operand_b = '0;
        rounding_mode = '0;

        check_case(32'h3fc00000, 32'h40000000, 3'b000,
                   32'h40400000, 5'b00000,
                   "1.5 * 2.0 = 3.0");
        check_case(32'hc0000000, 32'h3f000000, 3'b000,
                   32'hbf800000, 5'b00000,
                   "-2.0 * 0.5 = -1.0");
        check_case(32'h00800000, 32'h3f000000, 3'b000,
                   32'h00400000, 5'b00000,
                   "minimum normal times 0.5 is an exact subnormal");
        check_case(32'h00000001, 32'h3f000000, 3'b000,
                   32'h00000000, 5'b00011,
                   "half of the minimum subnormal raises UF and NX");
        check_case(32'h7f7fffff, 32'h40000000, 3'b000,
                   32'h7f800000, 5'b00101,
                   "RNE overflow produces infinity");
        check_case(32'h7f7fffff, 32'h40000000, 3'b001,
                   32'h7f7fffff, 5'b00101,
                   "RTZ overflow saturates at max finite");
        check_case(32'h00000000, 32'h7f800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "zero times infinity raises invalid");
        check_case(32'h7f800001, 32'h3f800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "signaling NaN raises invalid");
        check_case(32'h80000000, 32'h40000000, 3'b000,
                   32'h80000000, 5'b00000,
                   "negative zero sign is preserved");

        if (errors == 0) begin
            $display("==== tb_fp_mul_unit PASS ====");
        end else begin
            $display("==== tb_fp_mul_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
