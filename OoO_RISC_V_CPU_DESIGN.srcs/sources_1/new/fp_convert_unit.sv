`timescale 1ns / 1ps

// RV32F integer/float conversion numerical core.
//
// Supports signed and unsigned 32-bit integer conversions in both directions.
// It performs exponent/significand decode, rounding-mode handling, saturation
// or invalid-result selection for out-of-range inputs, and IEEE exception flag
// production. The destination register domain is selected by decode metadata,
// not by the 32-bit bit pattern produced here.
module fp_convert_unit (
    input  logic [4:0]  operation,
    input  logic [2:0]  rounding_mode,
    input  logic [31:0] operand,
    output logic [31:0] result,
    output logic [4:0]  flags
);
    import fp_defines_pkg::*;

    logic sign;
    logic [7:0] exponent;
    logic [22:0] fraction;
    logic [23:0] significand;
    logic [31:0] integer_magnitude;
    logic [63:0] base_magnitude;
    logic [63:0] rounded_magnitude;
    logic [63:0] remainder_mask;
    logic [63:0] remainder_value;
    logic [63:0] half_value;
    logic [24:0] rounded_significand;
    logic inexact;
    logic greater_half;
    logic tie_half;
    logic increment;
    logic invalid;
    logic unsigned_conversion;
    integer unbiased_exponent;
    integer shift_amount;
    integer msb_index;
    integer scan_index;
    integer output_exponent;

    function automatic logic should_increment(
        input logic [2:0] rm,
        input logic       value_sign,
        input logic       value_inexact,
        input logic       value_greater_half,
        input logic       value_tie_half,
        input logic       retained_lsb
    );
    begin
        unique case (rm)
            3'b000: should_increment =
                value_greater_half || (value_tie_half && retained_lsb);
            3'b001: should_increment = 1'b0;
            3'b010: should_increment = value_sign && value_inexact;
            3'b011: should_increment = !value_sign && value_inexact;
            3'b100: should_increment =
                value_greater_half || value_tie_half;
            default: should_increment =
                value_greater_half || (value_tie_half && retained_lsb);
        endcase
    end
    endfunction

    always_comb begin
        sign = operand[31];
        exponent = operand[30:23];
        fraction = operand[22:0];
        significand = '0;
        integer_magnitude = '0;
        base_magnitude = '0;
        rounded_magnitude = '0;
        remainder_mask = '0;
        remainder_value = '0;
        half_value = '0;
        rounded_significand = '0;
        inexact = 1'b0;
        greater_half = 1'b0;
        tie_half = 1'b0;
        increment = 1'b0;
        invalid = 1'b0;
        unsigned_conversion = 1'b0;
        unbiased_exponent = 0;
        shift_amount = 0;
        msb_index = -1;
        scan_index = 0;
        output_exponent = 0;
        result = '0;
        flags = '0;

        if ((operation == FP_OP_CVT_W_S) ||
            (operation == FP_OP_CVT_WU_S)) begin
            unsigned_conversion = (operation == FP_OP_CVT_WU_S);

            if (exponent == 8'hff) begin
                invalid = 1'b1;
                if (fraction != '0) begin
                    result = unsigned_conversion ? 32'hffffffff :
                                                     32'h7fffffff;
                end else if (sign) begin
                    result = unsigned_conversion ? 32'h00000000 :
                                                     32'h80000000;
                end else begin
                    result = unsigned_conversion ? 32'hffffffff :
                                                     32'h7fffffff;
                end
            end else if ((exponent == '0) && (fraction == '0)) begin
                result = '0;
            end else begin
                significand = (exponent == '0) ?
                              {1'b0, fraction} : {1'b1, fraction};
                unbiased_exponent = (exponent == '0) ?
                                    -126 : (integer'(exponent) - 127);

                if (unbiased_exponent >= 23) begin
                    shift_amount = unbiased_exponent - 23;
                    if (shift_amount <= 39) begin
                        base_magnitude =
                            {40'b0, significand} << shift_amount;
                    end else begin
                        base_magnitude = 64'hffffffffffffffff;
                    end
                end else if (unbiased_exponent >= 0) begin
                    shift_amount = 23 - unbiased_exponent;
                    base_magnitude = significand >> shift_amount;
                    remainder_mask = (64'h1 << shift_amount) - 1'b1;
                    remainder_value =
                        {40'b0, significand} & remainder_mask;
                    half_value = 64'h1 << (shift_amount - 1);
                    inexact = (remainder_value != '0);
                    greater_half = (remainder_value > half_value);
                    tie_half = (remainder_value == half_value);
                end else begin
                    base_magnitude = '0;
                    inexact = (significand != '0);
                    if (unbiased_exponent == -1) begin
                        half_value = 64'h0000000000800000;
                        greater_half =
                            ({40'b0, significand} > half_value);
                        tie_half =
                            ({40'b0, significand} == half_value);
                    end
                end

                increment = should_increment(
                    rounding_mode,
                    sign,
                    inexact,
                    greater_half,
                    tie_half,
                    base_magnitude[0]
                );
                rounded_magnitude = base_magnitude + increment;

                if (unsigned_conversion) begin
                    invalid = (sign && (rounded_magnitude != '0)) ||
                              (!sign &&
                               (rounded_magnitude >
                                64'h00000000ffffffff));
                    if (invalid) begin
                        result = sign ? 32'h00000000 : 32'hffffffff;
                    end else begin
                        result = rounded_magnitude[31:0];
                    end
                end else begin
                    invalid =
                        (!sign &&
                         (rounded_magnitude > 64'h000000007fffffff)) ||
                        (sign &&
                         (rounded_magnitude > 64'h0000000080000000));
                    if (invalid) begin
                        result = sign ? 32'h80000000 : 32'h7fffffff;
                    end else if (sign) begin
                        result = (~rounded_magnitude[31:0]) + 1'b1;
                    end else begin
                        result = rounded_magnitude[31:0];
                    end
                end
            end

            if (invalid) begin
                flags[4] = 1'b1;
            end else if (inexact) begin
                flags[0] = 1'b1;
            end
        end else if ((operation == FP_OP_CVT_S_W) ||
                     (operation == FP_OP_CVT_S_WU)) begin
            unsigned_conversion = (operation == FP_OP_CVT_S_WU);
            sign = !unsigned_conversion && operand[31];
            integer_magnitude =
                sign ? ((~operand) + 1'b1) : operand;

            if (integer_magnitude == '0) begin
                result = '0;
            end else begin
                msb_index = -1;
                for (scan_index = 31; scan_index >= 0;
                     scan_index = scan_index - 1) begin
                    if ((msb_index < 0) &&
                        integer_magnitude[scan_index]) begin
                        msb_index = scan_index;
                    end
                end

                if (msb_index <= 23) begin
                    base_magnitude =
                        {32'b0, integer_magnitude} << (23 - msb_index);
                end else begin
                    shift_amount = msb_index - 23;
                    base_magnitude =
                        {32'b0, integer_magnitude} >> shift_amount;
                    remainder_mask = (64'h1 << shift_amount) - 1'b1;
                    remainder_value =
                        {32'b0, integer_magnitude} & remainder_mask;
                    half_value = 64'h1 << (shift_amount - 1);
                    inexact = (remainder_value != '0);
                    greater_half = (remainder_value > half_value);
                    tie_half = (remainder_value == half_value);
                end

                increment = should_increment(
                    rounding_mode,
                    sign,
                    inexact,
                    greater_half,
                    tie_half,
                    base_magnitude[0]
                );
                rounded_significand =
                    {1'b0, base_magnitude[23:0]} + increment;
                output_exponent = 127 + msb_index;

                if (rounded_significand[24]) begin
                    output_exponent = output_exponent + 1;
                    result = {
                        sign,
                        output_exponent[7:0],
                        rounded_significand[23:1]
                    };
                end else begin
                    result = {
                        sign,
                        output_exponent[7:0],
                        rounded_significand[22:0]
                    };
                end

                if (inexact) begin
                    flags[0] = 1'b1;
                end
            end
        end
    end

endmodule
