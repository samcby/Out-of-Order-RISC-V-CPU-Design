`timescale 1ns / 1ps

module tb_fp_convert_unit;

    import fp_defines_pkg::*;

    logic [4:0] operation;
    logic [2:0] rounding_mode;
    logic [31:0] operand;
    logic [31:0] result;
    logic [4:0] flags;
    int errors;

    fp_convert_unit u_dut (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand(operand),
        .result(result),
        .flags(flags)
    );

    task automatic check_case(
        input logic [4:0] expected_operation,
        input logic [31:0] input_value,
        input logic [2:0] rm,
        input logic [31:0] expected_result,
        input logic [4:0] expected_flags,
        input string message
    );
    begin
        operation = expected_operation;
        operand = input_value;
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
        operation = FP_OP_NONE;
        rounding_mode = '0;
        operand = '0;

        check_case(FP_OP_CVT_W_S, 32'h3fc00000, 3'b000,
                   32'h00000002, 5'b00001,
                   "FCVT.W.S rounds 1.5 to even");
        check_case(FP_OP_CVT_W_S, 32'h40200000, 3'b000,
                   32'h00000002, 5'b00001,
                   "FCVT.W.S rounds 2.5 to even");
        check_case(FP_OP_CVT_W_S, 32'h40200000, 3'b100,
                   32'h00000003, 5'b00001,
                   "RMM rounds a positive tie away from zero");
        check_case(FP_OP_CVT_W_S, 32'hbfc00000, 3'b010,
                   32'hfffffffe, 5'b00001,
                   "RDN rounds -1.5 toward negative infinity");
        check_case(FP_OP_CVT_W_S, 32'hbfc00000, 3'b001,
                   32'hffffffff, 5'b00001,
                   "RTZ rounds -1.5 toward zero");
        check_case(FP_OP_CVT_W_S, 32'h4f000000, 3'b000,
                   32'h7fffffff, 5'b10000,
                   "positive signed overflow saturates and raises NV");
        check_case(FP_OP_CVT_W_S, 32'hcf000000, 3'b000,
                   32'h80000000, 5'b00000,
                   "negative 2^31 is an exact signed conversion");
        check_case(FP_OP_CVT_W_S, 32'h7fc00000, 3'b000,
                   32'h7fffffff, 5'b10000,
                   "NaN converts to signed saturation with NV");

        check_case(FP_OP_CVT_WU_S, 32'hbf000000, 3'b001,
                   32'h00000000, 5'b00001,
                   "negative half rounds to unsigned zero under RTZ");
        check_case(FP_OP_CVT_WU_S, 32'hbf000000, 3'b010,
                   32'h00000000, 5'b10000,
                   "negative unsigned result raises NV under RDN");
        check_case(FP_OP_CVT_WU_S, 32'h4f800000, 3'b000,
                   32'hffffffff, 5'b10000,
                   "unsigned 2^32 overflow saturates with NV");
        check_case(FP_OP_CVT_WU_S, 32'h4f7fffff, 3'b000,
                   32'hffffff00, 5'b00000,
                   "largest float below 2^32 converts exactly");

        check_case(FP_OP_CVT_S_W, 32'h00000001, 3'b000,
                   32'h3f800000, 5'b00000,
                   "signed integer one converts exactly");
        check_case(FP_OP_CVT_S_W, 32'hfffffffe, 3'b000,
                   32'hc0000000, 5'b00000,
                   "signed integer negative two converts exactly");
        check_case(FP_OP_CVT_S_W, 32'h7fffffff, 3'b000,
                   32'h4f000000, 5'b00001,
                   "signed maximum rounds to 2^31 under RNE");
        check_case(FP_OP_CVT_S_W, 32'h7fffffff, 3'b001,
                   32'h4effffff, 5'b00001,
                   "signed maximum truncates under RTZ");
        check_case(FP_OP_CVT_S_WU, 32'hffffffff, 3'b000,
                   32'h4f800000, 5'b00001,
                   "unsigned maximum rounds to 2^32 under RNE");
        check_case(FP_OP_CVT_S_WU, 32'hffffffff, 3'b001,
                   32'h4f7fffff, 5'b00001,
                   "unsigned maximum truncates under RTZ");

        if (errors == 0) begin
            $display("==== tb_fp_convert_unit PASS ====");
        end else begin
            $display("==== tb_fp_convert_unit FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
