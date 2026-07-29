`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for rename packet stage.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_rename_packet_stage;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic flush;
    logic restore_rat;
    cp_id_t restore_checkpoint_id;
    cp_mask_t active_checkpoint_mask;
    logic [1:0] retire_valid;
    preg_t retire_preg0;
    preg_t retire_preg1;

    pip_if #(decode_rat_packet_t) in_if  (.clk(clk), .rst_n(rst_n));
    pip_if #(rat_dis_packet_t)    out_if (.clk(clk), .rst_n(rst_n));

    rename_packet_stage dut (
        .flush(flush),
        .restore_rat(restore_rat),
        .restore_checkpoint_id(restore_checkpoint_id),
        .active_checkpoint_mask(active_checkpoint_mask),
        .in_if(in_if.consumer),
        .out_if(out_if.producer),
        .retire_valid(retire_valid),
        .retire_preg0(retire_preg0),
        .retire_preg1(retire_preg1)
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

    task automatic set_alu_lane(
        output decode_rat_lane_t lane,
        input  logic             valid,
        input  logic [31:0]      pc,
        input  areg_t            rs1,
        input  areg_t            rs2,
        input  areg_t            rd,
        input  logic             do_rename
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.datapath.pc = pc;
        lane.data.datapath.rs1 = rs1;
        lane.data.datapath.rs2 = rs2;
        lane.data.datapath.rd = rd;
        lane.data.datapath.instr = 32'h0000_0033;
        lane.data.control_signal.rs_control_signal.fu_type = FU_ALU;
        lane.data.control_signal.rs_control_signal.rename = do_rename;
        lane.data.control_signal.rs_control_signal.alu_control_signal.reg_write = do_rename;
        lane.data.control_signal.rs_control_signal.alu_control_signal.alu_op = ALU_ADD;
    end
    endtask

    task automatic set_branch_lane(
        output decode_rat_lane_t lane,
        input  logic             valid,
        input  logic [31:0]      pc,
        input  areg_t            rs1,
        input  areg_t            rs2,
        input  areg_t            rd,
        input  logic             do_rename
    );
    begin
        lane = '0;
        lane.valid = valid;
        lane.data.datapath.pc = pc;
        lane.data.datapath.rs1 = rs1;
        lane.data.datapath.rs2 = rs2;
        lane.data.datapath.rd = rd;
        lane.data.datapath.instr = 32'h0000_0063;
        lane.data.control_signal.rs_control_signal.fu_type = FU_BRANCH;
        lane.data.control_signal.rs_control_signal.rename = do_rename;
        lane.data.control_signal.rs_control_signal.branch_control_signal.branch = 1'b1;
        lane.data.control_signal.rob_control_signal.branch = 1'b1;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        flush = 1'b0;
        restore_rat = 1'b0;
        restore_checkpoint_id = '0;
        active_checkpoint_mask = '0;
        retire_valid = 2'b00;
        retire_preg0 = '0;
        retire_preg1 = '0;
        in_if.valid = 1'b0;
        in_if.data = '0;
        out_if.ready = 1'b0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        in_if.valid = 1'b1;
        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_0000, areg_t'(1), areg_t'(2), areg_t'(5), 1'b1);
        set_alu_lane(in_if.data.lane1, 1'b1, 32'h0000_0004, areg_t'(5), areg_t'(3), areg_t'(6), 1'b1);
        out_if.ready = 1'b0;
        #1;
        check_ok(out_if.valid == 1'b1, "rename packet can present valid under backpressure");
        check_ok(in_if.ready == 1'b0, "backpressure holds rename input");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(32), "lane0 previews first physical allocation");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.new_des_preg == preg_t'(33), "lane1 previews second physical allocation");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.src_reg_1p == preg_t'(32), "lane1 RAW source bypasses lane0 allocation");

        out_if.ready = 1'b1;
        #1;
        check_ok(in_if.ready == 1'b1, "ready propagates when packet rename can fire");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(0), "lane0 receives ROB tag 0");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(1), "lane1 receives ROB tag 1");
        check_ok(out_if.data.lane0.data.rob_entry.datapath.old_des_preg == preg_t'(5), "lane0 old dest comes from architectural mapping");
        check_ok(out_if.data.lane1.data.rob_entry.datapath.old_des_preg == preg_t'(6), "lane1 old dest comes from architectural mapping");
        step_clk;

        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_0008, areg_t'(5), areg_t'(6), areg_t'(0), 1'b0);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.src_reg_1p == preg_t'(32), "later packet sees lane0 RAT update");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.src_reg_2p == preg_t'(33), "later packet sees lane1 RAT update");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.rob_tag == rob_tag_t'(2), "single-lane packet receives next ROB tag");
        step_clk;

        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_000c, areg_t'(0), areg_t'(0), areg_t'(7), 1'b1);
        set_alu_lane(in_if.data.lane1, 1'b1, 32'h0000_0010, areg_t'(0), areg_t'(0), areg_t'(7), 1'b1);
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(34), "WAW lane0 receives next allocation");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.new_des_preg == preg_t'(35), "WAW lane1 receives following allocation");
        check_ok(out_if.data.lane1.data.rob_entry.datapath.old_des_preg == preg_t'(34), "WAW lane1 old dest is lane0 new mapping");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.rob_tag == rob_tag_t'(4), "WAW lane1 ROB tag accounts for prior single packet");
        step_clk;

        set_branch_lane(in_if.data.lane0, 1'b1, 32'h0000_0014, areg_t'(1), areg_t'(2), areg_t'(8), 1'b1);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(36), "branch lane receives next allocation");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.checkpoint_id == cp_id_t'(0), "branch allocates first checkpoint");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.speculation_mask == '0, "branch is not speculative under its own checkpoint");
        step_clk;

        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_0018, areg_t'(0), areg_t'(0), areg_t'(8), 1'b1);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(37), "post-checkpoint write advances allocation");
        step_clk;

        in_if.valid = 1'b0;
        restore_rat = 1'b1;
        restore_checkpoint_id = cp_id_t'(0);
        step_clk;

        restore_rat = 1'b0;
        in_if.valid = 1'b1;
        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_001c, areg_t'(8), areg_t'(0), areg_t'(0), 1'b0);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.src_reg_1p == preg_t'(36), "restore recovers checkpointed branch rename");

        in_if.valid = 1'b0;
        rst_n = 1'b0;
        step_clk;
        rst_n = 1'b1;
        step_clk;

        in_if.valid = 1'b1;
        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_0040,
                     areg_t'(0), areg_t'(0), areg_t'(9), 1'b1);
        set_branch_lane(in_if.data.lane1, 1'b1, 32'h0000_0044,
                        areg_t'(0), areg_t'(0), areg_t'(1), 1'b1);
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(32),
                 "lane0 before lane1 branch receives first allocation");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.new_des_preg == preg_t'(33),
                 "lane1 branch receives second allocation");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.checkpoint_id == cp_id_t'(0),
                 "lane1 branch allocates checkpoint zero");
        check_ok(out_if.data.lane1.data.rs_entry.datapath.speculation_mask == '0,
                 "lane1 branch is not speculative under its own checkpoint");
        step_clk;

        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_0048,
                     areg_t'(0), areg_t'(0), areg_t'(9), 1'b1);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.new_des_preg == preg_t'(34),
                 "younger packet advances mapping past lane1 checkpoint");
        step_clk;

        in_if.valid = 1'b0;
        restore_rat = 1'b1;
        restore_checkpoint_id = cp_id_t'(0);
        step_clk;
        restore_rat = 1'b0;

        in_if.valid = 1'b1;
        set_alu_lane(in_if.data.lane0, 1'b1, 32'h0000_004c,
                     areg_t'(9), areg_t'(1), areg_t'(0), 1'b0);
        in_if.data.lane1 = '0;
        #1;
        check_ok(out_if.data.lane0.data.rs_entry.datapath.src_reg_1p == preg_t'(32),
                 "lane1 branch restore preserves older lane0 rename");
        check_ok(out_if.data.lane0.data.rs_entry.datapath.src_reg_2p == preg_t'(33),
                 "lane1 branch restore preserves branch link rename");

        $display("==== tb_rename_packet_stage PASS ====");
        $finish;
    end

endmodule
