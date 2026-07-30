`timescale 1ns/1ps

// Verifies software-managed nested machine interrupts. The outer external
// interrupt saves the single architectural trap context before reenabling
// MIE. A software interrupt then nests inside the handler. After the inner
// MRET, the outer handler restores its saved context and returns to main.
module tb_top_packet_backend_nested_interrupt_smoke;

    import defines_pkg::*;

    localparam logic [31:0] HANDLER_PC    = 32'h00000300;
    localparam logic [31:0] OUTER_WAIT_PC = 32'h0000031c;
    localparam logic [31:0] MAIN_LOOP_PC  = 32'h0000002c;

    logic clk;
    logic rst_n;
    logic software_irq;
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
    int wait_cycles;
    int outer_take_count;
    int inner_take_count;
    int mret_count;
    logic [31:0] outer_restart_pc;
    logic [31:0] inner_restart_pc;
    logic [31:0] inner_mret_target;
    logic [31:0] outer_mret_target;
    preg_t a0_preg;
    preg_t depth_preg;
    preg_t inner_done_preg;
    preg_t main_done_preg;
    preg_t saved_status_preg;
    preg_t saved_mepc_preg;
    preg_t saved_mcause_preg;
    preg_t inner_mcause_preg;
    preg_t inner_mepc_preg;

    top_packet_backend dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .software_irq      (software_irq),
        .timer_irq         (1'b0),
        .external_irq      (external_irq),
        .load_en           (load_en),
        .load_addr         (load_addr),
        .load_instr_byte   (load_instr_byte),
        .issue_valid       (issue_valid),
        .issue_fu_type     (issue_fu_type),
        .issue_pc          (issue_pc),
        .issue_imm         (issue_imm),
        .rob_head_valid    (rob_head_valid),
        .rob_head_complete (rob_head_complete),
        .rob_head_rd       (rob_head_rd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            outer_take_count <= 0;
            inner_take_count <= 0;
            mret_count <= 0;
            outer_restart_pc <= '0;
            inner_restart_pc <= '0;
            inner_mret_target <= '0;
            outer_mret_target <= '0;
        end else begin
            if (dut.interrupt_take) begin
                if (dut.interrupt_mcause == 32'h8000000b) begin
                    outer_take_count <= outer_take_count + 1;
                    outer_restart_pc <= dut.interrupt_mepc;
                end
                if (dut.interrupt_mcause == 32'h80000003) begin
                    inner_take_count <= inner_take_count + 1;
                    inner_restart_pc <= dut.interrupt_mepc;
                end
            end
            if (dut.u_execution.csr_mret_en) begin
                mret_count <= mret_count + 1;
                if (mret_count == 0) begin
                    inner_mret_target <=
                        dut.u_execution.csr_mepc_value;
                end else begin
                    outer_mret_target <=
                        dut.u_execution.csr_mepc_value;
                end
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
        input [7:0] data_byte;
    begin
        load_en = 1'b1;
        load_addr = byte_addr;
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
        software_irq = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;
        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Main enables machine external and software interrupts, then waits
        // for the outer handler to set x15 after the nested interrupt returns.
        write_word(32'h000, 32'h30000093); // addi  x1,x0,0x300
        write_word(32'h004, 32'h30509073); // csrw  mtvec,x1
        write_word(32'h008, 32'h00800113); // addi  x2,x0,8
        write_word(32'h00c, 32'h30011073); // csrw  mstatus,x2
        write_word(32'h010, 32'h00100193); // addi  x3,x0,1
        write_word(32'h014, 32'h00319193); // slli  x3,x3,3
        write_word(32'h018, 32'h00100213); // addi  x4,x0,1
        write_word(32'h01c, 32'h00b21213); // slli  x4,x4,11
        write_word(32'h020, 32'h0041e1b3); // or    x3,x3,x4
        write_word(32'h024, 32'h30419073); // csrw  mie,x3
        write_word(32'h028, 32'h02200513); // addi  x10,x0,0x22
        write_word(MAIN_LOOP_PC, 32'h00078063); // beq x15,x0,0
        write_word(32'h030, 32'h05500513); // addi  x10,x0,0x55
        write_word(32'h034, 32'h0000006f); // jal   x0,0

        // Common direct-mode handler. x13 distinguishes the first and second
        // entry. The outer path saves the trap CSRs before setting MIE.
        write_word(32'h300, 32'h00168693); // addi  x13,x13,1
        write_word(32'h304, 32'h00100913); // addi  x18,x0,1
        write_word(32'h308, 32'h05269063); // bne   x13,x18,+64
        write_word(32'h30c, 32'h300029f3); // csrr  x19,mstatus
        write_word(32'h310, 32'h34102a73); // csrr  x20,mepc
        write_word(32'h314, 32'h34202af3); // csrr  x21,mcause
        write_word(32'h318, 32'h30046073); // csrrsi x0,mstatus,8
        write_word(OUTER_WAIT_PC, 32'h00070063); // beq x14,x0,0
        write_word(32'h320, 32'h00100793); // addi  x15,x0,1
        write_word(32'h324, 32'h30099073); // csrw  mstatus,x19
        write_word(32'h328, 32'h341a1073); // csrw  mepc,x20
        write_word(32'h32c, 32'h342a9073); // csrw  mcause,x21
        write_word(32'h330, 32'h30200073); // mret

        // Inner software-interrupt path records the overwritten trap context,
        // marks completion, and returns to the outer handler wait loop.
        write_word(32'h348, 32'h34202b73); // csrr  x22,mcause
        write_word(32'h34c, 32'h34102bf3); // csrr  x23,mepc
        write_word(32'h350, 32'h00100713); // addi  x14,x0,1
        write_word(32'h354, 32'h30200073); // mret

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        // Wait for main to enable interrupts and enter its wait loop.
        for (wait_cycles = 0;
             wait_cycles < 1000 &&
             !((dut.u_execution.u_csr_file.mstatus_q[3] == 1'b1) &&
               (dut.u_execution.u_csr_file.mie_q[11] == 1'b1) &&
               dut.rob_head_valid_i &&
               !dut.rob_head_complete_i &&
               (dut.rob_head.datapath.pc == MAIN_LOOP_PC));
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end
        check_ok(wait_cycles < 1000,
                 "main enabled interrupts and reached its wait loop");

        external_irq = 1'b1;
        for (wait_cycles = 0;
             wait_cycles < 100 && (outer_take_count == 0);
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end
        external_irq = 1'b0;
        check_ok(outer_take_count == 1,
                 "outer machine external interrupt was accepted once");

        // Do not inject the inner interrupt until the outer handler has saved
        // its context and deliberately reenabled MIE at the wait loop.
        for (wait_cycles = 0;
             wait_cycles < 1000 &&
             !((dut.u_execution.u_csr_file.mstatus_q[3] == 1'b1) &&
               dut.rob_head_valid_i &&
               !dut.rob_head_complete_i &&
               (dut.rob_head.datapath.pc == OUTER_WAIT_PC));
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end
        check_ok(wait_cycles < 1000,
                 "outer handler saved context and reenabled MIE");

        software_irq = 1'b1;
        for (wait_cycles = 0;
             wait_cycles < 100 && (inner_take_count == 0);
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end
        software_irq = 1'b0;
        check_ok(inner_take_count == 1,
                 "inner machine software interrupt was accepted once");

        repeat (500) step_clk;

        a0_preg           = dut.u_rename_packet.u_rat_2w.rat[10];
        depth_preg        = dut.u_rename_packet.u_rat_2w.rat[13];
        inner_done_preg   = dut.u_rename_packet.u_rat_2w.rat[14];
        main_done_preg    = dut.u_rename_packet.u_rat_2w.rat[15];
        saved_status_preg = dut.u_rename_packet.u_rat_2w.rat[19];
        saved_mepc_preg   = dut.u_rename_packet.u_rat_2w.rat[20];
        saved_mcause_preg = dut.u_rename_packet.u_rat_2w.rat[21];
        inner_mcause_preg = dut.u_rename_packet.u_rat_2w.rat[22];
        inner_mepc_preg   = dut.u_rename_packet.u_rat_2w.rat[23];

        $display("[SUMMARY] outer_takes=%0d inner_takes=%0d mretes=%0d outer_mepc=0x%08h inner_mepc=0x%08h inner_mret=0x%08h outer_mret=0x%08h saved_mepc=0x%08h inner_saved_mepc=0x%08h depth=%0d inner_done=%0d main_done=%0d a0=0x%08h saved_status=0x%08h saved_mcause=0x%08h inner_mcause=0x%08h final_status=0x%08h final_mcause=0x%08h fetch_pc=0x%08h rob_count=%0d",
                 outer_take_count,
                 inner_take_count,
                 mret_count,
                 outer_restart_pc,
                 inner_restart_pc,
                 inner_mret_target,
                 outer_mret_target,
                 dut.u_prf_2w.regs[saved_mepc_preg],
                 dut.u_prf_2w.regs[inner_mepc_preg],
                 dut.u_prf_2w.regs[depth_preg],
                 dut.u_prf_2w.regs[inner_done_preg],
                 dut.u_prf_2w.regs[main_done_preg],
                 dut.u_prf_2w.regs[a0_preg],
                 dut.u_prf_2w.regs[saved_status_preg],
                 dut.u_prf_2w.regs[saved_mcause_preg],
                 dut.u_prf_2w.regs[inner_mcause_preg],
                 dut.u_execution.u_csr_file.mstatus_q,
                 dut.u_execution.u_csr_file.mcause_q,
                 dut.u_fetch.fetch_pc,
                 dut.u_dispatch_packet.u_rob_2w.count_q);

        check_ok(dut.u_prf_2w.regs[depth_preg] == 32'd2,
                 "common handler observed exactly two nested entries");
        check_ok(dut.u_prf_2w.regs[saved_status_preg] == 32'h00001880,
                 "outer handler saved trap-entry MIE/MPIE/MPP state");
        check_ok(dut.u_prf_2w.regs[saved_mcause_preg] == 32'h8000000b,
                 "outer handler saved the external interrupt cause");
        check_ok(dut.u_prf_2w.regs[inner_mcause_preg] == 32'h80000003,
                 "inner handler observed the software interrupt cause");
        check_ok(dut.u_prf_2w.regs[inner_mepc_preg] == OUTER_WAIT_PC,
                 "inner MRET returned to the interrupted outer handler");
        check_ok(inner_restart_pc == OUTER_WAIT_PC,
                 "inner interrupt captured the outer wait-loop restart PC");
        check_ok(dut.u_prf_2w.regs[inner_done_preg] == 32'd1,
                 "inner handler completion survived its MRET");
        check_ok(dut.u_prf_2w.regs[main_done_preg] == 32'd1,
                 "outer handler signaled main after the inner return");
        check_ok(dut.u_prf_2w.regs[a0_preg] == 32'h00000055,
                 "outer MRET resumed main and completed post-interrupt work");
        check_ok(dut.u_execution.u_csr_file.mepc_q ==
                 dut.u_prf_2w.regs[saved_mepc_preg],
                 "outer handler restored its saved mepc");
        check_ok(dut.u_execution.u_csr_file.mcause_q == 32'h8000000b,
                 "outer handler restored its saved mcause");
        check_ok(dut.u_execution.u_csr_file.mstatus_q == 32'h00000088,
                 "outer MRET restored MIE and cleared MPP");
        check_ok(dut.u_execution.u_csr_file.current_priv_q == PRV_M,
                 "nested returns restored machine privilege");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_nested_interrupt_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_nested_interrupt_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
