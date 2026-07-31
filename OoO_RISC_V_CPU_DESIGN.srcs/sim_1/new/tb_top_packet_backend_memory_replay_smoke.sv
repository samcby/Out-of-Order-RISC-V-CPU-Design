`timescale 1ns/1ps

module tb_top_packet_backend_memory_replay_smoke;

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

        // The first load resolves the older store base to address 32. The
        // younger load may initially bypass while that address is unknown.
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[4] = 32'd32;
        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[8] = 32'd7;

        write_word(32'd0,  32'h01002083); // lw   x1,16(x0)
        write_word(32'd4,  32'h06300113); // addi x2,x0,99
        write_word(32'd8,  32'h0020a023); // sw   x2,0(x1), address initially unknown
        write_word(32'd12, 32'h02002183); // lw   x3,32(x0), younger alias
        write_word(32'd16, 32'h00018513); // addi x10,x3,0

        load_en = 1'b0;
        repeat (800) step_clk;

        $display(
            "[SUMMARY] replays=%0d x1=%0d x2=%0d x3=%0d a0=%0d rob_empty=%0d replay_pending=%0d replay_tag=%0d head_valid=%0d head_tag=%0d",
            dut.perf_memory_replay_count_q,
            arch_reg(1),
            arch_reg(2),
            arch_reg(3),
            arch_reg(10),
            dut.u_dispatch_packet.u_rob_2w.empty,
            dut.memory_replay_pending_q,
            dut.memory_replay_tag_q,
            dut.rob_head_valid_i,
            dut.rob_head.datapath.rob_tag
        );

        check_ok(dut.perf_memory_replay_count_q >= 1,
                 "late store-address alias triggered a backend replay");
        check_ok(arch_reg(1) == 32'd32 && arch_reg(2) == 32'd99,
                 "older load and store data retired before replay");
        check_ok(arch_reg(3) == 32'd99 && arch_reg(10) == 32'd99,
                 "replayed load observed the older committed store");
        check_ok(!dut.memory_replay_pending_q,
                 "replay request cleared after recovery");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drained after memory dependence replay");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_memory_replay_smoke PASS ====");
        end else begin
            $display(
                "==== tb_top_packet_backend_memory_replay_smoke FAIL (%0d errors) ====",
                fail_count
            );
        end
        $finish;
    end

endmodule
