`timescale 1ns / 1ps

module tb_fp_div_sqrt_iterative;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    logic in_valid;
    logic in_ready;
    alu_control_t in_control;
    rs_datapath_t in_datapath;
    logic [2:0] fp_frm;
    logic out_valid;
    logic out_ready;
    rob_tag_t out_tag;
    preg_t out_preg;
    logic out_dest_is_fp;
    logic out_reg_write;
    logic [31:0] out_result;
    logic [4:0] out_flags;
    logic busy;
    int errors;
    int wait_cycles;

    always #5 clk = ~clk;

    fp_div_sqrt_iterative #(
        .DIV_LATENCY(4),
        .SQRT_LATENCY(6)
    ) u_dut (
        .clk(clk),
        .rst_n(rst_n),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_control(in_control),
        .in_datapath(in_datapath),
        .fp_frm(fp_frm),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .out_tag(out_tag),
        .out_preg(out_preg),
        .out_dest_is_fp(out_dest_is_fp),
        .out_reg_write(out_reg_write),
        .out_result(out_result),
        .out_flags(out_flags),
        .busy(busy)
    );

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic condition, input string message);
    begin
        if (condition) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s", message);
            errors = errors + 1;
        end
    end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        in_valid = 1'b0;
        in_control = '0;
        in_datapath = '0;
        fp_frm = 3'b000;
        out_ready = 1'b1;
        errors = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        in_control.fp_en = 1'b1;
        in_control.fp_op = FP_OP_DIV;
        in_control.fp_rm = 3'b000;
        in_control.reg_write = 1'b1;
        in_datapath.src1_value = 32'h40c00000;
        in_datapath.src2_value = 32'h40000000;
        in_datapath.rob_tag = rob_tag_t'(7);
        in_datapath.new_des_preg = preg_t'(40);
        in_datapath.dest_is_fp = 1'b1;
        in_valid = 1'b1;
        check_ok(in_ready, "shared long-latency unit accepts FDIV");
        step_clk();
        in_valid = 1'b0;
        check_ok(busy && !in_ready,
                 "FDIV occupies the shared unit");

        wait_cycles = 0;
        while (!out_valid && (wait_cycles < 10)) begin
            step_clk();
            wait_cycles = wait_cycles + 1;
        end
        check_ok(out_valid && (wait_cycles >= 3),
                 "FDIV result appears only after configured latency");
        check_ok((out_result == 32'h40400000) &&
                 (out_tag == rob_tag_t'(7)) &&
                 (out_preg == preg_t'(40)) &&
                 out_dest_is_fp && out_reg_write,
                 "FDIV preserves result and completion metadata");

        out_ready = 1'b0;
        step_clk();
        check_ok(out_valid && (out_result == 32'h40400000),
                 "long-latency result holds under backpressure");
        out_ready = 1'b1;
        step_clk();
        check_ok(!out_valid, "accepted FDIV result releases the unit");

        in_control.fp_op = FP_OP_SQRT;
        in_datapath.src1_value = 32'h40000000;
        in_datapath.rob_tag = rob_tag_t'(9);
        in_datapath.new_des_preg = preg_t'(42);
        in_datapath.speculation_mask = 4'b0010;
        in_valid = 1'b1;
        step_clk();
        in_valid = 1'b0;
        check_ok(busy, "FSQRT starts as a long-latency operation");

        squash_checkpoint_id = cp_id_t'(1);
        squash_en = 1'b1;
        step_clk();
        squash_en = 1'b0;
        check_ok(!busy && !out_valid,
                 "branch squash cancels an in-flight FSQRT");

        repeat (8) step_clk();
        check_ok(!out_valid,
                 "squashed FSQRT never produces a late completion");

        if (errors == 0) begin
            $display("==== tb_fp_div_sqrt_iterative PASS ====");
        end else begin
            $display("==== tb_fp_div_sqrt_iterative FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
