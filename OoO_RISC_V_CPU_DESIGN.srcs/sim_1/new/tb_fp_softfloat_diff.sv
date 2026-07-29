`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp softfloat diff.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_softfloat_diff;
    import fp_defines_pkg::*;

    logic [4:0]  operation;
    logic [2:0]  rounding_mode;
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic [31:0] operand_c;

    logic [31:0] add_sub_result;
    logic [4:0]  add_sub_flags;
    logic [31:0] mul_result;
    logic [4:0]  mul_flags;
    logic [31:0] div_sqrt_result;
    logic [4:0]  div_sqrt_flags;
    logic [31:0] fma_result;
    logic [4:0]  fma_flags;
    logic [31:0] convert_result;
    logic [4:0]  convert_flags;
    logic [31:0] simple_result;
    logic [4:0]  simple_flags;
    logic [31:0] actual_result;
    logic [4:0]  actual_flags;

    integer vector_file;
    integer scan_count;
    integer operation_scan;
    integer rounding_scan;
    integer vector_count;
    integer error_count;
    integer displayed_errors;
    reg [31:0] expected_result;
    reg [7:0] expected_flags_scan;
    reg [1023:0] vector_path;

    fp_add_sub_unit u_add_sub (
        .subtract(operation == FP_OP_SUB),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(add_sub_result),
        .flags(add_sub_flags)
    );

    fp_mul_unit u_mul (
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(mul_result),
        .flags(mul_flags)
    );

    fp_div_sqrt_unit u_div_sqrt (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(div_sqrt_result),
        .flags(div_sqrt_flags)
    );

    fp_fma_unit u_fma (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .operand_c(operand_c),
        .result(fma_result),
        .flags(fma_flags)
    );

    fp_convert_unit u_convert (
        .operation(operation),
        .rounding_mode(rounding_mode),
        .operand(operand_a),
        .result(convert_result),
        .flags(convert_flags)
    );

    fp_simple_unit u_simple (
        .operation(operation),
        .operand_a(operand_a),
        .operand_b(operand_b),
        .result(simple_result),
        .flags(simple_flags)
    );

    always_comb begin
        actual_result = 32'b0;
        actual_flags = 5'b0;

        case (operation)
            FP_OP_ADD,
            FP_OP_SUB: begin
                actual_result = add_sub_result;
                actual_flags = add_sub_flags;
            end

            FP_OP_MUL: begin
                actual_result = mul_result;
                actual_flags = mul_flags;
            end

            FP_OP_DIV,
            FP_OP_SQRT: begin
                actual_result = div_sqrt_result;
                actual_flags = div_sqrt_flags;
            end

            FP_OP_MADD,
            FP_OP_MSUB,
            FP_OP_NMSUB,
            FP_OP_NMADD: begin
                actual_result = fma_result;
                actual_flags = fma_flags;
            end

            FP_OP_CVT_W_S,
            FP_OP_CVT_WU_S,
            FP_OP_CVT_S_W,
            FP_OP_CVT_S_WU: begin
                actual_result = convert_result;
                actual_flags = convert_flags;
            end

            FP_OP_EQ,
            FP_OP_LT,
            FP_OP_LE: begin
                actual_result = simple_result;
                actual_flags = simple_flags;
            end

            default: begin
                actual_result = 32'bx;
                actual_flags = 5'bx;
            end
        endcase
    end

    task open_vector_file;
        begin
            vector_file = 0;

            if ($value$plusargs("SOFTFLOAT_VECTORS=%s", vector_path)) begin
                vector_file = $fopen(vector_path, "r");
            end

            if (vector_file == 0) begin
                vector_path = "fp_softfloat_vectors.txt";
                vector_file = $fopen(vector_path, "r");
            end

            if (vector_file == 0) begin
                vector_path = "OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new/fp_softfloat_vectors.txt";
                vector_file = $fopen(vector_path, "r");
            end

            if (vector_file == 0) begin
                vector_path = "../../../../OoO_RISC_V_CPU_DESIGN.srcs/sim_1/new/fp_softfloat_vectors.txt";
                vector_file = $fopen(vector_path, "r");
            end

            if (vector_file == 0) begin
                $display("[FAIL] unable to open SoftFloat vector file; use +SOFTFLOAT_VECTORS=<absolute-path>");
                $fatal;
            end
        end
    endtask

    initial begin
        operation = FP_OP_NONE;
        rounding_mode = 3'b000;
        operand_a = 32'b0;
        operand_b = 32'b0;
        operand_c = 32'b0;
        vector_count = 0;
        error_count = 0;
        displayed_errors = 0;

        open_vector_file();

        while (!$feof(vector_file)) begin
            scan_count = $fscanf(
                vector_file,
                "%h %h %h %h %h %h %h\n",
                operation_scan,
                rounding_scan,
                operand_a,
                operand_b,
                operand_c,
                expected_result,
                expected_flags_scan
            );

            if (scan_count == 7) begin
                operation = operation_scan[4:0];
                rounding_mode = rounding_scan[2:0];
                #1;
                vector_count = vector_count + 1;

                if ((actual_result !== expected_result) ||
                    (actual_flags !== expected_flags_scan[4:0])) begin
                    error_count = error_count + 1;
                    if (displayed_errors < 20) begin
                        $display(
                            "[DIFF] vector=%0d op=%0d rm=%0d a=%08x b=%08x c=%08x rtl=%08x/%02x ref=%08x/%02x",
                            vector_count,
                            operation,
                            rounding_mode,
                            operand_a,
                            operand_b,
                            operand_c,
                            actual_result,
                            actual_flags,
                            expected_result,
                            expected_flags_scan[4:0]
                        );
                        displayed_errors = displayed_errors + 1;
                    end
                end
            end else if (!$feof(vector_file)) begin
                $display(
                    "[FAIL] malformed SoftFloat vector after vector %0d",
                    vector_count
                );
                $fatal;
            end
        end

        $fclose(vector_file);
        $display(
            "[SUMMARY] SoftFloat vectors=%0d mismatches=%0d",
            vector_count,
            error_count
        );

        if (error_count == 0) begin
            $display("==== tb_fp_softfloat_diff PASS ====");
        end else begin
            $display(
                "==== tb_fp_softfloat_diff FAIL (%0d mismatches) ====",
                error_count
            );
        end
        $finish;
    end

endmodule
