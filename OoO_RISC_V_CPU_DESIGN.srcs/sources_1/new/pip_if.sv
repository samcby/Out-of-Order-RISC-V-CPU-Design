interface pip_if #(
    parameter type T = logic [31:0]
)(
    input  logic clk,
    input  logic rst_n
);
    logic valid;
    logic ready;
    T     data;

    modport producer (
        input  clk, rst_n,
        input  ready,
        output valid, data
    );

    modport consumer (
        input  clk, rst_n,
        input  valid, data,
        output ready
    );
endinterface
