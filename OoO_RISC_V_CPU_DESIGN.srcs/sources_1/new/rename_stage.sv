module rename_stage (
    input  logic flush,
    input  logic restore_rat,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] restore_checkpoint_id,
    input  logic [defines_pkg::CHECKPOINT_NUM-1:0] active_checkpoint_mask,
    pip_if.consumer in_if,
    pip_if.producer out_if,

    input  logic               retire_valid,
    input  defines_pkg::preg_t retire_preg
);

    import defines_pkg::*;

    preg_t    src_reg_1p;
    preg_t    src_reg_2p;
    preg_t    new_des_preg;
    preg_t    old_des_preg;
    rob_tag_t rob_tag_q;
    logic [CHECKPOINT_W-1:0] checkpoint_id_q;

    logic free_pool_full;
    logic free_pool_empty;

    logic needs_rename;
    logic rename_fire;
    logic alloc_pop;
    logic is_branch;
    logic branch_checkpoint_fire;
    logic checkpoint_available;
    logic [CHECKPOINT_W-1:0] alloc_checkpoint_id;
    logic [CHECKPOINT_W-1:0] checkpoint_hint_q;
    logic allow_rename;

    assign needs_rename = in_if.data.control_signal.rs_control_signal.rename &&
                          (in_if.data.datapath.rd != '0);
    assign alloc_pop    = in_if.valid && out_if.ready && needs_rename;
    assign rename_fire  = in_if.valid && out_if.ready;
    assign is_branch = (in_if.data.control_signal.rs_control_signal.fu_type == FU_BRANCH);
    assign branch_checkpoint_fire = rename_fire && is_branch;

    always_comb begin
        checkpoint_available = 1'b0;
        alloc_checkpoint_id  = checkpoint_hint_q;

        for (int offset = 0; offset < CHECKPOINT_NUM; offset++) begin
            int idx;
            idx = checkpoint_hint_q + offset;
            if (idx >= CHECKPOINT_NUM) begin
                idx = idx - CHECKPOINT_NUM;
            end

            if (!checkpoint_available && !active_checkpoint_mask[idx]) begin
                checkpoint_available = 1'b1;
                alloc_checkpoint_id  = idx[CHECKPOINT_W-1:0];
            end
        end
    end

    assign allow_rename = (!needs_rename || !free_pool_empty) &&
                          (!is_branch || checkpoint_available);

    assign in_if.ready  = out_if.ready && allow_rename;
    assign out_if.valid = in_if.valid && allow_rename;

    assign out_if.data.rs_entry.control_signal  = in_if.data.control_signal.rs_control_signal;
    assign out_if.data.rob_entry.control_signal = in_if.data.control_signal.rob_control_signal;

    assign out_if.data.rs_entry.datapath.src_reg_1p   = src_reg_1p;
    assign out_if.data.rs_entry.datapath.src_reg_2p   = src_reg_2p;
    assign out_if.data.rs_entry.datapath.new_des_preg = needs_rename ? new_des_preg : '0;
    assign out_if.data.rs_entry.datapath.checkpoint_id = is_branch ? alloc_checkpoint_id : '0;
    assign out_if.data.rs_entry.datapath.speculation_mask = active_checkpoint_mask;
    assign out_if.data.rs_entry.datapath.rob_tag      = rob_tag_q;
    assign out_if.data.rs_entry.datapath.imm          = in_if.data.datapath.imm;
    assign out_if.data.rs_entry.datapath.pc           = in_if.data.datapath.pc;
    assign out_if.data.rs_entry.datapath.pred_taken   = in_if.data.datapath.pred_taken;
    assign out_if.data.rs_entry.datapath.pred_target  = in_if.data.datapath.pred_target;
    assign out_if.data.rs_entry.src1_ready            = 1'b0;
    assign out_if.data.rs_entry.src2_ready            = 1'b0;

    assign out_if.data.rob_entry.datapath.rob_tag      = rob_tag_q;
    assign out_if.data.rob_entry.datapath.new_des_preg = needs_rename ? new_des_preg : '0;
    assign out_if.data.rob_entry.datapath.old_des_preg = needs_rename ? old_des_preg : '0;
    assign out_if.data.rob_entry.datapath.checkpoint_id = is_branch ? alloc_checkpoint_id : '0;
    assign out_if.data.rob_entry.datapath.speculation_mask = active_checkpoint_mask;
    assign out_if.data.rob_entry.datapath.rd           = in_if.data.datapath.rd;
    assign out_if.data.rob_entry.datapath.complete     = 1'b0;
    assign out_if.data.rob_entry.datapath.result       = '0;

    reg_alias_table u_rat (
        .clk        (in_if.clk),
        .rst_n      (in_if.rst_n),
        .w_en       (alloc_pop),
        .checkpoint_save(branch_checkpoint_fire),
        .checkpoint_id_save(alloc_checkpoint_id),
        .restore_en (restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .src_reg_1a (in_if.data.datapath.rs1),
        .src_reg_2a (in_if.data.datapath.rs2),
        .des_reg_a  (in_if.data.datapath.rd),
        .new_des_preg(new_des_preg),
        .src_reg_1p (src_reg_1p),
        .src_reg_2p (src_reg_2p),
        .old_des_preg(old_des_preg)
    );

    free_pool u_free_pool (
        .clk                  (in_if.clk),
        .rst_n                (in_if.rst_n),
        .push                 (retire_valid),
        .pop                  (alloc_pop),
        .push_data            (retire_preg),
        .pop_data             (new_des_preg),
        .checkpoint_save      (branch_checkpoint_fire),
        .checkpoint_id_save   (alloc_checkpoint_id),
        .restore_en           (restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .full                 (free_pool_full),
        .empty                (free_pool_empty)
    );

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n) begin
            rob_tag_q       <= '0;
            checkpoint_id_q <= '0;
            checkpoint_hint_q <= '0;
        end else if (flush) begin
            rob_tag_q       <= '0;
            checkpoint_id_q <= '0;
            checkpoint_hint_q <= '0;
        end else if (rename_fire) begin
            rob_tag_q <= rob_tag_q + 1'b1;
            if (branch_checkpoint_fire) begin
                checkpoint_id_q <= alloc_checkpoint_id;
                checkpoint_hint_q <= alloc_checkpoint_id + 1'b1;
            end
        end
    end

endmodule
