`timescale 1ns/1ps

module tb_execution_stage_dual_alu;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic wb_valid;
    preg_t wb_preg;
    rob_tag_t wb_tag;
    logic [WIDTH-1:0] wb_result;
    logic wb1_valid;
    preg_t wb1_preg;
    rob_tag_t wb1_tag;
    logic [WIDTH-1:0] wb1_result;
    logic complete_valid;
    rob_tag_t complete_tag;
    logic [WIDTH-1:0] complete_result;
    logic branch_complete_valid;
    rob_tag_t branch_complete_tag;
    logic [WIDTH-1:0] branch_complete_result;
    logic lane1_complete_valid;
    rob_tag_t lane1_complete_tag;
    logic [WIDTH-1:0] lane1_complete_result;
    logic branch_resolve;
    cp_id_t resolve_checkpoint_id;
    logic bp_update_valid;
    logic [WIDTH-1:0] bp_update_pc;
    logic bp_update_taken;
    logic bp_update_is_jalr;
    logic [WIDTH-1:0] bp_update_target;
    logic pc_src;
    logic [WIDTH-1:0] pc_branch;
    logic recover_rat;
    logic [WIDTH-1:0] csr_mstatus_value;
    logic [WIDTH-1:0] csr_mie_value;

    pip_if #(issue_exe_t) issue0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue1_if (.clk(clk), .rst_n(rst_n));

    execution_stage dut (
        .in_if(issue0_if.consumer),
        .in1_if(issue1_if.consumer),
        .software_irq_pending(1'b0),
        .timer_irq_pending(1'b0),
        .external_irq_pending(1'b0),
        .interrupt_take(1'b0),
        .interrupt_mepc('0),
        .interrupt_mcause('0),
        .commit_store_valid0(1'b0),
        .commit_store_tag0('0),
        .commit_store_valid1(1'b0),
        .commit_store_tag1('0),
        .wb_valid(wb_valid),
        .wb_preg(wb_preg),
        .wb_tag(wb_tag),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_preg(wb1_preg),
        .wb1_tag(wb1_tag),
        .wb1_result(wb1_result),
        .complete_valid(complete_valid),
        .complete_tag(complete_tag),
        .complete_result(complete_result),
        .branch_complete_valid(branch_complete_valid),
        .branch_complete_tag(branch_complete_tag),
        .branch_complete_result(branch_complete_result),
        .lane1_complete_valid(lane1_complete_valid),
        .lane1_complete_tag(lane1_complete_tag),
        .lane1_complete_result(lane1_complete_result),
        .branch_resolve(branch_resolve),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_is_jalr(bp_update_is_jalr),
        .bp_update_target(bp_update_target),
        .pc_src(pc_src),
        .pc_branch(pc_branch),
        .recover_rat(recover_rat),
        .csr_mstatus_value(csr_mstatus_value),
        .csr_mie_value(csr_mie_value)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        issue0_if.valid = 1'b0;
        issue0_if.data = '0;
        issue1_if.valid = 1'b0;
        issue1_if.data = '0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        issue1_if.valid = 1'b1;
        issue1_if.data = '0;
        issue1_if.data.fu_sel = FU_ALU;
        issue1_if.data.control_signal.alu.reg_write = 1'b1;
        issue1_if.data.control_signal.alu.alu_src = 1'b0;
        issue1_if.data.control_signal.alu.alu_op = ALU_ADD;
        issue1_if.data.datapath.rob_tag = rob_tag_t'(7);
        issue1_if.data.datapath.new_des_preg = preg_t'(42);
        issue1_if.data.datapath.src1_value = 32'h0000_0011;
        issue1_if.data.datapath.src2_value = 32'h0000_0022;
        #1;
        check_ok(issue1_if.ready, "lane1 ordinary ALU is accepted");
        step_clk;

        issue1_if.valid = 1'b0;
        check_ok(wb1_valid, "lane1 ALU produces second writeback");
        check_ok(wb1_preg == preg_t'(42), "lane1 writeback preserves destination preg");
        check_ok(wb1_tag == rob_tag_t'(7), "lane1 writeback preserves ROB tag");
        check_ok(wb1_result == 32'h0000_0033, "lane1 writeback computes ALU result");
        check_ok(lane1_complete_valid, "lane1 ALU uses independent complete channel");
        check_ok(lane1_complete_tag == rob_tag_t'(7), "lane1 complete preserves ROB tag");
        check_ok(lane1_complete_result == 32'h0000_0033, "lane1 complete carries ALU result");
        check_ok(!branch_complete_valid, "branch complete channel remains idle for lane1 ALU");
        check_ok(!wb_valid && !complete_valid, "lane0 outputs remain idle");

        step_clk;
        issue1_if.valid = 1'b1;
        issue1_if.data = '0;
        issue1_if.data.fu_sel = FU_MEM;
        issue1_if.data.control_signal.lsu.mem_write = 1'b1;
        issue1_if.data.control_signal.lsu.funct3 = 3'b010;
        issue1_if.data.datapath.rob_tag = rob_tag_t'(8);
        issue1_if.data.datapath.src1_value = 32'h0000_0000;
        issue1_if.data.datapath.src2_value = 32'h1234_5678;
        #1;
        check_ok(issue1_if.ready, "lane1 accepts a memory operation after execution widening");
        step_clk;
        issue1_if.valid = 1'b0;
        step_clk;
        check_ok(complete_valid && complete_tag == rob_tag_t'(8),
                 "lane1 store completes through the tagged LSU response path");

        $display("==== tb_execution_stage_dual_alu PASS ====");
        $finish;
    end

endmodule
