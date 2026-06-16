module decode_packet_stage #(
    parameter int WIDTH = 32
)(
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    import defines_pkg::*;

    decode_rat_t lane0_decoded;
    decode_rat_t lane1_decoded;

    assign in_if.ready  = out_if.ready;
    assign out_if.valid = in_if.valid;

    decode_lane #(
        .WIDTH(WIDTH)
    ) u_decode_lane0 (
        .in_data (in_if.data.lane0.data),
        .out_data(lane0_decoded)
    );

    decode_lane #(
        .WIDTH(WIDTH)
    ) u_decode_lane1 (
        .in_data (in_if.data.lane1.data),
        .out_data(lane1_decoded)
    );

    always_comb begin
        out_if.data = '0;

        out_if.data.lane0.valid = in_if.data.lane0.valid;
        out_if.data.lane1.valid = in_if.data.lane1.valid;

        if (in_if.data.lane0.valid) begin
            out_if.data.lane0.data = lane0_decoded;
        end

        if (in_if.data.lane1.valid) begin
            out_if.data.lane1.data = lane1_decoded;
        end
    end

endmodule
