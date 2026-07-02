`timescale 1ns / 1ps

module fp_fma_unit (
    input  logic [4:0]  operation,
    input  logic [2:0]  rounding_mode,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [31:0] operand_c,
    output logic [31:0] result,
    output logic [4:0]  flags
);
    import fp_defines_pkg::*;

    logic sign_a;
    logic sign_b;
    logic sign_c;
    logic product_sign;
    logic c_effective_sign;
    logic [7:0] exp_a;
    logic [7:0] exp_b;
    logic [7:0] exp_c;
    logic [22:0] frac_a;
    logic [22:0] frac_b;
    logic [22:0] frac_c;
    logic a_nan;
    logic b_nan;
    logic c_nan;
    logic a_snan;
    logic b_snan;
    logic c_snan;
    logic a_inf;
    logic b_inf;
    logic c_inf;
    logic a_zero;
    logic b_zero;
    logic c_zero;
    logic invalid_product;
    logic invalid_infinity_sum;
    logic [23:0] sig_a;
    logic [23:0] sig_b;
    logic [23:0] sig_c;
    logic [47:0] product;
    logic [55:0] product_ext;
    logic [55:0] c_ext;
    logic [55:0] big_ext;
    logic [55:0] small_ext;
    logic [55:0] aligned_small;
    logic [56:0] add_ext;
    logic [55:0] normalized;
    logic big_sign;
    logic small_sign;
    logic result_sign;
    logic product_is_big;
    logic [23:0] main_sig;
    logic [24:0] rounded_sig;
    logic [7:0] result_exp;
    logic [22:0] result_frac;
    logic inexact;
    logic increment;
    logic overflow_to_infinity;
    integer unbiased_a;
    integer unbiased_b;
    integer unbiased_c;
    integer product_exponent;
    integer c_exponent;
    integer result_exponent;
    integer exp_work;
    integer leading_a;
    integer leading_b;
    integer leading_c;
    integer product_leading;
    integer shift_a;
    integer shift_b;
    integer shift_c;
    integer align_shift;
    integer subnormal_shift;

    function automatic logic [55:0] shift_right_sticky(
        input logic [55:0] value,
        input integer amount
    );
        logic [55:0] shifted;
        logic sticky;
    begin
        shifted = '0;
        sticky = 1'b0;
        if (amount <= 0) begin
            shifted = value;
        end else if (amount >= 56) begin
            sticky = |value;
        end else begin
            shifted = value >> amount;
            for (int bit_idx = 0; bit_idx < 56; bit_idx++) begin
                if (bit_idx < amount) sticky = sticky | value[bit_idx];
            end
        end
        shifted[0] = shifted[0] | sticky;
        shift_right_sticky = shifted;
    end
    endfunction

    always_comb begin
        sign_a = operand_a[31];
        sign_b = operand_b[31];
        sign_c = operand_c[31];
        exp_a = operand_a[30:23];
        exp_b = operand_b[30:23];
        exp_c = operand_c[30:23];
        frac_a = operand_a[22:0];
        frac_b = operand_b[22:0];
        frac_c = operand_c[22:0];

        a_nan = (&exp_a) && (frac_a != '0);
        b_nan = (&exp_b) && (frac_b != '0);
        c_nan = (&exp_c) && (frac_c != '0);
        a_snan = a_nan && !frac_a[22];
        b_snan = b_nan && !frac_b[22];
        c_snan = c_nan && !frac_c[22];
        a_inf = (&exp_a) && (frac_a == '0);
        b_inf = (&exp_b) && (frac_b == '0);
        c_inf = (&exp_c) && (frac_c == '0);
        a_zero = (exp_a == '0) && (frac_a == '0);
        b_zero = (exp_b == '0) && (frac_b == '0);
        c_zero = (exp_c == '0) && (frac_c == '0);

        product_sign = sign_a ^ sign_b ^
                       ((operation == FP_OP_NMSUB) ||
                        (operation == FP_OP_NMADD));
        c_effective_sign = sign_c ^
                           ((operation == FP_OP_MSUB) ||
                            (operation == FP_OP_NMADD));
        invalid_product = (a_inf && b_zero) || (b_inf && a_zero);
        invalid_infinity_sum =
            (a_inf || b_inf) && c_inf &&
            (product_sign != c_effective_sign);

        sig_a = {(exp_a != '0), frac_a};
        sig_b = {(exp_b != '0), frac_b};
        sig_c = {(exp_c != '0), frac_c};
        unbiased_a = integer'(exp_a) - 127;
        unbiased_b = integer'(exp_b) - 127;
        unbiased_c = integer'(exp_c) - 127;
        leading_a = 0;
        leading_b = 0;
        leading_c = 0;
        shift_a = 0;
        shift_b = 0;
        shift_c = 0;

        if ((exp_a == '0) && !a_zero) begin
            for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
                if (frac_a[bit_idx]) leading_a = bit_idx;
            end
            shift_a = 23 - leading_a;
            sig_a = sig_a << shift_a;
            unbiased_a = -126 - shift_a;
        end
        if ((exp_b == '0) && !b_zero) begin
            for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
                if (frac_b[bit_idx]) leading_b = bit_idx;
            end
            shift_b = 23 - leading_b;
            sig_b = sig_b << shift_b;
            unbiased_b = -126 - shift_b;
        end
        if ((exp_c == '0) && !c_zero) begin
            for (int bit_idx = 0; bit_idx < 23; bit_idx++) begin
                if (frac_c[bit_idx]) leading_c = bit_idx;
            end
            shift_c = 23 - leading_c;
            sig_c = sig_c << shift_c;
            unbiased_c = -126 - shift_c;
        end

        product = sig_a * sig_b;
        product_leading = 0;
        for (int bit_idx = 0; bit_idx < 48; bit_idx++) begin
            if (product[bit_idx]) product_leading = bit_idx;
        end

        product_ext = '0;
        c_ext = '0;
        product_exponent = -1000;
        c_exponent = -1000;
        if (product != '0) begin
            product_ext = {8'b0, product} << (55 - product_leading);
            product_exponent =
                unbiased_a + unbiased_b - 46 + product_leading;
        end
        if (!c_zero) begin
            c_ext = {32'b0, sig_c} << 32;
            c_exponent = unbiased_c;
        end

        product_is_big =
            (product_exponent > c_exponent) ||
            ((product_exponent == c_exponent) &&
             (product_ext >= c_ext));
        if (product_is_big) begin
            big_ext = product_ext;
            small_ext = c_ext;
            big_sign = product_sign;
            small_sign = c_effective_sign;
            result_exponent = product_exponent;
            align_shift = product_exponent - c_exponent;
        end else begin
            big_ext = c_ext;
            small_ext = product_ext;
            big_sign = c_effective_sign;
            small_sign = product_sign;
            result_exponent = c_exponent;
            align_shift = c_exponent - product_exponent;
        end

        aligned_small = shift_right_sticky(small_ext, align_shift);
        add_ext = '0;
        normalized = '0;
        result_sign = big_sign;

        if (big_sign == small_sign) begin
            add_ext = {1'b0, big_ext} + {1'b0, aligned_small};
            if (add_ext[56]) begin
                normalized = add_ext[56:1];
                normalized[0] = add_ext[1] | add_ext[0];
                result_exponent = result_exponent + 1;
            end else begin
                normalized = add_ext[55:0];
            end
        end else begin
            normalized = big_ext - aligned_small;
            for (int shift_idx = 0; shift_idx < 55; shift_idx++) begin
                if (!normalized[55] && (normalized != '0)) begin
                    normalized = normalized << 1;
                    result_exponent = result_exponent - 1;
                end
            end
            if (normalized == '0) begin
                result_sign =
                    (product_sign == c_effective_sign) ?
                    product_sign : (rounding_mode == 3'b010);
            end
        end

        exp_work = result_exponent + 127;
        if ((normalized != '0) && (exp_work <= 0)) begin
            subnormal_shift = 1 - exp_work;
            normalized = shift_right_sticky(normalized, subnormal_shift);
            exp_work = 1;
        end else begin
            subnormal_shift = 0;
        end

        main_sig = normalized[55:32];
        inexact = |normalized[31:0];
        increment = 1'b0;
        unique case (rounding_mode)
            3'b000: increment = normalized[31] &&
                               (normalized[30] || (|normalized[29:0]) ||
                                main_sig[0]);
            3'b001: increment = 1'b0;
            3'b010: increment = result_sign && inexact;
            3'b011: increment = !result_sign && inexact;
            3'b100: increment = normalized[31];
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
        if (normalized == '0) begin
            result_exp = '0;
            result_frac = '0;
        end else if ((exp_work == 1) && !main_sig[23]) begin
            result_exp = '0;
        end else begin
            result_exp = exp_work[7:0];
        end

        overflow_to_infinity =
            (rounding_mode == 3'b000) ||
            (rounding_mode == 3'b100) ||
            ((rounding_mode == 3'b011) && !result_sign) ||
            ((rounding_mode == 3'b010) && result_sign);

        result = {result_sign, result_exp, result_frac};
        flags = '0;

        if (a_nan || b_nan || c_nan ||
            invalid_product || invalid_infinity_sum) begin
            result = 32'h7fc00000;
            flags[4] = a_snan || b_snan || c_snan ||
                       invalid_product || invalid_infinity_sum;
        end else if (a_inf || b_inf) begin
            result = {product_sign, 8'hff, 23'b0};
        end else if (c_inf) begin
            result = {c_effective_sign, 8'hff, 23'b0};
        end else if (exp_work >= 255) begin
            if (overflow_to_infinity) begin
                result = {result_sign, 8'hff, 23'b0};
            end else begin
                result = {result_sign, 8'hfe, 23'h7fffff};
            end
            flags[2] = 1'b1;
            flags[0] = 1'b1;
        end else begin
            flags[0] = inexact;
            flags[1] = (result_exp == '0) && inexact;
        end
    end

endmodule
