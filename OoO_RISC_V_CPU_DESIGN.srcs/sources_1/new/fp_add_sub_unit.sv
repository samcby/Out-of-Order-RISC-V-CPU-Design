`timescale 1ns / 1ps

// IEEE-754 single-precision add/subtract numerical core.
//
// Unpacks operands, orders magnitudes, aligns the smaller significand with a
// sticky bit, performs add/subtract, normalizes, rounds according to rm, and
// handles NaN/Inf/zero/subnormal special cases. The output flags use the RISC-V
// fflags ordering NV,DZ,OF,UF,NX. This core is combinational; fp_execution_pipeline
// supplies the externally visible fixed latency and speculative metadata.
module fp_add_sub_unit (
    input  logic        subtract,
    input  logic [2:0]  rounding_mode,
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    output logic [31:0] result,
    output logic [4:0]  flags
);

    logic sign_a;
    logic sign_b;
    logic sign_b_effective;
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
    logic [26:0] ext_a;
    logic [26:0] ext_b;
    logic [26:0] big_ext;
    logic [26:0] small_ext;
    logic [26:0] aligned_small;
    logic [27:0] add_ext;
    logic [26:0] norm_ext;
    logic [23:0] main_sig;
    logic [24:0] rounded_sig;
    logic result_sign;
    logic big_sign;
    logic small_sign;
    logic magnitude_a_ge_b;
    logic inexact;
    logic increment;
    logic overflow_to_infinity;
    logic [7:0] result_exp;
    logic [22:0] result_frac;
    integer exp_a_eff;
    integer exp_b_eff;
    integer exp_work;
    integer shift_amount;

    function automatic logic [26:0] shift_right_sticky(
        input logic [26:0] value,
        input integer amount
    );
        logic sticky;
        logic [26:0] shifted;
    begin
        sticky = 1'b0;
        shifted = '0;
        if (amount <= 0) begin
            shifted = value;
        end else if (amount >= 27) begin
            shifted = '0;
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
        sign_a = operand_a[31];
        sign_b = operand_b[31];
        sign_b_effective = sign_b ^ subtract;
        exp_a = operand_a[30:23];
        exp_b = operand_b[30:23];
        frac_a = operand_a[22:0];
        frac_b = operand_b[22:0];

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
        ext_a = {sig_a, 3'b000};
        ext_b = {sig_b, 3'b000};
        exp_a_eff = (exp_a == 8'b0) ? 1 : exp_a;
        exp_b_eff = (exp_b == 8'b0) ? 1 : exp_b;

        magnitude_a_ge_b =
            (exp_a_eff > exp_b_eff) ||
            ((exp_a_eff == exp_b_eff) && (sig_a >= sig_b));

        if (magnitude_a_ge_b) begin
            big_ext = ext_a;
            small_ext = ext_b;
            big_sign = sign_a;
            small_sign = sign_b_effective;
            exp_work = exp_a_eff;
            shift_amount = exp_a_eff - exp_b_eff;
        end else begin
            big_ext = ext_b;
            small_ext = ext_a;
            big_sign = sign_b_effective;
            small_sign = sign_a;
            exp_work = exp_b_eff;
            shift_amount = exp_b_eff - exp_a_eff;
        end

        aligned_small = shift_right_sticky(small_ext, shift_amount);
        add_ext = '0;
        norm_ext = '0;
        result_sign = big_sign;

        if (big_sign == small_sign) begin
            add_ext = {1'b0, big_ext} + {1'b0, aligned_small};
            if (add_ext[27]) begin
                norm_ext = add_ext[27:1];
                norm_ext[0] = add_ext[1] | add_ext[0];
                exp_work = exp_work + 1;
            end else begin
                norm_ext = add_ext[26:0];
            end
        end else begin
            norm_ext = big_ext - aligned_small;
            for (int shift_idx = 0; shift_idx < 26; shift_idx++) begin
                if (!norm_ext[26] && (norm_ext != 27'b0) &&
                    (exp_work > 1)) begin
                    norm_ext = norm_ext << 1;
                    exp_work = exp_work - 1;
                end
            end
            if (norm_ext == 27'b0) begin
                result_sign = (rounding_mode == 3'b010);
            end
        end

        main_sig = norm_ext[26:3];
        inexact = |norm_ext[2:0];
        increment = 1'b0;
        unique case (rounding_mode)
            3'b000: increment = norm_ext[2] &&
                               (norm_ext[1] || norm_ext[0] || main_sig[0]);
            3'b001: increment = 1'b0;
            3'b010: increment = result_sign && inexact;
            3'b011: increment = !result_sign && inexact;
            3'b100: increment = norm_ext[2];
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
        if (norm_ext == 27'b0) begin
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

        if (a_nan || b_nan) begin
            result = 32'h7fc00000;
            flags[4] = a_snan || b_snan;
        end else if (a_inf && b_inf &&
                     (sign_a != sign_b_effective)) begin
            result = 32'h7fc00000;
            flags[4] = 1'b1;
        end else if (a_inf) begin
            result = {sign_a, 8'hff, 23'b0};
        end else if (b_inf) begin
            result = {sign_b_effective, 8'hff, 23'b0};
        end else if (a_zero && b_zero) begin
            if (sign_a == sign_b_effective) begin
                result = {sign_a, 31'b0};
            end else begin
                result = {(rounding_mode == 3'b010), 31'b0};
            end
        end else if (a_zero) begin
            result = {sign_b_effective, exp_b, frac_b};
        end else if (b_zero) begin
            result = operand_a;
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
            flags[1] = (result_exp == 8'b0) && inexact;
        end
    end

endmodule
