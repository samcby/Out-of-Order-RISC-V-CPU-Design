`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for decode packet stage.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_decode_packet_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;

    pip_if #(fetch_decode_packet_t) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(decode_rat_packet_t)   out_if (.clk(clk), .rst_n(rst_n));

    decode_packet_stage dut (
        .in_if (in_if.consumer),
        .out_if(out_if.producer)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

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

    initial begin
        rst_n = 1'b0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b1;

        in_if.valid = 1'b1;
        in_if.data = '0;
        in_if.data.lane0.valid = 1'b1;
        in_if.data.lane0.data.pc = 32'h0000_0000;
        in_if.data.lane0.data.instr = 32'h0050_0093; // addi x1, x0, 5

        in_if.data.lane1.valid = 1'b1;
        in_if.data.lane1.data.pc = 32'h0000_0004;
        in_if.data.lane1.data.instr = 32'h0021_a623; // sw x2, 12(x3)

        out_if.ready = 1'b0;
        #1;

        check_ok(in_if.ready == 1'b0, "backpressure propagates through packet decode");
        check_ok(out_if.valid == 1'b1, "decode packet valid follows input valid");
        check_ok(out_if.data.lane0.valid == 1'b1, "lane0 remains valid");
        check_ok(out_if.data.lane1.valid == 1'b1, "lane1 remains valid");

        check_ok(out_if.data.lane0.data.datapath.pc == 32'h0000_0000, "lane0 pc decoded");
        check_ok(out_if.data.lane0.data.datapath.rd == 5'd1, "lane0 rd decoded");
        check_ok(out_if.data.lane0.data.datapath.rs1 == 5'd0, "lane0 rs1 decoded");
        check_ok(out_if.data.lane0.data.datapath.rs2 == 5'd0, "lane0 rs2 decoded");
        check_ok(out_if.data.lane0.data.datapath.imm == 32'd5, "lane0 immediate decoded");
        check_ok(out_if.data.lane0.data.control_signal.rs_control_signal.fu_type == FU_ALU, "lane0 FU is ALU");
        check_ok(out_if.data.lane0.data.control_signal.rs_control_signal.rename == 1'b1, "lane0 requests rename");
        check_ok(out_if.data.lane0.data.control_signal.rs_control_signal.alu_control_signal.alu_op == ALU_ADD, "lane0 ADDI uses ADD ALU op");

        check_ok(out_if.data.lane1.data.datapath.pc == 32'h0000_0004, "lane1 pc decoded");
        check_ok(out_if.data.lane1.data.datapath.rd == 5'd12, "lane1 rd field preserved for ROB metadata");
        check_ok(out_if.data.lane1.data.datapath.rs1 == 5'd3, "lane1 rs1 decoded");
        check_ok(out_if.data.lane1.data.datapath.rs2 == 5'd2, "lane1 rs2 decoded");
        check_ok(out_if.data.lane1.data.datapath.imm == 32'd12, "lane1 store immediate decoded");
        check_ok(out_if.data.lane1.data.control_signal.rs_control_signal.fu_type == FU_MEM, "lane1 FU is MEM");
        check_ok(out_if.data.lane1.data.control_signal.rs_control_signal.rename == 1'b0, "lane1 store does not rename");
        check_ok(out_if.data.lane1.data.control_signal.rs_control_signal.lsu_control_signal.mem_write == 1'b1, "lane1 store enables memory write");

        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready == 1'b1, "ready propagates through packet decode");

        in_if.data.lane1.valid = 1'b0;
        #1;
        check_ok(out_if.data.lane0.valid == 1'b1, "lane0 can remain valid alone");
        check_ok(out_if.data.lane1.valid == 1'b0, "lane1 can be independently disabled");

        $display("==== tb_decode_packet_stage PASS ====");
        $finish;
    end

endmodule
