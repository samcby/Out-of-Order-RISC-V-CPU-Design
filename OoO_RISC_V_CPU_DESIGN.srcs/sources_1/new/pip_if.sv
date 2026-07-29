// Generic ready/valid transport used between pipeline stages.
//
// A transfer occurs only on a rising clock edge for which valid && ready is
// true. The producer owns valid/data and must keep data stable while stalled;
// the consumer owns ready and may apply backpressure. The interface carries
// clk/rst_n as shared timing signals so nested modules do not need duplicate
// clock/reset ports for every transport channel.
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
