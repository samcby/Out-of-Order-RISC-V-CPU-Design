`timescale 1ns / 1ps

module tb_fp_fma_unit;

    import fp_defines_pkg::*;

    logic [4:0] operation;
    logic [2:0] rounding_mode;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] operand_c;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_fma_unit u_dut (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .operand_c(operand_c),
        .result(result),
        .flags(flags)
    );

    task automatic check_case(
        input logic [4:0] op,
        input logic [31:0] a,
        input logic [31:0] b,
        input logic [31:0] c,
        input logic [2:0] rm,
        input logic [31:0] expected_result,
        input logic [4:0] expected_flags,
        input string message
    );
    begin
        operation = op;
        operand_a = a;
        operand_b = b;
        operand_c = c;
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
        operation = FP_OP_MADD;
        rounding_mode = '0;
        operand_a = '0;
        operand_b = '0;
        operand_c = '0;

        check_case(FP_OP_MADD, 32'h3fc00000, 32'h40000000,
                   32'h3f000000, 3'b000,
                   32'h40600000, 5'b00000,
                   "FMADD computes 1.5*2.0+0.5");
        check_case(FP_OP_MSUB, 32'h3fc00000, 32'h40000000,
                   32'h3f000000, 3'b000,
                   32'h40200000, 5'b00000,
                   "FMSUB computes 1.5*2.0-0.5");
        check_case(FP_OP_NMSUB, 32'h3fc00000, 32'h40000000,
                   32'h3f000000, 3'b000,
                   32'hc0200000, 5'b00000,
                   "FNMSUB computes -(1.5*2.0)+0.5");
        check_case(FP_OP_NMADD, 32'h3fc00000, 32'h40000000,
                   32'h3f000000, 3'b000,
                   32'hc0600000, 5'b00000,
                   "FNMADD computes -(1.5*2.0)-0.5");

        check_case(FP_OP_MADD, 32'h3f800001, 32'h3f7ffffe,
                   32'hbf800000, 3'b000,
                   32'ha8800000, 5'b00000,
                   "fused operation preserves product bits before addition");
        check_case(FP_OP_MADD, 32'h00000001, 32'h3f800000,
                   32'h00000001, 3'b000,
                   32'h00000002, 5'b00000,
                   "FMA adds exact subnormal values");
        check_case(FP_OP_MADD, 32'h7f800000, 32'h00000000,
                   32'h3f800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "infinity times zero raises NV");
        check_case(FP_OP_MADD, 32'h7f800000, 32'h3f800000,
                   32'hff800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "opposite infinities in the fused sum raise NV");
        check_case(FP_OP_MADD, 32'h7fc00000, 32'h3f800000,
                   32'h3f800000, 3'b000,
                   32'h7fc00000, 5'b00000,
                   "quiet NaN propagates as canonical NaN");
        check_case(FP_OP_MADD, 32'h7f800001, 32'h3f800000,
                   32'h3f800000, 3'b000,
                   32'h7fc00000, 5'b10000,
                   "signaling NaN raises NV");

        if (errors == 0) begin
            $display("==== tb_fp_fma_unit PASS ====");
        end else begin
            $display("==== tb_fp_fma_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
