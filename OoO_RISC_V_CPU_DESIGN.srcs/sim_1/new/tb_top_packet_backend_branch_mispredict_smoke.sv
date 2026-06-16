`timescale 1ns/1ps

module tb_top_packet_backend_branch_mispredict_smoke;

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
    int branch_redirect_count;
    int lane1_branch_issue_count;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t x12_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] x12_value;

    top_packet_backend dut (
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            branch_redirect_count = 0;
            lane1_branch_issue_count = 0;
        end else begin
            #1;
            if (dut.issue_if.valid && dut.issue_if.ready &&
                (dut.issue_if.data.fu_sel == FU_BRANCH) &&
                (dut.issue_if.data.datapath.pc == 32'd4)) begin
                lane1_branch_issue_count = lane1_branch_issue_count + 1;
            end

            if (dut.pc_src_exe) begin
                branch_redirect_count = branch_redirect_count + 1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h00100093); // addi x1,x0,1
        write_word(32'd4,  32'h00108863); // beq  x1,x1,+16, taken but initially predicted not taken
        write_word(32'd8,  32'h01100513); // wrong path: addi x10,x0,0x11
        write_word(32'd12, 32'h02200593); // wrong path: addi x11,x0,0x22
        write_word(32'd16, 32'h03300613); // wrong path: addi x12,x0,0x33
        write_word(32'd20, 32'h05500513); // target: addi x10,x0,0x55
        write_word(32'd24, 32'h06600593); // target: addi x11,x0,0x66
        write_word(32'd28, 32'h00000013); // nop
        write_word(32'd32, 32'h00000013); // nop

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (280) step_clk;

        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        x12_preg = dut.u_rename_packet.u_rat_2w.rat[12];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        x12_value = dut.u_prf_2w.regs[x12_preg];

        $display("[SUMMARY] lane1_branch_issue=%0d redirects=%0d a0_preg=%0d a0=0x%08h a1_preg=%0d a1=0x%08h x12_preg=%0d x12=0x%08h rob_empty=%0b",
                 lane1_branch_issue_count,
                 branch_redirect_count,
                 a0_preg, a0_value,
                 a1_preg, a1_value,
                 x12_preg, x12_value,
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(lane1_branch_issue_count >= 1,
                 "packet backend issued branch that entered through fetch/decode lane1");
        check_ok(branch_redirect_count >= 1,
                 "packet backend observed branch redirect on taken mispredict");
        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 "packet backend ROB drained after branch mispredict smoke program");
        check_ok(a0_value == 32'h00000055,
                 "branch target path wrote a0(x10)");
        check_ok(a1_value == 32'h00000066,
                 "branch target path wrote a1(x11)");
        check_ok(x12_value == 32'h00000000,
                 "wrong-path x12 write was squashed from architectural state");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_branch_mispredict_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_branch_mispredict_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
