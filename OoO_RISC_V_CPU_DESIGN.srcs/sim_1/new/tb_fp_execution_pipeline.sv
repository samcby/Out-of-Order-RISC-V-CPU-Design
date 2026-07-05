`timescale 1ns / 1ps

module tb_fp_execution_pipeline;

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
    int errors;

    always #5 clk = ~clk;

    fp_execution_pipeline #(
        .LATENCY(3)
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
        .out_flags(out_flags)
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

    task automatic drive_operation(
        input logic [4:0] operation,
        input logic [31:0] a,
        input logic [31:0] b,
        input rob_tag_t tag,
        input preg_t preg,
        input cp_mask_t mask
    );
    begin
        in_control = '0;
        in_control.fp_en = 1'b1;
        in_control.fp_op = operation;
        in_control.fp_rm = 3'b000;
        in_control.reg_write = 1'b1;
        in_datapath = '0;
        in_datapath.src1_value = a;
        in_datapath.src2_value = b;
        in_datapath.rob_tag = tag;
        in_datapath.new_des_preg = preg;
        in_datapath.dest_is_fp = 1'b1;
        in_datapath.speculation_mask = mask;
        in_valid = 1'b1;
        step_clk();
        in_valid = 1'b0;
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

        drive_operation(FP_OP_MUL, 32'h3fc00000, 32'h40000000,
                        rob_tag_t'(8'd12), preg_t'(7'd40), '0);
        check_ok(!out_valid, "FP result is not visible after one cycle");
        step_clk();
        check_ok(!out_valid, "FP result is not visible after two cycles");
        step_clk();
        check_ok(out_valid && out_tag == rob_tag_t'(8'd12),
                 "FP result becomes valid after three cycles");
        check_ok(out_result == 32'h40400000 && out_preg == preg_t'(7'd40),
                 "pipeline preserves FMUL result and destination metadata");

        step_clk();
        drive_operation(FP_OP_ADD, 32'h3f800000, 32'h40000000,
                        rob_tag_t'(8'd13), preg_t'(7'd41), '0);
        step_clk();
        out_ready = 1'b0;
        step_clk();
        check_ok(out_valid && out_tag == rob_tag_t'(8'd13),
                 "pipeline presents the next result under backpressure");
        step_clk();
        check_ok(out_valid && out_tag == rob_tag_t'(8'd13),
                 "pipeline holds its output while backpressured");
        check_ok(!in_ready, "backpressure propagates to the FP issue input");
        out_ready = 1'b1;
        step_clk();

        drive_operation(FP_OP_SUB, 32'h40000000, 32'h3f800000,
                        rob_tag_t'(8'd14), preg_t'(7'd42), cp_mask_t'(4'b0010));
        step_clk();
        squash_checkpoint_id = cp_id_t'(1);
        squash_en = 1'b1;
        step_clk();
        squash_en = 1'b0;
        repeat (3) step_clk();
        check_ok(!out_valid, "squashed FP operation never reaches completion");

        if (errors == 0) begin
            $display("==== tb_fp_execution_pipeline PASS ====");
        end else begin
            $display("==== tb_fp_execution_pipeline FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
