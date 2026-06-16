`timescale 1ns/1ps

module tb_reg_file_2w;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic w_en;
    preg_t w_addr;
    logic [WIDTH-1:0] w_data;
    logic w1_en;
    preg_t w1_addr;
    logic [WIDTH-1:0] w1_data;
    preg_t lane0_raddr0;
    preg_t lane0_raddr1;
    preg_t lane1_raddr0;
    preg_t lane1_raddr1;
    logic [WIDTH-1:0] lane0_rdata0;
    logic [WIDTH-1:0] lane0_rdata1;
    logic [WIDTH-1:0] lane1_rdata0;
    logic [WIDTH-1:0] lane1_rdata1;
    logic [1:0] rename_en;
    preg_t lane0_src1_valid_addr;
    preg_t lane0_src2_valid_addr;
    preg_t lane0_new_des_preg;
    preg_t lane1_src1_valid_addr;
    preg_t lane1_src2_valid_addr;
    preg_t lane1_new_des_preg;
    logic lane0_src1_ready;
    logic lane0_src2_ready;
    logic lane1_src1_ready;
    logic lane1_src2_ready;

    reg_file_2w dut (
        .clk(clk),
        .rst_n(rst_n),
        .w_en(w_en),
        .w_addr(w_addr),
        .w_data(w_data),
        .w1_en(w1_en),
        .w1_addr(w1_addr),
        .w1_data(w1_data),
        .lane0_raddr0(lane0_raddr0),
        .lane0_rdata0(lane0_rdata0),
        .lane0_raddr1(lane0_raddr1),
        .lane0_rdata1(lane0_rdata1),
        .lane1_raddr0(lane1_raddr0),
        .lane1_rdata0(lane1_rdata0),
        .lane1_raddr1(lane1_raddr1),
        .lane1_rdata1(lane1_rdata1),
        .rename_en(rename_en),
        .lane0_src1_valid_addr(lane0_src1_valid_addr),
        .lane0_src2_valid_addr(lane0_src2_valid_addr),
        .lane0_new_des_preg(lane0_new_des_preg),
        .lane1_src1_valid_addr(lane1_src1_valid_addr),
        .lane1_src2_valid_addr(lane1_src2_valid_addr),
        .lane1_new_des_preg(lane1_new_des_preg),
        .lane0_src1_ready(lane0_src1_ready),
        .lane0_src2_ready(lane0_src2_ready),
        .lane1_src1_ready(lane1_src1_ready),
        .lane1_src2_ready(lane1_src2_ready)
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

    task automatic write_preg(input preg_t addr, input logic [WIDTH-1:0] data);
    begin
        rename_en = 2'b00;
        w_en = 1'b1;
        w_addr = addr;
        w_data = data;
        step_clk;
        w_en = 1'b0;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        w_en = 1'b0;
        w_addr = '0;
        w_data = '0;
        w1_en = 1'b0;
        w1_addr = '0;
        w1_data = '0;
        lane0_raddr0 = '0;
        lane0_raddr1 = '0;
        lane1_raddr0 = '0;
        lane1_raddr1 = '0;
        rename_en = 2'b00;
        lane0_src1_valid_addr = '0;
        lane0_src2_valid_addr = '0;
        lane0_new_des_preg = '0;
        lane1_src1_valid_addr = '0;
        lane1_src2_valid_addr = '0;
        lane1_new_des_preg = '0;

        repeat (2) step_clk;
        rst_n = 1'b1;
        step_clk;

        lane0_src1_valid_addr = preg_t'(32);
        lane0_src2_valid_addr = preg_t'(33);
        lane1_src1_valid_addr = preg_t'(34);
        lane1_src2_valid_addr = preg_t'(35);
        #1;
        check_ok(lane0_src1_ready && lane0_src2_ready &&
                 lane1_src1_ready && lane1_src2_ready,
                 "all physical registers start ready");

        write_preg(preg_t'(32), 32'hAAAA_0032);
        write_preg(preg_t'(33), 32'hBBBB_0033);
        write_preg(preg_t'(34), 32'hCCCC_0034);
        write_preg(preg_t'(35), 32'hDDDD_0035);

        lane0_raddr0 = preg_t'(32);
        lane0_raddr1 = preg_t'(33);
        lane1_raddr0 = preg_t'(34);
        lane1_raddr1 = preg_t'(35);
        #1;
        check_ok(lane0_rdata0 == 32'hAAAA_0032, "lane0 read port 0 reads preg 32");
        check_ok(lane0_rdata1 == 32'hBBBB_0033, "lane0 read port 1 reads preg 33");
        check_ok(lane1_rdata0 == 32'hCCCC_0034, "lane1 read port 0 reads preg 34");
        check_ok(lane1_rdata1 == 32'hDDDD_0035, "lane1 read port 1 reads preg 35");

        rename_en = 2'b11;
        lane0_new_des_preg = preg_t'(40);
        lane1_new_des_preg = preg_t'(41);
        lane0_src1_valid_addr = preg_t'(40);
        lane1_src1_valid_addr = preg_t'(41);
        lane1_src2_valid_addr = preg_t'(40);
        #1;
        check_ok(!lane0_src1_ready, "lane0 sees pending rename clear before clock edge");
        check_ok(!lane1_src1_ready, "lane1 sees its own pending rename clear before clock edge");
        check_ok(!lane1_src2_ready, "lane1 sees lane0 pending rename clear for same-packet RAW");
        step_clk;

        rename_en = 2'b00;
        lane0_new_des_preg = '0;
        lane1_new_des_preg = '0;
        lane1_src2_valid_addr = preg_t'(35);
        #1;
        check_ok(!lane0_src1_ready, "lane0 rename clears new preg ready bit");
        check_ok(!lane1_src1_ready, "lane1 rename clears new preg ready bit");

        write_preg(preg_t'(40), 32'h4444_0040);
        #1;
        check_ok(lane0_src1_ready, "writeback marks lane0 renamed preg ready");
        write_preg(preg_t'(41), 32'h5555_0041);
        #1;
        check_ok(lane0_src1_ready, "lane0 renamed preg stays ready after lane1 writeback");
        check_ok(lane1_src1_ready, "writeback marks lane1 renamed preg ready");

        rename_en = 2'b11;
        lane0_new_des_preg = preg_t'(43);
        lane1_new_des_preg = preg_t'(44);
        lane0_src1_valid_addr = preg_t'(43);
        lane1_src1_valid_addr = preg_t'(44);
        step_clk;

        rename_en = 2'b00;
        w_en = 1'b1;
        w_addr = preg_t'(43);
        w_data = 32'h7777_0043;
        w1_en = 1'b1;
        w1_addr = preg_t'(44);
        w1_data = 32'h8888_0044;
        lane0_raddr0 = preg_t'(43);
        lane1_raddr0 = preg_t'(44);
        #1;
        check_ok(lane0_rdata0 == 32'h7777_0043, "dual writeback forwards lane0 write port");
        check_ok(lane1_rdata0 == 32'h8888_0044, "dual writeback forwards lane1 write port");
        step_clk;

        w_en = 1'b0;
        w1_en = 1'b0;
        #1;
        check_ok(lane0_src1_ready, "dual writeback marks first preg ready");
        check_ok(lane1_src1_ready, "dual writeback marks second preg ready");

        rename_en = 2'b01;
        lane0_new_des_preg = preg_t'(42);
        w_en = 1'b1;
        w_addr = preg_t'(42);
        w_data = 32'h6666_0042;
        lane0_src2_valid_addr = preg_t'(42);
        lane0_raddr1 = preg_t'(42);
        #1;
        check_ok(lane0_rdata1 == 32'h6666_0042, "same-cycle writeback forwards read data");
        step_clk;

        rename_en = 2'b00;
        w_en = 1'b0;
        #1;
        check_ok(lane0_src2_ready, "same-cycle writeback wins over rename clear");
        lane0_raddr1 = preg_t'(42);
        #1;
        check_ok(lane0_rdata1 == 32'h6666_0042, "same-cycle writeback data is stored");

        $display("==== tb_reg_file_2w PASS ====");
        $finish;
    end

endmodule
