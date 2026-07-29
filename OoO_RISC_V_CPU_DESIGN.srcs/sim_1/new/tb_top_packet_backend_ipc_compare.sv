`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend ipc compare.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_ipc_compare;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;

    logic dual_issue_valid;
    logic [1:0] dual_issue_fu_type;
    logic [31:0] dual_issue_pc;
    logic [31:0] dual_issue_imm;
    logic dual_rob_head_valid;
    logic dual_rob_head_complete;
    logic [4:0] dual_rob_head_rd;

    logic single_issue_valid;
    logic [1:0] single_issue_fu_type;
    logic [31:0] single_issue_pc;
    logic [31:0] single_issue_imm;
    logic single_rob_head_valid;
    logic single_rob_head_complete;
    logic [4:0] single_rob_head_rd;

    logic dual_done;
    logic single_done;
    logic [31:0] dual_finish_cycles;
    logic [31:0] single_finish_cycles;
    logic [31:0] dual_finish_commits;
    logic [31:0] single_finish_commits;

    int fail_count;

    top_packet_backend #(
        .ENABLE_2WIDE(1'b1)
    ) dut_dual (
        .clk(clk),
        .rst_n(rst_n),
        .software_irq(1'b0),
        .timer_irq(1'b0),
        .external_irq(1'b0),
        .load_en(load_en),
        .load_addr(load_addr),
        .load_instr_byte(load_instr_byte),
        .issue_valid(dual_issue_valid),
        .issue_fu_type(dual_issue_fu_type),
        .issue_pc(dual_issue_pc),
        .issue_imm(dual_issue_imm),
        .rob_head_valid(dual_rob_head_valid),
        .rob_head_complete(dual_rob_head_complete),
        .rob_head_rd(dual_rob_head_rd)
    );

    top_packet_backend #(
        .ENABLE_2WIDE(1'b0)
    ) dut_single (
        .clk(clk),
        .rst_n(rst_n),
        .software_irq(1'b0),
        .timer_irq(1'b0),
        .external_irq(1'b0),
        .load_en(load_en),
        .load_addr(load_addr),
        .load_instr_byte(load_instr_byte),
        .issue_valid(single_issue_valid),
        .issue_fu_type(single_issue_fu_type),
        .issue_pc(single_issue_pc),
        .issue_imm(single_issue_imm),
        .rob_head_valid(single_rob_head_valid),
        .rob_head_complete(single_rob_head_complete),
        .rob_head_rd(single_rob_head_rd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    wire dual_marker_commit0 =
        dut_dual.commit_en && (dut_dual.rob_head.datapath.rd == 5'd31);
    wire dual_marker_commit1 =
        dut_dual.commit_en1 && (dut_dual.rob_head1.datapath.rd == 5'd31);
    wire dual_marker_commit = dual_marker_commit0 || dual_marker_commit1;
    wire single_marker_commit0 =
        dut_single.commit_en && (dut_single.rob_head.datapath.rd == 5'd31);
    wire single_marker_commit1 =
        dut_single.commit_en1 && (dut_single.rob_head1.datapath.rd == 5'd31);
    wire single_marker_commit = single_marker_commit0 || single_marker_commit1;

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

    task automatic reset_duts;
    begin
        rst_n = 1'b0;
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

    function automatic [31:0] enc_addi(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input integer imm
    );
        logic [11:0] imm12;
    begin
        imm12 = imm[11:0];
        enc_addi = {imm12, rs1, 3'b000, rd, 7'b0010011};
    end
    endfunction

    function automatic [31:0] enc_lw(
        input logic [4:0] rd,
        input logic [4:0] rs1,
        input integer imm
    );
        logic [11:0] imm12;
    begin
        imm12 = imm[11:0];
        enc_lw = {imm12, rs1, 3'b010, rd, 7'b0000011};
    end
    endfunction

    function automatic [31:0] dual_arch_reg(input int unsigned index);
        preg_t preg;
    begin
        preg = dut_dual.u_rename_packet.u_rat_2w.rat[index];
        dual_arch_reg = dut_dual.u_prf_2w.regs[preg];
    end
    endfunction

    function automatic [31:0] single_arch_reg(input int unsigned index);
        preg_t preg;
    begin
        preg = dut_single.u_rename_packet.u_rat_2w.rat[index];
        single_arch_reg = dut_single.u_prf_2w.regs[preg];
    end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || load_en) begin
            dual_done <= 1'b0;
            single_done <= 1'b0;
            dual_finish_cycles <= '0;
            single_finish_cycles <= '0;
            dual_finish_commits <= '0;
            single_finish_commits <= '0;
        end else begin
            if (!dual_done && dual_marker_commit) begin
                dual_done <= 1'b1;
                dual_finish_cycles <= dut_dual.perf_active_cycle_count_q + 1'b1;
                // If the marker is head0, exclude a younger head1 instruction
                // that happens to retire in the same cycle.
                dual_finish_commits <= dut_dual.perf_commit_count_q +
                                       (dual_marker_commit1 ? 32'd2 : 32'd1);
            end

            if (!single_done && single_marker_commit) begin
                single_done <= 1'b1;
                single_finish_cycles <= dut_single.perf_active_cycle_count_q + 1'b1;
                single_finish_commits <= dut_single.perf_commit_count_q +
                                         (single_marker_commit1 ? 32'd2 : 32'd1);
            end
        end
    end

    task automatic wait_for_both(input int max_cycles, input string workload);
        int cycles;
    begin
        cycles = 0;
        while (!(dual_done && single_done) && (cycles < max_cycles)) begin
            step_clk;
            cycles++;
        end
        check_ok(dual_done && single_done,
                 {workload, " completed in both width modes"});
    end
    endtask

    task automatic report_ipc(input string workload, input int expected_commits);
        real dual_ipc;
        real single_ipc;
        real speedup;
    begin
        dual_ipc = $itor(dual_finish_commits) / $itor(dual_finish_cycles);
        single_ipc = $itor(single_finish_commits) / $itor(single_finish_cycles);
        speedup = $itor(single_finish_cycles) / $itor(dual_finish_cycles);

        $display("[IPC:%s] dual cycles=%0d commits=%0d ipc=%0.3f | single cycles=%0d commits=%0d ipc=%0.3f | speedup=%0.3fx",
                 workload,
                 dual_finish_cycles,
                 dual_finish_commits,
                 dual_ipc,
                 single_finish_cycles,
                 single_finish_commits,
                 single_ipc,
                 speedup);

        check_ok(dual_finish_commits == expected_commits &&
                 single_finish_commits == expected_commits,
                 {workload, " retired the expected instruction count"});
        check_ok(dut_single.perf_fetch_dual_count_q == 0 &&
                 dut_single.perf_dual_issue_count_q == 0 &&
                 dut_single.perf_dual_commit_count_q == 0,
                 {workload, " single-width baseline stayed strictly 1-wide"});
    end
    endtask

    task automatic run_independent_alu;
        int i;
    begin
        $display("---- IPC workload: independent ALU ----");
        reset_duts;

        for (i = 0; i < 24; i++) begin
            write_word(i * 4, enc_addi(5 + i, 0, i + 1));
        end
        write_word(32'd96, 32'h00000013);              // nop
        write_word(32'd100, enc_addi(31, 0, 12'h05a)); // commit sentinel
        write_word(32'd104, 32'h00000013);
        write_word(32'd108, 32'h00000013);

        load_en = 1'b0;
        wait_for_both(500, "independent ALU");
        report_ipc("independent_alu", 26);

        check_ok(dual_finish_cycles < single_finish_cycles,
                 "independent ALU benefits from 2-wide execution");
        check_ok(dut_dual.perf_dual_issue_count_q >= 1 &&
                 dut_dual.perf_dual_commit_count_q >= 1,
                 "independent ALU exercised dual issue and dual commit");
        check_ok(dual_arch_reg(5) == 32'd1 &&
                 dual_arch_reg(28) == 32'd24 &&
                 single_arch_reg(5) == 32'd1 &&
                 single_arch_reg(28) == 32'd24,
                 "independent ALU architectural results match");
    end
    endtask

    task automatic run_dependency_chain;
        int i;
    begin
        $display("---- IPC workload: dependency chain ----");
        reset_duts;

        write_word(32'd0, enc_addi(5, 0, 0));
        for (i = 1; i < 24; i++) begin
            write_word(i * 4, enc_addi(5, 5, 1));
        end
        write_word(32'd96, 32'h00000013);              // nop
        write_word(32'd100, enc_addi(31, 0, 12'h05a)); // commit sentinel
        write_word(32'd104, 32'h00000013);
        write_word(32'd108, 32'h00000013);

        load_en = 1'b0;
        wait_for_both(700, "dependency chain");
        report_ipc("dependency_chain", 26);

        check_ok(dual_finish_cycles <= single_finish_cycles,
                 "dependency chain does not regress in 2-wide mode");
        check_ok(dual_arch_reg(5) == 32'd23 &&
                 single_arch_reg(5) == 32'd23,
                 "dependency chain architectural results match");
    end
    endtask

    task automatic run_memory_mix;
        int i;
    begin
        $display("---- IPC workload: memory plus ALU ----");
        reset_duts;

        for (i = 0; i < 8; i++) begin
            dut_dual.u_execution.u_lsu.u_data_cache.u_data_memory.mem[i] = i + 1;
            dut_single.u_execution.u_lsu.u_data_cache.u_data_memory.mem[i] = i + 1;
            write_word(i * 8, enc_lw(5 + i, 0, i * 4));
            write_word(i * 8 + 4, enc_addi(16 + i, 0, 100 + i));
        end
        write_word(32'd64, 32'h00000013);             // nop
        write_word(32'd68, enc_addi(31, 0, 12'h05a)); // commit sentinel
        write_word(32'd72, 32'h00000013);
        write_word(32'd76, 32'h00000013);

        load_en = 1'b0;
        wait_for_both(900, "memory plus ALU");
        report_ipc("memory_plus_alu", 18);

        check_ok(dual_finish_cycles < single_finish_cycles,
                 "memory plus ALU benefits from paired issue");
        check_ok(dut_dual.perf_mem_alu_dual_issue_count_q >= 1,
                 "memory plus ALU exercised MEM+ALU dual issue");
        check_ok(dual_arch_reg(5) == 32'd1 &&
                 dual_arch_reg(12) == 32'd8 &&
                 single_arch_reg(5) == 32'd1 &&
                 single_arch_reg(12) == 32'd8,
                 "memory results match between width modes");
        check_ok(dual_arch_reg(16) == 32'd100 &&
                 dual_arch_reg(23) == 32'd107 &&
                 single_arch_reg(16) == 32'd100 &&
                 single_arch_reg(23) == 32'd107,
                 "paired ALU results match between width modes");
    end
    endtask

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        run_independent_alu;
        run_dependency_chain;
        run_memory_mix;

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_ipc_compare PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_ipc_compare FAIL (%0d errors) ====",
                     fail_count);
        end

        $finish;
    end

endmodule
