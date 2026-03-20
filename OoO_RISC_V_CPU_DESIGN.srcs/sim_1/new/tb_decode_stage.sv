`timescale 1ns/1ps

module tb_decode_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    pip_if #(fetch_decode_t) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_t)   out_if (.clk(clk), .rst_n(rst_n));

    decode_stage dut (
        .in_if (in_if.consumer),
        .out_if(out_if.producer)
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
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic drive_instr;
        input [31:0] pc_in;
        input [31:0] instr_in;
    begin
        in_if.valid   = 1'b1;
        in_if.data.pc = pc_in;
        in_if.data.instr = instr_in;
        #1;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        in_if.valid = 1'b0;
        in_if.data  = '0;
        out_if.ready = 1'b1;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // ADDI x1, x0, 5 => 0x00500093
        drive_instr(32'd0, 32'h00500093);
        check_ok(out_if.valid == 1'b1, "ADDI valid");
        check_ok(out_if.data.datapath.rs1 == 5'd0, "ADDI rs1");
        check_ok(out_if.data.datapath.rd  == 5'd1, "ADDI rd");
        check_ok(out_if.data.datapath.imm == 32'd5, "ADDI imm");
        check_ok(out_if.data.control_signal.rs_control_signal.fu_type == FU_ALU, "ADDI fu_type ALU");
        check_ok(out_if.data.control_signal.rs_control_signal.rename == 1'b1, "ADDI rename");
        check_ok(out_if.data.control_signal.rs_control_signal.alu_control_signal.alu_src == 1'b1, "ADDI alu_src");
        check_ok(out_if.data.control_signal.rs_control_signal.alu_control_signal.alu_op == ALU_ADD, "ADDI alu_op");

        // LW x2, 8(x1) => 0x0080A103
        drive_instr(32'd4, 32'h0080A103);
        check_ok(out_if.data.datapath.rs1 == 5'd1, "LW rs1");
        check_ok(out_if.data.datapath.rd  == 5'd2, "LW rd");
        check_ok(out_if.data.datapath.imm == 32'd8, "LW imm");
        check_ok(out_if.data.control_signal.rs_control_signal.fu_type == FU_MEM, "LW fu_type MEM");
        check_ok(out_if.data.control_signal.rs_control_signal.rename == 1'b1, "LW rename");
        check_ok(out_if.data.control_signal.rs_control_signal.lsu_control_signal.mem_read == 1'b1, "LW mem_read");

        // BNE x1, x2, 16 => 0x00209863
        drive_instr(32'd8, 32'h00209863);
        check_ok(out_if.data.datapath.rs1 == 5'd1, "BNE rs1");
        check_ok(out_if.data.datapath.rs2 == 5'd2, "BNE rs2");
        check_ok(out_if.data.datapath.imm == 32'd16, "BNE imm");
        check_ok(out_if.data.control_signal.rs_control_signal.fu_type == FU_BRANCH, "BNE fu_type BRANCH");
        check_ok(out_if.data.control_signal.rs_control_signal.rename == 1'b0, "BNE no rename");
        check_ok(out_if.data.control_signal.rs_control_signal.branch_control_signal.branch == 1'b1, "BNE branch bit");

        // JALR x4, x1, 12 => 0x00C08267
        drive_instr(32'd12, 32'h00C08267);
        check_ok(out_if.data.datapath.rs1 == 5'd1, "JALR rs1");
        check_ok(out_if.data.datapath.rd  == 5'd4, "JALR rd");
        check_ok(out_if.data.datapath.imm == 32'd12, "JALR imm");
        check_ok(out_if.data.control_signal.rs_control_signal.fu_type == FU_BRANCH, "JALR fu_type BRANCH");
        check_ok(out_if.data.control_signal.rs_control_signal.rename == 1'b1, "JALR rename");
        check_ok(out_if.data.control_signal.rs_control_signal.branch_control_signal.jump == 1'b1, "JALR jump bit");

        // LUI x3, 0x12345 => 0x123451B7
        drive_instr(32'd16, 32'h123451B7);
        check_ok(out_if.data.datapath.rd  == 5'd3, "LUI rd");
        check_ok(out_if.data.datapath.imm == 32'h12345000, "LUI imm");
        check_ok(out_if.data.control_signal.rs_control_signal.fu_type == FU_ALU, "LUI fu_type ALU");
        check_ok(out_if.data.control_signal.rs_control_signal.alu_control_signal.alu_op == ALU_LUI, "LUI alu_op");

        $display("==== tb_decode_stage PASS ====");
        $finish;
    end

endmodule
