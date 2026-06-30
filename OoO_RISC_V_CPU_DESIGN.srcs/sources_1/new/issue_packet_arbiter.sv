module issue_packet_arbiter (
    pip_if.consumer alu_if,
    pip_if.consumer alu1_if,
    pip_if.consumer lsu_if,
    pip_if.consumer branch_if,
    pip_if.producer issue0_if,
    pip_if.producer issue1_if,

    output logic [1:0] issue0_fu_sel,
    output logic [1:0] issue1_fu_sel
);
    import defines_pkg::*;

    logic alu_is_csr;
    logic alu1_is_csr;
    logic sel0_alu;
    logic sel0_alu1;
    logic sel0_lsu;
    logic sel0_branch;
    logic sel1_alu;
    logic sel1_alu1;
    logic sel1_lsu;
    logic sel1_branch;
    logic slot0_valid;
    logic slot1_valid;

    assign alu_is_csr = alu_if.valid &&
                        (alu_if.data.control_signal.csr_en ||
                         alu_if.data.control_signal.sys_en);
    assign alu1_is_csr = alu1_if.valid &&
                         (alu1_if.data.control_signal.csr_en ||
                          alu1_if.data.control_signal.sys_en);

    always_comb begin
        sel0_alu    = 1'b0;
        sel0_alu1   = 1'b0;
        sel0_lsu    = 1'b0;
        sel0_branch = 1'b0;
        sel1_alu    = 1'b0;
        sel1_alu1   = 1'b0;
        sel1_lsu    = 1'b0;
        sel1_branch = 1'b0;

        // CSR/system operations carry architectural side effects, so keep
        // them single-issue even when another FU is ready.
        if (alu_is_csr) begin
            sel0_alu = 1'b1;
        end else if (alu1_is_csr && !alu_if.valid && !branch_if.valid && !lsu_if.valid) begin
            sel0_alu1 = 1'b1;
        end else if (branch_if.valid) begin
            sel0_branch = 1'b1;
            if (alu_if.valid) begin
                sel1_alu = 1'b1;
            end else if (alu1_if.valid && !alu1_is_csr) begin
                sel1_alu1 = 1'b1;
            end else if (lsu_if.valid) begin
                sel1_lsu = 1'b1;
            end
        end else if (alu_if.valid && lsu_if.valid) begin
            sel0_lsu = 1'b1;
            sel1_alu = 1'b1;
        end else if (alu_if.valid && alu1_if.valid && !alu1_is_csr) begin
            sel0_alu = 1'b1;
            sel1_alu1 = 1'b1;
        end else if (alu_if.valid) begin
            sel0_alu = 1'b1;
        end else if (alu1_if.valid) begin
            sel0_alu1 = 1'b1;
        end else if (lsu_if.valid) begin
            sel0_lsu = 1'b1;
        end
    end

    assign slot0_valid = sel0_alu || sel0_alu1 || sel0_lsu || sel0_branch;
    assign slot1_valid = sel1_alu || sel1_alu1 || sel1_lsu || sel1_branch;

    assign issue0_fu_sel = sel0_branch ? FU_BRANCH :
                           (sel0_alu || sel0_alu1) ? FU_ALU :
                           sel0_lsu    ? FU_MEM :
                                         FU_NOP;
    assign issue1_fu_sel = sel1_branch ? FU_BRANCH :
                           (sel1_alu || sel1_alu1) ? FU_ALU :
                           sel1_lsu    ? FU_MEM :
                                         FU_NOP;

    assign alu_if.ready =
        (sel0_alu && issue0_if.ready) ||
        (sel1_alu && issue1_if.ready && (!slot0_valid || issue0_if.ready));
    assign alu1_if.ready =
        (sel0_alu1 && issue0_if.ready) ||
        (sel1_alu1 && issue1_if.ready && (!slot0_valid || issue0_if.ready));
    assign lsu_if.ready =
        (sel0_lsu && issue0_if.ready) ||
        (sel1_lsu && issue1_if.ready && (!slot0_valid || issue0_if.ready));
    assign branch_if.ready =
        (sel0_branch && issue0_if.ready) ||
        (sel1_branch && issue1_if.ready && (!slot0_valid || issue0_if.ready));

    always_comb begin
        issue0_if.valid = slot0_valid;
        issue0_if.data  = '0;
        issue0_if.data.fu_sel = issue0_fu_sel;

        if (sel0_branch) begin
            issue0_if.data.datapath = branch_if.data.datapath;
            issue0_if.data.control_signal.branch = branch_if.data.control_signal;
        end else if (sel0_alu) begin
            issue0_if.data.datapath = alu_if.data.datapath;
            issue0_if.data.control_signal.alu = alu_if.data.control_signal;
        end else if (sel0_alu1) begin
            issue0_if.data.datapath = alu1_if.data.datapath;
            issue0_if.data.control_signal.alu = alu1_if.data.control_signal;
        end else if (sel0_lsu) begin
            issue0_if.data.datapath = lsu_if.data.datapath;
            issue0_if.data.control_signal.lsu = lsu_if.data.control_signal;
        end
    end

    always_comb begin
        issue1_if.valid = slot1_valid && (!slot0_valid || issue0_if.ready);
        issue1_if.data  = '0;
        issue1_if.data.fu_sel = issue1_fu_sel;

        if (sel1_branch) begin
            issue1_if.data.datapath = branch_if.data.datapath;
            issue1_if.data.control_signal.branch = branch_if.data.control_signal;
        end else if (sel1_alu) begin
            issue1_if.data.datapath = alu_if.data.datapath;
            issue1_if.data.control_signal.alu = alu_if.data.control_signal;
        end else if (sel1_alu1) begin
            issue1_if.data.datapath = alu1_if.data.datapath;
            issue1_if.data.control_signal.alu = alu1_if.data.control_signal;
        end else if (sel1_lsu) begin
            issue1_if.data.datapath = lsu_if.data.datapath;
            issue1_if.data.control_signal.lsu = lsu_if.data.control_signal;
        end
    end

endmodule
