`timescale 1ns/1ps

// Consolidated sixteen-entry PMP test. Directed matcher checks cover static
// priority and every address mode; reset-separated end-to-end phases verify
// precise U-mode faults, high-entry CSR access, and architectural locking.
module tb_top_packet_backend_pmp_smoke;

    import defines_pkg::*;

    localparam logic [31:0] MRET_INSTR = 32'h30200073;
    localparam logic [31:0] USER_PC = 32'h00000040;
    localparam logic [31:0] HANDLER_PC = 32'h00000200;
    localparam logic [31:0] DATA_ADDR = 32'h00010000;

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
    int run_cycles;
    int drain_cycles;
    logic [31:0] expected_pc;
    logic [31:0] expected_cause;
    logic [31:0] expected_tval;
    logic [1:0] expected_privilege;
    logic [PMP_ENTRY_COUNT*8-1:0] matcher_cfg;
    logic [PMP_ENTRY_COUNT*WIDTH-1:0] matcher_addr;

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

    function automatic [31:0] enc_lui(
        input logic [4:0] rd,
        input logic [19:0] imm20
    );
    begin
        enc_lui = {imm20, rd, 7'b0110111};
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

    function automatic [31:0] enc_sw(
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input integer imm
    );
        logic [11:0] imm12;
    begin
        imm12 = imm[11:0];
        enc_sw = {
            imm12[11:5], rs2, rs1, 3'b010, imm12[4:0], 7'b0100011
        };
    end
    endfunction

    function automatic [31:0] arch_reg(input integer index);
        preg_t preg;
    begin
        preg = dut.u_rename_packet.u_rat_2w.rat[index];
        arch_reg = dut.u_prf_2w.regs[preg];
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

    task automatic reset_core;
    begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        step_clk;
        step_clk;
        rst_n = 1'b1;
        step_clk;
        trap_count = 0;
        bad_trap_count = 0;
    end
    endtask

    task automatic run_matcher_checks;
    begin
        matcher_cfg = '0;
        matcher_addr = '0;
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h0, 3'd3,
                1'b1, 1'b0, 1'b0),
            "all-OFF PMP entries deny unmatched U-mode access");
        check_ok(
            pmp_access_allowed(
                PRV_M, matcher_cfg, matcher_addr, 32'h0, 3'd3,
                1'b1, 1'b0, 1'b0),
            "all-OFF PMP entries preserve unmatched M-mode access");

        // Entry 0: [0, 0x1000) RX. Entry 1: [0x1000, 0x2000) RW.
        matcher_cfg[7:0] = 8'h0d;
        matcher_cfg[15:8] = 8'h0b;
        matcher_addr[WIDTH-1:0] = 32'h00000400;
        matcher_addr[2*WIDTH-1:WIDTH] = 32'h00000800;
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00000080, 3'd3,
                1'b0, 1'b0, 1'b1),
            "multi-entry TOR permits execute in the code region");
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00000080, 3'd3,
                1'b0, 1'b1, 1'b0),
            "multi-entry TOR denies writes to the code region");
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001000, 3'd3,
                1'b1, 1'b0, 1'b0),
            "multi-entry TOR permits reads from the data region");
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001000, 3'd3,
                1'b0, 1'b0, 1'b1),
            "multi-entry TOR denies execute in the data region");

        matcher_cfg = '0;
        matcher_addr = '0;
        matcher_cfg[7:0] = 8'h11;
        matcher_addr[WIDTH-1:0] = 32'h00000400;
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001000, 3'd3,
                1'b1, 1'b0, 1'b0),
            "NA4 matches its exact four-byte region");
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00000ffc, 3'd7,
                1'b1, 1'b0, 1'b0),
            "NA4 rejects an access that only partially overlaps");

        // NAPOT encoding 0x400 describes [0x1000,0x1008), while 0x401
        // describes [0x1000,0x1010).
        matcher_cfg = '0;
        matcher_addr = '0;
        matcher_cfg[7:0] = 8'h19;
        matcher_addr[WIDTH-1:0] = 32'h00000400;
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001004, 3'd3,
                1'b1, 1'b0, 1'b0),
            "8-byte NAPOT region includes its upper word");
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001008, 3'd3,
                1'b1, 1'b0, 1'b0),
            "8-byte NAPOT region excludes the next word");
        matcher_cfg[7] = 1'b1;
        check_ok(
            !pmp_access_allowed(
                PRV_M, matcher_cfg, matcher_addr, 32'h00001000, 3'd3,
                1'b0, 1'b1, 1'b0),
            "locked NAPOT permissions are enforced in M-mode");
        matcher_cfg[7] = 1'b0;
        matcher_addr[WIDTH-1:0] = 32'h00000401;
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h0000100c, 3'd3,
                1'b1, 1'b0, 1'b0),
            "16-byte NAPOT region decodes trailing address ones");

        // Entry 0 partially overlaps the access. Entry 1 covers it using an
        // 8 KiB NAPOT region, but static priority must still reject it.
        matcher_cfg = '0;
        matcher_addr = '0;
        matcher_cfg[7:0] = 8'h11;
        matcher_cfg[15:8] = 8'h1f;
        matcher_addr[WIDTH-1:0] = 32'h00000400;
        matcher_addr[2*WIDTH-1:WIDTH] = 32'h000003ff;
        check_ok(
            !pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00000ffc, 3'd7,
                1'b1, 1'b0, 1'b0),
            "lowest-numbered partial match blocks lower-priority coverage");
        check_ok(
            !pmp_access_allowed(
                PRV_M, matcher_cfg, matcher_addr, 32'h00000ffc, 3'd7,
                1'b1, 1'b0, 1'b0),
            "partial match also faults unlocked M-mode access");

        matcher_cfg = '0;
        matcher_addr = '0;
        matcher_cfg[(PMP_ENTRY_COUNT-1)*8 +: 8] = 8'h19;
        matcher_addr[(PMP_ENTRY_COUNT-1)*WIDTH +: WIDTH] = 32'h00000400;
        check_ok(
            pmp_access_allowed(
                PRV_U, matcher_cfg, matcher_addr, 32'h00001000, 3'd3,
                1'b1, 1'b0, 1'b0),
            "entry15 participates in priority matching");
    end
    endtask

    task automatic load_bootstrap(input logic [7:0] cfg);
    begin
        // Configure a full-address-space TOR entry and then restrict only its
        // permissions. The handler remains executable because unlocked PMP
        // entries do not constrain M-mode.
        write_word(32'h00000000, enc_addi(5'd1, 5'd0, HANDLER_PC));
        write_word(32'h00000004, enc_csr(CSR_MTVEC, 3'b001, 5'd0, 5'd1));
        write_word(32'h00000008, enc_lui(5'd3, 20'h40000));
        write_word(32'h0000000c, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000010, enc_addi(5'd4, 5'd0, cfg));
        write_word(32'h00000014, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd4));
        write_word(32'h00000018, enc_addi(5'd2, 5'd0, USER_PC));
        write_word(32'h0000001c, enc_csr(CSR_MEPC, 3'b001, 5'd0, 5'd2));
        write_word(32'h00000020, MRET_INSTR);

        write_word(HANDLER_PC + 0, enc_csr(CSR_MCAUSE, 3'b010, 5'd11, 5'd0));
        write_word(HANDLER_PC + 4, enc_csr(CSR_MTVAL, 3'b010, 5'd12, 5'd0));
        write_word(HANDLER_PC + 8, enc_addi(5'd10, 5'd0, 16'h05a));
    end
    endtask

    task automatic run_fault_case(
        input string case_name,
        input logic [7:0] cfg,
        input logic [31:0] user_instr0,
        input logic [31:0] user_instr1,
        input logic [31:0] fault_pc,
        input logic [31:0] fault_cause,
        input logic [31:0] fault_tval
    );
    begin
        reset_core;
        expected_pc = fault_pc;
        expected_cause = fault_cause;
        expected_tval = fault_tval;
        expected_privilege = PRV_U;

        load_bootstrap(cfg);
        write_word(USER_PC + 0, user_instr0);
        write_word(USER_PC + 4, user_instr1);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        for (run_cycles = 0;
             run_cycles < 600 &&
             !((trap_count == 1) && (arch_reg(10) == 32'h0000005a));
             run_cycles = run_cycles + 1) begin
            step_clk;
        end

        load_en = 1'b1;
        for (drain_cycles = 0;
             drain_cycles < 300 &&
             dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        $display("[SUMMARY:%s] traps=%0d bad=%0d priv=%0d cfg=0x%02h addr=0x%08h mcause=0x%08h mtval=0x%08h a0=0x%08h",
                 case_name,
                 trap_count,
                 bad_trap_count,
                 dut.u_execution.u_csr_file.current_priv_q,
                 dut.u_execution.u_csr_file.pmpcfg0_q[7:0],
                 dut.u_execution.u_csr_file.pmpaddr0_q,
                 dut.u_execution.u_csr_file.mcause_q,
                 dut.u_execution.u_csr_file.mtval_q,
                 arch_reg(10));
        check_ok(trap_count == 1,
                 {case_name, " produced exactly one precise trap"});
        check_ok(bad_trap_count == 0,
                 {case_name, " recorded the expected PC/cause/tval"});
        check_ok(arch_reg(11) == fault_cause,
                 {case_name, " handler read expected mcause"});
        check_ok(arch_reg(12) == fault_tval,
                 {case_name, " handler read expected mtval"});
        check_ok(dut.u_execution.u_csr_file.current_priv_q == PRV_M,
                 {case_name, " trap entered M-mode"});
        check_ok(dut.u_execution.u_csr_file.pmpaddr0_q == 32'h40000000,
                 {case_name, " retained programmed TOR top"});
    end
    endtask

    task automatic run_mprv_case;
    begin
        reset_core;
        expected_pc = 32'h0000002c;
        expected_cause = MCAUSE_LOAD_ACCESS_FAULT;
        expected_tval = DATA_ADDR;
        expected_privilege = PRV_M;

        // An unlocked no-permission TOR entry is bypassed by ordinary M-mode
        // accesses. Setting MPRV with MPP=U makes only the later data access
        // use U-mode PMP permissions; M-mode instruction fetch must continue.
        write_word(32'h00000000, enc_addi(5'd1, 5'd0, HANDLER_PC));
        write_word(32'h00000004, enc_csr(CSR_MTVEC, 3'b001, 5'd0, 5'd1));
        write_word(32'h00000008, enc_lui(5'd3, 20'h40000));
        write_word(32'h0000000c, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000010, enc_addi(5'd4, 5'd0, 8'h08));
        write_word(32'h00000014, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd4));
        write_word(32'h00000018, enc_lui(5'd8, 20'h00010));
        write_word(32'h0000001c, enc_lw(5'd5, 5'd8, 0));
        write_word(32'h00000020, enc_addi(5'd10, 5'd0, 16'h031));
        write_word(32'h00000024, enc_lui(5'd4, 20'h00020));
        write_word(32'h00000028, enc_csr(CSR_MSTATUS, 3'b001, 5'd0, 5'd4));
        write_word(32'h0000002c, enc_lw(5'd6, 5'd8, 0));
        write_word(32'h00000030, enc_addi(5'd10, 5'd0, 16'h07f));

        write_word(HANDLER_PC + 0,
                   enc_csr(CSR_MCAUSE, 3'b010, 5'd11, 5'd0));
        write_word(HANDLER_PC + 4,
                   enc_csr(CSR_MTVAL, 3'b010, 5'd12, 5'd0));
        write_word(HANDLER_PC + 8,
                   enc_csr(CSR_MSTATUS, 3'b010, 5'd14, 5'd0));
        write_word(HANDLER_PC + 12, enc_addi(5'd13, 5'd0, 16'h05d));

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        for (run_cycles = 0;
             run_cycles < 700 &&
             !((trap_count == 1) && (arch_reg(13) == 32'h0000005d));
             run_cycles = run_cycles + 1) begin
            step_clk;
        end

        load_en = 1'b1;
        for (drain_cycles = 0;
             drain_cycles < 300 &&
             dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        $display("[SUMMARY:mprv] traps=%0d bad=%0d priv=%0d mstatus=0x%08h mcause=0x%08h mtval=0x%08h a0=0x%08h marker=0x%08h",
                 trap_count,
                 bad_trap_count,
                 dut.u_execution.u_csr_file.current_priv_q,
                 dut.u_execution.u_csr_file.mstatus_q,
                 dut.u_execution.u_csr_file.mcause_q,
                 dut.u_execution.u_csr_file.mtval_q,
                 arch_reg(10),
                 arch_reg(13));
        check_ok(trap_count == 1,
                 "MPRV produced exactly one precise load access fault");
        check_ok(bad_trap_count == 0,
                 "MPRV fault recorded the expected M-mode PC/cause/tval");
        check_ok(arch_reg(10) == 32'h00000031,
                 "ordinary M-mode load bypassed the unlocked PMP entry");
        check_ok(arch_reg(11) == MCAUSE_LOAD_ACCESS_FAULT,
                 "MPRV handler read load-access-fault mcause");
        check_ok(arch_reg(12) == DATA_ADDR,
                 "MPRV handler read the denied data address");
        check_ok(arch_reg(13) == 32'h0000005d,
                 "M-mode handler fetch remained unaffected by MPRV");
        check_ok((arch_reg(14) & 32'h00020000) != 32'b0,
                 "trap handler observed MPRV retained in mstatus");
        check_ok(dut.u_execution.u_csr_file.current_priv_q == PRV_M,
                 "MPRV data fault entered and remained in M-mode");
    end
    endtask

    task automatic run_lock_case;
    begin
        reset_core;
        expected_pc = '0;
        expected_cause = '0;
        expected_tval = '0;

        write_word(32'h00000000, enc_lui(5'd3, 20'h40000));
        write_word(32'h00000004, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000008, enc_addi(5'd4, 5'd0, 8'h8f));
        write_word(32'h0000000c, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd4));
        write_word(32'h00000010, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd0));
        write_word(32'h00000014, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd0));
        write_word(32'h00000018, enc_addi(5'd2, 5'd0, USER_PC));
        write_word(32'h0000001c, enc_csr(CSR_MEPC, 3'b001, 5'd0, 5'd2));
        write_word(32'h00000020, MRET_INSTR);
        write_word(USER_PC, enc_addi(5'd10, 5'd0, 16'h06b));

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        for (run_cycles = 0;
             run_cycles < 600 && (arch_reg(10) != 32'h0000006b);
             run_cycles = run_cycles + 1) begin
            step_clk;
        end

        load_en = 1'b1;
        for (drain_cycles = 0;
             drain_cycles < 300 &&
             dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        $display("[SUMMARY:lock] traps=%0d priv=%0d cfg=0x%02h addr=0x%08h a0=0x%08h",
                 trap_count,
                 dut.u_execution.u_csr_file.current_priv_q,
                 dut.u_execution.u_csr_file.pmpcfg0_q[7:0],
                 dut.u_execution.u_csr_file.pmpaddr0_q,
                 arch_reg(10));
        check_ok(trap_count == 0, "locked permissive entry caused no trap");
        check_ok(dut.u_execution.u_csr_file.pmpcfg0_q[7:0] == 8'h8f,
                 "PMP lock blocked a later pmpcfg0 write");
        check_ok(dut.u_execution.u_csr_file.pmpaddr0_q == 32'h40000000,
                 "PMP lock blocked a later pmpaddr0 write");
        check_ok(arch_reg(10) == 32'h0000006b,
                 "locked RWX TOR entry allowed U-mode execution");
        check_ok(dut.u_execution.u_csr_file.current_priv_q == PRV_U,
                 "lock test remained in U-mode");
    end
    endtask

    task automatic run_tor_predecessor_lock_case;
    begin
        reset_core;
        expected_pc = '0;
        expected_cause = '0;
        expected_tval = '0;

        write_word(32'h00000000, enc_addi(5'd3, 5'd0, 16'h100));
        write_word(32'h00000004, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000008, enc_addi(5'd3, 5'd0, 16'h200));
        write_word(32'h0000000c, enc_csr(CSR_PMPADDR1, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000010, enc_lui(5'd4, 20'h00009));
        write_word(32'h00000014, enc_addi(5'd4, 5'd4, -256));
        write_word(32'h00000018, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd4));
        write_word(32'h0000001c, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd0));
        write_word(32'h00000020, enc_csr(CSR_PMPADDR1, 3'b001, 5'd0, 5'd0));
        write_word(32'h00000024, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd0));
        write_word(32'h00000028, enc_addi(5'd10, 5'd0, 16'h07c));

        load_en = 1'b0;
        for (run_cycles = 0;
             run_cycles < 400 && (arch_reg(10) != 32'h0000007c);
             run_cycles = run_cycles + 1) begin
            step_clk;
        end
        load_en = 1'b1;

        check_ok(trap_count == 0,
                 "locked TOR predecessor case caused no trap");
        check_ok(dut.u_execution.u_csr_file.pmpcfg_q[0][15:8] == 8'h8f,
                 "entry1 lock blocked a later configuration write");
        check_ok(dut.u_execution.u_csr_file.pmpaddr_q[0] == 32'h00000100,
                 "locked TOR entry blocked its predecessor pmpaddr write");
        check_ok(dut.u_execution.u_csr_file.pmpaddr_q[1] == 32'h00000200,
                 "entry1 lock blocked its own pmpaddr write");
    end
    endtask

    task automatic run_entry15_case;
    begin
        reset_core;
        expected_pc = '0;
        expected_cause = '0;
        expected_tval = '0;

        write_word(32'h00000000, enc_lui(5'd3, 20'h00004));
        write_word(32'h00000004, enc_csr(CSR_PMPADDR0, 3'b001, 5'd0, 5'd3));
        write_word(32'h00000008, enc_csr(CSR_PMPADDR15, 3'b001, 5'd0, 5'd3));
        write_word(32'h0000000c, enc_addi(5'd4, 5'd0, 8'h0d));
        write_word(32'h00000010, enc_csr(CSR_PMPCFG0, 3'b001, 5'd0, 5'd4));
        write_word(32'h00000014, enc_lui(5'd4, 20'h19000));
        write_word(32'h00000018, enc_csr(CSR_PMPCFG3, 3'b001, 5'd0, 5'd4));
        write_word(32'h0000001c, enc_addi(5'd2, 5'd0, USER_PC));
        write_word(32'h00000020, enc_csr(CSR_MEPC, 3'b001, 5'd0, 5'd2));
        write_word(32'h00000024, MRET_INSTR);
        write_word(USER_PC + 0, enc_lui(5'd8, 20'h00010));
        write_word(USER_PC + 4, enc_lw(5'd9, 5'd8, 0));
        write_word(USER_PC + 8, enc_addi(5'd10, 5'd0, 16'h077));

        load_en = 1'b0;
        for (run_cycles = 0;
             run_cycles < 600 &&
             (arch_reg(10) != 32'h00000077) &&
             (trap_count == 0);
             run_cycles = run_cycles + 1) begin
            step_clk;
        end
        load_en = 1'b1;

        check_ok(trap_count == 0,
                 "entry15 NAPOT data permission caused no U-mode trap");
        check_ok(arch_reg(10) == 32'h00000077,
                 "U-mode load completed through entry15");
        check_ok(dut.u_execution.u_csr_file.pmpcfg_q[3][31:24] == 8'h19,
                 "pmpcfg3 retained entry15 NAPOT permissions");
        check_ok(dut.u_execution.u_csr_file.pmpaddr_q[15] == 32'h00004000,
                 "pmpaddr15 retained the programmed NAPOT address");
    end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trap_count <= 0;
            bad_trap_count <= 0;
        end else if (dut.trap_commit) begin
            if ((dut.rob_head.datapath.pc != expected_pc) ||
                (dut.rob_head.datapath.exception_cause != expected_cause) ||
                (dut.rob_head.datapath.exception_tval != expected_tval) ||
                (dut.u_execution.u_csr_file.current_priv_q !=
                 expected_privilege)) begin
                bad_trap_count <= bad_trap_count + 1;
            end
            trap_count <= trap_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;
        expected_pc = '0;
        expected_cause = '0;
        expected_tval = '0;
        expected_privilege = PRV_U;

        run_matcher_checks;

        // X-only permits the first U instruction but denies its LW.
        run_fault_case(
            "load",
            8'h0c,
            enc_lui(5'd8, 20'h00010),
            enc_lw(5'd9, 5'd8, 0),
            USER_PC + 4,
            MCAUSE_LOAD_ACCESS_FAULT,
            DATA_ADDR
        );

        // R+X permits fetch but denies the SW write.
        run_fault_case(
            "store",
            8'h0d,
            enc_lui(5'd8, 20'h00010),
            enc_sw(5'd0, 5'd8, 0),
            USER_PC + 4,
            MCAUSE_STORE_ACCESS_FAULT,
            DATA_ADDR
        );

        // R+W removes execute permission, so the first U fetch itself faults.
        run_fault_case(
            "instruction",
            8'h0b,
            enc_addi(5'd9, 5'd0, 1),
            enc_addi(5'd9, 5'd9, 1),
            USER_PC,
            MCAUSE_INSTR_ACCESS_FAULT,
            USER_PC
        );

        run_lock_case;
        run_tor_predecessor_lock_case;
        run_entry15_case;
        run_mprv_case;

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_pmp_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_pmp_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
