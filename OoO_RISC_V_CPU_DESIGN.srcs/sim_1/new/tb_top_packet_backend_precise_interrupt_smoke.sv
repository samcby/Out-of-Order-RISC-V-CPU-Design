`timescale 1ns/1ps

// Verifies that a pending machine interrupt can be taken at a non-empty ROB
// boundary. The interrupted cache-miss load and all younger work must be
// discarded, then replayed from mepc after MRET.
module tb_top_packet_backend_precise_interrupt_smoke;

    import defines_pkg::*;

    localparam logic [31:0] LOAD_PC = 32'd32;
    localparam logic [31:0] LOAD_VALUE = 32'h12345678;

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
    int wait_cycles;
    int load_issue_count;
    logic saw_nonempty_interrupt;
    logic saw_incomplete_head;
    logic [31:0] interrupt_restart_pc;
    preg_t x5_preg;
    preg_t x6_preg;
    preg_t x7_preg;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t a2_preg;
    preg_t a3_preg;

    top_packet_backend dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .software_irq      (1'b0),
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
            load_issue_count <= 0;
        end else if (dut.u_execution.lsu_req_valid &&
                     dut.u_execution.lsu_req_ready &&
                     (dut.u_execution.selected_mem_datapath.pc == LOAD_PC)) begin
            load_issue_count <= load_issue_count + 1;
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
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;
        saw_nonempty_interrupt = 1'b0;
        saw_incomplete_head = 1'b0;
        interrupt_restart_pc = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Configure a direct-mode handler, enable MEIE/MIE, then execute a
        // cold-cache load followed by younger independent instructions.
        write_word(32'd0,  32'h20000093); // addi  x1,x0,0x200
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00800113); // addi  x2,x0,8
        write_word(32'd12, 32'h30011073); // csrrw x0,mstatus,x2
        write_word(32'd16, 32'h00100193); // addi  x3,x0,1
        write_word(32'd20, 32'h00b19193); // slli  x3,x3,11
        write_word(32'd24, 32'h30419073); // csrrw x0,mie,x3
        write_word(32'd28, 32'h00010437); // lui   x8,0x10
        write_word(LOAD_PC, 32'h00042283); // lw    x5,0(x8)
        write_word(32'd36, 32'h06600313); // addi  x6,x0,0x66
        write_word(32'd40, 32'h07700393); // addi  x7,x0,0x77
        write_word(32'd44, 32'h00128513); // addi  x10,x5,1
        write_word(32'd48, 32'h0000006f); // jal   x0,0

        // Handler records mcause/mepc, increments one architectural marker,
        // then returns without modifying mepc because interrupts are restartable.
        write_word(32'h200, 32'h342025f3); // csrrs x11,mcause,x0
        write_word(32'h204, 32'h34102673); // csrrs x12,mepc,x0
        write_word(32'h208, 32'h00168693); // addi  x13,x13,1
        write_word(32'h20c, 32'h30200073); // mret

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = LOAD_VALUE;

        // Wait until the cache-miss load is both executing and the oldest
        // incomplete architectural instruction.
        for (wait_cycles = 0;
             wait_cycles < 1000 &&
             !(dut.rob_head_valid_i &&
               !dut.rob_head_complete_i &&
               (dut.rob_head.datapath.pc == LOAD_PC) &&
               dut.u_execution.u_lsu.pending_valid);
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end
        check_ok(wait_cycles < 1000,
                 "cold-cache load reached the incomplete ROB head");

        external_irq = 1'b1;
        for (wait_cycles = 0;
             wait_cycles < 100 && !dut.interrupt_take;
             wait_cycles = wait_cycles + 1) begin
            step_clk;
        end

        if (dut.interrupt_take) begin
            saw_nonempty_interrupt = !dut.rob_empty_i;
            saw_incomplete_head = dut.rob_head_valid_i &&
                                  !dut.rob_head_complete_i;
            interrupt_restart_pc = dut.interrupt_mepc;
            step_clk;
        end
        external_irq = 1'b0;

        check_ok(wait_cycles < 100,
                 "pending external interrupt was accepted");
        check_ok(saw_nonempty_interrupt,
                 "interrupt was accepted without draining the ROB");
        check_ok(saw_incomplete_head,
                 "interrupt was accepted at an incomplete oldest instruction");
        check_ok(interrupt_restart_pc == LOAD_PC,
                 "interrupt restart PC equals the oldest unretired load PC");

        repeat (500) step_clk;

        x5_preg = dut.u_rename_packet.u_rat_2w.rat[5];
        x6_preg = dut.u_rename_packet.u_rat_2w.rat[6];
        x7_preg = dut.u_rename_packet.u_rat_2w.rat[7];
        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        a2_preg = dut.u_rename_packet.u_rat_2w.rat[12];
        a3_preg = dut.u_rename_packet.u_rat_2w.rat[13];

        $display("[SUMMARY] nonempty_take=%0b incomplete_head=%0b restart_pc=0x%08h load_issues=%0d x5=0x%08h x6=0x%08h x7=0x%08h a0=0x%08h mcause=0x%08h mepc=0x%08h marker=%0d",
                 saw_nonempty_interrupt,
                 saw_incomplete_head,
                 interrupt_restart_pc,
                 load_issue_count,
                 dut.u_prf_2w.regs[x5_preg],
                 dut.u_prf_2w.regs[x6_preg],
                 dut.u_prf_2w.regs[x7_preg],
                 dut.u_prf_2w.regs[a0_preg],
                 dut.u_prf_2w.regs[a1_preg],
                 dut.u_prf_2w.regs[a2_preg],
                 dut.u_prf_2w.regs[a3_preg]);

        check_ok(dut.u_prf_2w.regs[x5_preg] == LOAD_VALUE,
                 "interrupted load replayed and returned memory data");
        check_ok(dut.u_prf_2w.regs[x6_preg] == 32'h00000066,
                 "younger x6 instruction replayed after MRET");
        check_ok(dut.u_prf_2w.regs[x7_preg] == 32'h00000077,
                 "younger x7 instruction replayed after MRET");
        check_ok(dut.u_prf_2w.regs[a0_preg] == (LOAD_VALUE + 1'b1),
                 "post-load dependent result is correct after replay");
        check_ok(dut.u_prf_2w.regs[a1_preg] == 32'h8000000b,
                 "handler captured machine external interrupt cause");
        check_ok(dut.u_prf_2w.regs[a2_preg] == LOAD_PC,
                 "handler observed the precise restart mepc");
        check_ok(dut.u_prf_2w.regs[a3_preg] == 32'd1,
                 "interrupt handler executed exactly once");
        check_ok(load_issue_count >= 2,
                 "interrupted load was issued again after MRET");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_precise_interrupt_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_precise_interrupt_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
