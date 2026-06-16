module reg_file_2w (
    input  logic clk,
    input  logic rst_n,

    input  logic                           w_en,
    input  defines_pkg::preg_t             w_addr,
    input  logic [defines_pkg::WIDTH-1:0]  w_data,
    input  logic                           w1_en,
    input  defines_pkg::preg_t             w1_addr,
    input  logic [defines_pkg::WIDTH-1:0]  w1_data,

    input  defines_pkg::preg_t             lane0_raddr0,
    output logic [defines_pkg::WIDTH-1:0]  lane0_rdata0,
    input  defines_pkg::preg_t             lane0_raddr1,
    output logic [defines_pkg::WIDTH-1:0]  lane0_rdata1,
    input  defines_pkg::preg_t             lane1_raddr0,
    output logic [defines_pkg::WIDTH-1:0]  lane1_rdata0,
    input  defines_pkg::preg_t             lane1_raddr1,
    output logic [defines_pkg::WIDTH-1:0]  lane1_rdata1,

    input  logic [1:0]                     rename_en,
    input  defines_pkg::preg_t             lane0_src1_valid_addr,
    input  defines_pkg::preg_t             lane0_src2_valid_addr,
    input  defines_pkg::preg_t             lane0_new_des_preg,
    input  defines_pkg::preg_t             lane1_src1_valid_addr,
    input  defines_pkg::preg_t             lane1_src2_valid_addr,
    input  defines_pkg::preg_t             lane1_new_des_preg,

    output logic                           lane0_src1_ready,
    output logic                           lane0_src2_ready,
    output logic                           lane1_src1_ready,
    output logic                           lane1_src2_ready
);
    import defines_pkg::*;

    logic [WIDTH-1:0] regs [0:PREG_NUM-1];
    logic ready_bits [0:PREG_NUM-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PREG_NUM; i++) begin
                regs[i] <= '0;
                ready_bits[i] <= 1'b1;
            end
        end else begin
            for (int i = 0; i < PREG_NUM; i++) begin
                if ((rename_en[0] && (lane0_new_des_preg == preg_t'(i)) && (lane0_new_des_preg != '0)) ||
                    (rename_en[1] && (lane1_new_des_preg == preg_t'(i)) && (lane1_new_des_preg != '0))) begin
                    ready_bits[i] <= 1'b0;
                end

                if ((w_en && (w_addr == preg_t'(i))) ||
                    (w1_en && (w1_addr == preg_t'(i)))) begin
                    ready_bits[i] <= 1'b1;
                end
            end

            if (w_en) begin
                regs[w_addr] <= w_data;
            end
            if (w1_en) begin
                regs[w1_addr] <= w1_data;
            end
        end
    end

    assign lane0_rdata0 = (w1_en && (w1_addr == lane0_raddr0)) ? w1_data :
                          (w_en && (w_addr == lane0_raddr0)) ? w_data : regs[lane0_raddr0];
    assign lane0_rdata1 = (w1_en && (w1_addr == lane0_raddr1)) ? w1_data :
                          (w_en && (w_addr == lane0_raddr1)) ? w_data : regs[lane0_raddr1];
    assign lane1_rdata0 = (w1_en && (w1_addr == lane1_raddr0)) ? w1_data :
                          (w_en && (w_addr == lane1_raddr0)) ? w_data : regs[lane1_raddr0];
    assign lane1_rdata1 = (w1_en && (w1_addr == lane1_raddr1)) ? w1_data :
                          (w_en && (w_addr == lane1_raddr1)) ? w_data : regs[lane1_raddr1];

    always_comb begin
        lane0_src1_ready = ready_bits[lane0_src1_valid_addr];
        lane0_src2_ready = ready_bits[lane0_src2_valid_addr];
        lane1_src1_ready = ready_bits[lane1_src1_valid_addr];
        lane1_src2_ready = ready_bits[lane1_src2_valid_addr];

        if (rename_en[0] && (lane0_new_des_preg != '0)) begin
            if (lane0_src1_valid_addr == lane0_new_des_preg) lane0_src1_ready = 1'b0;
            if (lane0_src2_valid_addr == lane0_new_des_preg) lane0_src2_ready = 1'b0;
            if (lane1_src1_valid_addr == lane0_new_des_preg) lane1_src1_ready = 1'b0;
            if (lane1_src2_valid_addr == lane0_new_des_preg) lane1_src2_ready = 1'b0;
        end

        if (rename_en[1] && (lane1_new_des_preg != '0)) begin
            if (lane0_src1_valid_addr == lane1_new_des_preg) lane0_src1_ready = 1'b0;
            if (lane0_src2_valid_addr == lane1_new_des_preg) lane0_src2_ready = 1'b0;
            if (lane1_src1_valid_addr == lane1_new_des_preg) lane1_src1_ready = 1'b0;
            if (lane1_src2_valid_addr == lane1_new_des_preg) lane1_src2_ready = 1'b0;
        end

        if (w_en) begin
            if (lane0_src1_valid_addr == w_addr) lane0_src1_ready = 1'b1;
            if (lane0_src2_valid_addr == w_addr) lane0_src2_ready = 1'b1;
            if (lane1_src1_valid_addr == w_addr) lane1_src1_ready = 1'b1;
            if (lane1_src2_valid_addr == w_addr) lane1_src2_ready = 1'b1;
        end

        if (w1_en) begin
            if (lane0_src1_valid_addr == w1_addr) lane0_src1_ready = 1'b1;
            if (lane0_src2_valid_addr == w1_addr) lane0_src2_ready = 1'b1;
            if (lane1_src1_valid_addr == w1_addr) lane1_src1_ready = 1'b1;
            if (lane1_src2_valid_addr == w1_addr) lane1_src2_ready = 1'b1;
        end
    end

endmodule
