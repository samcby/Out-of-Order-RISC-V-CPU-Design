`timescale 1ns / 1ps

// IEEE-754 single-precision multiply numerical core.
//
// Multiplies normalized significands, adds unbiased exponents, normalizes and
// rounds with guard/round/sticky information, then applies IEEE special-value
// rules for NaN, infinity, zero, overflow, and underflow. It is a combinational
// operand/result block; surrounding FP pipeline registers define timing.
module fp_mul_unit (
    input  logic [2:0]  rounding_mode,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic [31:0] result,
    output logic [4:0]  flags
);

    logic sign_result;
    logic [7:0] exp_a;
    logic [7:0] exp_b;
    logic [22:0] frac_a;
    logic [22:0] frac_b;
    logic a_nan;
    logic b_nan;
    logic a_snan;
    logic b_snan;
    logic a_inf;
    logic b_inf;
    logic a_zero;
    logic b_zero;
    logic [23:0] sig_a;
    logic [23:0] sig_b;
    logic [47:0] product;
    logic [26:0] normalized;
    logic [23:0] main_sig;
    logic [24:0] rounded_sig;
    logic [7:0] result_exp;
    logic [22:0] result_frac;
    logic inexact;
    logic increment;
    logic overflow_to_infinity;
    integer exp_a_eff;
    integer exp_b_eff;
    integer exp_work;
    integer leading_index;
    integer normalize_shift;
    integer subnormal_shift;

    function automatic logic [26:0] product_shift_sticky(
        input logic [47:0] value,
        input integer amount
    );
        logic [47:0] shifted;
        logic sticky;
    begin
        shifted = '0;
        sticky = 1'b0;
        if (amount <= 0) begin
            shifted = value << (-amount);
        end else if (amount >= 48) begin
            sticky = |value;
        end else begin
            shifted = value >> amount;
            for (int bit_idx = 0; bit_idx < 48; bit_idx++) begin
                if (bit_idx < amount) sticky = sticky | value[bit_idx];
            end
        end
        product_shift_sticky = shifted[26:0];
        product_shift_sticky[0] = product_shift_sticky[0] | sticky;
    end
    endfunction

    function automatic logic [26:0] shift_right_sticky(
        input logic [26:0] value,
        input integer amount
    );
        logic [26:0] shifted;
        logic sticky;
    begin
        shifted = '0;
        sticky = 1'b0;
        if (amount <= 0) begin
            shifted = value;
        end else if (amount >= 27) begin
            sticky = |value;
        end else begin
            shifted = value >> amount;
            for (int bit_idx = 0; bit_idx < 27; bit_idx++) begin
                if (bit_idx < amount) sticky = sticky | value[bit_idx];
            end
        end
        shifted[0] = shifted[0] | sticky;
        shift_right_sticky = shifted;
    end
    endfunction

    always_comb begin
        exp_a = operand_a[30:23];
        exp_b = operand_b[30:23];
        frac_a = operand_a[22:0];
        frac_b = operand_b[22:0];
        sign_result = operand_a[31] ^ operand_b[31];

        a_nan = (&exp_a) && (frac_a != 23'b0);
        b_nan = (&exp_b) && (frac_b != 23'b0);
        a_snan = a_nan && !frac_a[22];
        b_snan = b_nan && !frac_b[22];
        a_inf = (&exp_a) && (frac_a == 23'b0);
        b_inf = (&exp_b) && (frac_b == 23'b0);
        a_zero = (exp_a == 8'b0) && (frac_a == 23'b0);
        b_zero = (exp_b == 8'b0) && (frac_b == 23'b0);

        sig_a = {(exp_a != 8'b0), frac_a};
        sig_b = {(exp_b != 8'b0), frac_b};
        exp_a_eff = (exp_a == 8'b0) ? 1 : exp_a;
        exp_b_eff = (exp_b == 8'b0) ? 1 : exp_b;
        product = sig_a * sig_b;

        leading_index = 0;
        for (int bit_idx = 0; bit_idx < 48; bit_idx++) begin
            if (product[bit_idx]) leading_index = bit_idx;
        end

        exp_work = exp_a_eff + exp_b_eff - 127 + leading_index - 46;
        normalize_shift = leading_index - 26;
        normalized = product_shift_sticky(product, normalize_shift);

        if (exp_work <= 0) begin
            subnormal_shift = 1 - exp_work;
            normalized = shift_right_sticky(normalized, subnormal_shift);
            exp_work = 1;
        end else begin
            subnormal_shift = 0;
        end

        main_sig = normalized[26:3];
        inexact = |normalized[2:0];
        increment = 1'b0;
        unique case (rounding_mode)
            3'b000: increment = normalized[2] &&
                               (normalized[1] || normalized[0] || main_sig[0]);
            3'b001: increment = 1'b0;
            3'b010: increment = sign_result && inexact;
            3'b011: increment = !sign_result && inexact;
            3'b100: increment = normalized[2];
            default: increment = 1'b0;
        endcase

        rounded_sig = {1'b0, main_sig} + increment;
        if (rounded_sig[24]) begin
            main_sig = rounded_sig[24:1];
            exp_work = exp_work + 1;
        end else begin
            main_sig = rounded_sig[23:0];
        end

        result_exp = '0;
        result_frac = main_sig[22:0];
        if ((exp_work == 1) && !main_sig[23]) begin
            result_exp = '0;
        end else begin
            result_exp = exp_work[7:0];
        end

        overflow_to_infinity =
            (rounding_mode == 3'b000) ||
            (rounding_mode == 3'b100) ||
            ((rounding_mode == 3'b011) && !sign_result) ||
            ((rounding_mode == 3'b010) && sign_result);

        result = {sign_result, result_exp, result_frac};
        flags = '0;

        if (a_nan || b_nan) begin
            result = 32'h7fc00000;
            flags[4] = a_snan || b_snan;
        end else if ((a_inf && b_zero) || (b_inf && a_zero)) begin
            result = 32'h7fc00000;
            flags[4] = 1'b1;
        end else if (a_inf || b_inf) begin
            result = {sign_result, 8'hff, 23'b0};
        end else if (a_zero || b_zero) begin
            result = {sign_result, 31'b0};
        end else if (exp_work >= 255) begin
            if (overflow_to_infinity) begin
                result = {sign_result, 8'hff, 23'b0};
            end else begin
                result = {sign_result, 8'hfe, 23'h7fffff};
            end
            flags[2] = 1'b1;
            flags[0] = 1'b1;
        end else begin
            flags[0] = inexact;
            flags[1] = (result_exp == 8'b0) && inexact;
        end
    end

endmodule
