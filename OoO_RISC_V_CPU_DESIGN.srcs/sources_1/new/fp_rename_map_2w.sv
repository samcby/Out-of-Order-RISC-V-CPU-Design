`timescale 1ns / 1ps

// Integrated two-wide FP rename helper.
//
// Couples fp_rat_2w source/destination mapping with fp_free_pool_2w allocation
// so a packet either receives all required FP resources or does not rename.
// It returns old mappings for later ROB retirement, new mappings for execution,
// and checkpoint metadata for speculative recovery. Three FP source operands
// per lane are supported for FMA-family instructions.
module fp_rename_map_2w #(
    parameter int CHECKPOINT_NUM = 4,
    parameter int CHECKPOINT_W   = $clog2(CHECKPOINT_NUM)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [1:0] rename_valid,
    input  logic rename_fire,

    input  fp_defines_pkg::fp_areg_t lane0_src0,
    input  fp_defines_pkg::fp_areg_t lane0_src1,
    input  fp_defines_pkg::fp_areg_t lane0_src2,
    input  fp_defines_pkg::fp_areg_t lane0_dest,
    input  fp_defines_pkg::fp_areg_t lane1_src0,
    input  fp_defines_pkg::fp_areg_t lane1_src1,
    input  fp_defines_pkg::fp_areg_t lane1_src2,
    input  fp_defines_pkg::fp_areg_t lane1_dest,

    output fp_defines_pkg::fp_preg_t lane0_src0_preg,
    output fp_defines_pkg::fp_preg_t lane0_src1_preg,
    output fp_defines_pkg::fp_preg_t lane0_src2_preg,
    output fp_defines_pkg::fp_preg_t lane0_new_preg,
    output fp_defines_pkg::fp_preg_t lane0_old_preg,
    output fp_defines_pkg::fp_preg_t lane1_src0_preg,
    output fp_defines_pkg::fp_preg_t lane1_src1_preg,
    output fp_defines_pkg::fp_preg_t lane1_src2_preg,
    output fp_defines_pkg::fp_preg_t lane1_new_preg,
    output fp_defines_pkg::fp_preg_t lane1_old_preg,
    output logic rename_ready,

    input  logic [1:0] retire_valid,
    input  fp_defines_pkg::fp_preg_t retire_preg0,
    input  fp_defines_pkg::fp_preg_t retire_preg1,

    input  logic checkpoint_save,
    input  logic [CHECKPOINT_W-1:0] checkpoint_id_save,
    input  logic restore_en,
    input  logic [CHECKPOINT_W-1:0] restore_checkpoint_id
);

    logic allocate_valid0;
    logic allocate_valid1;
    logic has_free_1;
    logic has_free_2;
    logic [1:0] needed_count;
    logic [1:0] rat_write_en;
    logic checkpoint_commit;

    assign needed_count = {1'b0, rename_valid[0]} +
                          {1'b0, rename_valid[1]};
    assign rename_ready = (needed_count == 2'd0) ||
                          (needed_count == 2'd1 && has_free_1) ||
                          (needed_count == 2'd2 && has_free_2);
    assign rat_write_en = (rename_fire && rename_ready) ?
                          rename_valid : 2'b00;
    assign checkpoint_commit = checkpoint_save && rename_fire && rename_ready;

    fp_rat_2w #(
        .CHECKPOINT_NUM(CHECKPOINT_NUM),
        .CHECKPOINT_W  (CHECKPOINT_W)
    ) u_fp_rat (
        .clk                  (clk),
        .rst_n                (rst_n),
        .bypass_en            (rename_ready ? rename_valid : 2'b00),
        .write_en             (rat_write_en),
        .checkpoint_save      (checkpoint_commit),
        .checkpoint_id_save   (checkpoint_id_save),
        .restore_en           (restore_en),
        .restore_checkpoint_id(restore_checkpoint_id),
        .lane0_src0           (lane0_src0),
        .lane0_src1           (lane0_src1),
        .lane0_src2           (lane0_src2),
        .lane0_dest           (lane0_dest),
        .lane0_new_preg       (lane0_new_preg),
        .lane1_src0           (lane1_src0),
        .lane1_src1           (lane1_src1),
        .lane1_src2           (lane1_src2),
        .lane1_dest           (lane1_dest),
        .lane1_new_preg       (lane1_new_preg),
        .lane0_src0_preg      (lane0_src0_preg),
        .lane0_src1_preg      (lane0_src1_preg),
        .lane0_src2_preg      (lane0_src2_preg),
        .lane0_old_preg       (lane0_old_preg),
        .lane1_src0_preg      (lane1_src0_preg),
        .lane1_src1_preg      (lane1_src1_preg),
        .lane1_src2_preg      (lane1_src2_preg),
        .lane1_old_preg       (lane1_old_preg)
    );

    fp_free_pool_2w #(
        .CHECKPOINT_NUM(CHECKPOINT_NUM),
        .CHECKPOINT_W  (CHECKPOINT_W)
    ) u_fp_free_pool (
        .clk                  (clk),
        .rst_n                (rst_n),
        .retire_valid         (retire_valid),
        .retire_preg0         (retire_preg0),
        .retire_preg1         (retire_preg1),
        .allocate             (rename_valid),
        .allocate_commit      (rename_fire && rename_ready),
        .allocate_preg0       (lane0_new_preg),
        .allocate_preg1       (lane1_new_preg),
        .allocate_valid0      (allocate_valid0),
        .allocate_valid1      (allocate_valid1),
        .has_free_1           (has_free_1),
        .has_free_2           (has_free_2),
        .checkpoint_save      (checkpoint_commit),
        .checkpoint_id_save   (checkpoint_id_save),
        .restore_en           (restore_en),
        .restore_checkpoint_id(restore_checkpoint_id)
    );

endmodule
