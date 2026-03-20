module reg_alias_table (
    input  logic clk,
    input  logic rst_n,

    input  logic w_en,
    input  logic checkpoint_save,
    input  defines_pkg::cp_id_t checkpoint_id_save,
    input  logic restore_en,
    input  defines_pkg::cp_id_t restore_checkpoint_id,

    input  defines_pkg::areg_t src_reg_1a,
    input  defines_pkg::areg_t src_reg_2a,
    input  defines_pkg::areg_t des_reg_a,

    input  defines_pkg::preg_t new_des_preg,

    output defines_pkg::preg_t src_reg_1p,
    output defines_pkg::preg_t src_reg_2p,
    output defines_pkg::preg_t old_des_preg
);
    import defines_pkg::*;

    preg_t rat [0:AREG_NUM-1];
    preg_t checkpoints [0:CHECKPOINT_NUM-1][0:AREG_NUM-1];

    assign src_reg_1p   = rat[src_reg_1a];
    assign src_reg_2p   = rat[src_reg_2a];
    assign old_des_preg = rat[des_reg_a];

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

                // Branch checkpoints must preserve the branch's own rename result.
                if (w_en && des_reg_a != '0) begin
                    checkpoints[checkpoint_id_save][des_reg_a] <= new_des_preg;
                end
            end

            if (w_en) begin
                if (des_reg_a != '0) begin
                    rat[des_reg_a] <= new_des_preg;
                end
            end
        end
    end

endmodule
