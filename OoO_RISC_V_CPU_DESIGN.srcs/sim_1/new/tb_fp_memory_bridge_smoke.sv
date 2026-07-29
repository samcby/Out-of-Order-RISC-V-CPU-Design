`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp memory bridge smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_memory_bridge_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

    localparam int MEM_WORDS = 16;

    logic clk;
    logic rst_n;
    logic req_valid;
    logic req_ready;
    logic req_store;
    logic [31:0] base_value;
    logic [31:0] store_value;
    logic [31:0] immediate;
    rob_tag_t request_tag;
    fp_preg_t dest_preg;
    cp_mask_t speculation_mask;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    logic commit_store_valid0;
    rob_tag_t commit_store_tag0;
    logic commit_store_valid1;
    rob_tag_t commit_store_tag1;
    logic resp_valid;
    rob_tag_t resp_tag;
    fp_preg_t resp_preg;
    logic resp_reg_write;
    logic resp_dest_is_fp;
    logic [31:0] resp_result;

    pip_if #(rat_dis_packet_t) rob_packet_if (.clk(clk), .rst_n(rst_n));
    rob_t rob_head;
    logic rob_head_valid;
    logic rob_head_complete;
    rob_t rob_head1;
    logic rob_head1_valid;
    logic rob_head1_complete;
    logic rob_commit;

    int errors;
    int wait_cycles;

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
            errors = errors + 1;
        end
    end
    endtask

    task automatic issue_fp_load(
        input rob_tag_t tag,
        input fp_preg_t preg,
        input logic [31:0] address
    );
    begin
        req_store = 1'b0;
        base_value = address;
        immediate = '0;
        request_tag = tag;
        dest_preg = preg;
        req_valid = 1'b1;
        while (!req_ready) step_clk();
        step_clk();
        req_valid = 1'b0;
    end
    endtask

    task automatic issue_fp_store(
        input rob_tag_t tag,
        input logic [31:0] address,
        input logic [31:0] data,
        input cp_mask_t spec_mask
    );
    begin
        req_store = 1'b1;
        base_value = address;
        store_value = data;
        immediate = '0;
        request_tag = tag;
        dest_preg = '0;
        speculation_mask = spec_mask;
        req_valid = 1'b1;
        while (!req_ready) step_clk();
        step_clk();
        req_valid = 1'b0;
        req_store = 1'b0;
        speculation_mask = '0;
    end
    endtask

    task automatic wait_for_response(input rob_tag_t tag);
    begin
        wait_cycles = 0;
        while ((!resp_valid || resp_tag != tag) && wait_cycles < 100) begin
            wait_cycles = wait_cycles + 1;
            step_clk();
        end
    end
    endtask

    fp_lsu_bridge #(
        .MEM_WORDS(MEM_WORDS),
        .DATA_CACHE_LINES(4),
        .DATA_CACHE_WAYS(2),
        .DATA_CACHE_WORDS_PER_LINE(4),
        .DATA_MEM_RESPONSE_LATENCY(2)
    ) u_bridge (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .req_valid             (req_valid),
        .req_ready             (req_ready),
        .req_store             (req_store),
        .base_value            (base_value),
        .store_value           (store_value),
        .immediate             (immediate),
        .rob_tag               (request_tag),
        .dest_preg             (dest_preg),
        .speculation_mask      (speculation_mask),
        .squash_en             (squash_en),
        .squash_checkpoint_id  (squash_checkpoint_id),
        .resolve_en            (resolve_en),
        .resolve_checkpoint_id (resolve_checkpoint_id),
        .commit_store_valid0   (commit_store_valid0),
        .commit_store_tag0     (commit_store_tag0),
        .commit_store_valid1   (commit_store_valid1),
        .commit_store_tag1     (commit_store_tag1),
        .resp_valid            (resp_valid),
        .resp_tag              (resp_tag),
        .resp_preg             (resp_preg),
        .resp_reg_write        (resp_reg_write),
        .resp_dest_is_fp       (resp_dest_is_fp),
        .resp_result           (resp_result)
    );

    rob_2w u_rob (
        .rob_packet_if         (rob_packet_if.consumer),
        .complete_en0          (resp_valid),
        .complete_tag0         (resp_tag),
        .complete_result0      (resp_result),
        .complete_en1          (1'b0),
        .complete_tag1         ('0),
        .complete_result1      ('0),
        .complete_en2          (1'b0),
        .complete_tag2         ('0),
        .complete_result2      ('0),
        .commit_en0            (rob_commit),
        .commit_en1            (1'b0),
        .flush                 (1'b0),
        .squash_en             (1'b0),
        .squash_checkpoint_id  ('0),
        .resolve_en            (1'b0),
        .resolve_checkpoint_id ('0),
        .head_entry            (rob_head),
        .head_valid            (rob_head_valid),
        .head_complete         (rob_head_complete),
        .head1_entry           (rob_head1),
        .head1_valid           (rob_head1_valid),
        .head1_complete        (rob_head1_complete),
        .full                  (),
        .empty                 ()
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        req_valid = 1'b0;
        req_store = 1'b0;
        base_value = '0;
        store_value = '0;
        immediate = '0;
        request_tag = '0;
        dest_preg = '0;
        speculation_mask = '0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        commit_store_valid1 = 1'b0;
        commit_store_tag1 = '0;
        rob_packet_if.valid = 1'b0;
        rob_packet_if.data = '0;
        rob_commit = 1'b0;
        errors = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        // Push an FP destination into the real ROB before issuing its FLW.
        rob_packet_if.data = '0;
        rob_packet_if.data.lane0.valid = 1'b1;
        rob_packet_if.data.lane0.data.rob_entry.datapath.rob_tag = rob_tag_t'(1);
        rob_packet_if.data.lane0.data.rob_entry.datapath.new_des_preg = preg_t'(40);
        rob_packet_if.data.lane0.data.rob_entry.datapath.old_des_preg = preg_t'(5);
        rob_packet_if.data.lane0.data.rob_entry.datapath.dest_is_fp = 1'b1;
        rob_packet_if.data.lane0.data.rob_entry.datapath.rd = areg_t'(5);
        rob_packet_if.valid = 1'b1;
        step_clk();
        rob_packet_if.valid = 1'b0;
        check_ok(rob_head_valid && rob_head.datapath.dest_is_fp,
                 "ROB preserves the floating-point destination domain");

        u_bridge.u_lsu.u_data_cache.u_data_memory.mem[4] = 32'h3fc00000;
        issue_fp_load(rob_tag_t'(1), fp_preg_t'(40), 32'd16);
        wait_for_response(rob_tag_t'(1));
        check_ok(resp_valid && resp_reg_write && resp_dest_is_fp,
                 "FLW response targets the floating-point register file");
        check_ok(resp_preg == fp_preg_t'(40) &&
                 resp_result == 32'h3fc00000,
                 "FLW preserves the IEEE-754 payload bits");
        step_clk();
        check_ok(rob_head_complete && rob_head.datapath.dest_is_fp &&
                 rob_head.datapath.result == 32'h3fc00000,
                 "FP load completes the tagged ROB entry");
        rob_commit = 1'b1;
        step_clk();
        rob_commit = 1'b0;

        issue_fp_store(rob_tag_t'(2), 32'd20, 32'hc0200000, '0);
        check_ok(resp_valid && !resp_reg_write && !resp_dest_is_fp,
                 "FSW completes without a register write");
        check_ok(u_bridge.u_lsu.u_data_cache.u_data_memory.mem[5] == '0,
                 "uncommitted FSW has no backing-memory side effect");

        commit_store_valid0 = 1'b1;
        commit_store_tag0 = rob_tag_t'(2);
        step_clk();
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;

        issue_fp_load(rob_tag_t'(3), fp_preg_t'(41), 32'd20);
        wait_for_response(rob_tag_t'(3));
        check_ok(resp_valid && resp_result == 32'hc0200000,
                 "FLW observes a committed older FSW");

        issue_fp_store(rob_tag_t'(4), 32'd24, 32'hdeadbeef,
                       cp_mask_t'(4'b0010));
        squash_en = 1'b1;
        squash_checkpoint_id = cp_id_t'(1);
        step_clk();
        squash_en = 1'b0;
        commit_store_valid0 = 1'b1;
        commit_store_tag0 = rob_tag_t'(4);
        step_clk();
        commit_store_valid0 = 1'b0;
        repeat (4) step_clk();
        check_ok(u_bridge.u_lsu.u_data_cache.u_data_memory.mem[6] == '0,
                 "squashed FSW remains side-effect free after a late commit tag");

        issue_fp_load(rob_tag_t'(5), fp_preg_t'(42), 32'd24);
        wait_for_response(rob_tag_t'(5));
        check_ok(resp_valid && resp_result == '0,
                 "FLW does not observe data from a squashed FSW");

        if (errors == 0) begin
            $display("==== tb_fp_memory_bridge_smoke PASS ====");
        end else begin
            $display("==== tb_fp_memory_bridge_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
