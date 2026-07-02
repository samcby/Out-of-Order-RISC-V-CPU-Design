`timescale 1ns / 1ps

module fp_simple_unit (
    input  logic [4:0]  operation,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic [31:0] result,
    output logic [4:0]  flags
);

    import fp_defines_pkg::*;

    logic a_nan;
    logic b_nan;
    logic a_snan;
    logic b_snan;
    logic a_zero;
    logic b_zero;
    logic fp_equal;
    logic fp_less;
    logic [9:0] class_bits;
    logic [31:0] min_result;
    logic [31:0] max_result;

    always_comb begin
        a_nan = (&operand_a[30:23]) && (operand_a[22:0] != 23'b0);
        b_nan = (&operand_b[30:23]) && (operand_b[22:0] != 23'b0);
        a_snan = a_nan && !operand_a[22];
        b_snan = b_nan && !operand_b[22];
        a_zero = (operand_a[30:0] == 31'b0);
        b_zero = (operand_b[30:0] == 31'b0);

        fp_equal = !a_nan && !b_nan &&
                   ((operand_a == operand_b) || (a_zero && b_zero));

        fp_less = 1'b0;
        if (!a_nan && !b_nan && !(a_zero && b_zero)) begin
            if (operand_a[31] != operand_b[31]) begin
                fp_less = operand_a[31];
            end else if (!operand_a[31]) begin
                fp_less = operand_a[30:0] < operand_b[30:0];
            end else begin
                fp_less = operand_a[30:0] > operand_b[30:0];
            end
        end

        if (a_nan && b_nan) begin
            min_result = 32'h7fc00000;
            max_result = 32'h7fc00000;
        end else if (a_nan) begin
            min_result = operand_b;
            max_result = operand_b;
        end else if (b_nan) begin
            min_result = operand_a;
            max_result = operand_a;
        end else if (a_zero && b_zero) begin
            min_result = operand_a[31] ? operand_a : operand_b;
            max_result = operand_a[31] ? operand_b : operand_a;
        end else if (fp_less) begin
            min_result = operand_a;
            max_result = operand_b;
        end else begin
            min_result = operand_b;
            max_result = operand_a;
        end

        class_bits = '0;
        if (&operand_a[30:23]) begin
            if (operand_a[22:0] == 23'b0) begin
                class_bits[operand_a[31] ? 0 : 7] = 1'b1;
            end else begin
                class_bits[operand_a[22] ? 9 : 8] = 1'b1;
            end
        end else if (operand_a[30:23] == 8'b0) begin
            if (operand_a[22:0] == 23'b0) begin
                class_bits[operand_a[31] ? 3 : 4] = 1'b1;
            end else begin
                class_bits[operand_a[31] ? 2 : 5] = 1'b1;
            end
        end else begin
            class_bits[operand_a[31] ? 1 : 6] = 1'b1;
        end

        flags = '0;
        unique case (operation)
            FP_OP_SGNJ:   result = {operand_b[31], operand_a[30:0]};
            FP_OP_SGNJN:  result = {~operand_b[31], operand_a[30:0]};
            FP_OP_SGNJX:  result = {operand_a[31] ^ operand_b[31],
                                    operand_a[30:0]};
            FP_OP_MIN: begin
                result = min_result;
                flags[4] = a_snan || b_snan;
            end
            FP_OP_MAX: begin
                result = max_result;
                flags[4] = a_snan || b_snan;
            end
            FP_OP_EQ: begin
                result = {31'b0, fp_equal};
                flags[4] = a_snan || b_snan;
            end
            FP_OP_LT: begin
                result = {31'b0, fp_less};
                flags[4] = a_nan || b_nan;
            end
            FP_OP_LE: begin
                result = {31'b0, fp_less || fp_equal};
                flags[4] = a_nan || b_nan;
            end
            FP_OP_CLASS:  result = {22'b0, class_bits};
            FP_OP_MV_X_W,
            FP_OP_MV_W_X: result = operand_a;
            default:      result = '0;
        endcase
    end

endmodule
