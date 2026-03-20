`timescale 1ns/1ps

module tb_trace_25r;

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

    int fail_count;
    int issue_count;
    int wb_count;
    int commit_count;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic issue_valid_q;
    logic [1:0] issue_fu_type_q;
    logic [31:0] issue_pc_q;
    logic wb_valid_q;
    logic [PREG_W-1:0] wb_preg_q;
    logic [ROB_TAG_W-1:0] wb_tag_q;
    logic [31:0] wb_result_q;
    logic retire_valid_q;
    logic [4:0] retire_rd_q;

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
        issue_valid_q  <= issue_valid;
        issue_fu_type_q <= issue_fu_type;
        issue_pc_q     <= issue_pc;
        wb_valid_q     <= dut.wb_valid;
        wb_preg_q      <= dut.wb_preg;
        wb_tag_q       <= dut.wb_tag;
        wb_result_q    <= dut.wb_result;
        retire_valid_q <= dut.retire_valid;
        retire_rd_q    <= dut.rob_head.datapath.rd;
    end

    always @(negedge clk) begin
        if (rst_n && issue_valid_q) begin
            $display("[ISSUE] idx=%0d fu=%0d pc=%08h", issue_count, issue_fu_type_q, issue_pc_q);
            issue_count = issue_count + 1;
        end

        if (rst_n && wb_valid_q) begin
            $display("[WB] idx=%0d preg=%0d tag=%0d result=%08h", wb_count, wb_preg_q, wb_tag_q, wb_result_q);
            wb_count = wb_count + 1;
        end

        if (rst_n && retire_valid_q) begin
            $display("[COMMIT] idx=%0d rd=x%0d", commit_count, retire_rd_q);
            commit_count = commit_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;
        issue_count = 0;
        wb_count = 0;
        commit_count = 0;
        issue_valid_q = 1'b0;
        issue_fu_type_q = '0;
        issue_pc_q = '0;
        wb_valid_q = 1'b0;
        wb_preg_q = '0;
        wb_tag_q = '0;
        wb_result_q = '0;
        retire_valid_q = 1'b0;
        retire_rd_q = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // 25r.txt
        write_word(32'd0,  32'h123452B7);
        write_word(32'd4,  32'h6782E293);
        write_word(32'd8,  32'h00ABC337);
        write_word(32'd12, 32'hDEF36313);
        write_word(32'd16, 32'h0062F3B3);
        write_word(32'd20, 32'h40628E33);
        write_word(32'd24, 32'h00D00F13);
        write_word(32'd28, 32'h41EE5EB3);
        write_word(32'd32, 32'h400EBF93);
        write_word(32'd36, 32'h0FF00413);
        write_word(32'd40, 32'h008EFBB3);
        write_word(32'd44, 32'h001B8B93);
        write_word(32'd48, 32'h100BEB93);
        write_word(32'd52, 32'h000084B7);
        write_word(32'd56, 32'h3C04E493);
        write_word(32'd60, 32'h41748C33);
        write_word(32'd64, 32'h41EC5C33);
        write_word(32'd68, 32'h800C3C93);
        write_word(32'd72, 32'h009C7533);
        write_word(32'd76, 32'h13579937);
        write_word(32'd80, 32'h24696913);
        write_word(32'd84, 32'h005975B3);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        a0_preg  = dut.u_rename.u_rat.rat[10];
        a1_preg  = dut.u_rename.u_rat.rat[11];
        a0_value = dut.u_prf.regs[a0_preg];
        a1_value = dut.u_prf.regs[a1_preg];

        $display("[SUMMARY] issue_count=%0d wb_count=%0d commit_count=%0d a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) rob_empty=%0b rob_head_valid=%0b rob_head_complete=%0b rob_head_rd=%0d",
                 issue_count, wb_count, commit_count,
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 dut.u_dispatch.u_rob.empty,
                 dut.rob_head_valid, dut.rob_head_complete, dut.rob_head_rd);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, "ROB drained after 25r program");
        check_ok(a0_value == 32'h00000000, "25r a0(x10) matches expected 0");
        check_ok(a1_value == 32'h12141240, "25r a1(x11) matches expected 303305280");

        if (fail_count == 0) begin
            $display("==== tb_trace_25r PASS ====");
        end else begin
            $display("==== tb_trace_25r FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
