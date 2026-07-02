`timescale 1ns / 1ps

module tb_fp_simple_unit;

    import fp_defines_pkg::*;

    logic [4:0] operation;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_simple_unit u_dut (
        .operation(operation),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(result),
        .flags(flags)
    );

    task automatic check_result(
        input logic [4:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] expected,
        input string message
    );
    begin
        operation = op;
        operand_a = a;
        operand_b = b;
        #1;
        if (result == expected) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s expected=0x%08h actual=0x%08h",
                     message, expected, result);
            errors = errors + 1;
        end
    end
    endtask

    task automatic check_flags(
        input logic [4:0] expected,
        input string message
    );
    begin
        if (flags == expected) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s expected=0x%02h actual=0x%02h",
                     message, expected, flags);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        errors = 0;
        operation = FP_OP_NONE;
        operand_a = '0;
        operand_b = '0;

        check_result(FP_OP_SGNJ, 32'h3f800000, 32'hc0000000,
                     32'hbf800000, "FSGNJ copies the second operand sign");
        check_result(FP_OP_SGNJN, 32'h3f800000, 32'hc0000000,
                     32'h3f800000, "FSGNJN copies the inverted sign");
        check_result(FP_OP_SGNJX, 32'hbf800000, 32'hc0000000,
                     32'h3f800000, "FSGNJX XORs operand signs");
        check_result(FP_OP_MIN, 32'h3f800000, 32'hc0000000,
                     32'hc0000000, "FMIN chooses the smaller finite operand");
        check_result(FP_OP_MAX, 32'h3f800000, 32'hc0000000,
                     32'h3f800000, "FMAX chooses the larger finite operand");
        check_result(FP_OP_MIN, 32'h00000000, 32'h80000000,
                     32'h80000000, "FMIN chooses negative zero");
        check_result(FP_OP_MAX, 32'h00000000, 32'h80000000,
                     32'h00000000, "FMAX chooses positive zero");
        check_result(FP_OP_MIN, 32'h7fc00000, 32'h3f800000,
                     32'h3f800000, "FMIN returns the numeric operand beside NaN");
        check_flags(5'b0, "FMIN with a quiet NaN does not raise invalid");
        check_result(FP_OP_MAX, 32'h7fc00000, 32'h7f800001,
                     32'h7fc00000, "FMAX canonicalizes a pair of NaNs");
        check_flags(5'b10000, "FMAX with a signaling NaN raises invalid");
        check_result(FP_OP_EQ, 32'h00000000, 32'h80000000,
                     32'd1, "FEQ treats signed zero values as equal");
        check_result(FP_OP_LT, 32'hc0000000, 32'h3f800000,
                     32'd1, "FLT orders a negative value below a positive value");
        check_result(FP_OP_LE, 32'h3f800000, 32'h3f800000,
                     32'd1, "FLE accepts equal finite operands");
        check_result(FP_OP_EQ, 32'h7fc00000, 32'h7fc00000,
                     32'd0, "FP comparison rejects NaN equality");
        check_flags(5'b0, "FEQ with quiet NaNs does not raise invalid");
        check_result(FP_OP_EQ, 32'h7f800001, 32'h7f800001,
                     32'd0, "FEQ rejects signaling NaN equality");
        check_flags(5'b10000, "FEQ with a signaling NaN raises invalid");
        check_result(FP_OP_LT, 32'h7fc00000, 32'h3f800000,
                     32'd0, "FLT rejects an unordered comparison");
        check_flags(5'b10000, "FLT with any NaN raises invalid");
        check_result(FP_OP_CLASS, 32'hc0000000, '0,
                     32'h00000002, "FCLASS identifies a negative normal value");
        check_result(FP_OP_CLASS, 32'h7f800001, '0,
                     32'h00000100, "FCLASS identifies a signaling NaN");
        check_result(FP_OP_CLASS, 32'h7fc00000, '0,
                     32'h00000200, "FCLASS identifies a quiet NaN");
        check_result(FP_OP_MV_X_W, 32'hdeadbeef, '0,
                     32'hdeadbeef, "FMV.X.W preserves all payload bits");
        check_result(FP_OP_MV_W_X, 32'h01234567, '0,
                     32'h01234567, "FMV.W.X preserves all payload bits");

        if (errors == 0) begin
            $display("==== tb_fp_simple_unit PASS ====");
        end else begin
            $display("==== tb_fp_simple_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
