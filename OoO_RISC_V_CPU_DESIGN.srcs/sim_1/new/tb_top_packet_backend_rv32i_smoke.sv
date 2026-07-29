`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend rv32i smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_rv32i_smoke;

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
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] store_word_way0;
    logic [31:0] store_word_way1;

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

        dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'h0154ff55;

        write_word(32'd0,   32'h000100b7); // lui   x1,0x10
        write_word(32'd4,   32'h00408b93); // addi  x23,x1,4
        write_word(32'd8,   32'hfff00113); // addi  x2,x0,-1
        write_word(32'd12,  32'h0ff14193); // xori  x3,x2,0xff
        write_word(32'd16,  32'h0f01f213); // andi  x4,x3,0xf0
        write_word(32'd20,  32'h05526213); // ori   x4,x4,0x55
        write_word(32'd24,  32'h00221293); // slli  x5,x4,2
        write_word(32'd28,  32'h0012d313); // srli  x6,x5,1
        write_word(32'd32,  32'h40415393); // srai  x7,x2,4
        write_word(32'd36,  32'h00012413); // slti  x8,x2,0
        write_word(32'd40,  32'h00113493); // sltiu x9,x2,1
        write_word(32'd44,  32'h00628533); // add   x10,x5,x6
        write_word(32'd48,  32'h40450533); // sub   x10,x10,x4
        write_word(32'd52,  32'h00008583); // lb    x11,0(x1)
        write_word(32'd56,  32'h0030c603); // lbu   x12,3(x1)
        write_word(32'd60,  32'h00209683); // lh    x13,2(x1)
        write_word(32'd64,  32'h0020d703); // lhu   x14,2(x1)
        write_word(32'd68,  32'h004b8023); // sb    x4,0(x23)
        write_word(32'd72,  32'h005b9123); // sh    x5,2(x23)
        write_word(32'd76,  32'h00001797); // auipc x15,0x1
        write_word(32'd80,  32'h00c59833); // sll   x16,x11,x12
        write_word(32'd84,  32'h00c6d8b3); // srl   x17,x13,x12
        write_word(32'd88,  32'h40c15933); // sra   x18,x2,x12
        write_word(32'd92,  32'h000129b3); // slt   x19,x2,x0
        write_word(32'd96,  32'h00013a33); // sltu  x20,x2,x0
        write_word(32'd100, 32'h01486ab3); // or    x21,x16,x20
        write_word(32'd104, 32'h011afb33); // and   x22,x21,x17
        write_word(32'd108, 32'h000b0513); // addi  x10,x22,0
        write_word(32'd112, 32'hfb478593); // addi  x11,x15,-76

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (450) step_clk;

        a0_preg  = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg  = dut.u_rename_packet.u_rat_2w.rat[11];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        store_word_way0 = dut.u_execution.u_lsu.u_data_cache.line_data[0][0][1];
        store_word_way1 = dut.u_execution.u_lsu.u_data_cache.line_data[0][1][1];

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) store_way0=0x%08h store_way1=0x%08h rob_empty=%0b",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 store_word_way0,
                 store_word_way1,
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "packet backend ROB drained after RV32I smoke program");
        check_ok(a0_value == 32'h000000aa,
                 "packet backend RV32I smoke a0(x10) matches expected 0xaa");
        check_ok(a1_value == 32'h00001000,
                 "packet backend RV32I smoke a1(x11) matches expected 0x1000");
        check_ok((store_word_way0 == 32'h01540055) ||
                 (store_word_way1 == 32'h01540055),
                 "packet backend cached sb/sh store word matches expected 0x01540055");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_rv32i_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_rv32i_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
