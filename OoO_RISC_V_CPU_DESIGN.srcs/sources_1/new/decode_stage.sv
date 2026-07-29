// Legacy scalar decode wrapper.
//
// Decodes one fetched instruction for the original single-wide pipeline. The
// active backend uses decode_packet_stage, which instantiates one decode_lane
// per packet lane. This module remains synthesizable for top.sv compatibility.
module decode_stage #(
    parameter int WIDTH = 32
)(
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    import defines_pkg::*;

    assign in_if.ready  = out_if.ready;
    assign out_if.valid = in_if.valid;

    decode_lane #(
        .WIDTH(WIDTH)
    ) u_decode_lane (
        .in_data (in_if.data),
        .out_data(out_if.data)
    );

endmodule
