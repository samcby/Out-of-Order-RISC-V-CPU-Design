`timescale 1ns / 1ps

module fp_csr (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        csr_we,
    input  logic [11:0] csr_addr,
    input  logic [31:0] csr_wdata,
    input  logic        flags_valid,
    input  logic [4:0]  flags,
    output logic [31:0] csr_rdata,
    output logic [4:0]  fflags,
    output logic [2:0]  frm,
    output logic [7:0]  fcsr
);

    import fp_defines_pkg::*;

    logic [4:0] next_fflags;
    logic [2:0] next_frm;

    always_comb begin
        next_fflags = fflags;
        next_frm = frm;

        if (csr_we) begin
            unique case (csr_addr)
                CSR_FFLAGS: next_fflags = csr_wdata[4:0];
                CSR_FRM:    next_frm = csr_wdata[2:0];
                CSR_FCSR: begin
                    next_fflags = csr_wdata[4:0];
                    next_frm = csr_wdata[7:5];
                end
                default: begin
                end
            endcase
        end

        if (flags_valid) next_fflags = next_fflags | flags;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fflags <= '0;
            frm <= '0;
        end else begin
            fflags <= next_fflags;
            frm <= next_frm;
        end
    end

    assign fcsr = {frm, fflags};

    always_comb begin
        unique case (csr_addr)
            CSR_FFLAGS: csr_rdata = {27'b0, fflags};
            CSR_FRM:    csr_rdata = {29'b0, frm};
            CSR_FCSR:   csr_rdata = {24'b0, fcsr};
            default:    csr_rdata = '0;
        endcase
    end

endmodule
