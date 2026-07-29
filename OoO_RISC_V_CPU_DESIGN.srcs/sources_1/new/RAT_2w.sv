// Two-wide speculative integer register-alias table.
//
// Four source lookups serve two instructions while two destination mappings
// may be installed atomically. Lane 1 observes lane 0's new mapping when the
// packet contains a RAW or WAW relationship, preserving program order within
// the packet. x0 is permanently mapped to p0 and is never renamed.
//
// Checkpoints hold complete RAT snapshots. Correct branch resolution releases
// a checkpoint; misprediction restore replaces the speculative map with the
// selected snapshot before refetch begins.
module reg_alias_table_2w (
    input  logic clk,
    input  logic rst_n,

    input  logic [1:0] w_en,
    input  logic checkpoint_save,
    input  defines_pkg::cp_id_t checkpoint_id_save,
    input  logic restore_en,
    input  defines_pkg::cp_id_t restore_checkpoint_id,

    input  defines_pkg::areg_t lane0_src_reg_1a,
    input  defines_pkg::areg_t lane0_src_reg_2a,
    input  defines_pkg::areg_t lane0_des_reg_a,
    input  defines_pkg::preg_t lane0_new_des_preg,

    input  defines_pkg::areg_t lane1_src_reg_1a,
    input  defines_pkg::areg_t lane1_src_reg_2a,
    input  defines_pkg::areg_t lane1_des_reg_a,
    input  defines_pkg::preg_t lane1_new_des_preg,

    output defines_pkg::preg_t lane0_src_reg_1p,
    output defines_pkg::preg_t lane0_src_reg_2p,
    output defines_pkg::preg_t lane0_old_des_preg,
    output defines_pkg::preg_t lane1_src_reg_1p,
    output defines_pkg::preg_t lane1_src_reg_2p,
    output defines_pkg::preg_t lane1_old_des_preg,
    output logic [defines_pkg::PREG_NUM-1:0] mapped_bitmap
);
    import defines_pkg::*;

    preg_t rat [0:AREG_NUM-1];
    preg_t checkpoints [0:CHECKPOINT_NUM-1][0:AREG_NUM-1];

    assign lane0_src_reg_1p   = rat[lane0_src_reg_1a];
    assign lane0_src_reg_2p   = rat[lane0_src_reg_2a];
    assign lane0_old_des_preg = rat[lane0_des_reg_a];

    assign lane1_src_reg_1p =
        (w_en[0] && (lane0_des_reg_a != '0) &&
         (lane1_src_reg_1a == lane0_des_reg_a)) ?
        lane0_new_des_preg : rat[lane1_src_reg_1a];
    assign lane1_src_reg_2p =
        (w_en[0] && (lane0_des_reg_a != '0) &&
         (lane1_src_reg_2a == lane0_des_reg_a)) ?
        lane0_new_des_preg : rat[lane1_src_reg_2a];
    assign lane1_old_des_preg =
        (w_en[0] && (lane0_des_reg_a != '0) &&
         (lane1_des_reg_a == lane0_des_reg_a)) ?
        lane0_new_des_preg : rat[lane1_des_reg_a];

    always_comb begin
        mapped_bitmap = '0;
        for (int i = 0; i < AREG_NUM; i++) begin
            if (restore_en) begin
                mapped_bitmap[checkpoints[restore_checkpoint_id][i]] = 1'b1;
            end else begin
                mapped_bitmap[rat[i]] = 1'b1;
            end
        end
        mapped_bitmap[0] = 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < AREG_NUM; i++) begin
                rat[i] <= preg_t'(i);
                for (int j = 0; j < CHECKPOINT_NUM; j++) begin
                    checkpoints[j][i] <= preg_t'(i);
                end
            end
        end else if (restore_en) begin
            for (int i = 0; i < AREG_NUM; i++) begin
                rat[i] <= checkpoints[restore_checkpoint_id][i];
            end
        end else begin
            if (checkpoint_save) begin
                for (int i = 0; i < AREG_NUM; i++) begin
                    checkpoints[checkpoint_id_save][i] <= rat[i];
                end

                if (w_en[0] && (lane0_des_reg_a != '0)) begin
                    checkpoints[checkpoint_id_save][lane0_des_reg_a] <= lane0_new_des_preg;
                end
                if (w_en[1] && (lane1_des_reg_a != '0)) begin
                    checkpoints[checkpoint_id_save][lane1_des_reg_a] <= lane1_new_des_preg;
                end
            end

            if (w_en[0] && (lane0_des_reg_a != '0)) begin
                rat[lane0_des_reg_a] <= lane0_new_des_preg;
            end
            if (w_en[1] && (lane1_des_reg_a != '0)) begin
                rat[lane1_des_reg_a] <= lane1_new_des_preg;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n === 1'b1) begin
            assert (rat[0] == '0)
                else $error("[ASSERT:RAT] architectural x0 mapping changed");
            assert (mapped_bitmap[0])
                else $error("[ASSERT:RAT] physical zero is not reserved");
            assert (!(w_en[0] && (lane0_des_reg_a != '0)) ||
                    (lane0_new_des_preg != '0))
                else $error("[ASSERT:RAT] lane0 allocated physical zero");
            assert (!(w_en[1] && (lane1_des_reg_a != '0)) ||
                    (lane1_new_des_preg != '0))
                else $error("[ASSERT:RAT] lane1 allocated physical zero");
            assert (!(w_en[0] && w_en[1] &&
                      (lane0_des_reg_a != '0) &&
                      (lane1_des_reg_a != '0)) ||
                    (lane0_new_des_preg != lane1_new_des_preg))
                else $error("[ASSERT:RAT] dual rename reused one physical register");
        end
    end
`endif

endmodule
