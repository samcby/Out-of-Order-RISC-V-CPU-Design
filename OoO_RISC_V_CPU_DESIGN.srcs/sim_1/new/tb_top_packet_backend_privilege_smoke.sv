`timescale 1ns/1ps

// End-to-end U/M privilege test. Machine mode enters user mode with MRET,
// handles two user illegal-instruction traps and one user ECALL, and returns
// to the interrupted user instruction stream after every trap.
module tb_top_packet_backend_privilege_smoke;

    import defines_pkg::*;

    localparam logic [31:0] USER_CSR_INSTR =
        {12'h300, 5'd0, 3'b010, 5'd5, 7'b1110011};
    localparam logic [31:0] MRET_INSTR = 32'h30200073;

    logic clk;
    logic rst_n;
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
    int trap_count;
    int bad_trap_count;
    int handler_issue_count;
    int run_cycles;
    int drain_cycles;

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

    function automatic [31:0] enc_csr(
        input logic [11:0] csr,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [4:0] rs1
    );
    begin
        enc_csr = {csr, rs1, funct3, rd, 7'b1110011};
    end
    endfunction

    function automatic [31:0] enc_beq(
        input logic [4:0] rs1,
        input logic [4:0] rs2,
        input integer imm
    );
        logic [12:0] imm13;
    begin
        imm13 = imm[12:0];
        enc_beq = {
            imm13[12],
            imm13[10:5],
            rs2,
            rs1,
            3'b000,
            imm13[4:1],
            imm13[11],
            7'b1100011
        };
    end
    endfunction

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic write_byte(
        input logic [31:0] byte_addr,
        input logic [7:0] data_byte
    );
    begin
        load_en = 1'b1;
        load_addr = byte_addr;
        load_instr_byte = data_byte;
        step_clk;
    end
    endtask

    task automatic write_word(
        input logic [31:0] byte_addr,
        input logic [31:0] data_word
    );
    begin
        write_byte(byte_addr + 0, data_word[7:0]);
        write_byte(byte_addr + 1, data_word[15:8]);
        write_byte(byte_addr + 2, data_word[23:16]);
        write_byte(byte_addr + 3, data_word[31:24]);
    end
    endtask

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (cond) begin
            $display("[PASS] %s", msg);
        end else begin
            $display("[FAIL] %s", msg);
            fail_count = fail_count + 1;
        end
    end
    endtask

    function automatic [31:0] arch_reg(input integer index);
        preg_t preg;
    begin
        preg = dut.u_rename_packet.u_rat_2w.rat[index];
        arch_reg = dut.u_prf_2w.regs[preg];
    end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trap_count <= 0;
            bad_trap_count <= 0;
            handler_issue_count <= 0;
        end else begin
            if (dut.trap_commit) begin
                case (trap_count)
                    0: begin
                        if ((dut.rob_head.datapath.pc != 32'h00000044) ||
                            (dut.rob_head.datapath.exception_cause !=
                             MCAUSE_ILLEGAL) ||
                            (dut.rob_head.datapath.exception_tval !=
                             USER_CSR_INSTR)) begin
                            bad_trap_count <= bad_trap_count + 1;
                        end
                    end
                    1: begin
                        if ((dut.rob_head.datapath.pc != 32'h0000004c) ||
                            (dut.rob_head.datapath.exception_cause !=
                             MCAUSE_ILLEGAL) ||
                            (dut.rob_head.datapath.exception_tval !=
                             MRET_INSTR)) begin
                            bad_trap_count <= bad_trap_count + 1;
                        end
                    end
                    2: begin
                        if ((dut.rob_head.datapath.pc != 32'h00000054) ||
                            (dut.rob_head.datapath.exception_cause !=
                             MCAUSE_ECALL_U) ||
                            (dut.rob_head.datapath.exception_tval != 32'b0)) begin
                            bad_trap_count <= bad_trap_count + 1;
                        end
                    end
                    default: bad_trap_count <= bad_trap_count + 1;
                endcase

                if (dut.u_execution.u_csr_file.current_priv_q != PRV_U) begin
                    bad_trap_count <= bad_trap_count + 1;
                end
                trap_count <= trap_count + 1;
            end

            if (dut.issue_if.valid && dut.issue_if.ready &&
                (dut.issue_if.data.datapath.pc >= 32'h00000200) &&
                (dut.issue_if.data.datapath.pc <= 32'h00000238) &&
                (dut.u_execution.u_csr_file.current_priv_q == PRV_M)) begin
                handler_issue_count <= handler_issue_count + 1;
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

        // Machine bootstrap: install mtvec, set user entry in mepc, then MRET.
        write_word(32'h00000000, enc_addi(5'd1, 5'd0, 16'h200));
        write_word(32'h00000004, enc_csr(12'h305, 3'b001, 5'd0, 5'd1));
        write_word(32'h00000008, enc_addi(5'd2, 5'd0, 16'h040));
        write_word(32'h0000000c, enc_csr(12'h341, 3'b001, 5'd0, 5'd2));
        write_word(32'h00000010, MRET_INSTR);

        // User program:
        //   1. Read mstatus (illegal in U).
        //   2. Execute MRET (illegal in U).
        //   3. Execute ECALL (user environment call, cause 8).
        // The handler advances mepc after each trap and returns to U mode.
        write_word(32'h00000040, enc_addi(5'd10, 5'd0, 16'h011));
        write_word(32'h00000044, USER_CSR_INSTR);
        write_word(32'h00000048, enc_addi(5'd10, 5'd10, 1));
        write_word(32'h0000004c, MRET_INSTR);
        write_word(32'h00000050, enc_addi(5'd10, 5'd10, 1));
        write_word(32'h00000054, 32'h00000073);
        write_word(32'h00000058, enc_addi(5'd10, 5'd10, 1));

        // Machine trap handler. Illegal traps update x12/x13/x14; user ECALL
        // updates x11. Both paths advance mepc and execute MRET.
        write_word(32'h00000200, enc_csr(12'h342, 3'b010, 5'd5, 5'd0));
        write_word(32'h00000204, enc_addi(5'd6, 5'd0, 2));
        write_word(32'h00000208, enc_beq(5'd5, 5'd6, 24));
        write_word(32'h0000020c, enc_addi(5'd11, 5'd5, 0));
        write_word(32'h00000210, enc_csr(12'h341, 3'b010, 5'd7, 5'd0));
        write_word(32'h00000214, enc_addi(5'd7, 5'd7, 4));
        write_word(32'h00000218, enc_csr(12'h341, 3'b001, 5'd0, 5'd7));
        write_word(32'h0000021c, MRET_INSTR);
        write_word(32'h00000220, enc_addi(5'd12, 5'd5, 0));
        write_word(32'h00000224, enc_csr(12'h343, 3'b010, 5'd13, 5'd0));
        write_word(32'h00000228, enc_addi(5'd14, 5'd14, 1));
        write_word(32'h0000022c, enc_csr(12'h341, 3'b010, 5'd7, 5'd0));
        write_word(32'h00000230, enc_addi(5'd7, 5'd7, 4));
        write_word(32'h00000234, enc_csr(12'h341, 3'b001, 5'd0, 5'd7));
        write_word(32'h00000238, MRET_INSTR);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        for (run_cycles = 0;
             run_cycles < 500 &&
             !((trap_count == 3) &&
               (arch_reg(10) == 32'h00000014) &&
               (dut.u_execution.u_csr_file.current_priv_q == PRV_U));
             run_cycles = run_cycles + 1) begin
            step_clk;
        end

        // Stop producing new fetch packets as soon as the architectural goal
        // is reached, then let already accepted work drain naturally.
        load_en = 1'b1;
        for (drain_cycles = 0;
             drain_cycles < 500 &&
             dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        $display("[SUMMARY] traps=%0d bad_traps=%0d handler_issue=%0d priv=%0d mstatus=0x%08h mepc=0x%08h mcause=0x%08h a0=0x%08h a1=0x%08h a2=0x%08h a3=0x%08h a4=0x%08h rob_empty=%0b",
                 trap_count,
                 bad_trap_count,
                 handler_issue_count,
                 dut.u_execution.u_csr_file.current_priv_q,
                 dut.u_execution.u_csr_file.mstatus_q,
                 dut.u_execution.u_csr_file.mepc_q,
                 dut.u_execution.u_csr_file.mcause_q,
                 arch_reg(10),
                 arch_reg(11),
                 arch_reg(12),
                 arch_reg(13),
                 arch_reg(14),
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(trap_count == 3,
                 "user program generated two illegal traps and one ECALL");
        check_ok(bad_trap_count == 0,
                 "all user traps preserved the expected pc/cause/tval");
        check_ok(handler_issue_count > 0,
                 "trap handler executed in machine mode");
        check_ok(dut.u_execution.u_csr_file.current_priv_q == PRV_U,
                 "MRET returned to user mode after every trap");
        check_ok(dut.u_execution.u_csr_file.mstatus_q[12:11] == PRV_U,
                 "MRET cleared mstatus.MPP to user mode");
        check_ok(arch_reg(10) == 32'h00000014,
                 "user instruction stream resumed after all three traps");
        check_ok(arch_reg(11) == MCAUSE_ECALL_U,
                 "user ECALL reported cause 8");
        check_ok(arch_reg(12) == MCAUSE_ILLEGAL,
                 "user privileged operations reported illegal instruction");
        check_ok(arch_reg(13) == MRET_INSTR,
                 "mtval captured the latest illegal privileged instruction");
        check_ok(arch_reg(14) == 32'd2,
                 "handler observed both user illegal-instruction traps");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "privilege smoke program drained the ROB");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_privilege_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_privilege_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
