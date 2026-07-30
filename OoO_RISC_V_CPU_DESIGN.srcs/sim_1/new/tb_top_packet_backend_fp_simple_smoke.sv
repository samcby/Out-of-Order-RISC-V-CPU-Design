`timescale 1ns / 1ps

// Simulation-only integration-level packet-backend testbench for top packet backend fp simple smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_fp_simple_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
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

    fp_preg_t f1_preg;
    fp_preg_t f2_preg;
    fp_preg_t f3_preg;
    fp_preg_t f4_preg;
    fp_preg_t f5_preg;
    preg_t x3_preg;
    preg_t x4_preg;
    preg_t x5_preg;
    preg_t x6_preg;
    preg_t x7_preg;
    logic [31:0] f1_value;
    logic [31:0] f2_value;
    logic [31:0] f3_value;
    logic [31:0] f4_value;
    logic [31:0] f5_value;
    logic [31:0] x3_value;
    logic [31:0] x4_value;
    logic [31:0] x5_value;
    logic [31:0] x6_value;
    logic [31:0] x7_value;
    int errors;

    always #5 clk = ~clk;

    function automatic logic [31:0] op_fp(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
    begin
        op_fp = {funct7, rs2, rs1, funct3, rd, 7'b1010011};
    end
    endfunction

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic write_byte(input logic [31:0] address, input logic [7:0] value);
    begin
        load_en = 1'b1;
        load_addr = address;
        load_instr_byte = value;
        step_clk();
    end
    endtask

    task automatic write_word(input logic [31:0] address, input logic [31:0] value);
    begin
        write_byte(address + 0, value[7:0]);
        write_byte(address + 1, value[15:8]);
        write_byte(address + 2, value[23:16]);
        write_byte(address + 3, value[31:24]);
    end
    endtask

    task automatic check_ok(input logic condition, input string message);
    begin
        if (condition) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s", message);
            errors = errors + 1;
        end
    end
    endtask

    top_packet_backend #(
        .RESET_FS_INITIAL(1'b1)
    ) u_dut (
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

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        errors = 0;

        step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h3f8000b7); // lui x1,0x3f800
        write_word(32'd4,  32'hc0000137); // lui x2,0xc0000
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, op_fp(7'b1111000, 5'd0, 5'd2, 3'b000, 5'd2));
                                              // fmv.w.x f2,x2
        write_word(32'd16, op_fp(7'b0010000, 5'd2, 5'd1, 3'b010, 5'd3));
                                              // fsgnjx.s f3,f1,f2
        write_word(32'd20, op_fp(7'b1010000, 5'd1, 5'd2, 3'b001, 5'd3));
                                              // flt.s x3,f2,f1
        write_word(32'd24, op_fp(7'b1010000, 5'd1, 5'd1, 3'b000, 5'd4));
                                              // fle.s x4,f1,f1
        write_word(32'd28, op_fp(7'b1010000, 5'd3, 5'd1, 3'b010, 5'd5));
                                              // feq.s x5,f1,f3
        write_word(32'd32, op_fp(7'b1110000, 5'd0, 5'd2, 3'b001, 5'd6));
                                              // fclass.s x6,f2
        write_word(32'd36, op_fp(7'b1110000, 5'd0, 5'd3, 3'b000, 5'd7));
                                              // fmv.x.w x7,f3
        write_word(32'd40, op_fp(7'b0010100, 5'd2, 5'd1, 3'b000, 5'd4));
                                              // fmin.s f4,f1,f2
        write_word(32'd44, op_fp(7'b0010100, 5'd2, 5'd1, 3'b001, 5'd5));
                                              // fmax.s f5,f1,f2

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (400) step_clk();

        f1_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[1];
        f2_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[2];
        f3_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[3];
        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        f5_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[5];
        x3_preg = u_dut.u_rename_packet.u_rat_2w.rat[3];
        x4_preg = u_dut.u_rename_packet.u_rat_2w.rat[4];
        x5_preg = u_dut.u_rename_packet.u_rat_2w.rat[5];
        x6_preg = u_dut.u_rename_packet.u_rat_2w.rat[6];
        x7_preg = u_dut.u_rename_packet.u_rat_2w.rat[7];

        f1_value = u_dut.u_fp_prf_2w.regs[f1_preg];
        f2_value = u_dut.u_fp_prf_2w.regs[f2_preg];
        f3_value = u_dut.u_fp_prf_2w.regs[f3_preg];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];
        f5_value = u_dut.u_fp_prf_2w.regs[f5_preg];
        x3_value = u_dut.u_prf_2w.regs[x3_preg];
        x4_value = u_dut.u_prf_2w.regs[x4_preg];
        x5_value = u_dut.u_prf_2w.regs[x5_preg];
        x6_value = u_dut.u_prf_2w.regs[x6_preg];
        x7_value = u_dut.u_prf_2w.regs[x7_preg];

        $display("[SUMMARY] f1=0x%08h f2=0x%08h f3=0x%08h f4=0x%08h f5=0x%08h x3=%0d x4=%0d x5=%0d x6=0x%08h x7=0x%08h rob_empty=%0b",
                 f1_value, f2_value, f3_value, f4_value, f5_value,
                 x3_value, x4_value,
                 x5_value, x6_value, x7_value,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "packet backend ROB drains after exact FP program");
        check_ok(f1_value == 32'h3f800000,
                 "FMV.W.X moves +1.0 payload into f1");
        check_ok(f2_value == 32'hc0000000,
                 "FMV.W.X moves -2.0 payload into f2");
        check_ok(f3_value == 32'hbf800000,
                 "FSGNJX.S produces -1.0 in f3");
        check_ok(f4_value == 32'hc0000000,
                 "FMIN.S chooses -2.0");
        check_ok(f5_value == 32'h3f800000,
                 "FMAX.S chooses +1.0");
        check_ok(x3_value == 32'd1, "FLT.S writes an integer result");
        check_ok(x4_value == 32'd1, "FLE.S writes an integer result");
        check_ok(x5_value == 32'd0, "FEQ.S writes an integer result");
        check_ok(x6_value == 32'h00000002,
                 "FCLASS.S identifies a negative normal value");
        check_ok(x7_value == 32'hbf800000,
                 "FMV.X.W moves the exact f3 payload to x7");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_simple_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_simple_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
