`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp rename smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_rename_smoke;

    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic [1:0] rename_valid;
    logic rename_fire;
    fp_areg_t lane0_src0;
    fp_areg_t lane0_src1;
    fp_areg_t lane0_src2;
    fp_areg_t lane0_dest;
    fp_areg_t lane1_src0;
    fp_areg_t lane1_src1;
    fp_areg_t lane1_src2;
    fp_areg_t lane1_dest;
    fp_preg_t lane0_src0_preg;
    fp_preg_t lane0_src1_preg;
    fp_preg_t lane0_src2_preg;
    fp_preg_t lane0_new_preg;
    fp_preg_t lane0_old_preg;
    fp_preg_t lane1_src0_preg;
    fp_preg_t lane1_src1_preg;
    fp_preg_t lane1_src2_preg;
    fp_preg_t lane1_new_preg;
    fp_preg_t lane1_old_preg;
    logic rename_ready;
    logic [1:0] retire_valid;
    fp_areg_t retire_areg0;
    fp_areg_t retire_areg1;
    fp_preg_t retire_preg0;
    fp_preg_t retire_preg1;
    fp_preg_t retire_new_preg0;
    fp_preg_t retire_new_preg1;
    logic checkpoint_save;
    logic [1:0] checkpoint_id_save;
    logic restore_en;
    logic [1:0] restore_checkpoint_id;
    logic architectural_restore;
    int errors;

    always #5 clk = ~clk;

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

    task automatic apply_clock;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    fp_rename_map_2w u_dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .rename_valid         (rename_valid),
        .rename_fire          (rename_fire),
        .lane0_src0           (lane0_src0),
        .lane0_src1           (lane0_src1),
        .lane0_src2           (lane0_src2),
        .lane0_dest           (lane0_dest),
        .lane1_src0           (lane1_src0),
        .lane1_src1           (lane1_src1),
        .lane1_src2           (lane1_src2),
        .lane1_dest           (lane1_dest),
        .lane0_src0_preg      (lane0_src0_preg),
        .lane0_src1_preg      (lane0_src1_preg),
        .lane0_src2_preg      (lane0_src2_preg),
        .lane0_new_preg       (lane0_new_preg),
        .lane0_old_preg       (lane0_old_preg),
        .lane1_src0_preg      (lane1_src0_preg),
        .lane1_src1_preg      (lane1_src1_preg),
        .lane1_src2_preg      (lane1_src2_preg),
        .lane1_new_preg       (lane1_new_preg),
        .lane1_old_preg       (lane1_old_preg),
        .rename_ready         (rename_ready),
        .retire_valid         (retire_valid),
        .retire_areg0         (retire_areg0),
        .retire_areg1         (retire_areg1),
        .retire_preg0         (retire_preg0),
        .retire_preg1         (retire_preg1),
        .retire_new_preg0     (retire_new_preg0),
        .retire_new_preg1     (retire_new_preg1),
        .checkpoint_save      (checkpoint_save),
        .checkpoint_id_save   (checkpoint_id_save),
        .restore_en           (restore_en),
        .restore_checkpoint_id(restore_checkpoint_id),
        .architectural_restore(architectural_restore)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        rename_valid = '0;
        rename_fire = 1'b0;
        lane0_src0 = '0;
        lane0_src1 = '0;
        lane0_src2 = '0;
        lane0_dest = '0;
        lane1_src0 = '0;
        lane1_src1 = '0;
        lane1_src2 = '0;
        lane1_dest = '0;
        retire_valid = '0;
        retire_areg0 = '0;
        retire_areg1 = '0;
        retire_preg0 = '0;
        retire_preg1 = '0;
        retire_new_preg0 = '0;
        retire_new_preg1 = '0;
        checkpoint_save = 1'b0;
        checkpoint_id_save = '0;
        restore_en = 1'b0;
        restore_checkpoint_id = '0;
        architectural_restore = 1'b0;
        errors = 0;

        repeat (2) apply_clock();
        rst_n = 1'b1;
        apply_clock();

        // FLW-like destination in lane0 followed by an FP consumer in lane1.
        rename_valid = 2'b11;
        lane0_src0 = fp_areg_t'(1);
        lane0_src1 = fp_areg_t'(2);
        lane0_dest = fp_areg_t'(5);
        lane1_src0 = fp_areg_t'(5);
        lane1_src1 = fp_areg_t'(3);
        lane1_dest = fp_areg_t'(6);
        #1;
        check_ok(rename_ready, "two FP destinations can allocate together");
        check_ok(lane0_new_preg == fp_preg_t'(32) &&
                 lane1_new_preg == fp_preg_t'(33),
                 "FP free pool returns the first two speculative registers");
        check_ok(lane0_old_preg == fp_preg_t'(5) &&
                 lane1_old_preg == fp_preg_t'(6),
                 "FP RAT reports initial destination mappings");
        check_ok(lane1_src0_preg == lane0_new_preg,
                 "lane1 FP source observes lane0 same-packet rename");

        rename_fire = 1'b1;
        checkpoint_save = 1'b1;
        checkpoint_id_save = 2'd0;
        apply_clock();
        rename_fire = 1'b0;
        checkpoint_save = 1'b0;
        rename_valid = '0;

        lane0_src0 = fp_areg_t'(5);
        lane0_src1 = fp_areg_t'(6);
        #1;
        check_ok(lane0_src0_preg == fp_preg_t'(32) &&
                 lane0_src1_preg == fp_preg_t'(33),
                 "committed FP renames update the speculative map");

        // Two writes to the same architectural destination test WAW ordering.
        rename_valid = 2'b11;
        lane0_dest = fp_areg_t'(7);
        lane1_dest = fp_areg_t'(7);
        lane1_src0 = fp_areg_t'(7);
        #1;
        check_ok(lane0_new_preg == fp_preg_t'(34) &&
                 lane1_new_preg == fp_preg_t'(35),
                 "second FP packet receives two new physical registers");
        check_ok(lane1_old_preg == lane0_new_preg &&
                 lane1_src0_preg == lane0_new_preg,
                 "lane1 WAW and RAW observe lane0 allocation");
        rename_fire = 1'b1;
        apply_clock();
        rename_fire = 1'b0;
        rename_valid = '0;

        restore_en = 1'b1;
        restore_checkpoint_id = 2'd0;
        apply_clock();
        restore_en = 1'b0;
        lane0_src0 = fp_areg_t'(5);
        lane0_src1 = fp_areg_t'(6);
        lane0_src2 = fp_areg_t'(7);
        #1;
        check_ok(lane0_src0_preg == fp_preg_t'(32) &&
                 lane0_src1_preg == fp_preg_t'(33),
                 "checkpoint restore preserves older FP mappings");
        check_ok(lane0_src2_preg == fp_preg_t'(7),
                 "checkpoint restore removes younger FP mappings");

        // f0 is an ordinary FP register. Its old physical mapping can retire
        // and later return to the free pool.
        rename_valid = 2'b11;
        lane0_dest = fp_areg_t'(0);
        lane1_src0 = fp_areg_t'(0);
        lane1_dest = fp_areg_t'(7);
        #1;
        check_ok(lane0_new_preg == fp_preg_t'(34) &&
                 lane1_new_preg == fp_preg_t'(35),
                 "restored speculative allocations return to the FP free pool");
        check_ok(lane1_src0_preg == lane0_new_preg,
                 "same-packet dependency through f0 is preserved");
        rename_fire = 1'b1;
        apply_clock();
        rename_fire = 1'b0;
        rename_valid = '0;

        retire_valid = 2'b11;
        retire_areg0 = fp_areg_t'(0);
        retire_areg1 = fp_areg_t'(7);
        retire_preg0 = fp_preg_t'(0);
        retire_preg1 = fp_preg_t'(7);
        retire_new_preg0 = fp_preg_t'(34);
        retire_new_preg1 = fp_preg_t'(35);
        apply_clock();
        retire_valid = '0;

        rename_valid = 2'b11;
        lane0_dest = fp_areg_t'(8);
        lane1_dest = fp_areg_t'(9);
        #1;
        check_ok(lane0_new_preg == fp_preg_t'(0) &&
                 lane1_new_preg == fp_preg_t'(7),
                 "retired initial FP mappings, including f0, are recyclable");

        rename_fire = 1'b1;
        apply_clock();
        rename_fire = 1'b0;
        rename_valid = '0;

        architectural_restore = 1'b1;
        apply_clock();
        architectural_restore = 1'b0;

        lane0_src0 = fp_areg_t'(0);
        lane0_src1 = fp_areg_t'(7);
        lane0_src2 = fp_areg_t'(8);
        #1;
        check_ok(lane0_src0_preg == fp_preg_t'(34) &&
                 lane0_src1_preg == fp_preg_t'(35),
                 "FP architectural restore preserves retired mappings");
        check_ok(lane0_src2_preg == fp_preg_t'(8),
                 "FP architectural restore removes younger mapping");

        rename_valid = 2'b11;
        lane0_dest = fp_areg_t'(8);
        lane1_dest = fp_areg_t'(9);
        #1;
        check_ok(lane0_new_preg == fp_preg_t'(0) &&
                 lane1_new_preg == fp_preg_t'(7),
                 "FP architectural restore rebuilds the speculative free pool");

        if (errors == 0) begin
            $display("==== tb_fp_rename_smoke PASS ====");
        end else begin
            $display("==== tb_fp_rename_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
