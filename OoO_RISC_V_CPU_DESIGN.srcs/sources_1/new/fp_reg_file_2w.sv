`timescale 1ns / 1ps

// Multiported floating-point physical register file.
//
// Six combinational reads provide three operands for each of two lanes, which
// is required by fused multiply-add instructions. Two independent writeback
// ports update value/ready state and provide same-cycle bypass. The FP physical
// namespace is separate from the integer PRF, and physical register zero is a
// normal writable location because RISC-V f0 is not hard-wired to zero.
module fp_reg_file_2w (
    input  logic clk,
    input  logic rst_n,

    input  logic                         wb0_en,
    input  fp_defines_pkg::fp_preg_t     wb0_addr,
    input  logic [31:0]                  wb0_data,
    input  logic                         wb1_en,
    input  fp_defines_pkg::fp_preg_t     wb1_addr,
    input  logic [31:0]                  wb1_data,

    input  fp_defines_pkg::fp_preg_t     lane0_raddr0,
    output logic [31:0]                  lane0_rdata0,
    input  fp_defines_pkg::fp_preg_t     lane0_raddr1,
    output logic [31:0]                  lane0_rdata1,
    input  fp_defines_pkg::fp_preg_t     lane0_raddr2,
    output logic [31:0]                  lane0_rdata2,
    input  fp_defines_pkg::fp_preg_t     lane1_raddr0,
    output logic [31:0]                  lane1_rdata0,
    input  fp_defines_pkg::fp_preg_t     lane1_raddr1,
    output logic [31:0]                  lane1_rdata1,
    input  fp_defines_pkg::fp_preg_t     lane1_raddr2,
    output logic [31:0]                  lane1_rdata2,

    input  logic [1:0]                   rename_en,
    input  fp_defines_pkg::fp_preg_t     lane0_src1_addr,
    input  fp_defines_pkg::fp_preg_t     lane0_src2_addr,
    input  fp_defines_pkg::fp_preg_t     lane0_src3_addr,
    input  fp_defines_pkg::fp_preg_t     lane0_new_preg,
    input  fp_defines_pkg::fp_preg_t     lane1_src1_addr,
    input  fp_defines_pkg::fp_preg_t     lane1_src2_addr,
    input  fp_defines_pkg::fp_preg_t     lane1_src3_addr,
    input  fp_defines_pkg::fp_preg_t     lane1_new_preg,

    output logic                         lane0_src1_ready,
    output logic                         lane0_src2_ready,
    output logic                         lane0_src3_ready,
    output logic                         lane1_src1_ready,
    output logic                         lane1_src2_ready,
    output logic                         lane1_src3_ready
);

    import fp_defines_pkg::*;

    logic [31:0] regs [0:FP_PREG_NUM-1];
    logic ready_bits [0:FP_PREG_NUM-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < FP_PREG_NUM; i++) begin
                regs[i] <= '0;
                ready_bits[i] <= 1'b1;
            end
        end else begin
            for (int i = 0; i < FP_PREG_NUM; i++) begin
                if ((rename_en[0] && lane0_new_preg == fp_preg_t'(i)) ||
                    (rename_en[1] && lane1_new_preg == fp_preg_t'(i))) begin
                    ready_bits[i] <= 1'b0;
                end

                if ((wb0_en && wb0_addr == fp_preg_t'(i)) ||
                    (wb1_en && wb1_addr == fp_preg_t'(i))) begin
                    ready_bits[i] <= 1'b1;
                end
            end

            if (wb0_en) regs[wb0_addr] <= wb0_data;
            if (wb1_en) regs[wb1_addr] <= wb1_data;
        end
    end

    assign lane0_rdata0 = (wb1_en && wb1_addr == lane0_raddr0) ? wb1_data :
                          (wb0_en && wb0_addr == lane0_raddr0) ? wb0_data :
                          regs[lane0_raddr0];
    assign lane0_rdata1 = (wb1_en && wb1_addr == lane0_raddr1) ? wb1_data :
                          (wb0_en && wb0_addr == lane0_raddr1) ? wb0_data :
                          regs[lane0_raddr1];
    assign lane0_rdata2 = (wb1_en && wb1_addr == lane0_raddr2) ? wb1_data :
                          (wb0_en && wb0_addr == lane0_raddr2) ? wb0_data :
                          regs[lane0_raddr2];
    assign lane1_rdata0 = (wb1_en && wb1_addr == lane1_raddr0) ? wb1_data :
                          (wb0_en && wb0_addr == lane1_raddr0) ? wb0_data :
                          regs[lane1_raddr0];
    assign lane1_rdata1 = (wb1_en && wb1_addr == lane1_raddr1) ? wb1_data :
                          (wb0_en && wb0_addr == lane1_raddr1) ? wb0_data :
                          regs[lane1_raddr1];
    assign lane1_rdata2 = (wb1_en && wb1_addr == lane1_raddr2) ? wb1_data :
                          (wb0_en && wb0_addr == lane1_raddr2) ? wb0_data :
                          regs[lane1_raddr2];

    always_comb begin
        lane0_src1_ready = ready_bits[lane0_src1_addr];
        lane0_src2_ready = ready_bits[lane0_src2_addr];
        lane0_src3_ready = ready_bits[lane0_src3_addr];
        lane1_src1_ready = ready_bits[lane1_src1_addr];
        lane1_src2_ready = ready_bits[lane1_src2_addr];
        lane1_src3_ready = ready_bits[lane1_src3_addr];

        if (rename_en[0]) begin
            if (lane0_src1_addr == lane0_new_preg) lane0_src1_ready = 1'b0;
            if (lane0_src2_addr == lane0_new_preg) lane0_src2_ready = 1'b0;
            if (lane0_src3_addr == lane0_new_preg) lane0_src3_ready = 1'b0;
            if (lane1_src1_addr == lane0_new_preg) lane1_src1_ready = 1'b0;
            if (lane1_src2_addr == lane0_new_preg) lane1_src2_ready = 1'b0;
            if (lane1_src3_addr == lane0_new_preg) lane1_src3_ready = 1'b0;
        end
        if (rename_en[1]) begin
            if (lane0_src1_addr == lane1_new_preg) lane0_src1_ready = 1'b0;
            if (lane0_src2_addr == lane1_new_preg) lane0_src2_ready = 1'b0;
            if (lane0_src3_addr == lane1_new_preg) lane0_src3_ready = 1'b0;
            if (lane1_src1_addr == lane1_new_preg) lane1_src1_ready = 1'b0;
            if (lane1_src2_addr == lane1_new_preg) lane1_src2_ready = 1'b0;
            if (lane1_src3_addr == lane1_new_preg) lane1_src3_ready = 1'b0;
        end

        if (wb0_en) begin
            if (lane0_src1_addr == wb0_addr) lane0_src1_ready = 1'b1;
            if (lane0_src2_addr == wb0_addr) lane0_src2_ready = 1'b1;
            if (lane0_src3_addr == wb0_addr) lane0_src3_ready = 1'b1;
            if (lane1_src1_addr == wb0_addr) lane1_src1_ready = 1'b1;
            if (lane1_src2_addr == wb0_addr) lane1_src2_ready = 1'b1;
            if (lane1_src3_addr == wb0_addr) lane1_src3_ready = 1'b1;
        end
        if (wb1_en) begin
            if (lane0_src1_addr == wb1_addr) lane0_src1_ready = 1'b1;
            if (lane0_src2_addr == wb1_addr) lane0_src2_ready = 1'b1;
            if (lane0_src3_addr == wb1_addr) lane0_src3_ready = 1'b1;
            if (lane1_src1_addr == wb1_addr) lane1_src1_ready = 1'b1;
            if (lane1_src2_addr == wb1_addr) lane1_src2_ready = 1'b1;
            if (lane1_src3_addr == wb1_addr) lane1_src3_ready = 1'b1;
        end
    end

endmodule
