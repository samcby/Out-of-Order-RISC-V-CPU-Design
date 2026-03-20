module skid_buffer_pipe #(
    parameter type T = logic [31:0]
)(
    input logic flush,
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    logic valid_q;
    T     data_q;

    assign in_if.ready  = !valid_q || out_if.ready;
    assign out_if.valid = valid_q;
    assign out_if.data  = data_q;

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            valid_q <= 1'b0;
            data_q  <= '0;
        end else if (in_if.ready) begin
            valid_q <= in_if.valid;
            if (in_if.valid) begin
                data_q <= in_if.data;
            end
        end
    end

endmodule
