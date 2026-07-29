`timescale 1ns / 1ps

// Simulation-only integration-level packet-backend testbench for top packet backend fp pipeline smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_fp_pipeline_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    fp_preg_t f3_preg;
    fp_preg_t f4_preg;
    fp_preg_t f5_preg;
    fp_preg_t f6_preg;
    logic [31:0] f3_value;
    logic [31:0] f4_value;
    logic [31:0] f5_value;
    logic [31:0] f6_value;
    int errors;
    int fp_issue_count;
    int fp_complete_count;
    int dual_fp_issue_count;

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

    top_packet_backend u_dut (
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
            if ((u_dut.issue_if.valid && u_dut.issue_if.ready &&
                 u_dut.issue_if.data.control_signal.alu.fp_en) ||
                (u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                 u_dut.issue1_if.data.control_signal.alu.fp_en)) begin
                fp_issue_count = fp_issue_count + 1;
            end
            if (u_dut.issue_if.valid && u_dut.issue_if.ready &&
                u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                u_dut.issue_if.data.control_signal.alu.fp_en &&
                u_dut.issue1_if.data.control_signal.alu.fp_en) begin
                dual_fp_issue_count = dual_fp_issue_count + 1;
            end
            if (u_dut.u_execution.fp0_out_valid ||
                u_dut.u_execution.fp1_out_valid) begin
                fp_complete_count = fp_complete_count + 1;
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
        fp_issue_count = 0;
        fp_complete_count = 0;
        dual_fp_issue_count = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h3fc000b7); // lui x1,0x3fc00 (1.5)
        write_word(32'd4,  32'h40000137); // lui x2,0x40000 (2.0)
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, op_fp(7'b1111000, 5'd0, 5'd2, 3'b000, 5'd2));
                                              // fmv.w.x f2,x2
        write_word(32'd16, op_fp(7'b0001000, 5'd2, 5'd1, 3'b000, 5'd3));
                                              // fmul.s f3,f1,f2
        write_word(32'd20, op_fp(7'b0001000, 5'd2, 5'd2, 3'b000, 5'd5));
                                              // fmul.s f5,f2,f2
        write_word(32'd24, op_fp(7'b0000000, 5'd1, 5'd3, 3'b000, 5'd4));
                                              // fadd.s f4,f3,f1
        write_word(32'd28, op_fp(7'b0000000, 5'd1, 5'd5, 3'b000, 5'd6));
                                              // fadd.s f6,f5,f1

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (500) step_clk();

        f3_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[3];
        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        f5_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[5];
        f6_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[6];
        f3_value = u_dut.u_fp_prf_2w.regs[f3_preg];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];
        f5_value = u_dut.u_fp_prf_2w.regs[f5_preg];
        f6_value = u_dut.u_fp_prf_2w.regs[f6_preg];

        $display("[SUMMARY] fp_issues=%0d dual_fp_issue=%0d fp_completions=%0d f3=0x%08h f4=0x%08h f5=0x%08h f6=0x%08h fflags=0x%02h rob_empty=%0b",
                 fp_issue_count, dual_fp_issue_count, fp_complete_count,
                 f3_value, f4_value, f5_value, f6_value,
                 u_dut.fp_fflags, u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after pipelined FP program");
        check_ok(fp_issue_count >= 2 && fp_complete_count >= 2,
                 "multi-cycle FP pipelines accepted and completed operations");
        check_ok(dual_fp_issue_count >= 1,
                 "independent FP operations issued into both pipelines together");
        check_ok(f3_value == 32'h40400000,
                 "FMUL.S produces 3.0");
        check_ok(f4_value == 32'h40900000,
                 "dependent FADD.S wakes after pipelined FMUL.S");
        check_ok(f5_value == 32'h40800000,
                 "lane1 FMUL.S produces 4.0");
        check_ok(f6_value == 32'h40b00000,
                 "lane1-dependent FADD.S produces 5.5");
        check_ok(u_dut.fp_fflags == 5'b00000,
                 "exact pipelined operations leave fflags clear");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_pipeline_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_pipeline_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
