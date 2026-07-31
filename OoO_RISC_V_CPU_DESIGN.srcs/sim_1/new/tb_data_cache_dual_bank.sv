`timescale 1ns/1ps

module tb_data_cache_dual_bank;
    import defines_pkg::*;

    localparam int MEM_WORDS = 32;
    localparam int ADDR_W = $clog2(MEM_WORDS);

    logic clk;
    logic rst_n;
    logic req_valid;
    logic req_ready;
    logic req_write;
    logic [ADDR_W-1:0] req_word_addr;
    logic [3:0] req_wmask;
    logic [WIDTH-1:0] req_wdata;
    logic resp_valid;
    logic [WIDTH-1:0] resp_rdata;
    logic req1_valid;
    logic req1_ready;
    logic req1_write;
    logic [ADDR_W-1:0] req1_word_addr;
    logic [3:0] req1_wmask;
    logic [WIDTH-1:0] req1_wdata;
    logic resp1_valid;
    logic [WIDTH-1:0] resp1_rdata;

    int fail_count;
    int wait_cycles;
    logic seen0;
    logic seen1;
    logic [WIDTH-1:0] result0;
    logic [WIDTH-1:0] result1;
    logic [31:0] conflicts_before;

    data_cache #(
        .MEM_WORDS(MEM_WORDS),
        .LINE_COUNT(4),
        .WAY_COUNT(2),
        .WORDS_PER_LINE(4),
        .MEMORY_RESPONSE_LATENCY(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_write(req_write),
        .req_word_addr(req_word_addr),
        .req_wmask(req_wmask),
        .req_wdata(req_wdata),
        .resp_valid(resp_valid),
        .resp_rdata(resp_rdata),
        .req1_valid(req1_valid),
        .req1_ready(req1_ready),
        .req1_write(req1_write),
        .req1_word_addr(req1_word_addr),
        .req1_wmask(req1_wmask),
        .req1_wdata(req1_wdata),
        .resp1_valid(resp1_valid),
        .resp1_rdata(resp1_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic condition, input string message);
    begin
        if (condition) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s", message);
            fail_count++;
        end
    end
    endtask

    task automatic collect_pair;
    begin
        seen0 = 1'b0;
        seen1 = 1'b0;
        result0 = '0;
        result1 = '0;
        wait_cycles = 0;
        while (!(seen0 && seen1) && (wait_cycles < 80)) begin
            if (resp_valid) begin
                seen0 = 1'b1;
                result0 = resp_rdata;
            end
            if (resp1_valid) begin
                seen1 = 1'b1;
                result1 = resp1_rdata;
            end
            wait_cycles++;
            step_clk;
        end
        if (resp_valid) begin
            seen0 = 1'b1;
            result0 = resp_rdata;
        end
        if (resp1_valid) begin
            seen1 = 1'b1;
            result1 = resp1_rdata;
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_word_addr = '0;
        req_wmask = '0;
        req_wdata = '0;
        req1_valid = 1'b0;
        req1_write = 1'b0;
        req1_word_addr = '0;
        req1_wmask = '0;
        req1_wdata = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        dut.u_data_memory.mem[0] = 32'h11112222;
        dut.u_data_memory.mem[1] = 32'h33334444;
        dut.u_data_memory.mem[4] = 32'haaaabbbb;

        req_valid = 1'b1;
        req_word_addr = ADDR_W'(0);
        req1_valid = 1'b1;
        req1_word_addr = ADDR_W'(4);
        #1;
        check_ok(req_ready && req1_ready,
                 "different-bank misses are accepted together");
        step_clk;
        req_valid = 1'b0;
        req1_valid = 1'b0;

        collect_pair;
        check_ok(seen0 && seen1,
                 "different-bank misses both receive responses");
        check_ok(result0 == 32'h11112222 && result1 == 32'haaaabbbb,
                 "dual-bank miss responses preserve port ownership");
        check_ok(dut.miss_count == 32'd2,
                 "dual-bank misses update both miss events");

        req_valid = 1'b1;
        req_word_addr = ADDR_W'(0);
        req1_valid = 1'b1;
        req1_word_addr = ADDR_W'(4);
        #1;
        check_ok(req_ready && req1_ready,
                 "different-bank hits are accepted together");
        step_clk;
        check_ok(resp_valid && resp1_valid,
                 "different-bank hits complete in the same cycle");
        check_ok(resp_rdata == 32'h11112222 &&
                 resp1_rdata == 32'haaaabbbb,
                 "dual-bank hit data is correct");
        req_valid = 1'b0;
        req1_valid = 1'b0;
        step_clk;

        conflicts_before = dut.bank_conflict_count;
        req_valid = 1'b1;
        req_word_addr = ADDR_W'(0);
        req1_valid = 1'b1;
        req1_word_addr = ADDR_W'(1);
        #1;
        check_ok(req_ready && !req1_ready,
                 "same-bank conflict gives deterministic port0 priority");
        step_clk;
        req_valid = 1'b0;
        req1_valid = 1'b0;
        check_ok(dut.bank_conflict_count == conflicts_before + 1'b1,
                 "same-bank conflict increments the conflict counter");

        $display("[SUMMARY] hits=%0d misses=%0d conflicts=%0d",
                 dut.hit_count, dut.miss_count, dut.bank_conflict_count);
        if (fail_count == 0) begin
            $display("==== tb_data_cache_dual_bank PASS ====");
        end else begin
            $display("==== tb_data_cache_dual_bank FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end
endmodule
