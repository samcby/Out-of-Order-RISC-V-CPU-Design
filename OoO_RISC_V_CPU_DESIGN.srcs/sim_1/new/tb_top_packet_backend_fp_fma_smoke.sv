`timescale 1ns / 1ps

module tb_top_packet_backend_fp_fma_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    fp_preg_t f4_preg;
    fp_preg_t f5_preg;
    fp_preg_t f6_preg;
    fp_preg_t f7_preg;
    fp_preg_t f8_preg;
    logic [31:0] f4_value;
    logic [31:0] f5_value;
    logic [31:0] f6_value;
    logic [31:0] f7_value;
    logic [31:0] f8_value;
    int errors;
    int fused_issue_count;
    int dual_fused_issue_count;

    always #5 clk = ~clk;

    function automatic logic [31:0] r4_fp(
        input logic [6:0] opcode,
        input logic [4:0] rs3,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] rm,
        input logic [4:0] rd
    );
    begin
        r4_fp = {rs3, 2'b00, rs2, rs1, rm, rd, opcode};
    end
    endfunction

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

    function automatic logic is_fused(input logic [4:0] operation);
    begin
        is_fused = (operation == FP_OP_MADD) ||
                   (operation == FP_OP_MSUB) ||
                   (operation == FP_OP_NMSUB) ||
                   (operation == FP_OP_NMADD);
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
            if (u_dut.issue_if.valid && u_dut.issue_if.ready &&
                is_fused(u_dut.issue_if.data.control_signal.alu.fp_op)) begin
                fused_issue_count = fused_issue_count + 1;
            end
            if (u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                is_fused(u_dut.issue1_if.data.control_signal.alu.fp_op)) begin
                fused_issue_count = fused_issue_count + 1;
            end
            if (u_dut.issue_if.valid && u_dut.issue_if.ready &&
                u_dut.issue1_if.valid && u_dut.issue1_if.ready &&
                is_fused(u_dut.issue_if.data.control_signal.alu.fp_op) &&
                is_fused(u_dut.issue1_if.data.control_signal.alu.fp_op)) begin
                dual_fused_issue_count = dual_fused_issue_count + 1;
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
        fused_issue_count = 0;
        dual_fused_issue_count = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h3fc000b7); // lui x1,0x3fc00 (1.5)
        write_word(32'd4,  32'h40000137); // lui x2,0x40000 (2.0)
        write_word(32'd8,  32'h3f0001b7); // lui x3,0x3f000 (0.5)
        write_word(32'd12, op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd16, op_fp(7'b1111000, 5'd0, 5'd2, 3'b000, 5'd2));
                                              // fmv.w.x f2,x2
        write_word(32'd20, op_fp(7'b1111000, 5'd0, 5'd3, 3'b000, 5'd3));
                                              // fmv.w.x f3,x3
        write_word(32'd24, r4_fp(7'b1000011, 5'd3, 5'd2, 5'd1,
                                 3'b000, 5'd4)); // fmadd.s f4,f1,f2,f3
        write_word(32'd28, r4_fp(7'b1000111, 5'd3, 5'd2, 5'd1,
                                 3'b000, 5'd5)); // fmsub.s f5,f1,f2,f3
        write_word(32'd32, r4_fp(7'b1001011, 5'd3, 5'd2, 5'd1,
                                 3'b000, 5'd6)); // fnmsub.s f6,f1,f2,f3
        write_word(32'd36, r4_fp(7'b1001111, 5'd3, 5'd2, 5'd1,
                                 3'b000, 5'd7)); // fnmadd.s f7,f1,f2,f3
        write_word(32'd40, r4_fp(7'b1000011, 5'd5, 5'd2, 5'd4,
                                 3'b000, 5'd8)); // fmadd.s f8,f4,f2,f5

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (600) step_clk();

        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        f5_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[5];
        f6_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[6];
        f7_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[7];
        f8_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[8];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];
        f5_value = u_dut.u_fp_prf_2w.regs[f5_preg];
        f6_value = u_dut.u_fp_prf_2w.regs[f6_preg];
        f7_value = u_dut.u_fp_prf_2w.regs[f7_preg];
        f8_value = u_dut.u_fp_prf_2w.regs[f8_preg];

        $display("[SUMMARY] fused_issues=%0d dual_fused=%0d f4=0x%08h f5=0x%08h f6=0x%08h f7=0x%08h f8=0x%08h fflags=0x%02h rob_empty=%0b",
                 fused_issue_count, dual_fused_issue_count,
                 f4_value, f5_value, f6_value, f7_value, f8_value,
                 u_dut.fp_fflags,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after fused-operation program");
        check_ok(fused_issue_count >= 5,
                 "all four fused forms issue through the FP pipelines");
        check_ok(dual_fused_issue_count >= 1,
                 "independent fused operations use both FP pipelines");
        check_ok(f4_value == 32'h40600000,
                 "FMADD.S produces 3.5");
        check_ok(f5_value == 32'h40200000,
                 "FMSUB.S produces 2.5");
        check_ok(f6_value == 32'hc0200000,
                 "FNMSUB.S produces -2.5");
        check_ok(f7_value == 32'hc0600000,
                 "FNMADD.S produces -3.5");
        check_ok(f8_value == 32'h41180000,
                 "dependent FMA wakes on both rs1 and rs3 results");
        check_ok(u_dut.fp_fflags == 5'b00000,
                 "exact fused operations leave fflags clear");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_fma_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_fma_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
