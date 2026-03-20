`timescale 1ns/1ps

module tb_top_phase5_btb;

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

    int issue_count;
    int branch_issue_count;
    int wrong_path_issue_count;
    int fail_count;

    logic        issue_valid_q;
    logic [1:0]  issue_fu_type_q;
    logic [31:0] issue_pc_q;

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

    always @(posedge clk) begin
        issue_valid_q   <= issue_valid;
        issue_fu_type_q <= issue_fu_type;
        issue_pc_q      <= issue_pc;
    end

    always @(negedge clk) begin
        if (rst_n && issue_valid_q) begin
            $display("[ISSUE] idx=%0d fu=%0d pc=%h",
                     issue_count, issue_fu_type_q, issue_pc_q);
            issue_count = issue_count + 1;

            if (issue_pc_q == 32'h00000000) begin
                branch_issue_count = branch_issue_count + 1;
            end

            if (issue_pc_q == 32'h00000004) begin
                wrong_path_issue_count = wrong_path_issue_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;

        issue_count = 0;
        branch_issue_count = 0;
        wrong_path_issue_count = 0;
        fail_count = 0;

        issue_valid_q = 1'b0;
        issue_fu_type_q = '0;
        issue_pc_q = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // 0x00: beq x0, x0, 16
        // 0x04: addi x2, x0, 1      wrong-path, cold miss only
        // 0x08: nop
        // 0x10: jal x0, -16         loop back to branch
        write_word(32'd0,  32'h00000863);
        write_word(32'd4,  32'h00100113);
        write_word(32'd8,  32'h00000013);
        write_word(32'd16, 32'hFF1FF06F);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (140) step_clk;

        $display("[SUMMARY] issue_count=%0d branch_issue_count=%0d wrong_path_issue_count=%0d btb_valid0=%0b btb_target0=%h",
                 issue_count, branch_issue_count, wrong_path_issue_count,
                 dut.u_fetch.btb_valid[0], dut.u_fetch.btb_target[0]);

        check_ok(branch_issue_count >= 3, "branch PC re-fetched multiple times");
        check_ok(wrong_path_issue_count <= 1, "branch wrong-path appears at most once");
        check_ok(dut.u_fetch.btb_valid[0] == 1'b1, "BTB entry for branch PC trained");
        check_ok(dut.u_fetch.btb_target[0] == 32'h00000010, "BTB target stored correctly");

        if (fail_count == 0) begin
            $display("==== tb_top_phase5_btb PASS ====");
        end else begin
            $display("==== tb_top_phase5_btb FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
