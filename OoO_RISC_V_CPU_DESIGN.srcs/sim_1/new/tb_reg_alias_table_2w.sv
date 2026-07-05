`timescale 1ns/1ps

module tb_reg_alias_table_2w;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic [1:0] w_en;
    logic checkpoint_save;
    cp_id_t checkpoint_id_save;
    logic restore_en;
    cp_id_t restore_checkpoint_id;

    areg_t lane0_src_reg_1a;
    areg_t lane0_src_reg_2a;
    areg_t lane0_des_reg_a;
    preg_t lane0_new_des_preg;
    areg_t lane1_src_reg_1a;
    areg_t lane1_src_reg_2a;
    areg_t lane1_des_reg_a;
    preg_t lane1_new_des_preg;

    preg_t lane0_src_reg_1p;
    preg_t lane0_src_reg_2p;
    preg_t lane0_old_des_preg;
    preg_t lane1_src_reg_1p;
    preg_t lane1_src_reg_2p;
    preg_t lane1_old_des_preg;
    logic [PREG_NUM-1:0] mapped_bitmap;

    reg_alias_table_2w dut (
        .clk(clk),
        .rst_n(rst_n),
        .w_en(w_en),
        .checkpoint_save(checkpoint_save),
        .checkpoint_id_save(checkpoint_id_save),
        .restore_en(restore_en),
        .restore_checkpoint_id(restore_checkpoint_id),
        .lane0_src_reg_1a(lane0_src_reg_1a),
        .lane0_src_reg_2a(lane0_src_reg_2a),
        .lane0_des_reg_a(lane0_des_reg_a),
        .lane0_new_des_preg(lane0_new_des_preg),
        .lane1_src_reg_1a(lane1_src_reg_1a),
        .lane1_src_reg_2a(lane1_src_reg_2a),
        .lane1_des_reg_a(lane1_des_reg_a),
        .lane1_new_des_preg(lane1_new_des_preg),
        .lane0_src_reg_1p(lane0_src_reg_1p),
        .lane0_src_reg_2p(lane0_src_reg_2p),
        .lane0_old_des_preg(lane0_old_des_preg),
        .lane1_src_reg_1p(lane1_src_reg_1p),
        .lane1_src_reg_2p(lane1_src_reg_2p),
        .lane1_old_des_preg(lane1_old_des_preg),
        .mapped_bitmap(mapped_bitmap)
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

    initial begin
        rst_n = 1'b0;
        w_en = 2'b00;
        checkpoint_save = 1'b0;
        checkpoint_id_save = '0;
        restore_en = 1'b0;
        restore_checkpoint_id = '0;
        lane0_src_reg_1a = '0;
        lane0_src_reg_2a = '0;
        lane0_des_reg_a = '0;
        lane0_new_des_preg = '0;
        lane1_src_reg_1a = '0;
        lane1_src_reg_2a = '0;
        lane1_des_reg_a = '0;
        lane1_new_des_preg = '0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        lane0_src_reg_1a = areg_t'(1);
        lane0_src_reg_2a = areg_t'(2);
        lane0_des_reg_a = areg_t'(5);
        lane0_new_des_preg = preg_t'(32);
        lane1_src_reg_1a = areg_t'(5);
        lane1_src_reg_2a = areg_t'(6);
        lane1_des_reg_a = areg_t'(6);
        lane1_new_des_preg = preg_t'(33);
        w_en = 2'b11;
        #1;
        check_ok(lane0_src_reg_1p == preg_t'(1), "lane0 source reads old RAT");
        check_ok(lane0_old_des_preg == preg_t'(5), "lane0 old dest reads old mapping");
        check_ok(lane1_src_reg_1p == preg_t'(32), "lane1 RAW source bypasses lane0 rename");
        check_ok(lane1_old_des_preg == preg_t'(6), "lane1 old dest reads old mapping");
        step_clk;

        w_en = 2'b00;
        lane0_src_reg_1a = areg_t'(5);
        lane1_src_reg_1a = areg_t'(6);
        #1;
        check_ok(lane0_src_reg_1p == preg_t'(32), "lane0 write committed into RAT");
        check_ok(lane1_src_reg_1p == preg_t'(33), "lane1 write committed into RAT");

        lane0_des_reg_a = areg_t'(7);
        lane0_new_des_preg = preg_t'(34);
        lane1_des_reg_a = areg_t'(7);
        lane1_new_des_preg = preg_t'(35);
        w_en = 2'b11;
        #1;
        check_ok(lane0_old_des_preg == preg_t'(7), "WAW lane0 old dest reads original mapping");
        check_ok(lane1_old_des_preg == preg_t'(34), "WAW lane1 old dest sees lane0 new mapping");
        step_clk;

        w_en = 2'b00;
        lane0_src_reg_1a = areg_t'(7);
        #1;
        check_ok(lane0_src_reg_1p == preg_t'(35), "WAW final RAT mapping comes from younger lane");

        lane0_des_reg_a = areg_t'(8);
        lane0_new_des_preg = preg_t'(36);
        lane1_des_reg_a = areg_t'(9);
        lane1_new_des_preg = preg_t'(37);
        checkpoint_save = 1'b1;
        checkpoint_id_save = cp_id_t'(1);
        w_en = 2'b11;
        step_clk;

        checkpoint_save = 1'b0;
        lane0_des_reg_a = areg_t'(8);
        lane0_new_des_preg = preg_t'(38);
        w_en = 2'b01;
        step_clk;

        w_en = 2'b00;
        restore_en = 1'b1;
        restore_checkpoint_id = cp_id_t'(1);
        step_clk;
        restore_en = 1'b0;
        lane0_src_reg_1a = areg_t'(8);
        lane1_src_reg_1a = areg_t'(9);
        #1;
        check_ok(lane0_src_reg_1p == preg_t'(36), "restore recovers checkpointed lane0 mapping");
        check_ok(lane1_src_reg_1p == preg_t'(37), "restore recovers checkpointed lane1 mapping");

        $display("==== tb_reg_alias_table_2w PASS ====");
        $finish;
    end

endmodule
