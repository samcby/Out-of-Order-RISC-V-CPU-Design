module reg_file (
    input  logic clk,
    input  logic rst_n,

    input  logic                 w_en,
    input  defines_pkg::preg_t   w_addr,
    input  logic [defines_pkg::WIDTH-1:0] w_data,

    input  defines_pkg::preg_t   raddr0,
    output logic [defines_pkg::WIDTH-1:0] rdata0,

    input  defines_pkg::preg_t   raddr1,
    output logic [defines_pkg::WIDTH-1:0] rdata1,

    input  logic                 rename_en,
    input  defines_pkg::preg_t   src1_valid_addr,
    input  defines_pkg::preg_t   src2_valid_addr,
    input  defines_pkg::preg_t   new_des_preg,

    output logic                 src1_ready,
    output logic                 src2_ready
);
    import defines_pkg::*;

    logic [WIDTH-1:0] regs [0:PREG_NUM-1];
    logic             ready_bits [0:PREG_NUM-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PREG_NUM; i++) begin
                regs[i] <= '0;
                ready_bits[i] <= 1'b1;
            end
        end else begin
            if (rename_en && (new_des_preg != '0)) begin
                ready_bits[new_des_preg] <= 1'b0;
            end

            if (w_en) begin
                regs[w_addr] <= w_data;
                ready_bits[w_addr] <= 1'b1;
            end
        end
    end

    assign rdata0 = regs[raddr0];
    assign rdata1 = regs[raddr1];

    assign src1_ready = ready_bits[src1_valid_addr];
    assign src2_ready = ready_bits[src2_valid_addr];

endmodule
