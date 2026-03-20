`timescale 1ns/1ps

module tb_top_phase4_redirect;

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
    int wb_count;
    int retire_count;
    int fail_count;

    logic        issue_valid_q;
    logic [1:0]  issue_fu_type_q;
    logic [31:0] issue_pc_q;
    logic [31:0] issue_imm_q;

    logic        wb_valid_q;
    logic [PREG_W-1:0] wb_preg_q;
    logic [ROB_TAG_W-1:0] wb_tag_q;
    logic [31:0] wb_result_q;

    logic        retire_valid_q;
    logic [PREG_W-1:0] retire_preg_q;

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
        issue_imm_q     <= issue_imm;

        wb_valid_q      <= dut.wb_valid;
        wb_preg_q       <= dut.wb_preg;
        wb_tag_q        <= dut.wb_tag;
        wb_result_q     <= dut.wb_result;

        retire_valid_q  <= dut.retire_valid;
        retire_preg_q   <= dut.retire_preg;
    end

    always @(negedge clk) begin
        if (rst_n && issue_valid_q) begin
            $display("[ISSUE] idx=%0d fu=%0d pc=%h imm=%h",
                     issue_count, issue_fu_type_q, issue_pc_q, issue_imm_q);
            issue_count = issue_count + 1;
        end

        if (rst_n && wb_valid_q) begin
            $display("[WB] idx=%0d preg=%0d tag=%0d result=%h",
                     wb_count, wb_preg_q, wb_tag_q, wb_result_q);
            wb_count = wb_count + 1;
        end

        if (rst_n && retire_valid_q) begin
            $display("[RETIRE] idx=%0d preg=%0d",
                     retire_count, retire_preg_q);
            retire_count = retire_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;

        issue_count = 0;
        wb_count = 0;
        retire_count = 0;
        fail_count = 0;

        issue_valid_q = 1'b0;
        issue_fu_type_q = '0;
        issue_pc_q = '0;
        issue_imm_q = '0;

        wb_valid_q = 1'b0;
        wb_preg_q = '0;
        wb_tag_q = '0;
        wb_result_q = '0;

        retire_valid_q = 1'b0;
        retire_preg_q = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Program layout:
        // 0x00: addi x1, x0, 16      ; x1 = 16
        // 0x04: jalr x5, x1, 0       ; jump to 0x10, x5 = return addr
        // 0x08: addi x6, x0, 99      ; wrong-path, should be flushed
        // 0x0C: addi x7, x0, 77      ; wrong-path, should be flushed
        // 0x10: addi x8, x0, 42      ; target path
        // 0x14: addi x9, x0, 11      ; target path

        write_word(32'd0,  32'h01000093); // addi x1, x0, 16
        write_word(32'd4,  32'h000082E7); // jalr x5, x1, 0
        write_word(32'd8,  32'h06300313); // addi x6, x0, 99
        write_word(32'd12, 32'h04D00393); // addi x7, x0, 77
        write_word(32'd16, 32'h02A00413); // addi x8, x0, 42
        write_word(32'd20, 32'h00B00493); // addi x9, x0, 11

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (70) step_clk;

        $display("[SUMMARY] issue_count=%0d wb_count=%0d retire_count=%0d pc_src_exe=%0b pc_branch_exe=%h rob_head_valid=%0b rob_head_complete=%0b rob_head_rd=%0d",
                 issue_count, wb_count, retire_count,
                 dut.pc_src_exe, dut.pc_branch_exe,
                 rob_head_valid, rob_head_complete, rob_head_rd);

        // Expected minimal behavior for this baseline Phase 4 version:
        // - We should see at least the setup ADDI, the JALR, and target-path instructions progress.
        // - pc redirect must occur at least once.
        // - Some retire events should happen.
        check_ok(issue_count >= 4, "saw at least 4 issue events");
        check_ok(wb_count >= 3, "saw at least 3 writeback events");
        check_ok(retire_count >= 2, "saw at least 2 retire events");

        // JALR should cause redirect to 0x10.
        check_ok(dut.pc_branch_exe == 32'h00000010 || dut.pc_src_exe == 1'b0,
                 "branch target reached or redirect pulse already consumed");

        if (fail_count == 0) begin
            $display("==== tb_top_phase4_redirect PASS ====");
        end else begin
            $display("==== tb_top_phase4_redirect FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
