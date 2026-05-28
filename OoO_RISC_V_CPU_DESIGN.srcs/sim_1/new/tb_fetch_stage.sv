`timescale 1ns/1ps

module tb_fetch_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    logic        load_en;
    logic [31:0] load_addr;
    logic [7:0]  load_instr_byte;

    logic        pc_src;
    logic [31:0] pc_branch;

    pip_if #(fetch_decode_t) fetch_if (.clk(clk), .rst_n(rst_n));

    fetch_stage dut (
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        .pc_src         (pc_src),
        .pc_branch      (pc_branch),
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
        fetch_if.ready = 1'b0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // hold fetch so PC does not advance while loading program
        fetch_if.ready = 1'b0;

        write_word(32'd0,  32'h00500093); // addi x1, x0, 5
        write_word(32'd4,  32'h0080A103); // lw   x2, 8(x1)
        write_word(32'd8,  32'h00209863); // bne  x1, x2, 16
        write_word(32'd12, 32'h123451B7); // lui  x3, 0x12345

        load_en = 1'b0;

        // release fetch
        fetch_if.ready = 1'b1;
        #1;

        check_ok(fetch_if.valid == 1'b1, "fetch valid asserted");
        check_ok(fetch_if.data.pc == 32'd0, "first pc = 0");
        check_ok(fetch_if.data.instr == 32'h00500093, "first instr correct");

        step_clk;
        check_ok(fetch_if.data.pc == 32'd4, "second pc = 4");
        check_ok(fetch_if.data.instr == 32'h0080A103, "second instr correct");

        step_clk;
        check_ok(fetch_if.data.pc == 32'd8, "third pc = 8");
        check_ok(fetch_if.data.instr == 32'h00209863, "third instr correct");

        step_clk;
        check_ok(fetch_if.data.pc == 32'd12, "fourth pc = 12");
        check_ok(fetch_if.data.instr == 32'h123451B7, "fourth instr correct");

        // redirect test
        pc_src    = 1'b1;
        pc_branch = 32'd8;
        #1;
        check_ok(fetch_if.data.pc == 32'd8, "redirect pc visible immediately");
        check_ok(fetch_if.data.instr == 32'h00209863, "redirect instr correct");

        step_clk;
        pc_src = 1'b0;
        check_ok(fetch_if.data.pc == 32'd8, "redirect latched into pc path");

        $display("==== tb_fetch_stage PASS ====");
        $finish;
    end

endmodule
