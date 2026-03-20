module issue_arbiter (
    pip_if.consumer alu_if,
    pip_if.consumer lsu_if,
    pip_if.consumer branch_if,
    pip_if.producer issue_if,

    output logic [1:0] fu_sel
);
    import defines_pkg::*;

    logic choose_alu;
    logic choose_lsu;
    logic choose_branch;

    always_comb begin
        choose_alu    = 1'b0;
        choose_lsu    = 1'b0;
        choose_branch = 1'b0;
        fu_sel        = FU_NOP;

        if (branch_if.valid) begin
            choose_branch = 1'b1;
            fu_sel        = FU_BRANCH;
        end else if (alu_if.valid) begin
            choose_alu = 1'b1;
            fu_sel     = FU_ALU;
        end else if (lsu_if.valid) begin
            choose_lsu = 1'b1;
            fu_sel     = FU_MEM;
        end
    end

    assign alu_if.ready    = issue_if.ready && choose_alu;
    assign lsu_if.ready    = issue_if.ready && choose_lsu;
    assign branch_if.ready = issue_if.ready && choose_branch;

    always_comb begin
        issue_if.valid = 1'b0;
        issue_if.data  = '0;

        if (choose_branch) begin
            issue_if.valid = branch_if.valid;
            issue_if.data.fu_sel = FU_BRANCH;
            issue_if.data.datapath = branch_if.data.datapath;
            issue_if.data.control_signal.branch = branch_if.data.control_signal;
        end else if (choose_alu) begin
            issue_if.valid = alu_if.valid;
            issue_if.data.fu_sel = FU_ALU;
            issue_if.data.datapath = alu_if.data.datapath;
            issue_if.data.control_signal.alu = alu_if.data.control_signal;
        end else if (choose_lsu) begin
            issue_if.valid = lsu_if.valid;
            issue_if.data.fu_sel = FU_MEM;
            issue_if.data.datapath = lsu_if.data.datapath;
            issue_if.data.control_signal.lsu = lsu_if.data.control_signal;
        end
    end

endmodule
