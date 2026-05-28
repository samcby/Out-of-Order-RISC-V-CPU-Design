`timescale 1ns/1ps

module tb_top_phase3;

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

            case (issue_count)
                0: begin
                    check_ok(issue_fu_type_q == FU_ALU, "issue0 fu=ALU");
                    check_ok(issue_pc_q == 32'd0, "issue0 pc=0");
                    check_ok(issue_imm_q == 32'd5, "issue0 imm=5");
                end
                1: begin
                    check_ok(issue_fu_type_q == FU_ALU, "issue1 fu=ALU");
                    check_ok(issue_pc_q == 32'd4, "issue1 pc=4");
                    check_ok(issue_imm_q == 32'h12345000, "issue1 imm=LUI");
                end
                2: begin
                    check_ok(issue_fu_type_q == FU_ALU, "issue2 fu=ALU");
                    check_ok(issue_pc_q == 32'd8, "issue2 pc=8");
                    check_ok(issue_imm_q == 32'd7, "issue2 imm=7");
                end
                3: begin
                    check_ok(issue_fu_type_q == FU_MEM, "issue3 fu=MEM");
                    check_ok(issue_pc_q == 32'd12, "issue3 pc=12");
                    check_ok(issue_imm_q == 32'd0, "issue3 imm=0");
                end
                default: begin
                    $display("[FAIL] unexpected extra issue");
                    fail_count = fail_count + 1;
                end
            endcase

            issue_count = issue_count + 1;
        end

        if (rst_n && wb_valid_q) begin
            $display("[WB] idx=%0d preg=%0d tag=%0d result=%h",
                     wb_count, wb_preg_q, wb_tag_q, wb_result_q);

            case (wb_count)
                0: check_ok(wb_result_q == 32'd5, "wb0 result=5");
                1: check_ok(wb_result_q == 32'h12345000, "wb1 result=LUI");
                2: check_ok(wb_result_q == 32'd7, "wb2 result=7");
                3: check_ok(wb_result_q == 32'd0, "wb3 result=0 from load");
                default: begin
                    $display("[FAIL] unexpected extra wb");
                    fail_count = fail_count + 1;
                end
            endcase

            wb_count = wb_count + 1;
        end

        if (rst_n && retire_valid_q) begin
            $display("[RETIRE] idx=%0d preg=%0d", retire_count, retire_preg_q);
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

        // Program:
        // addi x1, x0, 5
        // lui  x3, 0x12345
        // addi x4, x0, 7
        // lw   x5, 0(x0)
        write_word(32'd0,  32'h00500093);
        write_word(32'd4,  32'h123451B7);
        write_word(32'd8,  32'h00700213);
        write_word(32'd12, 32'h00002283);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (50) step_clk;

        $display("[SUMMARY] issue_count=%0d wb_count=%0d retire_count=%0d rob_head_valid=%0b rob_head_complete=%0b rob_head_rd=%0d",
                 issue_count, wb_count, retire_count,
                 rob_head_valid, rob_head_complete, rob_head_rd);

        check_ok(issue_count == 4, "saw 4 issue events");
        check_ok(wb_count == 4, "saw 4 writeback events");
        check_ok(retire_count >= 1, "saw at least 1 retire event");
        check_ok(rob_head_valid == 1'b1, "rob head valid still asserted or advanced to valid entry");

        if (fail_count == 0) begin
            $display("==== tb_top_phase3 PASS ====");
        end else begin
            $display("==== tb_top_phase3 FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
