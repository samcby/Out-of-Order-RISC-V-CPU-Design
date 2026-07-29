`timescale 1ns / 1ps

// Numerical core for single-precision floating-point divide and square root.
//
// Unpacks/normalizes operands, computes quotient or integer square-root
// significands, forms sticky information, applies the requested rounding mode,
// and handles all key IEEE special cases. The core is combinational in this
// educational implementation; fp_div_sqrt_iterative models the long occupied
// latency and provides the externally visible busy/handshake behavior.
module fp_div_sqrt_unit (
    input  logic [4:0]  operation,
    input  logic [2:0]  rounding_mode,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic [31:0] result,
    output logic [4:0]  flags
);
    import fp_defines_pkg::*;

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
    logic [23:0] sig_a_raw;
    logic [23:0] sig_b_raw;
    logic [24:0] sqrt_sig;
    logic [55:0] numerator;
    logic [55:0] quotient_wide;
    logic [55:0] division_remainder;
    logic [55:0] sqrt_radicand;
    logic [27:0] sqrt_root;
    logic [55:0] sqrt_square;
    logic [55:0] sqrt_remainder;
    logic [26:0] normalized;
    logic [23:0] main_sig;
    logic [24:0] rounded_sig;
    logic [7:0] result_exp;
    logic [22:0] result_frac;
    logic inexact;
    logic increment;
    logic overflow_to_infinity;
    integer unbiased_a;
    integer unbiased_b;
    integer result_unbiased;
    integer exp_work;
    integer leading_a;
    integer leading_b;
    integer normalize_shift_a;
    integer normalize_shift_b;
    integer subnormal_shift;

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

    function automatic logic [27:0] integer_sqrt(
        input logic [55:0] value
    );
        logic [27:0] root;
        logic [27:0] trial;
        logic [55:0] square;
    begin
        root = '0;
        trial = '0;
        square = '0;
        for (int root_bit = 27; root_bit >= 0; root_bit--) begin
            trial = root | (28'b1 << root_bit);
            square = trial * trial;
            if (square <= value) root = trial;
        end
        integer_sqrt = root;
    end
    endfunction

    always_comb begin
        exp_a = operand_a[30:23];
        exp_b = operand_b[30:23];
        frac_a = operand_a[22:0];
        frac_b = operand_b[22:0];
        sign_result = (operation == FP_OP_SQRT) ?
                      1'b0 : (operand_a[31] ^ operand_b[31]);

        a_nan = (&exp_a) && (frac_a != '0);
        b_nan = (&exp_b) && (frac_b != '0);
        a_snan = a_nan && !frac_a[22];
        b_snan = b_nan && !frac_b[22];
        a_inf = (&exp_a) && (frac_a == '0);
        b_inf = (&exp_b) && (frac_b == '0);
        a_zero = (exp_a == '0) && (frac_a == '0);
        b_zero = (exp_b == '0) && (frac_b == '0);

        sig_a_raw = {(exp_a != '0), frac_a};
        sig_b_raw = {(exp_b != '0), frac_b};
        sig_a = sig_a_raw;
        sig_b = sig_b_raw;
        unbiased_a = integer'(exp_a) - 127;
        unbiased_b = integer'(exp_b) - 127;
        leading_a = 0;
        leading_b = 0;
        normalize_shift_a = 0;
        normalize_shift_b = 0;

        if (exp_a == '0) begin
            for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
                if (frac_a[bit_idx]) leading_a = bit_idx;
            end
            normalize_shift_a = 23 - leading_a;
            sig_a = sig_a_raw << normalize_shift_a;
            unbiased_a = -126 - normalize_shift_a;
        end
        if (exp_b == '0) begin
            for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
                if (frac_b[bit_idx]) leading_b = bit_idx;
            end
            normalize_shift_b = 23 - leading_b;
            sig_b = sig_b_raw << normalize_shift_b;
            unbiased_b = -126 - normalize_shift_b;
        end

        sqrt_sig = '0;
        numerator = '0;
        quotient_wide = '0;
        division_remainder = '0;
        sqrt_radicand = '0;
        sqrt_root = '0;
        sqrt_square = '0;
        sqrt_remainder = '0;
        normalized = '0;
        result_unbiased = 0;

        if (operation == FP_OP_DIV) begin
            result_unbiased = unbiased_a - unbiased_b;
            if (sig_a < sig_b) begin
                numerator = {32'b0, sig_a} << 27;
                result_unbiased = result_unbiased - 1;
            end else begin
                numerator = {32'b0, sig_a} << 26;
            end
            if (sig_b != '0) begin
                quotient_wide = numerator / sig_b;
                division_remainder = numerator % sig_b;
            end
            normalized = quotient_wide[26:0];
            normalized[0] =
                normalized[0] | (division_remainder != '0);
        end else begin
            if (unbiased_a & 1) begin
                sqrt_sig = {sig_a, 1'b0};
                result_unbiased = (unbiased_a - 1) / 2;
            end else begin
                sqrt_sig = {1'b0, sig_a};
                result_unbiased = unbiased_a / 2;
            end
            sqrt_radicand = {31'b0, sqrt_sig} << 29;
            sqrt_root = integer_sqrt(sqrt_radicand);
            sqrt_square = sqrt_root * sqrt_root;
            sqrt_remainder = sqrt_radicand - sqrt_square;
            normalized = sqrt_root[26:0];
            normalized[0] = normalized[0] | (sqrt_remainder != '0);
        end

        exp_work = result_unbiased + 127;
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

        if (operation == FP_OP_DIV) begin
            if (a_nan || b_nan) begin
                result = 32'h7fc00000;
                flags[4] = a_snan || b_snan;
            end else if ((a_zero && b_zero) || (a_inf && b_inf)) begin
                result = 32'h7fc00000;
                flags[4] = 1'b1;
            end else if (a_inf) begin
                result = {sign_result, 8'hff, 23'b0};
            end else if (b_inf) begin
                result = {sign_result, 31'b0};
            end else if (b_zero) begin
                result = {sign_result, 8'hff, 23'b0};
                flags[3] = 1'b1;
            end else if (a_zero) begin
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
                flags[1] = (result_exp == '0) && inexact;
            end
        end else begin
            if (a_nan) begin
                result = 32'h7fc00000;
                flags[4] = a_snan;
            end else if (operand_a[31] && !a_zero) begin
                result = 32'h7fc00000;
                flags[4] = 1'b1;
            end else if (a_inf) begin
                result = 32'h7f800000;
            end else if (a_zero) begin
                result = operand_a;
            end else begin
                flags[0] = inexact;
                flags[1] = (result_exp == '0) && inexact;
            end
        end
    end

endmodule
