`timescale 1ns / 1ps

module tb_top_packet_backend_fp_flags_smoke;

    import defines_pkg::*;

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
    int errors;
    int wrong_path_fp_issue_count;

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

    task automatic reset_core;
    begin
        rst_n = 1'b0;
        load_en = 1'b0;
        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();
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
        .issue_valid(issue_valid),
        .issue_fu_type(issue_fu_type),
        .issue_pc(issue_pc),
        .issue_imm(issue_imm),
        .rob_head_valid(rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head_rd(rob_head_rd)
    );

    always @(posedge clk) begin
        if (rst_n &&
            ((u_dut.issue_if.valid && u_dut.issue_if.ready &&
              (u_dut.issue_if.data.datapath.pc == 32'd16)) ||
             (u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
              (u_dut.issue1_if.data.datapath.pc == 32'd16)))) begin
            wrong_path_fp_issue_count <= wrong_path_fp_issue_count + 1;
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        errors = 0;
        wrong_path_fp_issue_count = 0;

        reset_core();

        write_word(32'd0,  32'h7f8000b7); // lui x1,0x7f800
        write_word(32'd4,  32'h00108093); // addi x1,x1,1 (sNaN)
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, 32'h00000663); // beq x0,x0,+12
        write_word(32'd16, op_fp(7'b1010000, 5'd1, 5'd1, 3'b001, 5'd2));
                                              // flt.s x2,f1,f1 (wrong path)
        write_word(32'd20, 32'h06300193); // addi x3,x0,99 (wrong path)
        write_word(32'd24, 32'h00700213); // addi x4,x0,7
        write_word(32'd28, 32'b0);

        load_en = 1'b0;
        repeat (350) step_clk();

        check_ok(wrong_path_fp_issue_count > 0,
                 "signaling-NaN compare executes speculatively");
        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after wrong-path FP scenario");
        check_ok(u_dut.u_fp_csr.fflags == 5'b0,
                 "squashed FP exception does not update fflags");

        reset_core();

        write_word(32'd0,  32'h7f8000b7); // lui x1,0x7f800
        write_word(32'd4,  32'h00108093); // addi x1,x1,1 (sNaN)
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, op_fp(7'b1010000, 5'd1, 5'd1, 3'b010, 5'd2));
                                              // feq.s x2,f1,f1
        write_word(32'd16, 32'b0);
        write_word(32'd20, 32'b0);
        write_word(32'd24, 32'b0);
        write_word(32'd28, 32'b0);

        load_en = 1'b0;
        repeat (300) step_clk();

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after committed FP exception scenario");
        check_ok(u_dut.u_fp_csr.fflags == 5'b10000,
                 "retired signaling-NaN comparison commits NV");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_flags_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_flags_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
