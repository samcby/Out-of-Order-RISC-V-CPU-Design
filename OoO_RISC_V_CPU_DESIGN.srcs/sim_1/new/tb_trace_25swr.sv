`timescale 1ns/1ps

module tb_trace_25swr;

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

    top dut (
        .clk              (clk),
        .rst_n            (rst_n),
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

        // 25swr.txt
        write_word(32'd0,   32'h00010437);
        write_word(32'd4,   32'h02040413);
        write_word(32'd8,   32'h000204B7);
        write_word(32'd12,  32'hFF048493);
        write_word(32'd16,  32'h12306293);
        write_word(32'd20,  32'h4062D333);
        write_word(32'd24,  32'h00542023);
        write_word(32'd28,  32'h00641223);
        write_word(32'd32,  32'h0FF00393);
        write_word(32'd36,  32'h00742423);
        write_word(32'd40,  32'h00944E03);
        write_word(32'd44,  32'h00042E83);
        write_word(32'd48,  32'h007EFF33);
        write_word(32'd52,  32'h01E42623);
        write_word(32'd56,  32'h02040913);
        write_word(32'd60,  32'hFFE91F23);
        write_word(32'd64,  32'hFFE94F83);
        write_word(32'd68,  32'hFFF94B83);
        write_word(32'd72,  32'h01D4A023);
        write_word(32'd76,  32'h00749323);
        write_word(32'd80,  32'h0004AC03);
        write_word(32'd84,  32'h0074CC83);
        write_word(32'd88,  32'h0FF00993);
        write_word(32'd92,  32'h013C7533);
        write_word(32'd96,  32'h000E0593);
        write_word(32'd100, 32'h41F00A33);
        write_word(32'd104, 32'h414585B3);
        write_word(32'd108, 32'h41700AB3);
        write_word(32'd112, 32'h41D585B3);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (450) step_clk;

        a0_preg  = dut.u_rename.u_rat.rat[10];
        a1_preg  = dut.u_rename.u_rat.rat[11];
        a0_value = dut.u_prf.regs[a0_preg];
        a1_value = dut.u_prf.regs[a1_preg];

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) rob_empty=%0b",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 dut.u_dispatch.u_rob.empty);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, "ROB drained after 25swr program");
        check_ok(a0_value == 32'h00000023, "25swr a0(x10) matches expected 35");
        check_ok(a1_value == 32'hFFFFFF00, "25swr a1(x11) matches expected -256");

        if (fail_count == 0) begin
            $display("==== tb_trace_25swr PASS ====");
        end else begin
            $display("==== tb_trace_25swr FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
