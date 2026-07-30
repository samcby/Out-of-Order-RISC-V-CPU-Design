`timescale 1ns/1ps

// A synchronous ROB-head exception must win over an enabled pending interrupt.
module tb_top_packet_backend_exception_interrupt_priority;

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
    int overlap_count;
    int priority_bad_count;
    int trap_count;

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
            overlap_count <= 0;
            priority_bad_count <= 0;
            trap_count <= 0;
        end else begin
            if (dut.trap_commit && dut.external_irq_enabled) begin
                overlap_count <= overlap_count + 1;
                if (dut.interrupt_take) begin
                    priority_bad_count <= priority_bad_count + 1;
                end
            end

            if (dut.u_execution.csr_trap_write_en) begin
                trap_count <= trap_count + 1;
                if (!dut.u_execution.commit_trap_fire ||
                    dut.u_execution.interrupt_take ||
                    (dut.u_execution.csr_trap_mcause !=
                     MCAUSE_LOAD_ACCESS_FAULT)) begin
                    priority_bad_count <= priority_bad_count + 1;
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
        fail_count = 0;
        rst_n = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00001137); // lui   x2,0x1
        write_word(32'd12, 32'h80010113); // addi  x2,x2,-2048 -> 0x800
        write_word(32'd16, 32'h30411073); // csrrw x0,mie,x2
        write_word(32'd20, 32'h00800113); // addi  x2,x0,8
        write_word(32'd24, 32'h30011073); // csrrw x0,mstatus,x2
        write_word(32'd28, 32'h00002283); // lw    x5,0(x0), access fault
        write_word(32'd32, 32'h05500513); // wrong until handler policy returns

        write_word(32'd2032, 32'h342025f3); // csrrs x11,mcause,x0
        write_word(32'd2036, 32'h34302673); // csrrs x12,mtval,x0
        write_word(32'd2040, 32'h0000006f); // jal x0,0

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        // Assert the IRQ after the fault completion pulse. The ROB still
        // contains older work, so the pending bit becomes visible before the
        // fault reaches the architectural trap boundary.
        while (!(dut.complete_valid &&
                 dut.complete_exception_valid &&
                 (dut.complete_exception_cause ==
                  MCAUSE_LOAD_ACCESS_FAULT))) begin
            step_clk;
        end

        external_irq = 1'b1;
        repeat (3) step_clk;
        external_irq = 1'b0;
        repeat (80) step_clk;

        $display("[SUMMARY] overlap=%0d bad=%0d traps=%0d mcause=0x%08h mtval=0x%08h mstatus=0x%08h mie=0x%08h",
                 overlap_count,
                 priority_bad_count,
                 trap_count,
                 dut.u_execution.u_csr_file.mcause_q,
                 dut.u_execution.u_csr_file.mtval_q,
                 dut.u_execution.u_csr_file.mstatus_q,
                 dut.u_execution.u_csr_file.mie_q);

        check_ok(overlap_count == 1,
                 "enabled external interrupt overlapped the ROB-head exception");
        check_ok(priority_bad_count == 0,
                 "synchronous exception won every overlap arbitration check");
        check_ok(trap_count == 1,
                 "only the synchronous access fault entered trap state");
        check_ok(dut.u_execution.u_csr_file.mcause_q ==
                 MCAUSE_LOAD_ACCESS_FAULT,
                 "mcause records load access fault rather than interrupt");
        check_ok(dut.u_execution.u_csr_file.mtval_q == 32'h00000000,
                 "mtval records the faulting load address");
        check_ok(dut.interrupt_take == 1'b0,
                 "interrupt remains blocked while trap handler has MIE cleared");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_exception_interrupt_priority PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_exception_interrupt_priority FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
