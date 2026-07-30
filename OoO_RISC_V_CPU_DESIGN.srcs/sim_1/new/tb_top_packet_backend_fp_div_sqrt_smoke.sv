`timescale 1ns / 1ps

// Simulation-only integration-level packet-backend testbench for top packet backend fp div sqrt smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_fp_div_sqrt_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    preg_t x5_preg;
    fp_preg_t f3_preg;
    fp_preg_t f4_preg;
    fp_preg_t f5_preg;
    logic [31:0] x5_value;
    logic [31:0] f3_value;
    logic [31:0] f4_value;
    logic [31:0] f5_value;
    int errors;
    int long_issue_count;
    int busy_cycles;
    int independent_issue_while_busy;

    always #5 clk = ~clk;

    function automatic logic [31:0] op_fp(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] rm,
        input logic [4:0] rd
    );
    begin
        op_fp = {funct7, rs2, rs1, rm, rd, 7'b1010011};
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
        .issue_valid(),
        .issue_fu_type(),
        .issue_pc(),
        .issue_imm(),
        .rob_head_valid(),
        .rob_head_complete(),
        .rob_head_rd()
    );

    always @(posedge clk) begin
        if (rst_n) begin
            if (u_dut.u_execution.fp_long_busy) begin
                busy_cycles = busy_cycles + 1;
                if ((u_dut.issue_if.valid && u_dut.issue_if.ready &&
                     !u_dut.u_execution.issue0_fp_long_candidate) ||
                    (u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                     !u_dut.u_execution.issue1_fp_long_candidate)) begin
                    independent_issue_while_busy =
                        independent_issue_while_busy + 1;
                end
            end
            if (u_dut.u_execution.u_fp_div_sqrt.in_valid &&
                u_dut.u_execution.u_fp_div_sqrt.in_ready) begin
                long_issue_count = long_issue_count + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        errors = 0;
        long_issue_count = 0;
        busy_cycles = 0;
        independent_issue_while_busy = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h40c000b7); // lui x1,0x40c00 (6.0)
        write_word(32'd4,  32'h40000137); // lui x2,0x40000 (2.0)
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, op_fp(7'b1111000, 5'd0, 5'd2, 3'b000, 5'd2));
                                              // fmv.w.x f2,x2
        write_word(32'd16, op_fp(7'b0001100, 5'd2, 5'd1, 3'b000, 5'd3));
                                              // fdiv.s f3,f1,f2
        write_word(32'd20, 32'h00100293);      // addi x5,x0,1
        write_word(32'd24, 32'h00128293);      // addi x5,x5,1
        write_word(32'd28, 32'h00128293);      // addi x5,x5,1
        write_word(32'd32, 32'h00128293);      // addi x5,x5,1
        write_word(32'd36, 32'h00128293);      // addi x5,x5,1
        write_word(32'd40, 32'h00128293);      // addi x5,x5,1
        write_word(32'd44, 32'h00128293);      // addi x5,x5,1
        write_word(32'd48, 32'h00128293);      // addi x5,x5,1
        write_word(32'd52, op_fp(7'b0101100, 5'd0, 5'd3, 3'b000, 5'd4));
                                              // fsqrt.s f4,f3
        write_word(32'd56, op_fp(7'b0000000, 5'd2, 5'd3, 3'b000, 5'd5));
                                              // fadd.s f5,f3,f2

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (700) step_clk();

        x5_preg = u_dut.u_rename_packet.u_rat_2w.rat[5];
        f3_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[3];
        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        f5_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[5];
        x5_value = u_dut.u_prf_2w.regs[x5_preg];
        f3_value = u_dut.u_fp_prf_2w.regs[f3_preg];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];
        f5_value = u_dut.u_fp_prf_2w.regs[f5_preg];

        $display("[SUMMARY] long_issues=%0d busy_cycles=%0d independent_while_busy=%0d x5=0x%08h f3=0x%08h f4=0x%08h f5=0x%08h fflags=0x%02h rob_empty=%0b",
                 long_issue_count, busy_cycles, independent_issue_while_busy,
                 x5_value, f3_value, f4_value, f5_value, u_dut.fp_fflags,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after FDIV/FSQRT program");
        check_ok(long_issue_count >= 2,
                 "FDIV and FSQRT enter the shared long-latency unit");
        check_ok(busy_cycles >= 30,
                 "shared unit exposes multi-cycle occupancy");
        check_ok(independent_issue_while_busy > 0,
                 "OoO backend continues issuing independent work during FDIV");
        check_ok(x5_value == 32'h00000008,
                 "independent integer work completes while FP divide is busy");
        check_ok(f3_value == 32'h40400000,
                 "FDIV.S produces 3.0");
        check_ok(f4_value == 32'h3fddb3d7,
                 "dependent FSQRT.S produces rounded sqrt(3)");
        check_ok(f5_value == 32'h40a00000,
                 "short FP pipeline consumes the FDIV result");
        check_ok(u_dut.fp_fflags == 5'b00001,
                 "inexact FSQRT commits sticky NX");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_div_sqrt_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_div_sqrt_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
