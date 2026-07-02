`timescale 1ns / 1ps

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
    output fp_defines_pkg::fp_preg_t lane1_old_preg
);

    import fp_defines_pkg::*;

    fp_preg_t rat [0:FP_AREG_NUM-1];
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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FP_AREG_NUM; i++) begin
                rat[i] <= fp_preg_t'(i);
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][i] <= fp_preg_t'(i);
                end
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
    end

endmodule
