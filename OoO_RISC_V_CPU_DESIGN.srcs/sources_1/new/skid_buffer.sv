module skid_buffer #(
    parameter type T = logic [31:0]
)(
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    logic hold_valid;
    T     hold_data;

    assign out_if.valid = hold_valid ? 1'b1    : in_if.valid;
    assign out_if.data  = hold_valid ? hold_data : in_if.data;
    assign in_if.ready  = !hold_valid && out_if.ready;

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n) begin
            hold_valid <= 1'b0;
            hold_data  <= '0;
        end else begin
            if (!hold_valid && in_if.valid && !out_if.ready) begin
                hold_valid <= 1'b1;
                hold_data  <= in_if.data;
            end else if (hold_valid && out_if.ready) begin
                hold_valid <= 1'b0;
            end
        end
    end

endmodule
