`timescale 1ns/1ps

module tb_icache;

    localparam int WIDTH = 32;
    localparam int DEPTH_BYTES = 64;

    logic clk;
    logic rst_n;
    logic start;

    logic             load_en;
    logic [WIDTH-1:0] load_addr;
    logic [7:0]       load_instr_byte;

    logic [WIDTH-1:0] addr;
    logic [WIDTH-1:0] instr;

    icache #(
        .WIDTH(WIDTH),
        .DEPTH_BYTES(DEPTH_BYTES)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (start),
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        .addr           (addr),
        .instr          (instr)
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
        start = 1'b0;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        addr = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0, 32'h00500093); // addi x1, x0, 5
        write_word(32'd4, 32'h123451B7); // lui  x3, 0x12345

        load_en = 1'b0;
        start   = 1'b1;

        addr = 32'd0;
        #1;
        check_ok(instr == 32'h00500093, "read word @0");

        addr = 32'd4;
        #1;
        check_ok(instr == 32'h123451B7, "read word @4");

        addr = 32'd8;
        #1;
        check_ok(instr == 32'h00000000, "uninitialized word is zero");

        $display("==== tb_icache PASS ====");
        $finish;
    end

endmodule
