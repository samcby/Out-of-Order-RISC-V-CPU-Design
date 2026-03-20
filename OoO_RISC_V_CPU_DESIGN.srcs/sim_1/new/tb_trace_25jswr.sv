`timescale 1ns/1ps

module tb_trace_25jswr;

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

        // 25jswr.txt
        write_word(32'd0,   32'h00010437);
        write_word(32'd4,   32'h04040413);
        write_word(32'd8,   32'h000204B7);
        write_word(32'd12,  32'hFE048493);
        write_word(32'd16,  32'h000DE2B7);
        write_word(32'd20,  32'h0AD2E293);
        write_word(32'd24,  32'h0054A023);
        write_word(32'd28,  32'h0FF00313);
        write_word(32'd32,  32'h00649223);
        write_word(32'd36,  32'h00049323);
        write_word(32'd40,  32'h00000393);
        write_word(32'd44,  32'h00400E13);
        write_word(32'd48,  32'h0004CE83);
        write_word(32'd52,  32'h01D42023);
        write_word(32'd56,  32'h00148493);
        write_word(32'd60,  32'h00440413);
        write_word(32'd64,  32'h00138393);
        write_word(32'd68,  32'hFFC396E3);
        write_word(32'd72,  32'hF0040413);
        write_word(32'd76,  32'hF0148493);
        write_word(32'd80,  32'h00042F03);
        write_word(32'd84,  32'h0004CF83);
        write_word(32'd88,  32'h01F41423);
        write_word(32'd92,  32'h00442B83);
        write_word(32'd96,  32'h01741623);
        write_word(32'd100, 32'h00000EB7);
        write_word(32'd104, 32'h080E8E93);
        write_word(32'd108, 32'h000E80E7);
        write_word(32'd112, 32'h00000EB7);
        write_word(32'd116, 32'h0ACE8E93);
        write_word(32'd120, 32'h000E80E7);
        write_word(32'd124, 32'h00008067);
        write_word(32'd128, 32'h00042283);
        write_word(32'd132, 32'h00442303);
        write_word(32'd136, 32'h0062F3B3);
        write_word(32'd140, 32'h4063D3B3);
        write_word(32'd144, 32'h4003BE13);
        write_word(32'd148, 32'h000E1463);
        write_word(32'd152, 32'hC0038393);
        write_word(32'd156, 32'h00742823);
        write_word(32'd160, 32'h01042F03);
        write_word(32'd164, 32'h006F7533);
        write_word(32'd168, 32'h00008067);
        write_word(32'd172, 32'h00844283);
        write_word(32'd176, 32'h00C44303);
        write_word(32'd180, 32'h0062F3B3);
        write_word(32'd184, 32'h01F00E13);
        write_word(32'd188, 32'h41C3D3B3);
        write_word(32'd192, 32'h0013BE93);
        write_word(32'd196, 32'h000E9663);
        write_word(32'd200, 32'h00000393);
        write_word(32'd204, 32'h00001463);
        write_word(32'd208, 32'h00100393);
        write_word(32'd212, 32'h00742A23);
        write_word(32'd216, 32'h01442583);
        write_word(32'd220, 32'h004E8513);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (650) step_clk;

        a0_preg  = dut.u_rename.u_rat.rat[10];
        a1_preg  = dut.u_rename.u_rat.rat[11];
        a0_value = dut.u_prf.regs[a0_preg];
        a1_value = dut.u_prf.regs[a1_preg];

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) rob_empty=%0b",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 dut.u_dispatch.u_rob.empty);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, "ROB drained after 25jswr program");
        check_ok(a0_value == 32'h00000005, "25jswr a0(x10) matches expected 5");
        check_ok(a1_value == 32'h00000001, "25jswr a1(x11) matches expected 1");

        if (fail_count == 0) begin
            $display("==== tb_trace_25jswr PASS ====");
        end else begin
            $display("==== tb_trace_25jswr FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
