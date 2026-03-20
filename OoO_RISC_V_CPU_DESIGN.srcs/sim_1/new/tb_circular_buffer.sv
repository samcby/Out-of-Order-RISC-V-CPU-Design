`timescale 1ns/1ps

module tb_circular_buffer;

    localparam int DEPTH = 4;

    logic clk;
    logic rst_n;

    logic        push;
    logic        pop;
    logic [31:0] push_data;
    logic [31:0] pop_data;
    logic        full;
    logic        empty;
    logic [$clog2(DEPTH+1)-1:0] count;

    circular_buffer #(
        .T(logic [31:0]),
        .DEPTH(DEPTH),
        .INIT_FULL(1'b0),
        .INIT_BASE(0)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .push     (push),
        .pop      (pop),
        .push_data(push_data),
        .pop_data (pop_data),
        .full     (full),
        .empty    (empty),
        .count    (count)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok;
        input bit cond;
        input string msg;
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end
        else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    initial begin
        push = 1'b0;
        pop = 1'b0;
        push_data = 32'd0;
        rst_n = 1'b0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        check_ok(empty == 1'b1, "reset empty");
        check_ok(full  == 1'b0, "reset not full");
        check_ok(count == 0,    "reset count zero");

        push = 1'b1; pop = 1'b0; push_data = 32'h11;
        step_clk;
        check_ok(count == 1, "push 11 count=1");
        check_ok(pop_data == 32'h11, "head is 11");

        push_data = 32'h22;
        step_clk;
        check_ok(count == 2, "push 22 count=2");
        check_ok(pop_data == 32'h11, "head still 11");

        push_data = 32'h33;
        step_clk;

        push_data = 32'h44;
        step_clk;
        check_ok(full == 1'b1, "buffer full");
        check_ok(count == DEPTH, "count == depth");

        push = 1'b0; pop = 1'b1;
        check_ok(pop_data == 32'h11, "pop first sees 11");
        step_clk;
        check_ok(count == DEPTH-1, "after pop count=3");
        check_ok(pop_data == 32'h22, "new head is 22");

        push = 1'b1; pop = 1'b1; push_data = 32'h55;
        step_clk;
        check_ok(count == DEPTH-1, "simultaneous push/pop keeps count");
        check_ok(pop_data == 32'h33, "new head is 33");

        push = 1'b0; pop = 1'b1;
        step_clk;
        check_ok(pop_data == 32'h44, "new head is 44");

        step_clk;
        check_ok(pop_data == 32'h55, "new head is 55");

        step_clk;
        check_ok(empty == 1'b1, "buffer empty after drain");
        check_ok(count == 0, "count back to zero");

        $display("==== tb_circular_buffer PASS ====");
        $finish;
    end

endmodule
