`timescale 1ns / 1ps

// Two-wide speculative floating-point register-alias table.
//
// Provides three source mappings per lane for fused multiply-add operations and
// accepts up to two destination updates. Same-packet forwarding makes lane 1
// observe lane 0's rename before its own source/destination decisions. Complete
// map snapshots support branch checkpoint restore. Unlike integer x0, f0 is
// writable and participates in ordinary mapping updates.
module fp_rat_2w #(
    parameter int CHECKPOINT_NUM = 4,
    parameter int CHECKPOINT_W   = $clog2(CHECKPOINT_NUM)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [1:0] bypass_en,
    input  logic [1:0] write_en,

    input  logic checkpoint_save,
    input  logic [CHECKPOINT_W-1:0] checkpoint_id_save,
    input  logic restore_en,
    input  logic [CHECKPOINT_W-1:0] restore_checkpoint_id,
    input  logic architectural_restore,

    input  logic [1:0] retire_valid,
    input  fp_defines_pkg::fp_areg_t retire_areg0,
    input  fp_defines_pkg::fp_areg_t retire_areg1,
    input  fp_defines_pkg::fp_preg_t retire_new_preg0,
    input  fp_defines_pkg::fp_preg_t retire_new_preg1,

    input  fp_defines_pkg::fp_areg_t lane0_src0,
    input  fp_defines_pkg::fp_areg_t lane0_src1,
    input  fp_defines_pkg::fp_areg_t lane0_src2,
    input  fp_defines_pkg::fp_areg_t lane0_dest,
    input  fp_defines_pkg::fp_preg_t lane0_new_preg,

    input  fp_defines_pkg::fp_areg_t lane1_src0,
    input  fp_defines_pkg::fp_areg_t lane1_src1,
    input  fp_defines_pkg::fp_areg_t lane1_src2,
    input  fp_defines_pkg::fp_areg_t lane1_dest,
    input  fp_defines_pkg::fp_preg_t lane1_new_preg,

    output fp_defines_pkg::fp_preg_t lane0_src0_preg,
    output fp_defines_pkg::fp_preg_t lane0_src1_preg,
    output fp_defines_pkg::fp_preg_t lane0_src2_preg,
    output fp_defines_pkg::fp_preg_t lane0_old_preg,
    output fp_defines_pkg::fp_preg_t lane1_src0_preg,
    output fp_defines_pkg::fp_preg_t lane1_src1_preg,
    output fp_defines_pkg::fp_preg_t lane1_src2_preg,
    output fp_defines_pkg::fp_preg_t lane1_old_preg,
    output logic [fp_defines_pkg::FP_PREG_NUM-1:0] mapped_bitmap
);

    import fp_defines_pkg::*;

    fp_preg_t rat [0:FP_AREG_NUM-1];
    fp_preg_t committed_rat [0:FP_AREG_NUM-1];
    fp_preg_t checkpoints [0:CHECKPOINT_NUM-1][0:FP_AREG_NUM-1];

    assign lane0_src0_preg = rat[lane0_src0];
    assign lane0_src1_preg = rat[lane0_src1];
    assign lane0_src2_preg = rat[lane0_src2];
    assign lane0_old_preg  = rat[lane0_dest];

    assign lane1_src0_preg =
        (bypass_en[0] && lane1_src0 == lane0_dest) ?
        lane0_new_preg : rat[lane1_src0];
    assign lane1_src1_preg =
        (bypass_en[0] && lane1_src1 == lane0_dest) ?
        lane0_new_preg : rat[lane1_src1];
    assign lane1_src2_preg =
        (bypass_en[0] && lane1_src2 == lane0_dest) ?
        lane0_new_preg : rat[lane1_src2];
    assign lane1_old_preg =
        (bypass_en[0] && lane1_dest == lane0_dest) ?
        lane0_new_preg : rat[lane1_dest];

    always_comb begin
        mapped_bitmap = '0;
        for (int i = 0; i < FP_AREG_NUM; i++) begin
            if (architectural_restore === 1'b1) begin
                mapped_bitmap[committed_rat[i]] = 1'b1;
            end else if (restore_en) begin
                mapped_bitmap[checkpoints[restore_checkpoint_id][i]] = 1'b1;
            end else begin
                mapped_bitmap[rat[i]] = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FP_AREG_NUM; i++) begin
                rat[i] <= fp_preg_t'(i);
                committed_rat[i] <= fp_preg_t'(i);
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][i] <= fp_preg_t'(i);
                end
            end
        end else if (architectural_restore === 1'b1) begin
            for (int i = 0; i < FP_AREG_NUM; i++) begin
                rat[i] <= committed_rat[i];
            end
        end else if (restore_en) begin
            for (int i = 0; i < FP_AREG_NUM; i++) begin
                rat[i] <= checkpoints[restore_checkpoint_id][i];
            end
        end else begin
            if (checkpoint_save) begin
                for (int i = 0; i < FP_AREG_NUM; i++) begin
                    checkpoints[checkpoint_id_save][i] <= rat[i];
                end
                if (write_en[0]) begin
                    checkpoints[checkpoint_id_save][lane0_dest] <= lane0_new_preg;
                end
                if (write_en[1]) begin
                    checkpoints[checkpoint_id_save][lane1_dest] <= lane1_new_preg;
                end
            end

            if (write_en[0]) rat[lane0_dest] <= lane0_new_preg;
            if (write_en[1]) rat[lane1_dest] <= lane1_new_preg;
        end

        if (rst_n) begin
            if (retire_valid[0] === 1'b1) begin
                committed_rat[retire_areg0] <= retire_new_preg0;
            end
            if (retire_valid[1] === 1'b1) begin
                committed_rat[retire_areg1] <= retire_new_preg1;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n === 1'b1) begin
            assert (!((retire_valid[0] === 1'b1) &&
                      (retire_valid[1] === 1'b1) &&
                      (retire_areg0 != retire_areg1)) ||
                    (retire_new_preg0 != retire_new_preg1))
                else $error("[ASSERT:FP_RAT] dual retirement reused one physical register");
        end
    end
`endif

endmodule
