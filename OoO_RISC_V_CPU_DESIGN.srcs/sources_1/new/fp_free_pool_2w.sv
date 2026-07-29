`timescale 1ns / 1ps

// Two-wide floating-point physical-register allocator.
//
// Functionally mirrors the integer free pool but uses the independent FP
// register namespace. f0 is an ordinary writable architectural register, so
// physical register zero is not treated as a hard-wired constant. Allocation,
// retirement reclamation, checkpoint save, resolve, and restore are all kept
// coherent with the FP RAT.
module fp_free_pool_2w #(
    parameter int CHECKPOINT_NUM = 4,
    parameter int CHECKPOINT_W   = $clog2(CHECKPOINT_NUM)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic [1:0] retire_valid,
    input  fp_defines_pkg::fp_preg_t retire_preg0,
    input  fp_defines_pkg::fp_preg_t retire_preg1,
    input  logic [1:0] allocate,
    input  logic allocate_commit,

    output fp_defines_pkg::fp_preg_t allocate_preg0,
    output fp_defines_pkg::fp_preg_t allocate_preg1,
    output logic allocate_valid0,
    output logic allocate_valid1,
    output logic has_free_1,
    output logic has_free_2,

    input  logic checkpoint_save,
    input  logic [CHECKPOINT_W-1:0] checkpoint_id_save,
    input  logic restore_en,
    input  logic [CHECKPOINT_W-1:0] restore_checkpoint_id
);

    import fp_defines_pkg::*;

    logic [FP_PREG_NUM-1:0] free_bitmap_q;
    logic [FP_PREG_NUM-1:0] free_bitmap_n;
    logic [FP_PREG_NUM-1:0] search_bitmap;
    logic [FP_PREG_NUM-1:0] checkpoint_bitmap;
    logic [FP_PREG_NUM-1:0] checkpoints [0:CHECKPOINT_NUM-1];
    logic [$clog2(FP_PREG_NUM+1)-1:0] free_count;

    always_comb begin
        free_count = '0;
        for (int i = 0; i < FP_PREG_NUM; i++) begin
            if (free_bitmap_q[i]) free_count = free_count + 1'b1;
        end
    end

    assign has_free_1 = (free_count >= 1);
    assign has_free_2 = (free_count >= 2);

    always_comb begin
        allocate_preg0 = '0;
        allocate_preg1 = '0;
        allocate_valid0 = 1'b0;
        allocate_valid1 = 1'b0;
        search_bitmap = free_bitmap_q;

        if (allocate[0]) begin
            for (int i = 0; i < FP_PREG_NUM; i++) begin
                if (!allocate_valid0 && search_bitmap[i]) begin
                    allocate_valid0 = 1'b1;
                    allocate_preg0 = fp_preg_t'(i);
                    search_bitmap[i] = 1'b0;
                end
            end
        end

        if (allocate[1]) begin
            for (int i = 0; i < FP_PREG_NUM; i++) begin
                if (!allocate_valid1 && search_bitmap[i]) begin
                    allocate_valid1 = 1'b1;
                    allocate_preg1 = fp_preg_t'(i);
                    search_bitmap[i] = 1'b0;
                end
            end
        end

        free_bitmap_n = free_bitmap_q;
        if (allocate_commit && allocate[0] && allocate_valid0) begin
            free_bitmap_n[allocate_preg0] = 1'b0;
        end
        if (allocate_commit && allocate[1] && allocate_valid1) begin
            free_bitmap_n[allocate_preg1] = 1'b0;
        end
        if (retire_valid[0]) free_bitmap_n[retire_preg0] = 1'b1;
        if (retire_valid[1]) free_bitmap_n[retire_preg1] = 1'b1;

        checkpoint_bitmap = free_bitmap_n;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FP_PREG_NUM; i++) begin
                free_bitmap_q[i] <= (i >= FP_AREG_NUM);
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][i] <= (i >= FP_AREG_NUM);
                end
            end
        end else begin
            if (restore_en) begin
                free_bitmap_q <= checkpoints[restore_checkpoint_id];
                if (retire_valid[0]) free_bitmap_q[retire_preg0] <= 1'b1;
                if (retire_valid[1]) free_bitmap_q[retire_preg1] <= 1'b1;
            end else begin
                free_bitmap_q <= free_bitmap_n;
            end

            if (retire_valid[0]) begin
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][retire_preg0] <= 1'b1;
                end
            end
            if (retire_valid[1]) begin
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][retire_preg1] <= 1'b1;
                end
            end

            if (checkpoint_save) begin
                checkpoints[checkpoint_id_save] <= checkpoint_bitmap;
            end
        end
    end

endmodule
