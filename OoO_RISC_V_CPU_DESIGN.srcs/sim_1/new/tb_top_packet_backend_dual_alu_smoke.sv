`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend dual alu smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_dual_alu_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    logic        load_en;
    logic [31:0] load_addr;
    logic [7:0]  load_instr_byte;

    logic        issue_valid;
    logic [1:0]  issue_fu_type;
    logic [31:0] issue_pc;
    logic [31:0] issue_imm;

    logic        rob_head_valid;
    logic        rob_head_complete;
    logic [4:0]  rob_head_rd;

    int fail_count;
    int dual_issue_count;
    int lane1_wb_count;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t x5_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] x5_value;

    top_packet_backend dut (
        .clk(clk),
        .rst_n(rst_n),
        .software_irq(1'b0),
        .timer_irq(1'b0),
        .external_irq(1'b0),
        .load_en(load_en),
        .load_addr(load_addr),
        .load_instr_byte(load_instr_byte),
        .issue_valid(issue_valid),
        .issue_fu_type(issue_fu_type),
        .issue_pc(issue_pc),
        .issue_imm(issue_imm),
        .rob_head_valid(rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head_rd(rob_head_rd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok;
        input logic cond;
        input string msg;
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic write_byte;
        input [31:0] byte_addr;
        input [7:0]  data_byte;
    begin
        load_en         = 1'b1;
        load_addr       = byte_addr;
        load_instr_byte = data_byte;
        step_clk;
    end
    endtask

    task automatic write_word;
        input [31:0] byte_addr;
        input [31:0] data_word;
    begin
        write_byte(byte_addr + 0, data_word[7:0]);
        write_byte(byte_addr + 1, data_word[15:8]);
        write_byte(byte_addr + 2, data_word[23:16]);
        write_byte(byte_addr + 3, data_word[31:24]);
    end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dual_issue_count = 0;
            lane1_wb_count = 0;
        end else begin
            #1;
            if (dut.issue_if.valid && dut.issue_if.ready &&
                dut.issue1_if.valid && dut.issue1_if.ready &&
                (dut.issue_if.data.fu_sel == FU_BRANCH) &&
                (dut.issue1_if.data.fu_sel == FU_ALU)) begin
                dual_issue_count = dual_issue_count + 1;
            end

            if (dut.wb1_valid) begin
                lane1_wb_count = lane1_wb_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'd3;

        write_word(32'd0,  32'h00002303); // lw   x6,0(x0)
        write_word(32'd4,  32'h00730293); // addi x5,x6,7, waits for load result
        write_word(32'd8,  32'h00030463); // beq  x6,x0,+8, not taken, waits for same load
        write_word(32'd12, 32'h00328513); // addi x10,x5,3
        write_word(32'd16, 32'h02200593); // addi x11,x0,0x22
        write_word(32'd20, 32'h00000013); // nop
        write_word(32'd24, 32'h00000013); // nop

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        x5_preg = dut.u_rename_packet.u_rat_2w.rat[5];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        x5_value = dut.u_prf_2w.regs[x5_preg];

        $display("[SUMMARY] dual_issue_count=%0d lane1_wb_count=%0d x5_preg=%0d x5=%0d a0_preg=%0d a0=%0d a1_preg=%0d a1=%0d rob_empty=%0b",
                 dual_issue_count,
                 lane1_wb_count,
                 x5_preg, $signed(x5_value),
                 a0_preg, $signed(a0_value),
                 a1_preg, $signed(a1_value),
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(dual_issue_count >= 1,
                 "packet backend observed branch+ALU dual issue");
        check_ok(lane1_wb_count >= 1,
                 "packet backend observed lane1 ALU writeback");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "packet backend ROB drained after dual-ALU smoke program");
        check_ok(x5_value == 32'd10,
                 "dual-issue lane1 ALU produced x5=10");
        check_ok(a0_value == 32'd13,
                 "dependent instruction consumed lane1 ALU result");
        check_ok(a1_value == 32'h00000022,
                 "post-branch fall-through instruction completed");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_dual_alu_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_dual_alu_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
