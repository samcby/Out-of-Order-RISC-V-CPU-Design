module circular_buffer #(
    parameter type T = logic [31:0],
    parameter int DEPTH = 8,
    parameter bit INIT_FULL = 1'b0,
    parameter int INIT_BASE = 0
)(
    input  logic clk,
    input  logic rst_n,

    input  logic push,
    input  logic pop,
    input  T     push_data,
    output T     pop_data,

    output logic full,
    output logic empty,
    output logic [$clog2(DEPTH+1)-1:0] count
);

    localparam int PTR_W = $clog2(DEPTH);

    T mem [0:DEPTH-1];

    logic [PTR_W-1:0] head_q, tail_q;
    logic [PTR_W-1:0] head_n, tail_n;
    logic [$clog2(DEPTH+1)-1:0] count_q, count_n;

    assign pop_data = mem[head_q];
    assign full     = (count_q == DEPTH);
    assign empty    = (count_q == 0);
    assign count    = count_q;

    always_comb begin
        head_n  = head_q;
        tail_n  = tail_q;
        count_n = count_q;

        case ({push && !full, pop && !empty})
            2'b10: begin
                tail_n  = (tail_q == DEPTH-1) ? '0 : (tail_q + 1'b1);
                count_n = count_q + 1'b1;
            end
            2'b01: begin
                head_n  = (head_q == DEPTH-1) ? '0 : (head_q + 1'b1);
                count_n = count_q - 1'b1;
            end
            2'b11: begin
                tail_n  = (tail_q == DEPTH-1) ? '0 : (tail_q + 1'b1);
                head_n  = (head_q == DEPTH-1) ? '0 : (head_q + 1'b1);
                count_n = count_q;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= INIT_FULL ? DEPTH : '0;

            for (int i = 0; i < DEPTH; i++) begin
                mem[i] <= T'(INIT_BASE + i);
            end
        end else begin
            if (push && !full) begin
                mem[tail_q] <= push_data;
            end

            head_q  <= head_n;
            tail_q  <= tail_n;
            count_q <= count_n;
        end
    end

endmodule
