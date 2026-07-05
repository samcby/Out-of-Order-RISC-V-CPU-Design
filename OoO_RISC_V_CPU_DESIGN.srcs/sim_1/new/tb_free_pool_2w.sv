`timescale 1ns/1ps

module tb_free_pool_2w;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic [1:0] push;
    logic [1:0] pop;
    logic pop_commit;
    preg_t push_data0;
    preg_t push_data1;
    preg_t pop_data0;
    preg_t pop_data1;
    logic [PREG_NUM-1:0] mapped_bitmap;
    logic pop_valid0;
    logic pop_valid1;
    logic checkpoint_save;
    cp_id_t checkpoint_id_save;
    logic restore_en;
    cp_id_t restore_checkpoint_id;
    logic full;
    logic empty;
    logic has_free_1;
    logic has_free_2;

    free_pool_2w dut (
        .clk(clk),
        .rst_n(rst_n),
        .push(push),
        .pop(pop),
        .pop_commit(pop_commit),
        .push_data0(push_data0),
        .push_data1(push_data1),
        .mapped_bitmap(mapped_bitmap),
        .pop_data0(pop_data0),
        .pop_data1(pop_data1),
        .pop_valid0(pop_valid0),
        .pop_valid1(pop_valid1),
        .checkpoint_save(checkpoint_save),
        .checkpoint_id_save(checkpoint_id_save),
        .restore_en(restore_en),
        .restore_checkpoint_id(restore_checkpoint_id),
        .full(full),
        .empty(empty),
        .has_free_1(has_free_1),
        .has_free_2(has_free_2)
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
        push = 2'b00;
        pop = 2'b00;
        pop_commit = 1'b0;
        push_data0 = '0;
        push_data1 = '0;
        mapped_bitmap = '0;
        checkpoint_save = 1'b0;
        checkpoint_id_save = '0;
        restore_en = 1'b0;
        restore_checkpoint_id = '0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(!empty, "free pool has physical registers after reset");
        check_ok(full, "free pool starts with all non-architectural registers free");

        pop = 2'b11;
        #1;
        check_ok(pop_valid0 && pop_valid1, "dual pop returns two valid registers");
        check_ok(pop_data0 == preg_t'(32), "dual pop lane0 receives first free preg");
        check_ok(pop_data1 == preg_t'(33), "dual pop lane1 receives second free preg");
        pop_commit = 1'b1;
        step_clk;
        pop_commit = 1'b0;

        pop = 2'b10;
        #1;
        check_ok(!pop_valid0 && pop_valid1, "lane1-only pop is supported");
        check_ok(pop_data1 == preg_t'(34), "lane1-only pop receives next free preg");
        pop_commit = 1'b1;
        step_clk;
        pop_commit = 1'b0;

        pop = 2'b00;
        push = 2'b11;
        push_data0 = preg_t'(32);
        push_data1 = preg_t'(33);
        step_clk;

        push = 2'b00;
        pop = 2'b11;
        #1;
        check_ok(pop_data0 == preg_t'(32), "returned preg can be reallocated on lane0");
        check_ok(pop_data1 == preg_t'(33), "returned preg can be reallocated on lane1");
        pop_commit = 1'b1;
        step_clk;
        pop_commit = 1'b0;

        pop = 2'b00;
        checkpoint_save = 1'b1;
        checkpoint_id_save = cp_id_t'(2);
        step_clk;

        checkpoint_save = 1'b0;
        pop = 2'b11;
        #1;
        check_ok(pop_data0 == preg_t'(35), "post-checkpoint allocation lane0 advances");
        check_ok(pop_data1 == preg_t'(36), "post-checkpoint allocation lane1 advances");
        pop_commit = 1'b1;
        step_clk;
        pop_commit = 1'b0;

        pop = 2'b00;
        restore_en = 1'b1;
        restore_checkpoint_id = cp_id_t'(2);
        step_clk;

        restore_en = 1'b0;
        pop = 2'b11;
        #1;
        check_ok(pop_data0 == preg_t'(35), "restore makes checkpointed free preg visible again on lane0");
        check_ok(pop_data1 == preg_t'(36), "restore makes checkpointed free preg visible again on lane1");
        pop_commit = 1'b1;
        step_clk;
        pop_commit = 1'b0;

        $display("==== tb_free_pool_2w PASS ====");
        $finish;
    end

endmodule
