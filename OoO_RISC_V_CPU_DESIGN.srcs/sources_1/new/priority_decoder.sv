// Lowest-index priority encoder.
//
// `in` is a request bitmap. `valid` is the reduction-OR of that bitmap and
// `out` identifies the first asserted bit, with index zero having the highest
// priority. Queue modules use this block to select a free entry; age-based
// instruction issue is implemented separately and must not rely on index order.
module priority_decoder #(
    parameter int WIDTH = 8
)(
    input  logic [WIDTH-1:0] in,
    output logic                  valid,
    output logic [$clog2(WIDTH)-1:0] idx
);

    always_comb begin
        valid = |in;
        idx   = '0;

        for (int i = 0; i < WIDTH; i++) begin
            if (in[i]) begin
                idx = i[$clog2(WIDTH)-1:0];
                break;
            end
        end
    end

endmodule
