module decode_packet_lane0_adapter (
    input logic flush,
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    import defines_pkg::*;

    logic        hold_valid_q;
    decode_rat_t hold_data_q;

    logic packet_has_data;
    logic packet_two_lanes;

    assign packet_has_data = in_if.valid &&
                             (in_if.data.lane0.valid || in_if.data.lane1.valid);
    assign packet_two_lanes = in_if.valid &&
                              in_if.data.lane0.valid &&
                              in_if.data.lane1.valid;

    assign out_if.valid = !flush && (hold_valid_q || packet_has_data);
    assign out_if.data  = hold_valid_q ? hold_data_q :
                          in_if.data.lane0.valid ? in_if.data.lane0.data :
                          in_if.data.lane1.data;

    // Serializer mode: consume a packet only when lane0 can be accepted. If
    // lane1 is also valid, it is retained and replayed on the following cycle.
    assign in_if.ready = !flush && !hold_valid_q && (!packet_has_data || out_if.ready);

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            hold_valid_q <= 1'b0;
            hold_data_q  <= '0;
        end else begin
            if (hold_valid_q && out_if.ready) begin
                hold_valid_q <= 1'b0;
            end

            if (!hold_valid_q && in_if.ready && packet_two_lanes) begin
                hold_valid_q <= 1'b1;
                hold_data_q  <= in_if.data.lane1.data;
            end
        end
    end

endmodule
