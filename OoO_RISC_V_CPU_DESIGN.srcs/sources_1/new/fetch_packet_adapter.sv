module fetch_packet_adapter (
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    import defines_pkg::*;

    assign in_if.ready = out_if.ready;
    assign out_if.valid = in_if.valid;

    always_comb begin
        out_if.data = '0;
        out_if.data.lane0.valid = in_if.valid;
        out_if.data.lane0.data  = in_if.data;
        out_if.data.lane1.valid = 1'b0;
    end

endmodule
