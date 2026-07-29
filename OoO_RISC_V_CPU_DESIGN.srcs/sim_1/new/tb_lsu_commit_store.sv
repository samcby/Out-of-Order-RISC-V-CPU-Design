`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for lsu commit store.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_lsu_commit_store;

    import defines_pkg::*;

    localparam int MEM_WORDS = 16;

    logic clk;
    logic rst_n;

    logic req_valid;
    logic req_ready;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    logic commit_store_valid0;
    rob_tag_t commit_store_tag0;
    logic commit_store_valid1;
    rob_tag_t commit_store_tag1;
    lsu_control_t control_signal;
    rs_datapath_t datapath;
    logic resp_valid;
    rob_tag_t resp_tag;
    preg_t resp_preg;
    logic resp_reg_write;
    logic [WIDTH-1:0] resp_result;

    int fail_count;
    int wait_cycles;

    lsu #(
        .MEM_WORDS(MEM_WORDS),
        .DATA_CACHE_LINES(4),
        .DATA_CACHE_WAYS(2),
        .DATA_CACHE_WORDS_PER_LINE(4),
        .DATA_MEM_RESPONSE_LATENCY(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .commit_store_valid0(commit_store_valid0),
        .commit_store_tag0(commit_store_tag0),
        .commit_store_valid1(commit_store_valid1),
        .commit_store_tag1(commit_store_tag1),
        .control_signal(control_signal),
        .datapath(datapath),
        .resp_valid(resp_valid),
        .resp_tag(resp_tag),
        .resp_preg(resp_preg),
        .resp_reg_write(resp_reg_write),
        .resp_result(resp_result)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            fail_count++;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    // Store helpers intentionally separate execution from commit. They verify
    // that an accepted store completes to the ROB before it may change cache or
    // backing memory, which is the precise-state contract of the LSU.
    task automatic issue_store(
        input rob_tag_t tag,
        input logic [WIDTH-1:0] addr,
        input logic [WIDTH-1:0] data,
        input cp_mask_t spec_mask
    );
    begin
        control_signal = '0;
        control_signal.mem_write = 1'b1;
        control_signal.funct3 = 3'b010;
        datapath = '0;
        datapath.rob_tag = tag;
        datapath.src1_value = addr;
        datapath.src2_value = data;
        datapath.imm = '0;
        datapath.speculation_mask = spec_mask;
        req_valid = 1'b1;
        while (!req_ready) begin
            step_clk;
        end
        step_clk;
        req_valid = 1'b0;
        control_signal = '0;
        datapath = '0;
    end
    endtask

    task automatic issue_store_access(
        input rob_tag_t tag,
        input logic [WIDTH-1:0] addr,
        input logic [WIDTH-1:0] data,
        input logic [2:0] funct3,
        input cp_mask_t spec_mask
    );
    begin
        control_signal = '0;
        control_signal.mem_write = 1'b1;
        control_signal.funct3 = funct3;
        datapath = '0;
        datapath.rob_tag = tag;
        datapath.src1_value = addr;
        datapath.src2_value = data;
        datapath.imm = '0;
        datapath.speculation_mask = spec_mask;
        req_valid = 1'b1;
        while (!req_ready) begin
            step_clk;
        end
        step_clk;
        req_valid = 1'b0;
        control_signal = '0;
        datapath = '0;
    end
    endtask

    task automatic issue_store_with_commit(
        input rob_tag_t tag,
        input logic [WIDTH-1:0] addr,
        input logic [WIDTH-1:0] data
    );
    begin
        control_signal = '0;
        control_signal.mem_write = 1'b1;
        control_signal.funct3 = 3'b010;
        datapath = '0;
        datapath.rob_tag = tag;
        datapath.src1_value = addr;
        datapath.src2_value = data;
        datapath.imm = '0;
        req_valid = 1'b1;
        commit_store_valid0 = 1'b1;
        commit_store_tag0 = tag;
        while (!req_ready) begin
            step_clk;
        end
        step_clk;
        req_valid = 1'b0;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        control_signal = '0;
        datapath = '0;
    end
    endtask

    // Load helpers observe both forwarded values and cache-visible values after
    // conflicting stores become committed and drain from the Store Buffer.
    task automatic issue_load(input rob_tag_t tag, input preg_t preg, input logic [WIDTH-1:0] addr);
    begin
        control_signal = '0;
        control_signal.mem_read = 1'b1;
        control_signal.reg_write = 1'b1;
        control_signal.funct3 = 3'b010;
        datapath = '0;
        datapath.rob_tag = tag;
        datapath.new_des_preg = preg;
        datapath.src1_value = addr;
        datapath.imm = '0;
        req_valid = 1'b1;
        while (!req_ready) begin
            step_clk;
        end
        step_clk;
        req_valid = 1'b0;
        control_signal = '0;
        datapath = '0;
    end
    endtask

    task automatic issue_load_access(
        input rob_tag_t tag,
        input preg_t preg,
        input logic [WIDTH-1:0] addr,
        input logic [2:0] funct3
    );
    begin
        control_signal = '0;
        control_signal.mem_read = 1'b1;
        control_signal.reg_write = 1'b1;
        control_signal.funct3 = funct3;
        datapath = '0;
        datapath.rob_tag = tag;
        datapath.new_des_preg = preg;
        datapath.src1_value = addr;
        datapath.imm = '0;
        req_valid = 1'b1;
        while (!req_ready) begin
            step_clk;
        end
        step_clk;
        req_valid = 1'b0;
        control_signal = '0;
        datapath = '0;
    end
    endtask

    // The scenario also covers commit-tag replay, byte-mask stores, forwarding,
    // and the guarantee that wrong-path/uncommitted stores cannot reach memory.
    initial begin
        rst_n = 1'b0;
        req_valid = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        commit_store_valid1 = 1'b0;
        commit_store_tag1 = '0;
        control_signal = '0;
        datapath = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        dut.u_data_cache.u_data_memory.mem[0] = 32'h00000000;
        dut.u_data_cache.u_data_memory.mem[1] = 32'h00000000;
        dut.u_data_cache.u_data_memory.mem[9] = 32'h12345678;
        dut.u_data_cache.u_data_memory.mem[10] = 32'h11223344;

        issue_store(rob_tag_t'(8'd1), 32'h00000020, 32'haabbccdd,
                    cp_mask_t'(4'b0001));
        issue_load(rob_tag_t'(8'd2), preg_t'(7'd38), 32'h00000024);
        wait_cycles = 0;
        while (!resp_valid && wait_cycles < 40) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd2),
                 "non-alias load bypasses an older uncommitted store");
        check_ok(resp_result == 32'h12345678,
                 "non-alias load returns backing memory data");
        step_clk;

        issue_load(rob_tag_t'(8'd3), preg_t'(7'd39), 32'h00000020);
        wait_cycles = 0;
        while (!resp_valid && wait_cycles < 8) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd3),
                 "same-address load forwards from an uncommitted store");
        check_ok(resp_result == 32'haabbccdd,
                 "SW to LW forwarding preserves the complete word");
        step_clk;

        issue_store_access(rob_tag_t'(8'd4), 32'h00000022, 32'h0000005a,
                           3'b000, cp_mask_t'(4'b0001));
        issue_load_access(rob_tag_t'(8'd11), preg_t'(7'd41),
                          32'h00000022, 3'b101);
        wait_cycles = 0;
        while (!resp_valid && wait_cycles < 8) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd11),
                 "multi-store byte coverage forwards without cache access");
        check_ok(resp_result == 32'h0000aa5a,
                 "youngest overlapping store wins each forwarded byte");
        step_clk;

        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(0);
        step_clk;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;

        issue_store_access(rob_tag_t'(8'd12), 32'h00000029, 32'h000000aa,
                           3'b000, cp_mask_t'(4'b0010));
        issue_load(rob_tag_t'(8'd13), preg_t'(7'd43), 32'h00000028);
        repeat (4) step_clk;
        check_ok(!resp_valid,
                 "partially covered load waits for the older store to drain");

        commit_store_valid0 = 1'b1;
        commit_store_tag0 = rob_tag_t'(8'd12);
        step_clk;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        wait_cycles = 0;
        while (!resp_valid && wait_cycles < 40) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd13),
                 "partially covered load completes after store commit");
        check_ok(resp_result == 32'h1122aa44,
                 "partial store is merged through cache before load");
        step_clk;

        // Isolate the original precise-store checks from the forwarding/cache state above.
        rst_n = 1'b0;
        step_clk;
        rst_n = 1'b1;
        step_clk;
        dut.u_data_cache.u_data_memory.mem[0] = 32'h00000000;
        dut.u_data_cache.u_data_memory.mem[1] = 32'h00000000;

        issue_store(rob_tag_t'(8'd5), 32'h00000000, 32'hdeadbeef, '0);
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd5), "store issue completes ROB before cache write");
        check_ok(!resp_reg_write, "store issue does not write a physical register");
        check_ok(dut.u_data_cache.u_data_memory.mem[0] == 32'h00000000,
                 "uncommitted store has not updated backing memory");
        check_ok(!dut.u_data_cache.line_valid[0][0] && !dut.u_data_cache.line_valid[0][1],
                 "uncommitted store has not allocated or modified a cache line");

        step_clk;
        check_ok(req_ready, "uncommitted store does not hold the LSU issue port");

        commit_store_valid0 = 1'b1;
        commit_store_tag0 = rob_tag_t'(8'd5);
        step_clk;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;

        wait_cycles = 0;
        while (((dut.u_data_cache.line_data[0][0][0] != 32'hdeadbeef) &&
                (dut.u_data_cache.line_data[0][1][0] != 32'hdeadbeef)) &&
               (wait_cycles < 40)) begin
            wait_cycles++;
            step_clk;
        end
        check_ok((dut.u_data_cache.line_data[0][0][0] == 32'hdeadbeef) ||
                 (dut.u_data_cache.line_data[0][1][0] == 32'hdeadbeef),
                 "committed store drains into cache before later load");

        issue_load(rob_tag_t'(8'd6), preg_t'(7'd40), 32'h00000000);
        wait_cycles = 0;
        while (!resp_valid && wait_cycles < 40) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd6), "load after committed store completes");
        check_ok(resp_reg_write && resp_preg == preg_t'(7'd40), "load writes destination physical register");
        check_ok(resp_result == 32'hdeadbeef, "load after committed store observes stored word");
        step_clk;

        dut.u_data_cache.u_data_memory.mem[2] = 32'h00000000;
        issue_store_with_commit(rob_tag_t'(8'd8), 32'h00000008, 32'hcafe1234);
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd8),
                 "same-cycle committed store completes ROB");

        wait_cycles = 0;
        while (((dut.u_data_cache.line_data[0][0][2] != 32'hcafe1234) &&
                (dut.u_data_cache.line_data[0][1][2] != 32'hcafe1234)) &&
               (wait_cycles < 40)) begin
            wait_cycles++;
            step_clk;
        end
        check_ok((dut.u_data_cache.line_data[0][0][2] == 32'hcafe1234) ||
                 (dut.u_data_cache.line_data[0][1][2] == 32'hcafe1234),
                 "same-cycle committed store drains into cache line");

        issue_store(rob_tag_t'(8'd9), 32'h0000000c, 32'hfeedface, cp_mask_t'(4'b0100));
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd9),
                 "resolve+squash store completes ROB before cache write");
        squash_en = 1'b1;
        resolve_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(2);
        resolve_checkpoint_id = cp_id_t'(2);
        step_clk;
        squash_en = 1'b0;
        resolve_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_checkpoint_id = '0;
        check_ok(req_ready, "resolve+squash store buffer entry is released");
        check_ok((dut.u_data_cache.line_data[0][0][3] != 32'hfeedface) &&
                 (dut.u_data_cache.line_data[0][1][3] != 32'hfeedface),
                 "resolve+squash store did not update cached line data");

        issue_store(rob_tag_t'(8'd7), 32'h00000004, 32'hbad0bad0, cp_mask_t'(4'b0010));
        check_ok(resp_valid && resp_tag == rob_tag_t'(8'd7), "speculative store completes ROB before cache write");

        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(1);
        step_clk;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        check_ok(req_ready, "squashed store buffer is released before commit");
        check_ok(dut.u_data_cache.u_data_memory.mem[1] == 32'h00000000,
                 "squashed store did not update backing memory");
        check_ok((dut.u_data_cache.line_data[0][0][1] != 32'hbad0bad0) &&
                 (dut.u_data_cache.line_data[0][1][1] != 32'hbad0bad0),
                 "squashed store did not update cached line data");

        commit_store_valid0 = 1'b1;
        commit_store_tag0 = rob_tag_t'(8'd7);
        step_clk;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        repeat (4) step_clk;
        check_ok(dut.u_data_cache.u_data_memory.mem[1] == 32'h00000000,
                 "late commit tag for squashed store has no memory side effect");
        check_ok((dut.u_data_cache.line_data[0][0][1] != 32'hbad0bad0) &&
                 (dut.u_data_cache.line_data[0][1][1] != 32'hbad0bad0),
                 "late commit tag for squashed store has no cache side effect");

        $display("[SUMMARY] load_result=0x%08h line0_word0=0x%08h line1_word0=0x%08h mem0=0x%08h mem1=0x%08h",
                 resp_result,
                 dut.u_data_cache.line_data[0][0][0],
                 dut.u_data_cache.line_data[0][1][0],
                 dut.u_data_cache.u_data_memory.mem[0],
                 dut.u_data_cache.u_data_memory.mem[1]);

        if (fail_count == 0) begin
            $display("==== tb_lsu_commit_store PASS ====");
        end else begin
            $display("==== tb_lsu_commit_store FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
