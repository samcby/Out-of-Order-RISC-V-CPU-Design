`timescale 1ns / 1ps

module tb_top_packet_backend_fp_add_sub_smoke;

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
    fp_preg_t f3_preg;
    fp_preg_t f4_preg;
    preg_t x5_preg;
    preg_t x6_preg;
    preg_t x7_preg;
    logic [31:0] f3_value;
    logic [31:0] f4_value;
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

    function automatic logic [31:0] csr_instr(
        input logic [11:0] csr_addr,
        input logic [4:0] rs1_or_zimm,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
    begin
        csr_instr = {csr_addr, rs1_or_zimm, funct3, rd, 7'b1110011};
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

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        write_word(32'd0,  32'h3f8000b7); // lui x1,0x3f800 (+1.0)
        write_word(32'd4,  32'h33800137); // lui x2,0x33800 (2^-24)
        write_word(32'd8,  op_fp(7'b1111000, 5'd0, 5'd1, 3'b000, 5'd1));
                                              // fmv.w.x f1,x1
        write_word(32'd12, op_fp(7'b1111000, 5'd0, 5'd2, 3'b000, 5'd2));
                                              // fmv.w.x f2,x2
        write_word(32'd16, csr_instr(CSR_FRM, 5'd3, 3'b101, 5'd0));
                                              // csrrwi x0,frm,RUP
        write_word(32'd20, op_fp(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3));
                                              // fadd.s f3,f1,f2,dyn
        write_word(32'd24, op_fp(7'b0000100, 5'd1, 5'd3, 3'b000, 5'd4));
                                              // fsub.s f4,f3,f1,rne
        write_word(32'd28, csr_instr(CSR_FFLAGS, 5'd0, 3'b010, 5'd5));
                                              // csrrs x5,fflags,x0
        write_word(32'd32, csr_instr(CSR_FRM, 5'd0, 3'b010, 5'd6));
                                              // csrrs x6,frm,x0
        write_word(32'd36, csr_instr(CSR_FCSR, 5'd0, 3'b010, 5'd7));
                                              // csrrs x7,fcsr,x0

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (500) step_clk();

        f3_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[3];
        f4_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[4];
        x5_preg = u_dut.u_rename_packet.u_rat_2w.rat[5];
        x6_preg = u_dut.u_rename_packet.u_rat_2w.rat[6];
        x7_preg = u_dut.u_rename_packet.u_rat_2w.rat[7];
        f3_value = u_dut.u_fp_prf_2w.regs[f3_preg];
        f4_value = u_dut.u_fp_prf_2w.regs[f4_preg];
        x5_value = u_dut.u_prf_2w.regs[x5_preg];
        x6_value = u_dut.u_prf_2w.regs[x6_preg];
        x7_value = u_dut.u_prf_2w.regs[x7_preg];

        $display("[SUMMARY] f3=0x%08h f4=0x%08h fflags=0x%02h frm=%0d fcsr=0x%02h x5=0x%08h x6=0x%08h x7=0x%08h rob_empty=%0b",
                 f3_value, f4_value, u_dut.fp_fflags, u_dut.fp_frm,
                 u_dut.fp_fcsr, x5_value, x6_value, x7_value,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);
        if (!u_dut.u_dispatch_packet.u_rob_2w.empty) begin
            $display("[STATE] head_tag=%0d head_complete=%0b csr_pending=%0b csr_tag=%0d alu0=%0b/%0b tag=%0d csr=%0b alu1=%0b/%0b tag=%0d csr=%0b issue0=%0b/%0b",
                     u_dut.rob_head.datapath.rob_tag,
                     u_dut.rob_head.datapath.complete,
                     u_dut.u_dispatch_packet.csr_pending_q,
                     u_dut.u_dispatch_packet.csr_pending_tag_q,
                     u_dut.u_dispatch_packet.alu_out_if.valid,
                     u_dut.u_dispatch_packet.alu_out_if.ready,
                     u_dut.u_dispatch_packet.alu_out_if.data.datapath.rob_tag,
                     u_dut.u_dispatch_packet.alu_out_if.data.control_signal.csr_en,
                     u_dut.u_dispatch_packet.alu_out1_if.valid,
                     u_dut.u_dispatch_packet.alu_out1_if.ready,
                     u_dut.u_dispatch_packet.alu_out1_if.data.datapath.rob_tag,
                     u_dut.u_dispatch_packet.alu_out1_if.data.control_signal.csr_en,
                     u_dut.issue_if.valid, u_dut.issue_if.ready);
            $display("[ARB] head_valid=%b head_tag=%0d alu_is_csr=%b csr_ready=%b sel0_alu=%b",
                     u_dut.u_dispatch_packet.u_issue_packet_arbiter.rob_head_valid,
                     u_dut.u_dispatch_packet.u_issue_packet_arbiter.rob_head_tag,
                     u_dut.u_dispatch_packet.u_issue_packet_arbiter.alu_is_csr,
                     u_dut.u_dispatch_packet.u_issue_packet_arbiter.alu_csr_can_issue,
                     u_dut.u_dispatch_packet.u_issue_packet_arbiter.sel0_alu);
        end

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "ROB drains after FP add/sub and CSR program");
        check_ok(f3_value == 32'h3f800001,
                 "dynamic RUP rounds FADD.S upward");
        check_ok(f4_value == 32'h34000000,
                 "FSUB.S preserves the exact one-ULP difference");
        check_ok(u_dut.fp_fflags == 5'b00001,
                 "inexact FADD.S commits NX");
        check_ok(u_dut.fp_frm == 3'b011,
                 "CSRRWI updates frm to RUP");
        check_ok(x5_value == 32'h00000001,
                 "CSRRS reads committed fflags");
        check_ok(x6_value == 32'h00000003,
                 "CSRRS reads frm");
        check_ok(x7_value == 32'h00000061,
                 "CSRRS reads the combined fcsr value");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_add_sub_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_add_sub_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
