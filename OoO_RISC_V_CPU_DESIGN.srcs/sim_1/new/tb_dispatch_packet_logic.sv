`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for dispatch packet logic.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_dispatch_packet_logic;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic lane0_src1_ready;
    logic lane0_src2_ready;
    logic [WIDTH-1:0] lane0_src1_value;
    logic [WIDTH-1:0] lane0_src2_value;
    logic lane1_src1_ready;
    logic lane1_src2_ready;
    logic [WIDTH-1:0] lane1_src1_value;
    logic [WIDTH-1:0] lane1_src2_value;
    logic csr_pending;

    pip_if #(rat_dis_packet_t) in_if (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t) rob_packet_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) alu_if (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t) alu1_if (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t) lsu_if (.clk(clk), .rst_n(rst_n));
    pip_if #(branch_rs_t) branch_if (.clk(clk), .rst_n(rst_n));

    dispatch_packet_logic dut (
        .in_if(in_if.consumer),
        .lane0_src1_ready(lane0_src1_ready),
        .lane0_src2_ready(lane0_src2_ready),
        .lane0_src1_value(lane0_src1_value),
        .lane0_src2_value(lane0_src2_value),
        .lane1_src1_ready(lane1_src1_ready),
        .lane1_src2_ready(lane1_src2_ready),
        .lane1_src1_value(lane1_src1_value),
        .lane1_src2_value(lane1_src2_value),
        .csr_pending(csr_pending),
        .rob_packet_if(rob_packet_if.producer),
        .alu_if(alu_if.producer),
        .alu1_if(alu1_if.producer),
        .lsu_if(lsu_if.producer),
        .branch_if(branch_if.producer)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

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
        input  logic          valid,
        input  logic [1:0]    fu_type,
        input  rob_tag_t      tag,
        input  logic          csr_en
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.rs_entry.control_signal.fu_type = fu_type;
        lane.data.rs_entry.control_signal.alu_control_signal.csr_en = csr_en;
        lane.data.rs_entry.datapath.rob_tag = tag;
        lane.data.rob_entry.datapath.rob_tag = tag;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        rob_packet_if.ready = 1'b0;
        alu_if.ready = 1'b0;
        alu1_if.ready = 1'b0;
        lsu_if.ready = 1'b0;
        branch_if.ready = 1'b0;
        lane0_src1_ready = 1'b0;
        lane0_src2_ready = 1'b0;
        lane0_src1_value = '0;
        lane0_src2_value = '0;
        lane1_src1_ready = 1'b0;
        lane1_src2_ready = 1'b0;
        lane1_src1_value = '0;
        lane1_src2_value = '0;
        csr_pending = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b1;

        in_if.valid = 1'b1;
        rob_packet_if.ready = 1'b1;
        alu_if.ready = 1'b1;
        alu1_if.ready = 1'b1;
        lsu_if.ready = 1'b1;
        branch_if.ready = 1'b1;
        lane0_src1_ready = 1'b1;
        lane0_src2_ready = 1'b0;
        lane0_src1_value = 32'h1111_0001;
        lane0_src2_value = 32'h1111_0002;
        lane1_src1_ready = 1'b0;
        lane1_src2_ready = 1'b1;
        lane1_src1_value = 32'h2222_0001;
        lane1_src2_value = 32'h2222_0002;
        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(1), 1'b0);
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(2), 1'b0);
        #1;
        check_ok(in_if.ready, "mixed ALU/MEM packet dispatches");
        check_ok(rob_packet_if.valid, "ROB packet valid for mixed packet");
        check_ok(rob_packet_if.data.lane0.valid && rob_packet_if.data.lane1.valid, "ROB receives both lanes");
        check_ok(alu_if.valid && alu_if.data.datapath.rob_tag == rob_tag_t'(1), "ALU receives lane0");
        check_ok(lsu_if.valid && lsu_if.data.datapath.rob_tag == rob_tag_t'(2), "LSU receives lane1");
        check_ok(alu_if.data.src1_ready == 1'b1, "lane0 source readiness is inserted");
        check_ok(lsu_if.data.datapath.src2_value == 32'h2222_0002, "lane1 source value is inserted");

        rob_packet_if.ready = 1'b0;
        #1;
        check_ok(!in_if.ready, "ROB backpressure stalls packet dispatch");
        check_ok(!alu_if.valid && !lsu_if.valid, "no RS valid when packet is stalled");

        rob_packet_if.ready = 1'b1;
        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(3), 1'b0);
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(4), 1'b0);
        #1;
        check_ok(in_if.ready, "duplicate ALU lanes dispatch through dual ALU RS ports");
        check_ok(alu_if.valid && alu_if.data.datapath.rob_tag == rob_tag_t'(3),
                 "first ALU receives lane0");
        check_ok(alu1_if.valid && alu1_if.data.datapath.rob_tag == rob_tag_t'(4),
                 "second ALU receives lane1");

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(9), 1'b0);
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(10), 1'b0);
        in_if.data.lane0.data.rs_entry.datapath.speculation_mask = cp_mask_t'(1);
        in_if.data.lane1.data.rs_entry.datapath.speculation_mask = cp_mask_t'(1);
        #1;
        check_ok(!in_if.ready, "speculative ALU+ALU packet is held for splitter serialization");
        check_ok(!alu_if.valid && !alu1_if.valid,
                 "speculative ALU+ALU packet does not dispatch both ALU ports directly");

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(11), 1'b0);
        set_lane(in_if.data.lane1, 1'b1, FU_ALU, rob_tag_t'(12), 1'b0);
        in_if.data.lane0.data.rs_entry.datapath.new_des_preg = preg_t'(7'd45);
        in_if.data.lane1.data.rs_entry.datapath.src_reg_1p = preg_t'(7'd45);
        #1;
        check_ok(!in_if.ready, "dependent ALU+ALU packet is held for splitter serialization");
        check_ok(!alu_if.valid && !alu1_if.valid,
                 "dependent ALU+ALU packet does not dispatch both ALU ports directly");

        set_lane(in_if.data.lane0, 1'b1, FU_NOP, rob_tag_t'(5), 1'b0);
        set_lane(in_if.data.lane1, 1'b1, FU_BRANCH, rob_tag_t'(6), 1'b0);
        #1;
        check_ok(in_if.ready, "NOP plus branch packet dispatches");
        check_ok(rob_packet_if.data.lane0.valid == 1'b0, "NOP lane is removed from ROB packet");
        check_ok(rob_packet_if.data.lane1.valid == 1'b1, "branch lane remains in ROB packet");
        check_ok(branch_if.valid && branch_if.data.datapath.rob_tag == rob_tag_t'(6), "branch receives lane1");

        set_lane(in_if.data.lane0, 1'b1, FU_ALU, rob_tag_t'(7), 1'b1);
        in_if.data.lane1 = '0;
        csr_pending = 1'b0;
        #1;
        check_ok(in_if.ready && alu_if.valid, "single CSR lane dispatches when CSR is free");

        csr_pending = 1'b1;
        #1;
        check_ok(!in_if.ready, "CSR pending blocks a new CSR lane");

        csr_pending = 1'b0;
        set_lane(in_if.data.lane1, 1'b1, FU_MEM, rob_tag_t'(8), 1'b0);
        #1;
        check_ok(!in_if.ready, "CSR lane serializes with non-CSR younger lane");

        $display("==== tb_dispatch_packet_logic PASS ====");
        $finish;
    end

endmodule
