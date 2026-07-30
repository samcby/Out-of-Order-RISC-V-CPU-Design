`timescale 1ns / 1ps

// Simulation-only integration-level packet-backend testbench for top packet backend fp convert smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_fp_convert_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    preg_t x5_preg;
    preg_t x6_preg;
    preg_t x7_preg;
    fp_preg_t f2_preg;
    fp_preg_t f3_preg;
    fp_preg_t f4_preg;
    logic [31:0] x5_value;
    logic [31:0] x6_value;
    logic [31:0] x7_value;
    logic [31:0] f2_value;
    logic [31:0] f3_value;
    logic [31:0] f4_value;
    int errors;
    int conversion_issue_count;

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
            if (u_dut.issue_if.valid && u_dut.issue_if.ready &&
                u_dut.issue_if.data.control_signal.alu.fp_en &&
                ((u_dut.issue_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_W_S) ||
                 (u_dut.issue_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_WU_S) ||
                 (u_dut.issue_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_S_W) ||
                 (u_dut.issue_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_S_WU))) begin
                conversion_issue_count = conversion_issue_count + 1;
            end
            if (u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                u_dut.issue1_if.data.control_signal.alu.fp_en &&
                ((u_dut.issue1_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_W_S) ||
                 (u_dut.issue1_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_WU_S) ||
                 (u_dut.issue1_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_S_W) ||
                 (u_dut.issue1_if.data.control_signal.alu.fp_op ==
                  FP_OP_CVT_S_WU))) begin
                conversion_issue_count = conversion_issue_count + 1;
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
        conversion_issue_count = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h3fc000b7); // lui x1,0x3fc00 (1.5)
        write_word(32'd4,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd8,  op_fp(7'b1100000, 5'd0, 5'd1, 3'b000, 5'd5));
                                              // fcvt.w.s x5,f1,rne
        write_word(32'd12, op_fp(7'b1101000, 5'd0, 5'd5, 3'b000, 5'd2));
                                              // fcvt.s.w f2,x5,rne
        write_word(32'd16, 32'hffd00113);      // addi x2,x0,-3
        write_word(32'd20, op_fp(7'b1101000, 5'd0, 5'd2, 3'b000, 5'd3));
                                              // fcvt.s.w f3,x2,rne
        write_word(32'd24, op_fp(7'b1100000, 5'd0, 5'd3, 3'b001, 5'd6));
                                              // fcvt.w.s x6,f3,rtz
        write_word(32'd28, 32'hfff00193);      // addi x3,x0,-1
        write_word(32'd32, op_fp(7'b1101000, 5'd1, 5'd3, 3'b000, 5'd4));
                                              // fcvt.s.wu f4,x3,rne
        write_word(32'd36, op_fp(7'b1100000, 5'd1, 5'd1, 3'b001, 5'd7));
                                              // fcvt.wu.s x7,f1,rtz

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (500) step_clk();

        x5_preg = u_dut.u_rename_packet.u_rat_2w.rat[5];
        x6_preg = u_dut.u_rename_packet.u_rat_2w.rat[6];
        x7_preg = u_dut.u_rename_packet.u_rat_2w.rat[7];
        f2_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[2];
        f3_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[3];
        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        x5_value = u_dut.u_prf_2w.regs[x5_preg];
        x6_value = u_dut.u_prf_2w.regs[x6_preg];
        x7_value = u_dut.u_prf_2w.regs[x7_preg];
        f2_value = u_dut.u_fp_prf_2w.regs[f2_preg];
        f3_value = u_dut.u_fp_prf_2w.regs[f3_preg];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];

        $display("[SUMMARY] conversions=%0d x5=0x%08h x6=0x%08h x7=0x%08h f2=0x%08h f3=0x%08h f4=0x%08h fflags=0x%02h rob_empty=%0b",
                 conversion_issue_count, x5_value, x6_value, x7_value,
                 f2_value, f3_value, f4_value, u_dut.fp_fflags,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after cross-domain conversion program");
        check_ok(conversion_issue_count >= 6,
                 "all FCVT forms issue through the FP pipelines");
        check_ok(x5_value == 32'h00000002,
                 "FCVT.W.S writes the integer PRF");
        check_ok(f2_value == 32'h40000000,
                 "FCVT.S.W consumes the preceding integer result");
        check_ok(f3_value == 32'hc0400000,
                 "signed integer converts to negative single precision");
        check_ok(x6_value == 32'hfffffffd,
                 "FP-to-signed conversion returns the original integer");
        check_ok(f4_value == 32'h4f800000,
                 "FCVT.S.WU treats the integer source as unsigned");
        check_ok(x7_value == 32'h00000001,
                 "FCVT.WU.S honors RTZ for 1.5");
        check_ok(u_dut.fp_fflags == 5'b00001,
                 "inexact conversions commit sticky NX");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_convert_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_convert_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
