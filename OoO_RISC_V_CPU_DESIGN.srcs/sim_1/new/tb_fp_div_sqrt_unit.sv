`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp div sqrt unit.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_div_sqrt_unit;

    import fp_defines_pkg::*;

    logic [4:0] operation;
    logic [2:0] rounding_mode;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_div_sqrt_unit u_dut (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .flags(flags)
    );

    task automatic check_case(
        input logic [4:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [2:0] rm,
        input logic [31:0] expected_result,
        input logic [4:0] expected_flags,
        input string message
    );
    begin
        operation = op;
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
        operation = FP_OP_DIV;
        rounding_mode = '0;
        operand_a = '0;
        operand_b = '0;

        check_case(FP_OP_DIV, 32'h40c00000, 32'h40000000, 3'b000,
                   32'h40400000, 5'b00000,
                   "6.0 / 2.0 = 3.0");
        check_case(FP_OP_DIV, 32'h3f800000, 32'h40400000, 3'b000,
                   32'h3eaaaaab, 5'b00001,
                   "RNE rounds one third");
        check_case(FP_OP_DIV, 32'h3f800000, 32'h40400000, 3'b001,
                   32'h3eaaaaaa, 5'b00001,
                   "RTZ truncates one third");
        check_case(FP_OP_DIV, 32'hbf800000, 32'h00000000, 3'b000,
                   32'hff800000, 5'b01000,
                   "finite nonzero divided by zero raises DZ");
        check_case(FP_OP_DIV, 32'h00000000, 32'h00000000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "zero divided by zero raises NV");
        check_case(FP_OP_DIV, 32'h7f800000, 32'h7f800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "infinity divided by infinity raises NV");
        check_case(FP_OP_DIV, 32'h00800000, 32'h40000000, 3'b000,
                   32'h00400000, 5'b00000,
                   "minimum normal divided by two is exact subnormal");
        check_case(FP_OP_DIV, 32'h00000001, 32'h40000000, 3'b000,
                   32'h00000000, 5'b00011,
                   "minimum subnormal divided by two raises UF and NX");

        check_case(FP_OP_SQRT, 32'h40800000, 32'h00000000, 3'b000,
                   32'h40000000, 5'b00000,
                   "square root of four is two");
        check_case(FP_OP_SQRT, 32'h40000000, 32'h00000000, 3'b000,
                   32'h3fb504f3, 5'b00001,
                   "RNE rounds square root of two");
        check_case(FP_OP_SQRT, 32'h40000000, 32'h00000000, 3'b011,
                   32'h3fb504f4, 5'b00001,
                   "RUP rounds square root of two upward");
        check_case(FP_OP_SQRT, 32'hbf800000, 32'h00000000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "square root of a negative value raises NV");
        check_case(FP_OP_SQRT, 32'h80000000, 32'h00000000, 3'b000,
                   32'h80000000, 5'b00000,
                   "square root preserves negative zero");
        check_case(FP_OP_SQRT, 32'h00000001, 32'h00000000, 3'b000,
                   32'h1a3504f3, 5'b00001,
                   "square root normalizes the minimum subnormal");

        if (errors == 0) begin
            $display("==== tb_fp_div_sqrt_unit PASS ====");
        end else begin
            $display("==== tb_fp_div_sqrt_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
