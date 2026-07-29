`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for rat dis packet splitter.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_rat_dis_packet_splitter;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic flush;

    pip_if #(rat_dis_packet_t) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t) out_if (.clk(clk), .rst_n(rst_n));

    rat_dis_packet_splitter dut (
        .flush(flush),
        .in_if(in_if.consumer),
        .out_if(out_if.producer)
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
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic set_lane(
        output rat_dis_lane_t lane,
        input logic valid,
        input logic [1:0] fu_type,
        input rob_tag_t tag
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.rs_entry.control_signal.fu_type = fu_type;
        lane.data.rs_entry.datapath.rob_tag = tag;
        lane.data.rob_entry.datapath.rob_tag = tag;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        flush = 1'b0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(8'h10));
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(8'h11));
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready, "mixed packet is accepted");
        check_ok(out_if.valid, "mixed packet produces output");
        check_ok(out_if.data.lane0.valid && out_if.data.lane1.valid,
                 "mixed packet keeps both lanes");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h10),
                 "mixed packet lane0 preserved");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h11),
                 "mixed packet lane1 preserved");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(8'h20));
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(8'h21));
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.lane0.valid && out_if.data.lane1.valid,
                 "ALU+ALU packet stays 2-wide after ALU RS dual-enqueue");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h20),
                 "ALU+ALU lane0 tag preserved");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h21),
                 "ALU+ALU lane1 tag preserved");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(8'h24));
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(8'h25));
        in_if.data.lane0.data.rs_entry.datapath.speculation_mask = cp_mask_t'(1);
        in_if.data.lane1.data.rs_entry.datapath.speculation_mask = cp_mask_t'(1);
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.lane0.valid && !out_if.data.lane1.valid,
                 "speculative ALU+ALU packet emits lane0 first");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h24),
                 "speculative ALU+ALU lane0 tag preserved");
        step_clk;

        in_if.valid = 1'b0;
        #1;
        check_ok(out_if.valid && !out_if.data.lane0.valid && out_if.data.lane1.valid,
                 "speculative ALU+ALU deferred lane returns as lane1");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h25),
                 "speculative ALU+ALU deferred lane1 tag preserved");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(8'h26));
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(8'h27));
        in_if.data.lane0.data.rs_entry.datapath.new_des_preg = preg_t'(7'd45);
        in_if.data.lane1.data.rs_entry.datapath.src_reg_1p = preg_t'(7'd45);
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.lane0.valid && !out_if.data.lane1.valid,
                 "dependent ALU+ALU packet emits lane0 first");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h26),
                 "dependent ALU+ALU lane0 tag preserved");
        step_clk;

        in_if.valid = 1'b0;
        #1;
        check_ok(out_if.valid && !out_if.data.lane0.valid && out_if.data.lane1.valid,
                 "dependent ALU+ALU deferred lane returns as lane1");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h27),
                 "dependent ALU+ALU deferred lane1 tag preserved");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_MEM, rob_tag_t'(8'h22));
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(8'h23));
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.lane0.valid && !out_if.data.lane1.valid,
                 "MEM+MEM duplicate-FU packet emits lane0 first");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h22),
                 "MEM+MEM duplicate-FU lane0 tag preserved");
        step_clk;

        in_if.valid = 1'b0;
        #1;
        check_ok(out_if.valid, "deferred lane remains valid");
        check_ok(!in_if.ready, "input stalls while deferred lane is pending");
        check_ok(!out_if.data.lane0.valid && out_if.data.lane1.valid,
                 "deferred instruction returns as lane1");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(8'h23),
                 "deferred lane1 tag preserved");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_MEM, rob_tag_t'(8'h28));
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(8'h29));
        in_if.valid = 1'b1;
        out_if.ready = 1'b1;
        #1;
        check_ok(out_if.data.lane0.valid && !out_if.data.lane1.valid,
                 "flush test split packet emits lane0 first");
        step_clk;

        in_if.valid = 1'b0;
        flush = 1'b1;
        #1;
        check_ok(!out_if.valid, "flush suppresses pending deferred lane output");
        step_clk;

        flush = 1'b0;
        #1;
        check_ok(!out_if.valid, "flush clears pending deferred lane");
        step_clk;

        set_lane(in_if.data.lane0, 1'b1, FU_MEM, rob_tag_t'(8'h30));
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(8'h31));
        in_if.valid = 1'b1;
        out_if.ready = 1'b0;
        #1;
        check_ok(!in_if.ready, "backpressure blocks new packet");
        check_ok(out_if.valid, "output remains valid under backpressure");
        step_clk;

        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready, "input accepted after backpressure clears");
        step_clk;

        in_if.valid = 1'b0;
        #1;
        check_ok(out_if.valid && out_if.data.lane1.valid,
                 "deferred lane appears after accepted split under backpressure");
        step_clk;

        $display("==== tb_rat_dis_packet_splitter PASS ====");
        $finish;
    end

endmodule
