module execution_stage (
    pip_if.consumer in_if,

    output logic                           wb_valid,
    output defines_pkg::preg_t             wb_preg,
    output defines_pkg::rob_tag_t          wb_tag,
    output logic [defines_pkg::WIDTH-1:0]  wb_result,
    output logic                           complete_valid,
    output defines_pkg::rob_tag_t          complete_tag,
    output logic [defines_pkg::WIDTH-1:0]  complete_result,
    output logic                           branch_complete_valid,
    output defines_pkg::rob_tag_t          branch_complete_tag,
    output logic [defines_pkg::WIDTH-1:0]  branch_complete_result,

    output logic                           branch_resolve,
    output logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,
    output logic                           bp_update_valid,
    output logic [defines_pkg::WIDTH-1:0]  bp_update_pc,
    output logic                           bp_update_taken,
    output logic                           bp_update_is_jalr,
    output logic [defines_pkg::WIDTH-1:0]  bp_update_target,

    output logic                           pc_src,
    output logic [defines_pkg::WIDTH-1:0]  pc_branch
    
);
    import defines_pkg::*;

    localparam int BR_RESOLVE_LAT = 4;

    logic [WIDTH-1:0] alu_result;
    logic [WIDTH-1:0] lsu_result;
    logic [WIDTH-1:0] branch_link_result;
    logic             branch_taken;
    logic [WIDTH-1:0] branch_target;
    logic             branch_actual_taken_now;
    logic             branch_mispredict_now;
    logic [WIDTH-1:0] branch_recovery_pc_now;
    logic br_pipe_valid        [0:BR_RESOLVE_LAT-1];
    logic br_pipe_pc_src       [0:BR_RESOLVE_LAT-1];
    logic [ROB_TAG_W-1:0] br_pipe_tag [0:BR_RESOLVE_LAT-1];
    logic [CHECKPOINT_W-1:0] br_pipe_cp_id [0:BR_RESOLVE_LAT-1];
    cp_mask_t br_pipe_spec_mask [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_pc_branch [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_valid     [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_bp_pc [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_taken     [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_is_jalr   [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_bp_target [0:BR_RESOLVE_LAT-1];
    logic br_pipe_valid_n        [0:BR_RESOLVE_LAT-1];
    logic br_pipe_pc_src_n       [0:BR_RESOLVE_LAT-1];
    logic [ROB_TAG_W-1:0] br_pipe_tag_n [0:BR_RESOLVE_LAT-1];
    logic [CHECKPOINT_W-1:0] br_pipe_cp_id_n [0:BR_RESOLVE_LAT-1];
    cp_mask_t br_pipe_spec_mask_n [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_pc_branch_n [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_valid_n     [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_bp_pc_n [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_taken_n     [0:BR_RESOLVE_LAT-1];
    logic br_pipe_bp_is_jalr_n   [0:BR_RESOLVE_LAT-1];
    logic [WIDTH-1:0] br_pipe_bp_target_n [0:BR_RESOLVE_LAT-1];
    logic resolve_now;
    logic resolve_pc_src_now;
    logic [CHECKPOINT_W-1:0] resolve_cp_id_now;
    logic branch_issue_now;

    assign resolve_now = br_pipe_valid[BR_RESOLVE_LAT-1];
    assign resolve_pc_src_now = br_pipe_pc_src[BR_RESOLVE_LAT-1];
    assign resolve_cp_id_now = br_pipe_cp_id[BR_RESOLVE_LAT-1];
    assign branch_issue_now = in_if.valid && in_if.ready && (in_if.data.fu_sel == FU_BRANCH);
    assign branch_actual_taken_now = in_if.data.control_signal.branch.jump || branch_taken;
    assign branch_recovery_pc_now  = branch_actual_taken_now ? branch_target : (in_if.data.datapath.pc + 32'd4);
    assign branch_mispredict_now   = (branch_actual_taken_now != in_if.data.datapath.pred_taken) ||
                                     (branch_actual_taken_now &&
                                      (branch_target != in_if.data.datapath.pred_target));

    always_comb begin
        for (int i = 0; i < BR_RESOLVE_LAT; i++) begin
            br_pipe_valid_n[i]      = 1'b0;
            br_pipe_pc_src_n[i]     = 1'b0;
            br_pipe_tag_n[i]        = '0;
            br_pipe_cp_id_n[i]      = '0;
            br_pipe_spec_mask_n[i]  = '0;
            br_pipe_pc_branch_n[i]  = '0;
            br_pipe_bp_valid_n[i]   = 1'b0;
            br_pipe_bp_pc_n[i]      = '0;
            br_pipe_bp_taken_n[i]   = 1'b0;
            br_pipe_bp_is_jalr_n[i] = 1'b0;
            br_pipe_bp_target_n[i]  = '0;
        end

        for (int i = 1; i < BR_RESOLVE_LAT; i++) begin
            br_pipe_valid_n[i]      = br_pipe_valid[i-1];
            br_pipe_pc_src_n[i]     = br_pipe_pc_src[i-1];
            br_pipe_tag_n[i]        = br_pipe_tag[i-1];
            br_pipe_cp_id_n[i]      = br_pipe_cp_id[i-1];
            br_pipe_spec_mask_n[i]  = br_pipe_spec_mask[i-1];
            br_pipe_pc_branch_n[i]  = br_pipe_pc_branch[i-1];
            br_pipe_bp_valid_n[i]   = br_pipe_bp_valid[i-1];
            br_pipe_bp_pc_n[i]      = br_pipe_bp_pc[i-1];
            br_pipe_bp_taken_n[i]   = br_pipe_bp_taken[i-1];
            br_pipe_bp_is_jalr_n[i] = br_pipe_bp_is_jalr[i-1];
            br_pipe_bp_target_n[i]  = br_pipe_bp_target[i-1];
        end

        if (branch_issue_now) begin
            br_pipe_valid_n[0]      = 1'b1;
            br_pipe_tag_n[0]        = in_if.data.datapath.rob_tag;
            br_pipe_cp_id_n[0]      = in_if.data.datapath.checkpoint_id;
            br_pipe_spec_mask_n[0]  = in_if.data.datapath.speculation_mask;
            br_pipe_pc_src_n[0]     = branch_mispredict_now;
            br_pipe_pc_branch_n[0]  = branch_recovery_pc_now;
            br_pipe_bp_pc_n[0]      = in_if.data.datapath.pc;
            br_pipe_bp_target_n[0]  = branch_target;

            if (in_if.data.control_signal.branch.branch) begin
                br_pipe_bp_valid_n[0]   = 1'b1;
                br_pipe_bp_taken_n[0]   = branch_taken;
                br_pipe_bp_is_jalr_n[0] = 1'b0;
            end else if (in_if.data.control_signal.branch.jump &&
                         !in_if.data.control_signal.branch.jump_reg) begin
                br_pipe_bp_valid_n[0]   = 1'b1;
                br_pipe_bp_taken_n[0]   = 1'b1;
                br_pipe_bp_is_jalr_n[0] = 1'b0;
            end else if (in_if.data.control_signal.branch.jump_reg) begin
                br_pipe_bp_valid_n[0]   = 1'b1;
                br_pipe_bp_taken_n[0]   = 1'b1;
                br_pipe_bp_is_jalr_n[0] = 1'b1;
            end
        end

        if (resolve_now) begin
            for (int i = 0; i < BR_RESOLVE_LAT-1; i++) begin
                if (br_pipe_valid_n[i]) begin
                    if (resolve_pc_src_now &&
                        br_pipe_spec_mask_n[i][resolve_cp_id_now]) begin
                        br_pipe_valid_n[i]      = 1'b0;
                        br_pipe_pc_src_n[i]     = 1'b0;
                        br_pipe_tag_n[i]        = '0;
                        br_pipe_cp_id_n[i]      = '0;
                        br_pipe_spec_mask_n[i]  = '0;
                        br_pipe_pc_branch_n[i]  = '0;
                        br_pipe_bp_valid_n[i]   = 1'b0;
                        br_pipe_bp_pc_n[i]      = '0;
                        br_pipe_bp_taken_n[i]   = 1'b0;
                        br_pipe_bp_is_jalr_n[i] = 1'b0;
                        br_pipe_bp_target_n[i]  = '0;
                    end else begin
                        br_pipe_spec_mask_n[i][resolve_cp_id_now] = 1'b0;
                    end
                end
            end
        end
    end

    assign in_if.ready = 1'b1;

    alu u_alu (
        .control_signal(in_if.data.control_signal.alu),
        .datapath      (in_if.data.datapath),
        .result        (alu_result)
    );

    lsu u_lsu (
        .clk           (in_if.clk),
        .rst_n         (in_if.rst_n),
        .control_signal(in_if.data.control_signal.lsu),
        .datapath      (in_if.data.datapath),
        .load_result   (lsu_result)
    );

    branch_unit u_branch (
        .control_signal(in_if.data.control_signal.branch),
        .datapath      (in_if.data.datapath),
        .branch_taken  (branch_taken),
        .branch_target (branch_target),
        .link_result   (branch_link_result)
    );

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n) begin
            wb_valid  <= 1'b0;
            wb_preg   <= '0;
            wb_tag    <= '0;
            wb_result <= '0;
            complete_valid <= 1'b0;
            complete_tag   <= '0;
            complete_result <= '0;
            branch_complete_valid <= 1'b0;
            branch_complete_tag   <= '0;
            branch_complete_result <= '0;
            pc_src    <= 1'b0;
            pc_branch <= '0;
            branch_resolve <= 1'b0;
            resolve_checkpoint_id <= '0;
            bp_update_valid <= 1'b0;
            bp_update_pc    <= '0;
            bp_update_taken <= 1'b0;
            bp_update_is_jalr <= 1'b0;
            bp_update_target <= '0;
            for (int i = 0; i < BR_RESOLVE_LAT; i++) begin
                br_pipe_valid[i]      <= 1'b0;
                br_pipe_pc_src[i]     <= 1'b0;
                br_pipe_tag[i]        <= '0;
                br_pipe_cp_id[i]      <= '0;
                br_pipe_spec_mask[i]  <= '0;
                br_pipe_pc_branch[i]  <= '0;
                br_pipe_bp_valid[i]   <= 1'b0;
                br_pipe_bp_pc[i]      <= '0;
                br_pipe_bp_taken[i]   <= 1'b0;
                br_pipe_bp_is_jalr[i] <= 1'b0;
                br_pipe_bp_target[i]  <= '0;
            end
        end else begin
            wb_valid  <= 1'b0;
            wb_preg   <= '0;
            wb_tag    <= '0;
            wb_result <= '0;
            complete_valid <= 1'b0;
            complete_tag   <= '0;
            complete_result <= '0;
            branch_complete_valid <= br_pipe_valid[BR_RESOLVE_LAT-1];
            branch_complete_tag   <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_tag[BR_RESOLVE_LAT-1] : '0;
            branch_complete_result <= '0;
            branch_resolve <= br_pipe_valid[BR_RESOLVE_LAT-1];
            resolve_checkpoint_id <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_cp_id[BR_RESOLVE_LAT-1] : '0;
            pc_src    <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_pc_src[BR_RESOLVE_LAT-1];
            pc_branch <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_pc_branch[BR_RESOLVE_LAT-1] : '0;
            bp_update_valid <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_valid[BR_RESOLVE_LAT-1];
            bp_update_pc    <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_bp_pc[BR_RESOLVE_LAT-1] : '0;
            bp_update_taken <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_taken[BR_RESOLVE_LAT-1];
            bp_update_is_jalr <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_is_jalr[BR_RESOLVE_LAT-1];
            bp_update_target <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_bp_target[BR_RESOLVE_LAT-1] : '0;

            for (int i = 0; i < BR_RESOLVE_LAT; i++) begin
                br_pipe_valid[i]      <= br_pipe_valid_n[i];
                br_pipe_pc_src[i]     <= br_pipe_pc_src_n[i];
                br_pipe_tag[i]        <= br_pipe_tag_n[i];
                br_pipe_cp_id[i]      <= br_pipe_cp_id_n[i];
                br_pipe_spec_mask[i]  <= br_pipe_spec_mask_n[i];
                br_pipe_pc_branch[i]  <= br_pipe_pc_branch_n[i];
                br_pipe_bp_valid[i]   <= br_pipe_bp_valid_n[i];
                br_pipe_bp_pc[i]      <= br_pipe_bp_pc_n[i];
                br_pipe_bp_taken[i]   <= br_pipe_bp_taken_n[i];
                br_pipe_bp_is_jalr[i] <= br_pipe_bp_is_jalr_n[i];
                br_pipe_bp_target[i]  <= br_pipe_bp_target_n[i];
            end

            if (in_if.valid && in_if.ready) begin
                unique case (in_if.data.fu_sel)
                    FU_ALU: begin
                        if (in_if.data.control_signal.alu.reg_write &&
                            (in_if.data.datapath.new_des_preg != '0)) begin
                            wb_valid  <= 1'b1;
                            wb_preg   <= in_if.data.datapath.new_des_preg;
                            wb_tag    <= in_if.data.datapath.rob_tag;
                            wb_result <= alu_result;
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= alu_result;
                        end
                    end

                    FU_MEM: begin
                        if (in_if.data.control_signal.lsu.mem_read &&
                            (in_if.data.datapath.new_des_preg != '0)) begin
                            wb_valid  <= 1'b1;
                            wb_preg   <= in_if.data.datapath.new_des_preg;
                            wb_tag    <= in_if.data.datapath.rob_tag;
                            wb_result <= lsu_result;
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= lsu_result;
                        end else if (in_if.data.control_signal.lsu.mem_write) begin
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= '0;
                        end
                    end

                    FU_BRANCH: begin
                        if (in_if.data.control_signal.branch.jump &&
                            (in_if.data.datapath.new_des_preg != '0)) begin
                            wb_valid  <= 1'b1;
                            wb_preg   <= in_if.data.datapath.new_des_preg;
                            wb_tag    <= in_if.data.datapath.rob_tag;
                            wb_result <= branch_link_result;
                        end
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule
