module rename_packet_stage (
    input  logic flush,
    input  logic restore_rat,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] restore_checkpoint_id,
    input  logic [defines_pkg::CHECKPOINT_NUM-1:0] active_checkpoint_mask,
    pip_if.consumer in_if,
    pip_if.producer out_if,

    input  logic [1:0]         retire_valid,
    input  defines_pkg::preg_t retire_preg0,
    input  defines_pkg::preg_t retire_preg1
);

    import defines_pkg::*;

    preg_t lane0_src_reg_1p_raw;
    preg_t lane0_src_reg_2p_raw;
    preg_t lane0_old_des_preg_raw;
    preg_t lane1_src_reg_1p_raw;
    preg_t lane1_src_reg_2p_raw;
    preg_t lane1_old_des_preg_raw;

    preg_t lane0_alloc_preg;
    preg_t lane1_alloc_preg;
    preg_t lane1_src_reg_1p_eff;
    preg_t lane1_src_reg_2p_eff;
    preg_t lane1_old_des_preg_eff;
    logic  lane0_alloc_valid;
    logic  lane1_alloc_valid;
    logic  free_pool_full;
    logic  free_pool_empty;
    logic  has_free_1;
    logic  has_free_2;

    rob_tag_t rob_tag_q;
    logic [CHECKPOINT_W-1:0] checkpoint_hint_q;
    logic [CHECKPOINT_W-1:0] lane0_checkpoint_id;
    logic [CHECKPOINT_W-1:0] lane1_checkpoint_id;
    logic lane0_checkpoint_available;
    logic lane1_checkpoint_available;

    logic packet_has_data;
    logic lane0_valid;
    logic lane1_valid;
    logic lane0_needs_rename;
    logic lane1_needs_rename;
    logic lane0_is_branch;
    logic lane1_is_branch;
    logic [1:0] needed_free_count;
    logic [1:0] branch_count;
    logic free_available;
    logic checkpoint_available;
    logic allow_rename;
    logic rename_fire;
    logic [1:0] alloc_pop;
    logic checkpoint_save;
    cp_id_t checkpoint_id_save;
    cp_mask_t lane1_visible_mask;

    assign packet_has_data = in_if.valid &&
                             (in_if.data.lane0.valid || in_if.data.lane1.valid);
    assign lane0_valid = packet_has_data && in_if.data.lane0.valid;
    assign lane1_valid = packet_has_data && in_if.data.lane1.valid;

    assign lane0_needs_rename = lane0_valid &&
                                in_if.data.lane0.data.control_signal.rs_control_signal.rename &&
                                (in_if.data.lane0.data.datapath.rd != '0);
    assign lane1_needs_rename = lane1_valid &&
                                in_if.data.lane1.data.control_signal.rs_control_signal.rename &&
                                (in_if.data.lane1.data.datapath.rd != '0);

    assign lane0_is_branch = lane0_valid &&
                             (in_if.data.lane0.data.control_signal.rs_control_signal.fu_type == FU_BRANCH);
    assign lane1_is_branch = lane1_valid &&
                             (in_if.data.lane1.data.control_signal.rs_control_signal.fu_type == FU_BRANCH);

    assign needed_free_count = {1'b0, lane0_needs_rename} + {1'b0, lane1_needs_rename};
    assign branch_count      = {1'b0, lane0_is_branch} + {1'b0, lane1_is_branch};

    assign free_available = (needed_free_count == 2'd0) ||
                            ((needed_free_count == 2'd1) && has_free_1) ||
                            ((needed_free_count == 2'd2) && has_free_2);

    assign checkpoint_available = (branch_count == 2'd0) ||
                                  (lane0_is_branch && lane0_checkpoint_available) ||
                                  (lane1_is_branch &&
                                   (lane0_is_branch ? lane1_checkpoint_available :
                                                      lane0_checkpoint_available));

    // The current packet fetch policy suppresses younger control-flow lanes.
    // Keep dual-branch packets stalled until the backend grows precise
    // per-lane checkpoint snapshots.
    assign allow_rename = free_available &&
                          checkpoint_available &&
                          (branch_count < 2'd2);

    assign out_if.valid = !flush && packet_has_data && allow_rename;
    assign in_if.ready  = !flush && out_if.ready && (!packet_has_data || allow_rename);
    assign rename_fire  = out_if.valid && out_if.ready;
    assign alloc_pop    = packet_has_data ? {lane1_needs_rename, lane0_needs_rename} : 2'b00;

    always_comb begin
        lane0_checkpoint_available = 1'b0;
        lane1_checkpoint_available = 1'b0;
        lane0_checkpoint_id = checkpoint_hint_q;
        lane1_checkpoint_id = checkpoint_hint_q;

        for (int offset = 0; offset < CHECKPOINT_NUM; offset++) begin
            int idx;
            idx = checkpoint_hint_q + offset;
            if (idx >= CHECKPOINT_NUM) begin
                idx = idx - CHECKPOINT_NUM;
            end

            if (!lane0_checkpoint_available && !active_checkpoint_mask[idx]) begin
                lane0_checkpoint_available = 1'b1;
                lane0_checkpoint_id = idx[CHECKPOINT_W-1:0];
            end else if (!lane1_checkpoint_available && !active_checkpoint_mask[idx]) begin
                lane1_checkpoint_available = 1'b1;
                lane1_checkpoint_id = idx[CHECKPOINT_W-1:0];
            end
        end
    end

    assign checkpoint_save = rename_fire && (lane0_is_branch || lane1_is_branch);
    assign checkpoint_id_save = lane0_is_branch ? lane0_checkpoint_id :
                                lane1_is_branch ? lane0_checkpoint_id : '0;
    assign lane1_visible_mask = active_checkpoint_mask |
                                (lane0_is_branch ? (cp_mask_t'(1'b1) << lane0_checkpoint_id) : '0);

    assign lane1_src_reg_1p_eff =
        (lane0_needs_rename &&
         (in_if.data.lane1.data.datapath.rs1 == in_if.data.lane0.data.datapath.rd)) ?
        lane0_alloc_preg : lane1_src_reg_1p_raw;
    assign lane1_src_reg_2p_eff =
        (lane0_needs_rename &&
         (in_if.data.lane1.data.datapath.rs2 == in_if.data.lane0.data.datapath.rd)) ?
        lane0_alloc_preg : lane1_src_reg_2p_raw;
    assign lane1_old_des_preg_eff =
        (lane0_needs_rename &&
         (in_if.data.lane1.data.datapath.rd == in_if.data.lane0.data.datapath.rd)) ?
        lane0_alloc_preg : lane1_old_des_preg_raw;

    assign out_if.data.lane0.valid = lane0_valid;
    assign out_if.data.lane1.valid = lane1_valid;

    assign out_if.data.lane0.data.rs_entry.control_signal  =
        in_if.data.lane0.data.control_signal.rs_control_signal;
    assign out_if.data.lane0.data.rob_entry.control_signal =
        in_if.data.lane0.data.control_signal.rob_control_signal;
    assign out_if.data.lane1.data.rs_entry.control_signal  =
        in_if.data.lane1.data.control_signal.rs_control_signal;
    assign out_if.data.lane1.data.rob_entry.control_signal =
        in_if.data.lane1.data.control_signal.rob_control_signal;

    assign out_if.data.lane0.data.rs_entry.datapath.src_reg_1p =
        lane0_src_reg_1p_raw;
    assign out_if.data.lane0.data.rs_entry.datapath.src_reg_2p =
        lane0_src_reg_2p_raw;
    assign out_if.data.lane0.data.rs_entry.datapath.new_des_preg =
        lane0_needs_rename ? lane0_alloc_preg : '0;
    assign out_if.data.lane0.data.rs_entry.datapath.checkpoint_id =
        lane0_is_branch ? lane0_checkpoint_id : '0;
    assign out_if.data.lane0.data.rs_entry.datapath.speculation_mask =
        active_checkpoint_mask;
    assign out_if.data.lane0.data.rs_entry.datapath.src1_value = '0;
    assign out_if.data.lane0.data.rs_entry.datapath.src2_value = '0;
    assign out_if.data.lane0.data.rs_entry.datapath.rob_tag = rob_tag_q;
    assign out_if.data.lane0.data.rs_entry.datapath.imm =
        in_if.data.lane0.data.datapath.imm;
    assign out_if.data.lane0.data.rs_entry.datapath.instr =
        in_if.data.lane0.data.datapath.instr;
    assign out_if.data.lane0.data.rs_entry.datapath.pc =
        in_if.data.lane0.data.datapath.pc;
    assign out_if.data.lane0.data.rs_entry.datapath.pred_taken =
        in_if.data.lane0.data.datapath.pred_taken;
    assign out_if.data.lane0.data.rs_entry.datapath.pred_target =
        in_if.data.lane0.data.datapath.pred_target;
    assign out_if.data.lane0.data.rs_entry.src1_ready = 1'b0;
    assign out_if.data.lane0.data.rs_entry.src2_ready = 1'b0;

    assign out_if.data.lane1.data.rs_entry.datapath.src_reg_1p =
        lane1_src_reg_1p_eff;
    assign out_if.data.lane1.data.rs_entry.datapath.src_reg_2p =
        lane1_src_reg_2p_eff;
    assign out_if.data.lane1.data.rs_entry.datapath.new_des_preg =
        lane1_needs_rename ? lane1_alloc_preg : '0;
    assign out_if.data.lane1.data.rs_entry.datapath.checkpoint_id =
        lane1_is_branch ? (lane0_is_branch ? lane1_checkpoint_id : lane0_checkpoint_id) : '0;
    assign out_if.data.lane1.data.rs_entry.datapath.speculation_mask =
        lane1_visible_mask;
    assign out_if.data.lane1.data.rs_entry.datapath.src1_value = '0;
    assign out_if.data.lane1.data.rs_entry.datapath.src2_value = '0;
    assign out_if.data.lane1.data.rs_entry.datapath.rob_tag =
        rob_tag_q + rob_tag_t'(lane0_valid);
    assign out_if.data.lane1.data.rs_entry.datapath.imm =
        in_if.data.lane1.data.datapath.imm;
    assign out_if.data.lane1.data.rs_entry.datapath.instr =
        in_if.data.lane1.data.datapath.instr;
    assign out_if.data.lane1.data.rs_entry.datapath.pc =
        in_if.data.lane1.data.datapath.pc;
    assign out_if.data.lane1.data.rs_entry.datapath.pred_taken =
        in_if.data.lane1.data.datapath.pred_taken;
    assign out_if.data.lane1.data.rs_entry.datapath.pred_target =
        in_if.data.lane1.data.datapath.pred_target;
    assign out_if.data.lane1.data.rs_entry.src1_ready = 1'b0;
    assign out_if.data.lane1.data.rs_entry.src2_ready = 1'b0;

    assign out_if.data.lane0.data.rob_entry.datapath.rob_tag = rob_tag_q;
    assign out_if.data.lane0.data.rob_entry.datapath.new_des_preg =
        lane0_needs_rename ? lane0_alloc_preg : '0;
    assign out_if.data.lane0.data.rob_entry.datapath.old_des_preg =
        lane0_needs_rename ? lane0_old_des_preg_raw : '0;
    assign out_if.data.lane0.data.rob_entry.datapath.checkpoint_id =
        lane0_is_branch ? lane0_checkpoint_id : '0;
    assign out_if.data.lane0.data.rob_entry.datapath.speculation_mask =
        active_checkpoint_mask;
    assign out_if.data.lane0.data.rob_entry.datapath.rd =
        in_if.data.lane0.data.datapath.rd;
    assign out_if.data.lane0.data.rob_entry.datapath.complete = 1'b0;
    assign out_if.data.lane0.data.rob_entry.datapath.result = '0;

    assign out_if.data.lane1.data.rob_entry.datapath.rob_tag =
        rob_tag_q + rob_tag_t'(lane0_valid);
    assign out_if.data.lane1.data.rob_entry.datapath.new_des_preg =
        lane1_needs_rename ? lane1_alloc_preg : '0;
    assign out_if.data.lane1.data.rob_entry.datapath.old_des_preg =
        lane1_needs_rename ? lane1_old_des_preg_eff : '0;
    assign out_if.data.lane1.data.rob_entry.datapath.checkpoint_id =
        lane1_is_branch ? (lane0_is_branch ? lane1_checkpoint_id : lane0_checkpoint_id) : '0;
    assign out_if.data.lane1.data.rob_entry.datapath.speculation_mask =
        lane1_visible_mask;
    assign out_if.data.lane1.data.rob_entry.datapath.rd =
        in_if.data.lane1.data.datapath.rd;
    assign out_if.data.lane1.data.rob_entry.datapath.complete = 1'b0;
    assign out_if.data.lane1.data.rob_entry.datapath.result = '0;

    reg_alias_table_2w u_rat_2w (
        .clk(in_if.clk),
        .rst_n(in_if.rst_n),
        .w_en(rename_fire ? {lane1_needs_rename, lane0_needs_rename} : 2'b00),
        .checkpoint_save(checkpoint_save),
        .checkpoint_id_save(checkpoint_id_save),
        .restore_en(restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .lane0_src_reg_1a(in_if.data.lane0.data.datapath.rs1),
        .lane0_src_reg_2a(in_if.data.lane0.data.datapath.rs2),
        .lane0_des_reg_a(in_if.data.lane0.data.datapath.rd),
        .lane0_new_des_preg(lane0_alloc_preg),
        .lane1_src_reg_1a(in_if.data.lane1.data.datapath.rs1),
        .lane1_src_reg_2a(in_if.data.lane1.data.datapath.rs2),
        .lane1_des_reg_a(in_if.data.lane1.data.datapath.rd),
        .lane1_new_des_preg(lane1_alloc_preg),
        .lane0_src_reg_1p(lane0_src_reg_1p_raw),
        .lane0_src_reg_2p(lane0_src_reg_2p_raw),
        .lane0_old_des_preg(lane0_old_des_preg_raw),
        .lane1_src_reg_1p(lane1_src_reg_1p_raw),
        .lane1_src_reg_2p(lane1_src_reg_2p_raw),
        .lane1_old_des_preg(lane1_old_des_preg_raw)
    );

    free_pool_2w u_free_pool_2w (
        .clk(in_if.clk),
        .rst_n(in_if.rst_n),
        .push(retire_valid),
        .pop(alloc_pop),
        .pop_commit(rename_fire),
        .push_data0(retire_preg0),
        .push_data1(retire_preg1),
        .pop_data0(lane0_alloc_preg),
        .pop_data1(lane1_alloc_preg),
        .pop_valid0(lane0_alloc_valid),
        .pop_valid1(lane1_alloc_valid),
        .checkpoint_save(checkpoint_save),
        .checkpoint_id_save(checkpoint_id_save),
        .restore_en(restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .full(free_pool_full),
        .empty(free_pool_empty),
        .has_free_1(has_free_1),
        .has_free_2(has_free_2)
    );

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n) begin
            rob_tag_q <= '0;
            checkpoint_hint_q <= '0;
        end else if (rename_fire) begin
            rob_tag_q <= rob_tag_q + rob_tag_t'(lane0_valid ? 1 : 0) +
                         rob_tag_t'(lane1_valid ? 1 : 0);
            if (lane0_is_branch) begin
                checkpoint_hint_q <= lane0_checkpoint_id + 1'b1;
            end else if (lane1_is_branch) begin
                checkpoint_hint_q <= lane0_checkpoint_id + 1'b1;
            end
        end
    end

endmodule
