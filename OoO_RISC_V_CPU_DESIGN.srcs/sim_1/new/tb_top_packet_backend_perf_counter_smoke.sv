`timescale 1ns/1ps

module tb_top_packet_backend_perf_counter_smoke;

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
    preg_t x5_preg;
    preg_t x7_preg;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t a2_preg;
    preg_t x13_preg;
    preg_t x14_preg;
    logic [31:0] x5_value;
    logic [31:0] x7_value;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] a2_value;
    logic [31:0] x13_value;
    logic [31:0] x14_value;

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

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic write_byte(input [31:0] byte_addr, input [7:0] data_byte);
    begin
        load_en = 1'b1;
        load_addr = byte_addr;
        load_instr_byte = data_byte;
        step_clk;
    end
    endtask

    task automatic write_word(input [31:0] byte_addr, input [31:0] data_word);
    begin
        write_byte(byte_addr + 0, data_word[7:0]);
        write_byte(byte_addr + 1, data_word[15:8]);
        write_byte(byte_addr + 2, data_word[23:16]);
        write_byte(byte_addr + 3, data_word[31:24]);
    end
    endtask

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
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[1] = 32'd8;

        write_word(32'd0,  32'h00002303); // lw   x6,0(x0)
        write_word(32'd4,  32'h00730293); // addi x5,x6,7, pairs with branch after x6 is ready
        write_word(32'd8,  32'h00030463); // beq  x6,x0,+8, not taken
        write_word(32'd12, 32'h00328513); // addi x10,x5,3
        write_word(32'd16, 32'h00402383); // lw   x7,4(x0), MEM lane0
        write_word(32'd20, 32'h00900593); // addi x11,x0,9, ALU lane1
        write_word(32'd24, 32'h00038613); // addi x12,x7,0
        write_word(32'd28, 32'h01500693); // addi x13,x0,21, ALU lane0
        write_word(32'd32, 32'h01600713); // addi x14,x0,22, ALU lane1
        write_word(32'd36, 32'h00000013); // nop
        write_word(32'd40, 32'h00000013); // nop

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (360) step_clk;

        x5_preg = dut.u_rename_packet.u_rat_2w.rat[5];
        x7_preg = dut.u_rename_packet.u_rat_2w.rat[7];
        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        a2_preg = dut.u_rename_packet.u_rat_2w.rat[12];
        x13_preg = dut.u_rename_packet.u_rat_2w.rat[13];
        x14_preg = dut.u_rename_packet.u_rat_2w.rat[14];
        x5_value = dut.u_prf_2w.regs[x5_preg];
        x7_value = dut.u_prf_2w.regs[x7_preg];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        a2_value = dut.u_prf_2w.regs[a2_preg];
        x13_value = dut.u_prf_2w.regs[x13_preg];
        x14_value = dut.u_prf_2w.regs[x14_preg];

        $display("[SUMMARY] fetch=%0d dual_fetch=%0d rename=%0d dual_rename=%0d dispatch=%0d dual_dispatch=%0d issue=%0d dual_issue=%0d branch_alu=%0d mem_alu=%0d alu_alu=%0d lane1_wb=%0d dual_commit=%0d",
                 dut.perf_fetch_packet_count_q,
                 dut.perf_fetch_dual_count_q,
                 dut.perf_rename_packet_count_q,
                 dut.perf_rename_dual_count_q,
                 dut.perf_dispatch_packet_count_q,
                 dut.perf_dispatch_dual_count_q,
                 dut.perf_issue_count_q,
                 dut.perf_dual_issue_count_q,
                 dut.perf_branch_alu_dual_issue_count_q,
                 dut.perf_mem_alu_dual_issue_count_q,
                 dut.perf_alu_alu_dual_issue_count_q,
                 dut.perf_lane1_wb_count_q,
                 dut.perf_dual_commit_count_q);
        $display("[STATE] x5=0x%08h x7=0x%08h a0=0x%08h a1=0x%08h a2=0x%08h x13=0x%08h x14=0x%08h rob_empty=%0b",
                 x5_value,
                 x7_value,
                 a0_value,
                 a1_value,
                 a2_value,
                 x13_value,
                 x14_value,
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "packet backend ROB drained after perf counter smoke program");
        check_ok(x5_value == 32'd10,
                 "branch+ALU section produced x5=10");
        check_ok(a0_value == 32'd13,
                 "dependent ALU consumed lane1 branch+ALU result");
        check_ok(x7_value == 32'd8,
                 "MEM+ALU section loaded x7=8");
        check_ok(a1_value == 32'd9,
                 "MEM+ALU section produced lane1 a1=9");
        check_ok(a2_value == 32'd8,
                 "dependent ALU consumed loaded x7");
        check_ok(x13_value == 32'd21,
                 "ALU+ALU section produced x13=21");
        check_ok(x14_value == 32'd22,
                 "ALU+ALU section produced x14=22");
        check_ok(dut.perf_fetch_packet_count_q >= 1,
                 "perf counter recorded packet fetch");
        check_ok(dut.perf_fetch_dual_count_q >= 1,
                 "perf counter recorded dual-lane fetch");
        check_ok(dut.perf_rename_dual_count_q >= 1,
                 "perf counter recorded dual-lane rename");
        check_ok(dut.perf_dispatch_dual_count_q >= 1,
                 "perf counter recorded dual-lane dispatch");
        check_ok(dut.perf_dual_issue_count_q >= 2,
                 "perf counter recorded multiple dual-issue cycles");
        check_ok(dut.perf_branch_alu_dual_issue_count_q >= 1,
                 "perf counter recorded branch+ALU dual issue");
        check_ok(dut.perf_mem_alu_dual_issue_count_q >= 1,
                 "perf counter recorded MEM+ALU dual issue");
        check_ok(dut.perf_alu_alu_dual_issue_count_q >= 1,
                 "perf counter recorded ALU+ALU dual issue");
        check_ok(dut.perf_lane1_wb_count_q >= 2,
                 "perf counter recorded lane1 ALU writebacks");
        check_ok(dut.perf_dual_commit_count_q >= 1,
                 "perf counter recorded dual commit");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_perf_counter_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_perf_counter_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
