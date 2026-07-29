`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp domain wakeup smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_domain_wakeup_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic wb_valid;
    logic wb_is_fp;
    preg_t wb_preg;
    logic [31:0] wb_result;
    logic wb1_valid;
    logic wb1_is_fp;
    preg_t wb1_preg;
    logic [31:0] wb1_result;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;

    pip_if #(alu_rs_t) in0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) in1_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) out0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) out1_if (.clk(clk), .rst_n(rst_n));

    int errors;

    always #5 clk = ~clk;

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

    task automatic enqueue_waiter(
        input logic use_lane1,
        input logic source_is_fp,
        input rob_tag_t tag
    );
        alu_rs_t entry;
    begin
        entry = '0;
        entry.datapath.src_reg_1p = preg_t'(40);
        entry.datapath.src1_is_fp = source_is_fp;
        entry.datapath.rob_tag = tag;
        entry.src1_ready = 1'b0;
        entry.src2_ready = 1'b1;

        if (use_lane1) begin
            in1_if.data = entry;
            in1_if.valid = 1'b1;
        end else begin
            in0_if.data = entry;
            in0_if.valid = 1'b1;
        end
        step_clk();
        in0_if.valid = 1'b0;
        in1_if.valid = 1'b0;
    end
    endtask

    rs_2issue #(
        .T(alu_rs_t)
    ) u_rs (
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in_if(in0_if.consumer),
        .in1_if(in1_if.consumer),
        .out0_if(out0_if.producer),
        .out1_if(out1_if.producer)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        wb_valid = 1'b0;
        wb_is_fp = 1'b0;
        wb_preg = '0;
        wb_result = '0;
        wb1_valid = 1'b0;
        wb1_is_fp = 1'b0;
        wb1_preg = '0;
        wb1_result = '0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        in0_if.valid = 1'b0;
        in0_if.data = '0;
        in1_if.valid = 1'b0;
        in1_if.data = '0;
        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        errors = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        enqueue_waiter(1'b0, 1'b0, rob_tag_t'(1));
        enqueue_waiter(1'b0, 1'b1, rob_tag_t'(2));

        wb_valid = 1'b1;
        wb_is_fp = 1'b0;
        wb_preg = preg_t'(40);
        wb_result = 32'h11111111;
        step_clk();
        wb_valid = 1'b0;
        #1;
        check_ok(out0_if.valid && out0_if.data.datapath.rob_tag == rob_tag_t'(1),
                 "integer p40 writeback wakes the integer-domain waiter");
        check_ok(!out1_if.valid,
                 "integer p40 writeback does not wake FP p40");

        out0_if.ready = 1'b1;
        step_clk();
        out0_if.ready = 1'b0;

        wb_valid = 1'b1;
        wb_is_fp = 1'b1;
        wb_preg = preg_t'(40);
        wb_result = 32'h3f800000;
        step_clk();
        wb_valid = 1'b0;
        #1;
        check_ok(out0_if.valid && out0_if.data.datapath.rob_tag == rob_tag_t'(2),
                 "FP p40 writeback wakes the FP-domain waiter");
        check_ok(out0_if.data.datapath.src1_value == 32'h3f800000,
                 "FP wakeup forwards the FP payload");

        out0_if.ready = 1'b1;
        step_clk();
        out0_if.ready = 1'b0;
        check_ok(!out0_if.valid && !out1_if.valid,
                 "domain-separated waiters drain independently");

        if (errors == 0) begin
            $display("==== tb_fp_domain_wakeup_smoke PASS ====");
        end else begin
            $display("==== tb_fp_domain_wakeup_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
