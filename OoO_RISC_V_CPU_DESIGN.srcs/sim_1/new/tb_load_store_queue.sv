`timescale 1ns/1ps

module tb_load_store_queue;
    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic wb_valid;
    logic wb_is_fp;
    preg_t wb_preg;
    logic [WIDTH-1:0] wb_result;
    logic wb1_valid;
    logic wb1_is_fp;
    preg_t wb1_preg;
    logic [WIDTH-1:0] wb1_result;
    logic complete_valid0;
    rob_tag_t complete_tag0;
    logic complete_valid1;
    rob_tag_t complete_tag1;
    logic commit_valid0;
    rob_tag_t commit_tag0;
    logic commit_valid1;
    rob_tag_t commit_tag1;
    logic flush;
    logic squash_en;
    cp_id_t squash_checkpoint_id;
    logic resolve_en;
    cp_id_t resolve_checkpoint_id;
    logic replay_valid;
    rob_tag_t replay_tag;
    logic [WIDTH-1:0] replay_pc;

    pip_if #(lsu_rs_t) in0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t) in1_if (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t) out0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t) out1_if (.clk(clk), .rst_n(rst_n));

    int fail_count;

    load_store_queue #(
        .LOAD_DEPTH(4),
        .STORE_DEPTH(4)
    ) dut (
        .wb_valid(wb_valid),
        .wb_is_fp(wb_is_fp),
        .wb_preg(wb_preg),
        .wb_result(wb_result),
        .wb1_valid(wb1_valid),
        .wb1_is_fp(wb1_is_fp),
        .wb1_preg(wb1_preg),
        .wb1_result(wb1_result),
        .complete_valid0(complete_valid0),
        .complete_tag0(complete_tag0),
        .complete_valid1(complete_valid1),
        .complete_tag1(complete_tag1),
        .commit_valid0(commit_valid0),
        .commit_tag0(commit_tag0),
        .commit_valid1(commit_valid1),
        .commit_tag1(commit_tag1),
        .flush(flush),
        .squash_en(squash_en),
        .squash_checkpoint_id(squash_checkpoint_id),
        .resolve_en(resolve_en),
        .resolve_checkpoint_id(resolve_checkpoint_id),
        .in0_if(in0_if.consumer),
        .in1_if(in1_if.consumer),
        .out0_if(out0_if.producer),
        .out1_if(out1_if.producer),
        .replay_valid(replay_valid),
        .replay_tag(replay_tag),
        .replay_pc(replay_pc)
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

    function automatic lsu_rs_t make_load(
        input rob_tag_t tag,
        input logic [WIDTH-1:0] pc,
        input logic [WIDTH-1:0] address
    );
        lsu_rs_t entry;
    begin
        entry = '0;
        entry.control_signal.reg_write = 1'b1;
        entry.control_signal.mem_read = 1'b1;
        entry.control_signal.funct3 = 3'b010;
        entry.datapath.rob_tag = tag;
        entry.datapath.pc = pc;
        entry.datapath.src1_value = address;
        entry.src1_ready = 1'b1;
        entry.src2_ready = 1'b1;
        make_load = entry;
    end
    endfunction

    function automatic lsu_rs_t make_store(
        input rob_tag_t tag,
        input logic [WIDTH-1:0] address,
        input logic address_ready,
        input preg_t address_preg
    );
        lsu_rs_t entry;
    begin
        entry = '0;
        entry.control_signal.mem_write = 1'b1;
        entry.control_signal.funct3 = 3'b010;
        entry.datapath.rob_tag = tag;
        entry.datapath.src_reg_1p = address_preg;
        entry.datapath.src1_value = address;
        entry.datapath.src2_value = 32'hdead_beef;
        entry.src1_ready = address_ready;
        entry.src2_ready = 1'b1;
        make_store = entry;
    end
    endfunction

    initial begin
        rst_n = 1'b0;
        wb_valid = 1'b0;
        wb_is_fp = 1'b0;
        wb_preg = '0;
        wb_result = '0;
        wb1_valid = 1'b0;
        wb1_is_fp = 1'b0;
        wb1_preg = '0;
        wb1_result = '0;
        complete_valid0 = 1'b0;
        complete_tag0 = '0;
        complete_valid1 = 1'b0;
        complete_tag1 = '0;
        commit_valid0 = 1'b0;
        commit_tag0 = '0;
        commit_valid1 = 1'b0;
        commit_tag1 = '0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        in0_if.valid = 1'b0;
        in0_if.data = '0;
        in1_if.valid = 1'b0;
        in1_if.data = '0;
        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        fail_count = 0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        in0_if.valid = 1'b1;
        in0_if.data = make_load(rob_tag_t'(8'd1), 32'h100, 32'h0);
        in1_if.valid = 1'b1;
        in1_if.data = make_load(rob_tag_t'(8'd2), 32'h104, 32'h4);
        #1;
        check_ok(in0_if.ready && in1_if.ready,
                 "LSQ accepts two loads atomically");
        step_clk;
        in0_if.valid = 1'b0;
        in1_if.valid = 1'b0;
        #1;
        check_ok(out0_if.valid && out1_if.valid,
                 "LSQ exposes two ready memory operations");
        check_ok(out0_if.data.datapath.rob_tag == rob_tag_t'(8'd1) &&
                 out1_if.data.datapath.rob_tag == rob_tag_t'(8'd2),
                 "dual dequeue preserves program order");
        check_ok(out0_if.data.datapath.mem_seq + 1'b1 ==
                 out1_if.data.datapath.mem_seq,
                 "same-packet memory sequence numbers are consecutive");

        out0_if.ready = 1'b1;
        out1_if.ready = 1'b1;
        step_clk;
        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;
        #1;
        check_ok(!out0_if.valid && !out1_if.valid,
                 "issued loads stay in history without issuing twice");

        complete_valid0 = 1'b1;
        complete_tag0 = rob_tag_t'(8'd1);
        complete_valid1 = 1'b1;
        complete_tag1 = rob_tag_t'(8'd2);
        step_clk;
        complete_valid0 = 1'b0;
        complete_valid1 = 1'b0;
        commit_valid0 = 1'b1;
        commit_tag0 = rob_tag_t'(8'd1);
        commit_valid1 = 1'b1;
        commit_tag1 = rob_tag_t'(8'd2);
        step_clk;
        commit_valid0 = 1'b0;
        commit_valid1 = 1'b0;

        in0_if.valid = 1'b1;
        in0_if.data = make_store(
            rob_tag_t'(8'd10), 32'h0, 1'b0, preg_t'(7'd40));
        in1_if.valid = 1'b1;
        in1_if.data = make_load(
            rob_tag_t'(8'd11), 32'h200, 32'h20);
        step_clk;
        in0_if.valid = 1'b0;
        in1_if.valid = 1'b0;
        #1;
        check_ok(out0_if.valid &&
                 (out0_if.data.datapath.rob_tag == rob_tag_t'(8'd11)),
                 "younger load may bypass an older unresolved store");
        out0_if.ready = 1'b1;
        step_clk;
        out0_if.ready = 1'b0;

        wb_valid = 1'b1;
        wb_preg = preg_t'(7'd40);
        wb_result = 32'h20;
        step_clk;
        wb_valid = 1'b0;
        #1;
        check_ok(replay_valid &&
                 (replay_tag == rob_tag_t'(8'd11)) &&
                 (replay_pc == 32'h200),
                 "late older-store alias requests load replay");
        step_clk;
        check_ok(replay_valid &&
                 (replay_tag == rob_tag_t'(8'd11)),
                 "memory-order violation remains sticky until recovery");

        flush = 1'b1;
        step_clk;
        flush = 1'b0;
        #1;
        check_ok(!replay_valid && !out0_if.valid,
                 "full replay flush clears load/store history");

        in0_if.valid = 1'b1;
        in0_if.data = make_store(
            rob_tag_t'(8'd20), 32'h0, 1'b0, preg_t'(7'd40));
        in1_if.valid = 1'b1;
        in1_if.data = make_load(
            rob_tag_t'(8'd21), 32'h300, 32'h20);
        step_clk;
        in0_if.data = make_store(
            rob_tag_t'(8'd22), 32'h0, 1'b0, preg_t'(7'd41));
        in1_if.data = make_load(
            rob_tag_t'(8'd23), 32'h304, 32'h24);
        step_clk;
        in0_if.valid = 1'b0;
        in1_if.valid = 1'b0;
        out0_if.ready = 1'b1;
        out1_if.ready = 1'b1;
        repeat (2) step_clk;
        out0_if.ready = 1'b0;
        out1_if.ready = 1'b0;

        wb_valid = 1'b1;
        wb_preg = preg_t'(7'd41);
        wb_result = 32'h24;
        step_clk;
        wb_valid = 1'b0;
        #1;
        check_ok(replay_valid &&
                 (replay_tag == rob_tag_t'(8'd23)),
                 "younger violation may become pending first");

        wb_valid = 1'b1;
        wb_preg = preg_t'(7'd40);
        wb_result = 32'h20;
        step_clk;
        wb_valid = 1'b0;
        #1;
        check_ok(replay_valid &&
                 (replay_tag == rob_tag_t'(8'd21)) &&
                 (replay_pc == 32'h300),
                 "older late violation supersedes younger replay");

        if (fail_count == 0) begin
            $display("==== tb_load_store_queue PASS ====");
        end else begin
            $display("==== tb_load_store_queue FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
