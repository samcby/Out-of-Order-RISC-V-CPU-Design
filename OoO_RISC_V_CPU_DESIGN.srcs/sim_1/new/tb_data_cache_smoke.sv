`timescale 1ns/1ps

module tb_data_cache_smoke;

    import defines_pkg::*;

    localparam int MEM_WORDS = 32;
    localparam int LINE_COUNT = 4;
    localparam int WAY_COUNT = 2;
    localparam int WORDS_PER_LINE = 4;

    logic clk;
    logic rst_n;

    logic                          req_valid;
    logic                          req_ready;
    logic                          req_write;
    logic [$clog2(MEM_WORDS)-1:0]  req_word_addr;
    logic [3:0]                    req_wmask;
    logic [WIDTH-1:0]              req_wdata;
    logic                          resp_valid;
    logic [WIDTH-1:0]              resp_rdata;

    int fail_count;
    logic [WIDTH-1:0] read_data;
    int wait_cycles;

    data_cache #(
        .MEM_WORDS(MEM_WORDS),
        .LINE_COUNT(LINE_COUNT),
        .WAY_COUNT(WAY_COUNT),
        .WORDS_PER_LINE(WORDS_PER_LINE),
        .MEMORY_RESPONSE_LATENCY(2)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (req_valid),
        .req_ready    (req_ready),
        .req_write    (req_write),
        .req_word_addr(req_word_addr),
        .req_wmask    (req_wmask),
        .req_wdata    (req_wdata),
        .resp_valid   (resp_valid),
        .resp_rdata   (resp_rdata)
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

    task automatic issue_cache_req;
        input  logic                         write;
        input  logic [$clog2(MEM_WORDS)-1:0] word_addr;
        input  logic [3:0]                   wmask;
        input  logic [WIDTH-1:0]             wdata;
        output logic [WIDTH-1:0]             rdata;
        output int                           cycles_waited;
    begin
        req_valid = 1'b1;
        req_write = write;
        req_word_addr = word_addr;
        req_wmask = wmask;
        req_wdata = wdata;
        cycles_waited = 0;

        while (!req_ready) begin
            step_clk;
        end
        step_clk;

        req_valid = 1'b0;
        req_write = 1'b0;
        req_word_addr = '0;
        req_wmask = '0;
        req_wdata = '0;

        while (!resp_valid) begin
            cycles_waited = cycles_waited + 1;
            step_clk;
        end

        rdata = resp_rdata;
        step_clk;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_word_addr = '0;
        req_wmask = '0;
        req_wdata = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        dut.u_data_memory.mem[0]  = 32'h11223344;
        dut.u_data_memory.mem[1]  = 32'h55667788;
        dut.u_data_memory.mem[2]  = 32'haaaabbbb;
        dut.u_data_memory.mem[3]  = 32'hccccdddd;
        dut.u_data_memory.mem[8]  = 32'h88880000;
        dut.u_data_memory.mem[9]  = 32'h88881111;
        dut.u_data_memory.mem[10] = 32'h88882222;
        dut.u_data_memory.mem[11] = 32'h88883333;
        dut.u_data_memory.mem[16] = 32'h16160000;
        dut.u_data_memory.mem[17] = 32'h16161111;
        dut.u_data_memory.mem[18] = 32'h16162222;
        dut.u_data_memory.mem[19] = 32'h16163333;

        issue_cache_req(1'b0, 5'd0, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h11223344, "line load miss returns requested word");
        check_ok(dut.miss_count == 32'd1, "first line access increments miss counter");
        check_ok(wait_cycles > 0, "line miss waits for backing memory refill");

        issue_cache_req(1'b0, 5'd1, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h55667788, "same line word hits after refill");
        check_ok(dut.hit_count == 32'd1, "same line load increments hit counter");
        check_ok(wait_cycles == 0, "same line load hit responds immediately");

        issue_cache_req(1'b1, 5'd2, 4'b0011, 32'h0000beef, read_data, wait_cycles);
        check_ok(dut.hit_count == 32'd2, "store hit within filled line increments hit counter");
        check_ok(((dut.line_data[0][0][2] == 32'haaaabeef) && dut.line_dirty[0][0]) ||
                 ((dut.line_data[0][1][2] == 32'haaaabeef) && dut.line_dirty[0][1]),
                 "store hit updates selected word and marks line dirty");
        check_ok(dut.u_data_memory.mem[2] == 32'haaaabbbb, "dirty store hit does not immediately update backing memory");

        issue_cache_req(1'b0, 5'd8, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h88880000, "second same-set line miss returns backing word");
        check_ok(dut.miss_count == 32'd2, "second same-set line increments miss counter");
        check_ok(dut.writeback_count == 32'd0, "2-way fill into empty way avoids writeback");
        check_ok(dut.line_valid[0][0] && dut.line_valid[0][1], "2-way set holds two cache lines");

        issue_cache_req(1'b0, 5'd9, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h88881111, "second line adjacent word hits after line refill");
        check_ok(dut.hit_count == 32'd3, "second line adjacent word increments hit counter");

        issue_cache_req(1'b0, 5'd0, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h11223344, "first same-set line still hits in other way");
        check_ok(dut.hit_count == 32'd4, "first same-set line hit updates replacement state");

        issue_cache_req(1'b0, 5'd8, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h88880000, "second same-set line still hits before replacement");
        check_ok(dut.hit_count == 32'd5, "second same-set line hit updates replacement state");

        issue_cache_req(1'b0, 5'd16, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h16160000, "third same-set line miss returns backing word");
        check_ok(dut.miss_count == 32'd3, "third same-set line increments miss counter");
        check_ok(dut.writeback_count == 32'd1, "third same-set line evicts dirty way");
        check_ok(dut.u_data_memory.mem[2] == 32'haaaabeef, "dirty multi-word line eviction writes back modified word");
        check_ok(dut.u_data_memory.mem[0] == 32'h11223344, "dirty line writeback preserves unmodified word 0");
        check_ok(dut.u_data_memory.mem[1] == 32'h55667788, "dirty line writeback preserves unmodified word 1");
        check_ok(dut.u_data_memory.mem[3] == 32'hccccdddd, "dirty line writeback preserves unmodified word 3");

        issue_cache_req(1'b0, 5'd17, 4'b0000, 32'h0, read_data, wait_cycles);
        check_ok(read_data == 32'h16161111, "third same-set adjacent word hits after multi-word refill");
        check_ok(dut.hit_count == 32'd6, "third line adjacent word increments hit counter");

        $display("[SUMMARY] hits=%0d misses=%0d writebacks=%0d set0_way0_word0=0x%08h set0_way1_word0=0x%08h mem2=0x%08h",
                 dut.hit_count,
                 dut.miss_count,
                 dut.writeback_count,
                 dut.line_data[0][0][0],
                 dut.line_data[0][1][0],
                 dut.u_data_memory.mem[2]);

        if (fail_count == 0) begin
            $display("==== tb_data_cache_smoke PASS ====");
        end else begin
            $display("==== tb_data_cache_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
