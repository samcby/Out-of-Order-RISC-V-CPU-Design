module execution_stage (
    pip_if.consumer in_if,
    pip_if.consumer in1_if,

    input  logic                           software_irq_pending,
    input  logic                           timer_irq_pending,
    input  logic                           external_irq_pending,
    input  logic                           interrupt_take,
    input  logic [defines_pkg::WIDTH-1:0]  interrupt_mepc,
    input  logic [defines_pkg::WIDTH-1:0]  interrupt_mcause,

    output logic                           wb_valid,
    output defines_pkg::preg_t             wb_preg,
    output defines_pkg::rob_tag_t          wb_tag,
    output logic [defines_pkg::WIDTH-1:0]  wb_result,
    output logic                           wb1_valid,
    output defines_pkg::preg_t             wb1_preg,
    output defines_pkg::rob_tag_t          wb1_tag,
    output logic [defines_pkg::WIDTH-1:0]  wb1_result,
    output logic                           complete_valid,
    output defines_pkg::rob_tag_t          complete_tag,
    output logic [defines_pkg::WIDTH-1:0]  complete_result,
    output logic                           branch_complete_valid,
    output defines_pkg::rob_tag_t          branch_complete_tag,
    output logic [defines_pkg::WIDTH-1:0]  branch_complete_result,
    output logic                           lane1_complete_valid,
    output defines_pkg::rob_tag_t          lane1_complete_tag,
    output logic [defines_pkg::WIDTH-1:0]  lane1_complete_result,

    output logic                           branch_resolve,
    output logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,
    output logic                           bp_update_valid,
    output logic [defines_pkg::WIDTH-1:0]  bp_update_pc,
    output logic                           bp_update_taken,
    output logic                           bp_update_is_jalr,
    output logic [defines_pkg::WIDTH-1:0]  bp_update_target,

    output logic                           pc_src,
    output logic [defines_pkg::WIDTH-1:0]  pc_branch,
    output logic                           recover_rat,
    output logic [defines_pkg::WIDTH-1:0]  csr_mstatus_value,
    output logic [defines_pkg::WIDTH-1:0]  csr_mie_value
    
);
    import defines_pkg::*;

    localparam int BR_RESOLVE_LAT = 4;

    logic [WIDTH-1:0] alu_result;
    logic [WIDTH-1:0] alu1_result;
    lsu_control_t     lsu_control_safe;
    logic             lsu_req_valid;
    logic             lsu_req_ready;
    logic             lsu_resp_valid;
    rob_tag_t         lsu_resp_tag;
    preg_t            lsu_resp_preg;
    logic             lsu_resp_reg_write;
    logic [WIDTH-1:0] lsu_resp_result;
    logic [WIDTH-1:0] csr_result;
    logic [WIDTH-1:0] csr_mtvec_value;
    logic [WIDTH-1:0] csr_mepc_value;
    logic [WIDTH-1:0] csr_operand;
    logic             csr_write_en;
    logic             sys_issue_now;
    logic             trap_write_en;
    logic             sync_exception_write_en;
    logic             csr_trap_write_en;
    logic             csr_mret_en;
    logic             illegal_trap_en;
    logic [WIDTH-1:0] csr_trap_mepc;
    logic [WIDTH-1:0] csr_trap_mcause;
    logic [WIDTH-1:0] csr_trap_mtval;
    logic [WIDTH-1:0] trap_mcause;
    logic [WIDTH-1:0] trap_mtval;
    logic [WIDTH-1:0] mtvec_base;
    logic [WIDTH-1:0] interrupt_cause_index;
    logic [WIDTH-1:0] exception_vector_pc;
    logic [WIDTH-1:0] interrupt_vector_pc;
    logic             branch_fu_fire;
    logic             branch_addr_misaligned_now;
    logic             mem_issue_candidate;
    logic             mem_fu_fire;
    logic [WIDTH-1:0] mem_eff_addr;
    logic             mem_load_misaligned_candidate;
    logic             mem_store_misaligned_candidate;
    logic             mem_addr_misaligned_candidate;
    logic             mem_load_misaligned_now;
    logic             mem_store_misaligned_now;
    logic             mem_addr_misaligned_now;
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
    logic branch_squash_now;
    logic branch_issue_now;
    logic issue1_alu_candidate;
    logic issue1_alu_fire;

    assign resolve_now = br_pipe_valid[BR_RESOLVE_LAT-1];
    assign resolve_pc_src_now = br_pipe_pc_src[BR_RESOLVE_LAT-1];
    assign resolve_cp_id_now = br_pipe_cp_id[BR_RESOLVE_LAT-1];
    assign branch_squash_now = resolve_now && resolve_pc_src_now;
    assign branch_fu_fire = in_if.valid && in_if.ready && (in_if.data.fu_sel == FU_BRANCH);
    assign branch_actual_taken_now = in_if.data.control_signal.branch.jump || branch_taken;
    assign branch_recovery_pc_now  = branch_actual_taken_now ? branch_target : (in_if.data.datapath.pc + 32'd4);
    assign branch_mispredict_now   = (branch_actual_taken_now != in_if.data.datapath.pred_taken) ||
                                     (branch_actual_taken_now &&
                                      (branch_target != in_if.data.datapath.pred_target));
    assign branch_addr_misaligned_now = branch_fu_fire &&
                                        branch_actual_taken_now &&
                                        (branch_target[1:0] != 2'b00);
    assign branch_issue_now = branch_fu_fire && !branch_addr_misaligned_now;
    assign issue1_alu_candidate =
        in1_if.valid &&
        (in1_if.data.fu_sel == FU_ALU) &&
        !in1_if.data.control_signal.alu.csr_en &&
        !in1_if.data.control_signal.alu.sys_en;
    assign in1_if.ready =
        !in1_if.valid ||
        (issue1_alu_candidate &&
         !interrupt_take);
    assign issue1_alu_fire = in1_if.valid && in1_if.ready && issue1_alu_candidate;
    assign mem_issue_candidate = in_if.valid && (in_if.data.fu_sel == FU_MEM);
    assign mem_fu_fire = in_if.valid && in_if.ready && (in_if.data.fu_sel == FU_MEM);
    assign mem_eff_addr = in_if.data.datapath.src1_value + in_if.data.datapath.imm;
    assign mem_load_misaligned_candidate =
        mem_issue_candidate &&
        in_if.data.control_signal.lsu.mem_read &&
        ((((in_if.data.control_signal.lsu.funct3 == 3'b001) ||
           (in_if.data.control_signal.lsu.funct3 == 3'b101)) && mem_eff_addr[0]) ||
         ((in_if.data.control_signal.lsu.funct3 == 3'b010) && (mem_eff_addr[1:0] != 2'b00)));
    assign mem_store_misaligned_candidate =
        mem_issue_candidate &&
        in_if.data.control_signal.lsu.mem_write &&
        (((in_if.data.control_signal.lsu.funct3 == 3'b001) && mem_eff_addr[0]) ||
         ((in_if.data.control_signal.lsu.funct3 == 3'b010) && (mem_eff_addr[1:0] != 2'b00)));
    assign mem_addr_misaligned_candidate =
        mem_load_misaligned_candidate || mem_store_misaligned_candidate;
    assign mem_load_misaligned_now =
        mem_fu_fire && mem_load_misaligned_candidate;
    assign mem_store_misaligned_now =
        mem_fu_fire && mem_store_misaligned_candidate;
    assign mem_addr_misaligned_now = mem_load_misaligned_now || mem_store_misaligned_now;
    assign lsu_req_valid = mem_fu_fire &&
                           !mem_addr_misaligned_now &&
                           (in_if.data.control_signal.lsu.mem_read ||
                            in_if.data.control_signal.lsu.mem_write);
    always_comb begin
        lsu_control_safe = in_if.data.control_signal.lsu;
        if (mem_addr_misaligned_now) begin
            lsu_control_safe.mem_read  = 1'b0;
            lsu_control_safe.mem_write = 1'b0;
        end
    end
    assign csr_operand = in_if.data.control_signal.alu.csr_use_imm ?
                         {27'b0, in_if.data.control_signal.alu.csr_zimm} :
                         in_if.data.datapath.src1_value;
    assign csr_write_en = !interrupt_take &&
                          in_if.valid && in_if.ready &&
                          (in_if.data.fu_sel == FU_ALU) &&
                          in_if.data.control_signal.alu.csr_en &&
                          ((in_if.data.control_signal.alu.csr_op == CSR_RW) ||
                           (csr_operand != '0));
    assign sys_issue_now = in_if.valid && in_if.ready &&
                           (in_if.data.fu_sel == FU_ALU) &&
                           in_if.data.control_signal.alu.sys_en;
    assign illegal_trap_en = sys_issue_now &&
                             (in_if.data.control_signal.alu.sys_op == SYS_ILLEGAL);
    assign trap_write_en = sys_issue_now &&
                           ((in_if.data.control_signal.alu.sys_op == SYS_ECALL) ||
                            (in_if.data.control_signal.alu.sys_op == SYS_EBREAK) ||
                            (in_if.data.control_signal.alu.sys_op == SYS_ILLEGAL));
    assign trap_mcause = illegal_trap_en ? MCAUSE_ILLEGAL :
                         (in_if.data.control_signal.alu.sys_op == SYS_EBREAK) ?
                         MCAUSE_EBREAK : MCAUSE_ECALL_M;
    always_comb begin
        trap_mtval = 32'b0;
        if (illegal_trap_en) begin
            trap_mtval = in_if.data.datapath.instr;
        end else if (branch_addr_misaligned_now) begin
            trap_mtval = branch_target;
        end else if (mem_addr_misaligned_now) begin
            trap_mtval = mem_eff_addr;
        end
    end
    assign sync_exception_write_en = trap_write_en ||
                                     branch_addr_misaligned_now ||
                                     mem_addr_misaligned_now;
    assign csr_trap_write_en = sync_exception_write_en || interrupt_take;
    assign csr_mret_en       = !interrupt_take &&
                               sys_issue_now &&
                               (in_if.data.control_signal.alu.sys_op == SYS_MRET);
    assign csr_trap_mepc     = interrupt_take ? interrupt_mepc : in_if.data.datapath.pc;
    assign csr_trap_mcause   = interrupt_take ? interrupt_mcause :
                                branch_addr_misaligned_now ? MCAUSE_INSTR_ADDR_MISALIGNED :
                                mem_load_misaligned_now ? MCAUSE_LOAD_ADDR_MISALIGNED :
                                mem_store_misaligned_now ? MCAUSE_STORE_ADDR_MISALIGNED :
                                trap_mcause;
    assign csr_trap_mtval    = interrupt_take ? 32'b0 : trap_mtval;
    assign mtvec_base         = {csr_mtvec_value[WIDTH-1:2], 2'b00};
    assign interrupt_cause_index = interrupt_mcause & 32'h7fff_ffff;
    assign exception_vector_pc   = mtvec_base;
    assign interrupt_vector_pc   = (csr_mtvec_value[1:0] == 2'b01) ?
                                   (mtvec_base + (interrupt_cause_index << 2)) :
                                   mtvec_base;

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
            for (int i = 0; i < BR_RESOLVE_LAT; i++) begin
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

    assign in_if.ready = !lsu_resp_valid &&
                         (!in_if.valid ||
                          (in_if.data.fu_sel != FU_MEM) ||
                          mem_addr_misaligned_candidate ||
                          lsu_req_ready);

    alu u_alu (
        .control_signal(in_if.data.control_signal.alu),
        .datapath      (in_if.data.datapath),
        .result        (alu_result)
    );

    alu u_alu1 (
        .control_signal(in1_if.data.control_signal.alu),
        .datapath      (in1_if.data.datapath),
        .result        (alu1_result)
    );

    csr_file u_csr_file (
        .clk       (in_if.clk),
        .rst_n     (in_if.rst_n),
        .csr_en    (csr_write_en),
        .csr_op    (in_if.data.control_signal.alu.csr_op),
        .csr_addr  (in_if.data.control_signal.alu.csr_addr),
        .csr_wdata (csr_operand),
        .trap_en   (csr_trap_write_en),
        .trap_mepc (csr_trap_mepc),
        .trap_mcause(csr_trap_mcause),
        .trap_mtval(csr_trap_mtval),
        .mret_en   (csr_mret_en),
        .software_irq_pending(software_irq_pending),
        .timer_irq_pending(timer_irq_pending),
        .external_irq_pending(external_irq_pending),
        .csr_rdata (csr_result),
        .mstatus_value(csr_mstatus_value),
        .mie_value (csr_mie_value),
        .mtvec_value(csr_mtvec_value),
        .mepc_value(csr_mepc_value)
    );

    lsu u_lsu (
        .clk           (in_if.clk),
        .rst_n         (in_if.rst_n),
        .req_valid     (lsu_req_valid),
        .req_ready     (lsu_req_ready),
        .squash_en     (branch_squash_now),
        .squash_checkpoint_id(resolve_cp_id_now),
        .resolve_en    (resolve_now),
        .resolve_checkpoint_id(resolve_cp_id_now),
        .control_signal(lsu_control_safe),
        .datapath      (in_if.data.datapath),
        .resp_valid    (lsu_resp_valid),
        .resp_tag      (lsu_resp_tag),
        .resp_preg     (lsu_resp_preg),
        .resp_reg_write(lsu_resp_reg_write),
        .resp_result   (lsu_resp_result)
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
            wb1_valid  <= 1'b0;
            wb1_preg   <= '0;
            wb1_tag    <= '0;
            wb1_result <= '0;
            complete_valid <= 1'b0;
            complete_tag   <= '0;
            complete_result <= '0;
            branch_complete_valid <= 1'b0;
            branch_complete_tag   <= '0;
            branch_complete_result <= '0;
            lane1_complete_valid <= 1'b0;
            lane1_complete_tag   <= '0;
            lane1_complete_result <= '0;
            pc_src    <= 1'b0;
            pc_branch <= '0;
            recover_rat <= 1'b0;
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
            wb1_valid  <= 1'b0;
            wb1_preg   <= '0;
            wb1_tag    <= '0;
            wb1_result <= '0;
            complete_valid <= 1'b0;
            complete_tag   <= '0;
            complete_result <= '0;
            branch_complete_valid <= br_pipe_valid[BR_RESOLVE_LAT-1];
            branch_complete_tag   <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_tag[BR_RESOLVE_LAT-1] : '0;
            branch_complete_result <= '0;
            lane1_complete_valid <= 1'b0;
            lane1_complete_tag   <= '0;
            lane1_complete_result <= '0;
            branch_resolve <= br_pipe_valid[BR_RESOLVE_LAT-1];
            resolve_checkpoint_id <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_cp_id[BR_RESOLVE_LAT-1] : '0;
            pc_src    <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_pc_src[BR_RESOLVE_LAT-1];
            pc_branch <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_pc_branch[BR_RESOLVE_LAT-1] : '0;
            recover_rat <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_pc_src[BR_RESOLVE_LAT-1];
            bp_update_valid <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_valid[BR_RESOLVE_LAT-1];
            bp_update_pc    <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_bp_pc[BR_RESOLVE_LAT-1] : '0;
            bp_update_taken <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_taken[BR_RESOLVE_LAT-1];
            bp_update_is_jalr <= br_pipe_valid[BR_RESOLVE_LAT-1] && br_pipe_bp_is_jalr[BR_RESOLVE_LAT-1];
            bp_update_target <= br_pipe_valid[BR_RESOLVE_LAT-1] ? br_pipe_bp_target[BR_RESOLVE_LAT-1] : '0;

            if (issue1_alu_fire) begin
                lane1_complete_valid <= 1'b1;
                lane1_complete_tag   <= in1_if.data.datapath.rob_tag;
                lane1_complete_result <= alu1_result;

                if (in1_if.data.control_signal.alu.reg_write &&
                    (in1_if.data.datapath.new_des_preg != '0)) begin
                    wb1_valid  <= 1'b1;
                    wb1_preg   <= in1_if.data.datapath.new_des_preg;
                    wb1_tag    <= in1_if.data.datapath.rob_tag;
                    wb1_result <= alu1_result;
                end
            end

            if (interrupt_take) begin
                pc_src       <= 1'b1;
                pc_branch    <= interrupt_vector_pc;
                recover_rat  <= 1'b0;
                branch_resolve <= 1'b0;
                bp_update_valid <= 1'b0;
            end

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

            if (lsu_resp_valid) begin
                complete_valid  <= 1'b1;
                complete_tag    <= lsu_resp_tag;
                complete_result <= lsu_resp_result;

                if (lsu_resp_reg_write) begin
                    wb_valid  <= 1'b1;
                    wb_preg   <= lsu_resp_preg;
                    wb_tag    <= lsu_resp_tag;
                    wb_result <= lsu_resp_result;
                end
            end

            if (!lsu_resp_valid && !interrupt_take && in_if.valid && in_if.ready) begin
                unique case (in_if.data.fu_sel)
                    FU_ALU: begin
                        if (in_if.data.control_signal.alu.sys_en) begin
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= '0;

                            unique case (in_if.data.control_signal.alu.sys_op)
                                SYS_ECALL,
                                SYS_EBREAK,
                                SYS_ILLEGAL: begin
                                    pc_src    <= 1'b1;
                                    pc_branch <= exception_vector_pc;
                                    recover_rat <= 1'b0;
                                end
                                SYS_MRET: begin
                                    pc_src    <= 1'b1;
                                    pc_branch <= csr_mepc_value;
                                    recover_rat <= 1'b0;
                                end
                                default: begin
                                end
                            endcase
                        end else if (in_if.data.control_signal.alu.reg_write) begin
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= in_if.data.control_signal.alu.csr_en ?
                                               csr_result : alu_result;

                            if (in_if.data.datapath.new_des_preg != '0) begin
                                wb_valid  <= 1'b1;
                                wb_preg   <= in_if.data.datapath.new_des_preg;
                                wb_tag    <= in_if.data.datapath.rob_tag;
                                wb_result <= in_if.data.control_signal.alu.csr_en ?
                                             csr_result : alu_result;
                            end
                        end
                    end

                    FU_MEM: begin
                        if (mem_addr_misaligned_now) begin
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= '0;
                            pc_src    <= 1'b1;
                            pc_branch <= exception_vector_pc;
                            recover_rat <= 1'b0;
                        end
                    end

                    FU_BRANCH: begin
                        if (branch_addr_misaligned_now) begin
                            complete_valid <= 1'b1;
                            complete_tag   <= in_if.data.datapath.rob_tag;
                            complete_result <= '0;
                            branch_resolve <= 1'b1;
                            resolve_checkpoint_id <= in_if.data.datapath.checkpoint_id;
                            pc_src    <= 1'b1;
                            pc_branch <= exception_vector_pc;
                            recover_rat <= 1'b0;
                        end else if (in_if.data.control_signal.branch.jump &&
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
