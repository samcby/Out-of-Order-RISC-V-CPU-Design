`timescale 1ns/1ps

module tb_top_packet_backend_dual_commit_smoke;

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
    int dual_commit_count;
    int dual_retire_count;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;

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
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] %s", msg);
        end
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dual_commit_count <= 0;
            dual_retire_count <= 0;
        end else begin
            #1;
            if (dut.commit_en && dut.commit_en1) begin
                dual_commit_count <= dual_commit_count + 1;
            end

            if (dut.u_rename_packet.retire_valid == 2'b11) begin
                dual_retire_count <= dual_retire_count + 1;
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

        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'd8;

        write_word(32'd0,  32'h00002283); // lw   x5,0(x0), miss delays oldest ROB entry
        write_word(32'd4,  32'h00900593); // addi x11,x0,9, completes while load is pending
        write_word(32'd8,  32'h00000013); // nop
        write_word(32'd12, 32'h00000013); // nop
        write_word(32'd16, 32'h00000013); // nop
        write_word(32'd20, 32'h00000013); // nop
        write_word(32'd24, 32'h00000013); // nop
        write_word(32'd28, 32'h00028513); // addi x10,x5,0, checks loaded value after commit
        write_word(32'd32, 32'h00000013); // nop
        write_word(32'd36, 32'h00000013); // nop
        write_word(32'd40, 32'h00000013); // nop

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (300) step_clk;

        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];

        $display("[SUMMARY] dual_commit=%0d dual_retire=%0d a0=0x%08h a1=0x%08h rob_empty=%0b",
                 dual_commit_count,
                 dual_retire_count,
                 a0_value,
                 a1_value,
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(dual_commit_count >= 1,
                 "packet backend committed two adjacent completed ROB entries in one cycle");
        check_ok(dual_retire_count >= 1,
                 "rename free pool observed two retired physical registers in one cycle");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "packet backend ROB drained after dual-commit smoke program");
        check_ok(a0_value == 32'd8,
                 "final a0(x10) value is correct after dual commit");
        check_ok(a1_value == 32'd9,
                 "final a1(x11) value is correct after dual commit");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_dual_commit_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_dual_commit_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
