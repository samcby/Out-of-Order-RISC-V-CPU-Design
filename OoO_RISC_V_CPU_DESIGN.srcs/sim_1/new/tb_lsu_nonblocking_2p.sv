`timescale 1ns/1ps

module tb_lsu_nonblocking_2p;
    import defines_pkg::*;

    localparam int MEM_WORDS = 32;

    logic clk;
    logic rst_n;
    logic req_valid;
    logic req_ready;
    logic flush;
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
    logic resp_dest_is_fp;
    logic [WIDTH-1:0] resp_result;
    logic idle;

    logic req1_valid;
    logic req1_ready;
    lsu_control_t control_signal1;
    rs_datapath_t datapath1;
    logic resp1_valid;
    rob_tag_t resp1_tag;
    preg_t resp1_preg;
    logic resp1_reg_write;
    logic resp1_dest_is_fp;
    logic [WIDTH-1:0] resp1_result;

    int fail_count;
    int wait_cycles;
    logic seen_tag1;
    logic seen_tag2;
    logic [WIDTH-1:0] result_tag1;
    logic [WIDTH-1:0] result_tag2;

    lsu #(
        .MEM_WORDS(MEM_WORDS),
        .DATA_CACHE_LINES(4),
        .DATA_CACHE_WAYS(2),
        .DATA_CACHE_WORDS_PER_LINE(4),
        .DATA_MEM_RESPONSE_LATENCY(3)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .flush(flush),
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
        .resp_dest_is_fp(resp_dest_is_fp),
        .resp_result(resp_result),
        .idle(idle),
        .req1_valid(req1_valid),
        .req1_ready(req1_ready),
        .control_signal1(control_signal1),
        .datapath1(datapath1),
        .resp1_valid(resp1_valid),
        .resp1_tag(resp1_tag),
        .resp1_preg(resp1_preg),
        .resp1_reg_write(resp1_reg_write),
        .resp1_dest_is_fp(resp1_dest_is_fp),
        .resp1_result(resp1_result)
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

    task automatic set_load(
        output lsu_control_t control,
        output rs_datapath_t data,
        input rob_tag_t tag,
        input preg_t preg,
        input logic [WIDTH-1:0] address,
        input mem_seq_t mem_order
    );
    begin
        control = '0;
        control.mem_read = 1'b1;
        control.reg_write = 1'b1;
        control.funct3 = 3'b010;
        data = '0;
        data.rob_tag = tag;
        data.new_des_preg = preg;
        data.src1_value = address;
        data.mem_seq = mem_order;
    end
    endtask

    task automatic observe_completions(
        input rob_tag_t tag_a,
        input rob_tag_t tag_b
    );
    begin
        seen_tag1 = 1'b0;
        seen_tag2 = 1'b0;
        result_tag1 = '0;
        result_tag2 = '0;
        wait_cycles = 0;
        while (!(seen_tag1 && seen_tag2) && (wait_cycles < 100)) begin
            if (resp_valid && (resp_tag == tag_a)) begin
                seen_tag1 = 1'b1;
                result_tag1 = resp_result;
            end
            if (resp_valid && (resp_tag == tag_b)) begin
                seen_tag2 = 1'b1;
                result_tag2 = resp_result;
            end
            if (resp1_valid && (resp1_tag == tag_a)) begin
                seen_tag1 = 1'b1;
                result_tag1 = resp1_result;
            end
            if (resp1_valid && (resp1_tag == tag_b)) begin
                seen_tag2 = 1'b1;
                result_tag2 = resp1_result;
            end
            wait_cycles++;
            step_clk;
        end
    end
    endtask

    initial begin
        rst_n = 1'b0;
        req_valid = 1'b0;
        req1_valid = 1'b0;
        flush = 1'b0;
        squash_en = 1'b0;
        squash_checkpoint_id = '0;
        resolve_en = 1'b0;
        resolve_checkpoint_id = '0;
        commit_store_valid0 = 1'b0;
        commit_store_tag0 = '0;
        commit_store_valid1 = 1'b0;
        commit_store_tag1 = '0;
        control_signal = '0;
        control_signal1 = '0;
        datapath = '0;
        datapath1 = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        dut.u_data_cache.u_data_memory.mem[0] = 32'h10203040;
        dut.u_data_cache.u_data_memory.mem[1] = 32'h55667788;
        dut.u_data_cache.u_data_memory.mem[4] = 32'ha1b2c3d4;

        set_load(control_signal, datapath, rob_tag_t'(8'd1),
                 preg_t'(7'd40), 32'h00000000, mem_seq_t'(16'd1));
        set_load(control_signal1, datapath1, rob_tag_t'(8'd2),
                 preg_t'(7'd41), 32'h00000010, mem_seq_t'(16'd2));
        req_valid = 1'b1;
        req1_valid = 1'b1;
        #1;
        check_ok(req_ready && req1_ready,
                 "LSU accepts two loads in the same cycle");
        step_clk;
        req_valid = 1'b0;
        req1_valid = 1'b0;
        control_signal = '0;
        control_signal1 = '0;
        datapath = '0;
        datapath1 = '0;

        step_clk;
        check_ok(dut.bank_owner_valid[0] && dut.bank_owner_valid[1],
                 "different-bank loads occupy both LSU MSHRs");
        observe_completions(rob_tag_t'(8'd1), rob_tag_t'(8'd2));
        check_ok(seen_tag1 && seen_tag2,
                 "both outstanding loads complete independently");
        check_ok(result_tag1 == 32'h10203040 &&
                 result_tag2 == 32'ha1b2c3d4,
                 "two-bank LSU load data is correct");

        set_load(control_signal, datapath, rob_tag_t'(8'd3),
                 preg_t'(7'd42), 32'h00000000, mem_seq_t'(16'd3));
        set_load(control_signal1, datapath1, rob_tag_t'(8'd4),
                 preg_t'(7'd43), 32'h00000004, mem_seq_t'(16'd4));
        req_valid = 1'b1;
        req1_valid = 1'b1;
        #1;
        check_ok(req_ready && req1_ready,
                 "same-bank loads are both retained by the load queue");
        step_clk;
        req_valid = 1'b0;
        req1_valid = 1'b0;
        control_signal = '0;
        control_signal1 = '0;
        datapath = '0;
        datapath1 = '0;

        observe_completions(rob_tag_t'(8'd3), rob_tag_t'(8'd4));
        check_ok(seen_tag1 && seen_tag2,
                 "same-bank loads serialize without losing a request");
        check_ok(result_tag1 == 32'h10203040 &&
                 result_tag2 == 32'h55667788,
                 "serialized same-bank load data is correct");

        wait_cycles = 0;
        while (!idle && (wait_cycles < 20)) begin
            wait_cycles++;
            step_clk;
        end
        check_ok(idle, "non-blocking LSU drains all queued operations");

        if (fail_count == 0) begin
            $display("==== tb_lsu_nonblocking_2p PASS ====");
        end else begin
            $display("==== tb_lsu_nonblocking_2p FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end
endmodule
