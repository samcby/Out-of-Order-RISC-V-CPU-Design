`timescale 1ns/1ps

module tb_top_packet_backend_multi_issue_suite;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic software_irq;
    logic timer_irq;
    logic external_irq;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    logic issue_valid;
    logic [1:0] issue_fu_type;
    logic [31:0] issue_pc;
    logic [31:0] issue_imm;
    logic rob_head_valid;
    logic rob_head_complete;
    logic [4:0] rob_head_rd;

    int fail_count;
    int lane1_jal_fetch_count;
    int lane1_branch_fetch_count;
    int lane1_jalr_fetch_count;
    int jalr_wait_count;
    int redirect_count;

    top_packet_backend dut (
        .clk(clk),
        .rst_n(rst_n),
        .software_irq(software_irq),
        .timer_irq(timer_irq),
        .external_irq(external_irq),
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
            fail_count++;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic reset_dut;
    begin
        rst_n = 1'b0;
        software_irq = 1'b0;
        timer_irq = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;
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

    function automatic [31:0] arch_reg(input int unsigned index);
        preg_t preg;
    begin
        preg = dut.u_rename_packet.u_rat_2w.rat[index];
        arch_reg = dut.u_prf_2w.regs[preg];
    end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lane1_jal_fetch_count <= 0;
            lane1_branch_fetch_count <= 0;
            lane1_jalr_fetch_count <= 0;
            jalr_wait_count <= 0;
            redirect_count <= 0;
        end else begin
            if (dut.pipe_fd_pkt.valid && dut.pipe_fd_pkt.ready &&
                dut.pipe_fd_pkt.data.lane1.valid &&
                (dut.pipe_fd_pkt.data.lane1.data.pc == 32'd4) &&
                (dut.pipe_fd_pkt.data.lane1.data.instr == 32'h00c000ef)) begin
                lane1_jal_fetch_count <= lane1_jal_fetch_count + 1;
            end

            if (dut.pipe_fd_pkt.valid && dut.pipe_fd_pkt.ready &&
                dut.pipe_fd_pkt.data.lane1.valid &&
                (dut.pipe_fd_pkt.data.lane1.data.pc == 32'd20) &&
                (dut.pipe_fd_pkt.data.lane1.data.instr == 32'h00000663)) begin
                lane1_branch_fetch_count <= lane1_branch_fetch_count + 1;
            end

            if (dut.pipe_fd_pkt.valid && dut.pipe_fd_pkt.ready &&
                dut.pipe_fd_pkt.data.lane1.valid &&
                (dut.pipe_fd_pkt.data.lane1.data.pc == 32'd44) &&
                (dut.pipe_fd_pkt.data.lane1.data.instr == 32'h000101e7)) begin
                lane1_jalr_fetch_count <= lane1_jalr_fetch_count + 1;
            end

            if (dut.u_fetch.jalr_wait_q) begin
                jalr_wait_count <= jalr_wait_count + 1;
            end

            if (dut.pc_src_exe) begin
                redirect_count <= redirect_count + 1;
            end
        end
    end

    task automatic run_issue_mix;
    begin
        $display("---- multi-issue suite: issue mix and counters ----");
        reset_dut;

        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'd3;
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[1] = 32'd8;

        write_word(32'd0,  32'h00002303); // lw   x6,0(x0)
        write_word(32'd4,  32'h00a00293); // addi x5,x0,10
        write_word(32'd8,  32'h00030463); // beq  x6,x0,+8
        write_word(32'd12, 32'h00328513); // addi x10,x5,3
        write_word(32'd16, 32'h00402383); // lw   x7,4(x0)
        write_word(32'd20, 32'h00900593); // addi x11,x0,9
        write_word(32'd24, 32'h00038613); // addi x12,x7,0
        write_word(32'd28, 32'h00d38693); // addi x13,x7,13
        write_word(32'd32, 32'h01600713); // addi x14,x0,22
        write_word(32'd36, 32'h01700793); // addi x15,x0,23
        write_word(32'd40, 32'h01800813); // addi x16,x0,24
        write_word(32'd44, 32'h00000013); // nop

        load_en = 1'b0;
        repeat (360) step_clk;

        $display(
            "[ISSUE_MIX_COUNTERS] branch_alu=%0d mem_alu=%0d alu_alu=%0d lane1_wb=%0d dual_commit=%0d",
            dut.perf_branch_alu_dual_issue_count_q,
            dut.perf_mem_alu_dual_issue_count_q,
            dut.perf_alu_alu_dual_issue_count_q,
            dut.perf_lane1_wb_count_q,
            dut.perf_dual_commit_count_q
        );
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty,
                 "issue mix drained the ROB");
        check_ok(arch_reg(5) == 32'd10 && arch_reg(10) == 32'd13,
                 "branch+ALU result and dependent wakeup are correct");
        check_ok(arch_reg(7) == 32'd8 &&
                 arch_reg(11) == 32'd9 &&
                 arch_reg(12) == 32'd8,
                 "MEM+ALU results and load dependency are correct");
        check_ok(arch_reg(13) == 32'd21 &&
                 arch_reg(14) == 32'd22 &&
                 arch_reg(15) == 32'd23 &&
                 arch_reg(16) == 32'd24,
                 "ALU+ALU results are correct");
        check_ok(dut.perf_mem_alu_dual_issue_count_q >= 1,
                 "counter observed MEM+ALU dual issue");
        check_ok(dut.perf_alu_alu_dual_issue_count_q >= 1,
                 "counter observed ALU+ALU dual issue");
        check_ok(dut.perf_lane1_wb_count_q >= 1,
                 "counter observed lane1 writeback");
        check_ok(dut.perf_dual_commit_count_q >= 1,
                 "counter observed dual commit");
    end
    endtask

    task automatic run_branch_mem;
    begin
        $display("---- multi-issue suite: branch+MEM ----");
        reset_dut;

        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'd8;
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[2] = 32'd42;

        write_word(32'd0,  32'h00002083); // lw   x1,0(x0)
        write_word(32'd4,  32'h00008463); // beq  x1,x0,+8, not taken
        write_word(32'd8,  32'h0000a283); // lw   x5,0(x1)
        write_word(32'd12, 32'h00028513); // addi x10,x5,0
        write_word(32'd16, 32'h02200593); // addi x11,x0,0x22
        write_word(32'd20, 32'h00000013); // nop
        write_word(32'd24, 32'h00000013); // nop
        write_word(32'd28, 32'h00000013); // clear prior scenario tail
        write_word(32'd32, 32'h00000013);
        write_word(32'd36, 32'h00000013);
        write_word(32'd40, 32'h00000013);
        write_word(32'd44, 32'h00000013);
        write_word(32'd48, 32'h00000013);
        write_word(32'd52, 32'h00000013);
        write_word(32'd56, 32'h00000013);
        write_word(32'd60, 32'h00000013);

        load_en = 1'b0;
        repeat (400) step_clk;

        check_ok(dut.perf_branch_mem_dual_issue_count_q >= 1,
                 "counter observed branch+MEM dual issue");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty,
                 "branch+MEM scenario drained the ROB");
        check_ok(arch_reg(5) == 32'd42 && arch_reg(10) == 32'd42,
                 "slot1 load and its dependent consumer are correct");
        check_ok(arch_reg(11) == 32'h00000022,
                 "post-branch path completed");
    end
    endtask

    task automatic run_lane1_control;
    begin
        $display("---- multi-issue suite: lane1 control flow ----");
        reset_dut;

        write_word(32'd0,  32'h00700293); // addi x5,x0,7
        write_word(32'd4,  32'h00c000ef); // jal  x1,+12 -> 16, link=8
        write_word(32'd8,  32'h05500513); // wrong path after JAL
        write_word(32'd12, 32'h06600593); // wrong path after JAL
        write_word(32'd16, 32'h00328513); // addi x10,x5,3
        write_word(32'd20, 32'h00000663); // beq  x0,x0,+12 -> 32
        write_word(32'd24, 32'h06600613); // wrong path x12
        write_word(32'd28, 32'h07700693); // wrong path x13
        write_word(32'd32, 32'h00008593); // addi x11,x1,0
        write_word(32'd36, 32'h02200713); // addi x14,x0,0x22
        write_word(32'd40, 32'h03400113); // addi x2,x0,52
        write_word(32'd44, 32'h000101e7); // jalr x3,0(x2) -> 52, link=48
        write_word(32'd48, 32'h06300793); // blocked fall-through x15
        write_word(32'd52, 32'h00018813); // addi x16,x3,0
        write_word(32'd56, 32'h00000013); // nop
        write_word(32'd60, 32'h00000013); // nop

        load_en = 1'b0;
        repeat (400) step_clk;

        check_ok(lane1_jal_fetch_count >= 1 &&
                 lane1_branch_fetch_count >= 1 &&
                 lane1_jalr_fetch_count >= 1,
                 "frontend delivered JAL, branch, and JALR in lane1");
        check_ok(jalr_wait_count >= 1 && redirect_count >= 2,
                 "lane1 JALR miss wait and control redirects were observed");
        check_ok(dut.perf_branch_alu_dual_issue_count_q >= 1,
                 "lane1 control scenario observed branch+ALU dual issue");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty,
                 "lane1 control scenario drained the ROB");
        check_ok(arch_reg(1) == 32'd8 &&
                 arch_reg(2) == 32'd52 &&
                 arch_reg(3) == 32'd48,
                 "lane1 JAL/JALR links and same-packet JALR target are correct");
        check_ok(arch_reg(5) == 32'd7 &&
                 arch_reg(10) == 32'd10 &&
                 arch_reg(11) == 32'd8 &&
                 arch_reg(14) == 32'h00000022,
                 "older lane0 and recovered target-path results are correct");
        check_ok(arch_reg(12) == 32'd0 &&
                 arch_reg(13) == 32'd0 &&
                 arch_reg(15) == 32'd0,
                 "branch and JALR wrong paths did not commit");
        check_ok(arch_reg(16) == 32'd48,
                 "JALR target consumed the link register");
    end
    endtask

    initial begin
        rst_n = 1'b0;
        software_irq = 1'b0;
        timer_irq = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        run_issue_mix;
        run_branch_mem;
        run_lane1_control;

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_multi_issue_suite PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_multi_issue_suite FAIL (%0d errors) ====",
                     fail_count);
        end

        $finish;
    end

endmodule
