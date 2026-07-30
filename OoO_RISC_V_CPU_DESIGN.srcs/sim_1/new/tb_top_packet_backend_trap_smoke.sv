`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend trap smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_trap_smoke;

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
    int drain_cycles;
    int csr_system_issue_count;
    int csr_system_pair_count;
    int precise_trap_count;
    int precise_trap_bad_count;
    int early_ecall_side_effect_count;
    int ecall_retire_count;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] mtvec_value;
    logic [31:0] mepc_value;
    logic [31:0] mcause_value;
    logic [31:0] mstatus_value;

    top_packet_backend dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .software_irq     (1'b0),
        .timer_irq        (1'b0),
        .external_irq     (1'b0),
        .load_en          (load_en),
        .load_addr        (load_addr),
        .load_instr_byte  (load_instr_byte),
        .issue_valid      (issue_valid),
        .issue_fu_type    (issue_fu_type),
        .issue_pc         (issue_pc),
        .issue_imm        (issue_imm),
        .rob_head_valid   (rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head_rd      (rob_head_rd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_system_issue_count <= 0;
            csr_system_pair_count  <= 0;
        end else begin
            #1;
            if (dut.issue_if.valid && dut.issue_if.ready &&
                (dut.issue_if.data.fu_sel == FU_ALU) &&
                (dut.issue_if.data.control_signal.alu.csr_en ||
                 dut.issue_if.data.control_signal.alu.sys_en)) begin
                csr_system_issue_count <= csr_system_issue_count + 1;
                if (dut.issue1_if.valid && dut.issue1_if.ready) begin
                    csr_system_pair_count <= csr_system_pair_count + 1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            precise_trap_count           <= 0;
            precise_trap_bad_count       <= 0;
            early_ecall_side_effect_count <= 0;
            ecall_retire_count           <= 0;
        end else begin
            if (dut.trap_commit) begin
                precise_trap_count <= precise_trap_count + 1;
                if (!dut.rob_head.datapath.exception_valid ||
                    (dut.rob_head.datapath.pc != 32'h00000008) ||
                    (dut.rob_head.datapath.exception_cause != MCAUSE_ECALL_M) ||
                    (dut.rob_head.datapath.exception_tval != 32'b0)) begin
                    precise_trap_bad_count <= precise_trap_bad_count + 1;
                end
            end

            if (dut.issue_if.valid && dut.issue_if.ready &&
                (dut.issue_if.data.datapath.instr == 32'h00000073) &&
                (dut.u_execution.u_csr_file.mcause_q == MCAUSE_ECALL_M)) begin
                early_ecall_side_effect_count <=
                    early_ecall_side_effect_count + 1;
            end

            if ((dut.retire_trace0.valid &&
                 (dut.retire_trace0.instr == 32'h00000073)) ||
                (dut.retire_trace1.valid &&
                 (dut.retire_trace1.instr == 32'h00000073))) begin
                ecall_retire_count <= ecall_retire_count + 1;
            end
        end
    end

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

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Main program:
        //   mtvec = 0x7f0; ecall; after mret, set a0 = 0x55.
        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00000073); // ecall
        write_word(32'd12, 32'h05500513); // addi  x10,x0,0x55

        // Trap handler at 0x7f0:
        //   read mepc, advance it past ecall, read mcause into a1, return.
        write_word(32'd2032, 32'h34102173); // csrrs x2,mepc,x0
        write_word(32'd2036, 32'h00410113); // addi  x2,x2,4
        write_word(32'd2040, 32'h34111073); // csrrw x0,mepc,x2
        write_word(32'd2044, 32'h342021f3); // csrrs x3,mcause,x0
        write_word(32'd2048, 32'h00018593); // addi  x11,x3,0
        write_word(32'd2052, 32'h30200073); // mret

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        a0_preg       = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg       = dut.u_rename_packet.u_rat_2w.rat[11];
        a0_value      = dut.u_prf_2w.regs[a0_preg];
        a1_value      = dut.u_prf_2w.regs[a1_preg];
        mtvec_value   = dut.u_execution.u_csr_file.mtvec_q;
        mepc_value    = dut.u_execution.u_csr_file.mepc_q;
        mcause_value  = dut.u_execution.u_csr_file.mcause_q;
        mstatus_value = dut.u_execution.u_csr_file.mstatus_q;

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) mtvec=0x%08h mepc=0x%08h mcause=0x%08h mstatus=0x%08h csr_sys_issue=%0d csr_sys_pair=%0d precise_traps=%0d bad_traps=%0d early_side_effects=%0d ecall_retires=%0d rob_empty=%0b drain_cycles=%0d",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 mtvec_value,
                 mepc_value,
                 mcause_value,
                 mstatus_value,
                 csr_system_issue_count,
                 csr_system_pair_count,
                 precise_trap_count,
                 precise_trap_bad_count,
                 early_ecall_side_effect_count,
                 ecall_retire_count,
                 dut.u_dispatch_packet.u_rob_2w.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1, "packet backend ROB drained after trap smoke program");
        check_ok(a0_value == 32'h00000055, "packet backend trap returned from handler and executed post-ecall instruction");
        check_ok(a1_value == 32'h0000000b, "packet backend trap a1(x11) captured ECALL mcause 11");
        check_ok(mtvec_value == 32'h000007f0, "packet backend trap mtvec retains handler address 0x7f0");
        check_ok(mepc_value == 32'h0000000c, "packet backend trap handler advanced mepc to 0x0c");
        check_ok(mcause_value == 32'h0000000b, "packet backend trap mcause records machine ECALL");
        check_ok(mstatus_value == 32'h00000080, "packet backend trap mret set MPIE and restored disabled MIE");
        check_ok(csr_system_issue_count >= 1, "packet backend trap issued CSR/system operations");
        check_ok(csr_system_pair_count == 0, "packet backend trap kept CSR/system operations single-issue");
        check_ok(precise_trap_count == 1, "ECALL generated exactly one ROB-head trap");
        check_ok(precise_trap_bad_count == 0, "ROB-head trap preserved ECALL pc/cause/tval");
        check_ok(early_ecall_side_effect_count == 0, "ECALL did not update trap CSRs at execution");
        check_ok(ecall_retire_count == 0, "ECALL was not reported as a normally retired instruction");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_trap_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_trap_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
