`timescale 1ns/1ps

// Verifies level-sensitive machine interrupt pending behavior and WFI.
//
// A held external interrupt must be taken again after the first handler
// executes MRET. The same source must also wake WFI when mie.MEIE is set but
// mstatus.MIE is clear, without entering the trap handler.
module tb_top_packet_backend_wfi_level_irq_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
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
    int interrupt_take_count;
    int sleep_entry_count;
    int timeout_cycles;
    logic previous_sleep;
    logic [31:0] commit_count_at_sleep;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t a2_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] a2_value;

    top_packet_backend dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .software_irq     (1'b0),
        .timer_irq        (1'b0),
        .external_irq     (external_irq),
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
            interrupt_take_count <= 0;
            sleep_entry_count    <= 0;
            previous_sleep       <= 1'b0;
        end else begin
            if (dut.interrupt_take) begin
                interrupt_take_count <= interrupt_take_count + 1;
                $display("[IRQ_TAKE] t=%0t count=%0d mepc=0x%08h mstatus=0x%08h priv=%0d pending=%0b",
                         $time,
                         interrupt_take_count + 1,
                         dut.interrupt_mepc,
                         dut.csr_mstatus_value,
                         dut.csr_privilege_mode,
                         dut.external_irq_pending_q);
            end
            if (dut.wfi_sleep_q && !previous_sleep) begin
                sleep_entry_count <= sleep_entry_count + 1;
            end
            previous_sleep <= dut.wfi_sleep_q;
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
        rst_n           = 1'b0;
        external_irq    = 1'b0;
        load_en         = 1'b1;
        load_addr       = '0;
        load_instr_byte = '0;
        fail_count      = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Main:
        //   mtvec = 0x300; mie.MEIE = 1; mstatus.MIE = 1
        //   WFI
        //   a0++
        //   mstatus.MIE = 0
        //   WFI
        //   a2++
        //   WFI
        write_word(32'd0,  32'h30000093); // addi  x1,x0,0x300
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00100113); // addi  x2,x0,1
        write_word(32'd12, 32'h00b11113); // slli  x2,x2,11
        write_word(32'd16, 32'h30411073); // csrrw x0,mie,x2
        write_word(32'd20, 32'h00800193); // addi  x3,x0,8
        write_word(32'd24, 32'h30019073); // csrrw x0,mstatus,x3
        write_word(32'd28, 32'h10500073); // wfi
        write_word(32'd32, 32'h00150513); // addi  x10,x10,1
        write_word(32'd36, 32'h30001073); // csrrw x0,mstatus,x0
        write_word(32'd40, 32'h10500073); // wfi
        write_word(32'd44, 32'h00160613); // addi  x12,x12,1
        write_word(32'd48, 32'h10500073); // wfi
        write_word(32'd52, 32'h0000006f); // jal   x0,0

        // Handler counts entries. Keeping external_irq asserted across the
        // first MRET must cause a second machine external interrupt.
        write_word(32'h00000300, 32'h00158593); // addi x11,x11,1
        write_word(32'h00000304, 32'h30200073); // mret

        load_en         = 1'b0;
        load_addr       = '0;
        load_instr_byte = '0;

        for (timeout_cycles = 0;
             timeout_cycles < 600 && !dut.wfi_sleep_q;
             timeout_cycles = timeout_cycles + 1) begin
            step_clk;
        end
        check_ok(dut.wfi_sleep_q, "first WFI enters the sleep state");

        commit_count_at_sleep = dut.perf_commit_count_q;
        repeat (20) step_clk;
        check_ok(dut.wfi_sleep_q, "WFI remains asleep without a wake source");
        check_ok(dut.perf_commit_count_q == commit_count_at_sleep,
                 "no instruction retires while WFI is asleep");

        external_irq = 1'b1;
        for (timeout_cycles = 0;
             timeout_cycles < 1000 && interrupt_take_count < 2;
             timeout_cycles = timeout_cycles + 1) begin
            step_clk;
        end
        check_ok(interrupt_take_count == 2,
                 "held external interrupt retriggers after MRET");
        external_irq = 1'b0;

        for (timeout_cycles = 0;
             timeout_cycles < 1000 && sleep_entry_count < 2;
             timeout_cycles = timeout_cycles + 1) begin
            step_clk;
        end
        check_ok(sleep_entry_count >= 2,
                 "execution reaches WFI with global MIE disabled");
        check_ok(dut.wfi_sleep_q, "second WFI enters sleep");
        check_ok(dut.csr_privilege_mode == PRV_M &&
                 !dut.csr_mstatus_value[3],
                 "second WFI sleeps in M-mode with mstatus.MIE clear");

        // MEIE remains set, so the level wakes WFI. MIE is clear, so this
        // wakeup must not take another trap.
        external_irq = 1'b1;
        for (timeout_cycles = 0;
             timeout_cycles < 100 && dut.wfi_sleep_q;
             timeout_cycles = timeout_cycles + 1) begin
            step_clk;
        end
        check_ok(!dut.wfi_sleep_q,
                 "locally enabled interrupt wakes WFI with global MIE clear");
        external_irq = 1'b0;

        for (timeout_cycles = 0;
             timeout_cycles < 1000 && sleep_entry_count < 3;
             timeout_cycles = timeout_cycles + 1) begin
            step_clk;
        end
        repeat (5) step_clk;

        a0_preg  = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg  = dut.u_rename_packet.u_rat_2w.rat[11];
        a2_preg  = dut.u_rename_packet.u_rat_2w.rat[12];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        a2_value = dut.u_prf_2w.regs[a2_preg];

        check_ok(sleep_entry_count >= 3 && dut.wfi_sleep_q,
                 "program reaches the final WFI sleep state");
        check_ok(interrupt_take_count == 2,
                 "global MIE-disabled WFI wakeup does not enter a trap");
        check_ok(a0_value == 32'd1,
                 "post-interrupt instruction executes exactly once");
        check_ok(a1_value == 32'd2,
                 "handler executes once per held-level interrupt take");
        check_ok(a2_value == 32'd1,
                 "post-wakeup instruction executes without a trap");
        check_ok(dut.external_irq_pending_q == 1'b0,
                 "deasserted external interrupt clears mip pending state");

        $display("[SUMMARY] takes=%0d sleeps=%0d a0=%0d a1=%0d a2=%0d wfi_sleep=%0b mip=0x%08h",
                 interrupt_take_count,
                 sleep_entry_count,
                 a0_value,
                 a1_value,
                 a2_value,
                 dut.wfi_sleep_q,
                 dut.u_execution.u_csr_file.mip_q);

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_wfi_level_irq_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_wfi_level_irq_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
