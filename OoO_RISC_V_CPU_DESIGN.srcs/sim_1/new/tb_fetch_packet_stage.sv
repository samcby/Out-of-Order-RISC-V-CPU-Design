`timescale 1ns/1ps

module tb_fetch_packet_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    logic        load_en;
    logic [31:0] load_addr;
    logic [7:0]  load_instr_byte;
    logic        pc_src;
    logic [31:0] pc_branch;
    logic        bp_update_valid;
    logic [31:0] bp_update_pc;
    logic        bp_update_taken;
    logic        bp_update_is_jalr;
    logic [31:0] bp_update_target;

    pip_if #(fetch_decode_packet_t) fetch_if (.clk(clk), .rst_n(rst_n));

    fetch_packet_stage dut (
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        .pc_src         (pc_src),
        .pc_branch      (pc_branch),
        .bp_update_valid(bp_update_valid),
        .bp_update_pc   (bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_is_jalr(bp_update_is_jalr),
        .bp_update_target(bp_update_target),
        .out_if         (fetch_if.producer)
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

    initial begin
        rst_n = 1'b0;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        pc_src = 1'b0;
        pc_branch = '0;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_taken = 1'b0;
        bp_update_is_jalr = 1'b0;
        bp_update_target = '0;
        fetch_if.ready = 1'b0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h0050_0093); // addi x1, x0, 5
        write_word(32'd4,  32'h0060_0113); // addi x2, x0, 6
        write_word(32'd8,  32'h0010_0063); // beq x2, x1, +0
        write_word(32'd12, 32'h0070_0193); // addi x3, x0, 7
        write_word(32'd16, 32'h0010_0063); // beq x2, x1, +0
        write_word(32'd20, 32'h0080_0213); // addi x4, x0, 8
        write_word(32'd24, 32'h00b0_0393); // addi x7, x0, 11
        write_word(32'd32, 32'h0090_0293); // addi x5, x0, 9
        write_word(32'd36, 32'h00a0_0313); // addi x6, x0, 10
        write_word(32'd40, 32'h0010_0413); // addi x8, x0, 1
        write_word(32'd44, 32'h00c0_006f); // jal  x0, +12 -> 56
        write_word(32'd48, 32'h0630_0493); // wrong path
        write_word(32'd56, 32'h00b0_0513); // addi x10, x0, 11
        write_word(32'd64, 32'h0010_0613); // addi x12, x0, 1
        write_word(32'd68, 32'h0000_0663); // beq x0, x0, +12 -> 80
        write_word(32'd72, 32'h0630_0693); // predicted-away path
        write_word(32'd80, 32'h0160_0713); // addi x14, x0, 22
        write_word(32'd84, 32'h0010_0793); // addi x15, x0, 1
        write_word(32'd88, 32'h0000_8067); // jalr x0,0(x1), trained -> 100
        write_word(32'd92, 32'h0630_0813); // predicted-away path
        write_word(32'd100, 32'h0210_0893); // addi x17, x0, 33
        write_word(32'd104, 32'h0010_0913); // addi x18, x0, 1
        write_word(32'd108, 32'h0001_0067); // jalr x0,0(x2), miss -> 120
        write_word(32'd112, 32'h0630_0993); // blocked fall-through
        write_word(32'd120, 32'h02c0_0a13); // addi x20, x0, 44

        bp_update_valid = 1'b1;
        bp_update_pc = 32'd68;
        bp_update_taken = 1'b1;
        bp_update_target = 32'd80;
        step_clk;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_taken = 1'b0;
        bp_update_target = '0;

        bp_update_valid = 1'b1;
        bp_update_pc = 32'd88;
        bp_update_taken = 1'b1;
        bp_update_is_jalr = 1'b1;
        bp_update_target = 32'd100;
        step_clk;
        bp_update_valid = 1'b0;
        bp_update_pc = '0;
        bp_update_taken = 1'b0;
        bp_update_is_jalr = 1'b0;
        bp_update_target = '0;

        load_en = 1'b0;
        fetch_if.ready = 1'b1;
        #1;

        check_ok(fetch_if.valid == 1'b1, "packet fetch valid asserted");
        check_ok(fetch_if.data.lane0.valid == 1'b1, "first packet lane0 valid");
        check_ok(fetch_if.data.lane1.valid == 1'b1, "first packet lane1 valid");
        check_ok(fetch_if.data.lane0.data.pc == 32'd0, "first packet lane0 pc");
        check_ok(fetch_if.data.lane1.data.pc == 32'd4, "first packet lane1 pc");
        check_ok(fetch_if.data.lane0.data.instr == 32'h0050_0093, "first packet lane0 instruction");
        check_ok(fetch_if.data.lane1.data.instr == 32'h0060_0113, "first packet lane1 instruction");

        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd8, "control packet lane0 pc");
        check_ok(fetch_if.data.lane0.data.instr == 32'h0010_0063, "control packet lane0 instruction");
        check_ok(fetch_if.data.lane1.valid == 1'b0, "lane1 suppressed when lane0 is control flow");

        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd12, "post-control packet resumes at fall-through");
        check_ok(fetch_if.data.lane1.valid == 1'b1, "lane1 conditional branch remains in packet");
        check_ok(fetch_if.data.lane1.data.pc == 32'd16, "lane1 branch pc is preserved");
        check_ok(fetch_if.data.lane1.data.instr == 32'h0010_0063, "lane1 branch instruction is preserved");
        check_ok(!fetch_if.data.lane1.data.pred_taken, "untrained lane1 branch predicts not taken");

        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd20, "packet resumes after lane1 control flow");
        check_ok(fetch_if.data.lane1.valid == 1'b1, "non-control packet can use both lanes");
        check_ok(fetch_if.data.lane1.data.pc == 32'd24, "non-control packet lane1 pc");

        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd28, "pc advances by two instructions after full packet");

        fetch_if.ready = 1'b0;
        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd28, "pc holds under backpressure");
        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd28, "pc still holds under continued backpressure");

        fetch_if.ready = 1'b1;
        pc_src = 1'b1;
        pc_branch = 32'd32;
        #1;
        check_ok(fetch_if.valid == 1'b0, "redirect suppresses same-cycle output");

        step_clk;
        pc_src = 1'b0;
        #1;
        check_ok(fetch_if.valid == 1'b0, "redirect hold suppresses target for one cycle");

        step_clk;
        #1;
        check_ok(fetch_if.valid == 1'b1, "redirect target packet valid");
        check_ok(fetch_if.data.lane0.data.pc == 32'd32, "redirect target lane0 pc");
        check_ok(fetch_if.data.lane1.data.pc == 32'd36, "redirect target lane1 pc");
        check_ok(fetch_if.data.lane0.data.instr == 32'h0090_0293, "redirect target lane0 instruction");
        check_ok(fetch_if.data.lane1.data.instr == 32'h00a0_0313, "redirect target lane1 instruction");

        step_clk;
        check_ok(fetch_if.data.lane0.data.pc == 32'd40, "lane1 JAL packet starts at pc 40");
        check_ok(fetch_if.data.lane1.valid, "lane1 JAL remains valid");
        check_ok(fetch_if.data.lane1.data.pc == 32'd44, "lane1 JAL pc is preserved");
        check_ok(fetch_if.data.lane1.data.instr == 32'h00c0_006f, "lane1 JAL instruction is preserved");
        check_ok(fetch_if.data.lane1.data.pred_taken, "lane1 JAL predicts taken");
        check_ok(fetch_if.data.lane1.data.pred_target == 32'd56, "lane1 JAL computes direct target");

        step_clk;
        check_ok(!fetch_if.valid, "lane1 JAL redirect inserts redirect hold cycle");
        step_clk;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd56,
                 "lane1 JAL target packet is fetched");

        pc_src = 1'b1;
        pc_branch = 32'd64;
        #1;
        check_ok(!fetch_if.valid, "second explicit redirect suppresses output");
        step_clk;
        pc_src = 1'b0;
        step_clk;
        #1;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd64,
                 "trained lane1 branch packet is fetched");
        check_ok(fetch_if.data.lane1.valid &&
                 fetch_if.data.lane1.data.pc == 32'd68,
                 "trained branch remains in lane1");
        check_ok(fetch_if.data.lane1.data.pred_taken,
                 "trained lane1 branch predicts taken");
        check_ok(fetch_if.data.lane1.data.pred_target == 32'd80,
                 "trained lane1 branch uses BTB target");

        step_clk;
        check_ok(!fetch_if.valid, "lane1 branch prediction inserts redirect hold cycle");
        step_clk;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd80,
                 "trained lane1 branch target packet is fetched");

        pc_src = 1'b1;
        pc_branch = 32'd84;
        step_clk;
        pc_src = 1'b0;
        step_clk;
        #1;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd84,
                 "lane1 JALR hit packet is fetched");
        check_ok(fetch_if.data.lane1.valid &&
                 fetch_if.data.lane1.data.pc == 32'd88,
                 "JALR target-cache hit remains in lane1");
        check_ok(fetch_if.data.lane1.data.pred_taken,
                 "lane1 JALR target-cache hit predicts taken");
        check_ok(fetch_if.data.lane1.data.pred_target == 32'd100,
                 "lane1 JALR hit returns trained target");

        step_clk;
        check_ok(!fetch_if.valid, "lane1 JALR hit inserts redirect hold cycle");
        step_clk;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd100,
                 "lane1 JALR hit target packet is fetched");

        pc_src = 1'b1;
        pc_branch = 32'd104;
        step_clk;
        pc_src = 1'b0;
        step_clk;
        #1;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd104,
                 "lane1 JALR miss packet is fetched");
        check_ok(fetch_if.data.lane1.valid &&
                 fetch_if.data.lane1.data.pc == 32'd108,
                 "JALR target-cache miss remains in lane1");
        check_ok(!fetch_if.data.lane1.data.pred_taken,
                 "untrained lane1 JALR reports prediction miss");

        step_clk;
        check_ok(!fetch_if.valid && dut.jalr_wait_q,
                 "lane1 JALR miss stalls fetch after packet acceptance");
        step_clk;
        check_ok(!fetch_if.valid && dut.jalr_wait_q,
                 "lane1 JALR miss keeps fetch stalled");

        pc_src = 1'b1;
        pc_branch = 32'd120;
        step_clk;
        pc_src = 1'b0;
        step_clk;
        #1;
        check_ok(fetch_if.valid && fetch_if.data.lane0.data.pc == 32'd120,
                 "JALR execution redirect releases lane1 miss wait");

        $display("==== tb_fetch_packet_stage PASS ====");
        $finish;
    end

endmodule
