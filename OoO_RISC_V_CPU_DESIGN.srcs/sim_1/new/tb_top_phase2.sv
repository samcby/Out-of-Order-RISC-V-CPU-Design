`timescale 1ns/1ps

module tb_top_phase2;

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
    
    logic        issue_valid_q;
    logic [1:0]  issue_fu_type_q;
    logic [31:0] issue_pc_q;
    logic [31:0] issue_imm_q;


    logic        rob_head_valid;
    logic        rob_head_complete;
    logic [4:0]  rob_head_rd;

    int issue_count;
    int fail_count;
    int cycle_count;
    bit released_fetch;

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

    task automatic check_issue_event;
        input int idx;
    begin
        case (idx)
            0: begin
                check_ok(issue_fu_type == FU_ALU,       "issue0 fu=ALU");
                check_ok(issue_pc      == 32'd0,        "issue0 pc=0");
                check_ok(issue_imm     == 32'd5,        "issue0 imm=5");
            end
            1: begin
                check_ok(issue_fu_type == FU_ALU,       "issue1 fu=ALU");
                check_ok(issue_pc      == 32'd4,        "issue1 pc=4");
                check_ok(issue_imm     == 32'h12345000, "issue1 imm=LUI imm");
            end
            2: begin
                check_ok(issue_fu_type == FU_ALU,       "issue2 fu=ALU");
                check_ok(issue_pc      == 32'd8,        "issue2 pc=8");
                check_ok(issue_imm     == 32'd7,        "issue2 imm=7");
            end
            3: begin
                check_ok(issue_fu_type == FU_MEM,       "issue3 fu=MEM");
                check_ok(issue_pc      == 32'd12,       "issue3 pc=12");
                check_ok(issue_imm     == 32'd0,        "issue3 imm=0");
            end
            default: begin
                $display("[FAIL] unexpected extra issue event idx=%0d", idx);
                fail_count = fail_count + 1;
            end
        endcase
    end
    endtask

    always @(posedge clk) begin
        if (rst_n && released_fetch) begin
            cycle_count <= cycle_count + 1;
            #1;
            if (cycle_count < 25) begin
                $display("[DBG] cyc=%0d fd(v/r)=%0b/%0b fds=%0b/%0b dr=%0b/%0b drs=%0b/%0b rd=%0b/%0b rds=%0b/%0b issue=%0b fu=%0d pc=%h imm=%h s1r=%0b s2r=%0b alu_in=%0b alu_out=%0b lsu_in=%0b lsu_out=%0b rob_head_v=%0b rd=%0d",
                    cycle_count,
                    dut.pipe_fd.valid,   dut.pipe_fd.ready,
                    dut.pipe_fd_s.valid, dut.pipe_fd_s.ready,
                    dut.pipe_dr.valid,   dut.pipe_dr.ready,
                    dut.pipe_dr_s.valid, dut.pipe_dr_s.ready,
                    dut.pipe_rd.valid,   dut.pipe_rd.ready,
                    dut.pipe_rd_s.valid, dut.pipe_rd_s.ready,
                    issue_valid, issue_fu_type, issue_pc, issue_imm,
                    dut.src1_ready, dut.src2_ready,
                    dut.u_dispatch.alu_in_if.valid,
                    dut.u_dispatch.alu_out_if.valid,
                    dut.u_dispatch.lsu_in_if.valid,
                    dut.u_dispatch.lsu_out_if.valid,
                    rob_head_valid, rob_head_rd
                );
            end
        end
    end

    always @(posedge clk) begin
        issue_valid_q   <= issue_valid;
        issue_fu_type_q <= issue_fu_type;
        issue_pc_q      <= issue_pc;
        issue_imm_q     <= issue_imm;
    end

    always @(negedge clk) begin
        if (rst_n && issue_valid_q) begin
            $display("[ISSUE] t=%0t idx=%0d fu=%0d pc=%h imm=%h",
                     $time, issue_count, issue_fu_type_q, issue_pc_q, issue_imm_q);

            case (issue_count)
                0: begin
                    check_ok(issue_fu_type_q == FU_ALU,       "issue0 fu=ALU");
                    check_ok(issue_pc_q      == 32'd0,        "issue0 pc=0");
                    check_ok(issue_imm_q     == 32'd5,        "issue0 imm=5");
                end
                1: begin
                    check_ok(issue_fu_type_q == FU_ALU,       "issue1 fu=ALU");
                    check_ok(issue_pc_q      == 32'd4,        "issue1 pc=4");
                    check_ok(issue_imm_q     == 32'h12345000, "issue1 imm=LUI imm");
                end
                2: begin
                    check_ok(issue_fu_type_q == FU_ALU,       "issue2 fu=ALU");
                    check_ok(issue_pc_q      == 32'd8,        "issue2 pc=8");
                    check_ok(issue_imm_q     == 32'd7,        "issue2 imm=7");
                end
                3: begin
                    check_ok(issue_fu_type_q == FU_MEM,       "issue3 fu=MEM");
                    check_ok(issue_pc_q      == 32'd12,       "issue3 pc=12");
                    check_ok(issue_imm_q     == 32'd0,        "issue3 imm=0");
                end
                default: begin
                    $display("[FAIL] unexpected extra issue event idx=%0d", issue_count);
                    fail_count = fail_count + 1;
                end
            endcase

            issue_count = issue_count + 1;
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        issue_count = 0;
        fail_count = 0;
        cycle_count = 0;
        released_fetch = 1'b0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h00500093); // addi x1, x0, 5
        write_word(32'd4,  32'h123451B7); // lui  x3, 0x12345
        write_word(32'd8,  32'h00700213); // addi x4, x0, 7
        write_word(32'd12, 32'h00002283); // lw   x5, 0(x0)

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        released_fetch = 1'b1;

        repeat (35) step_clk;

        $display("[SUMMARY] issue_count=%0d fail_count=%0d rob_head_valid=%0b rob_head_complete=%0b rob_head_rd=%0d",
                 issue_count, fail_count, rob_head_valid, rob_head_complete, rob_head_rd);

        check_ok(issue_count == 4, "exactly 4 issue events observed");
        check_ok(rob_head_valid == 1'b1, "rob head valid asserted");
        check_ok(rob_head_complete == 1'b0, "rob head not complete yet");
        check_ok(rob_head_rd == 5'd1, "rob head rd is first instruction destination x1");

        if (fail_count == 0) begin
            $display("==== tb_top_phase2 PASS ====");
        end else begin
            $display("==== tb_top_phase2 FAIL (%0d errors) ====", fail_count);
        end
        $finish;
    end

endmodule
