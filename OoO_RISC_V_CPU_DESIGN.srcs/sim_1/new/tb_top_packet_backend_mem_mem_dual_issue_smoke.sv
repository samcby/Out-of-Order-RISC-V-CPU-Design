`timescale 1ns/1ps

module tb_top_packet_backend_mem_mem_dual_issue_smoke;

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

    top_packet_backend #(
        .DMEM_BASE_ADDR(32'h00000000)
    ) dut (
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
        if (cond) begin
            $display("[PASS] %s", msg);
        end else begin
            $display("[FAIL] %s", msg);
            fail_count++;
        end
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

    function automatic [31:0] arch_reg(input int unsigned index);
        preg_t preg;
    begin
        preg = dut.u_rename_packet.u_rat_2w.rat[index];
        arch_reg = dut.u_prf_2w.regs[preg];
    end
    endfunction

    initial begin
        rst_n = 1'b0;
        software_irq = 1'b0;
        timer_irq = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        // Addresses 0/16 and 32/48 map to opposite D-cache banks.
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'd5;
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[4] = 32'd6;

        write_word(32'd0,  32'h00b00393); // addi x7,x0,11
        write_word(32'd4,  32'h00000013); // nop
        write_word(32'd8,  32'h00002283); // lw   x5,0(x0)
        write_word(32'd12, 32'h01002303); // lw   x6,16(x0)
        write_word(32'd16, 32'h02702023); // sw   x7,32(x0)
        write_word(32'd20, 32'h02702823); // sw   x7,48(x0)
        write_word(32'd24, 32'h02002583); // lw   x11,32(x0)
        write_word(32'd28, 32'h03002603); // lw   x12,48(x0)
        write_word(32'd32, 32'h00628533); // add  x10,x5,x6
        write_word(32'd36, 32'h00c586b3); // add  x13,x11,x12

        load_en = 1'b0;
        repeat (500) step_clk;

        $display(
            "[SUMMARY] mem_mem_dual=%0d dual_wb=%0d x5=%0d x6=%0d a0=%0d x11=%0d x12=%0d x13=%0d rob_empty=%0d",
            dut.perf_mem_mem_dual_issue_count_q,
            dut.perf_dual_wb_count_q,
            arch_reg(5),
            arch_reg(6),
            arch_reg(10),
            arch_reg(11),
            arch_reg(12),
            arch_reg(13),
            dut.u_dispatch_packet.u_rob_2w.empty
        );

        check_ok(dut.perf_mem_mem_dual_issue_count_q >= 3,
                 "packet backend observed dual load, store, and reload issue");
        check_ok(dut.perf_dual_wb_count_q >= 1,
                 "two loads completed through both writeback ports");
        check_ok(arch_reg(5) == 32'd5 && arch_reg(6) == 32'd6,
                 "first different-bank load pair returned correct data");
        check_ok(arch_reg(10) == 32'd11,
                 "consumer observed both first-pair load results");
        check_ok(arch_reg(11) == 32'd11 && arch_reg(12) == 32'd11,
                 "loads observed both precisely retired stores");
        check_ok(arch_reg(13) == 32'd22,
                 "consumer observed both reloaded store values");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drained after MEM+MEM dual-issue program");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_mem_mem_dual_issue_smoke PASS ====");
        end else begin
            $display(
                "==== tb_top_packet_backend_mem_mem_dual_issue_smoke FAIL (%0d errors) ====",
                fail_count
            );
        end
        $finish;
    end

endmodule
