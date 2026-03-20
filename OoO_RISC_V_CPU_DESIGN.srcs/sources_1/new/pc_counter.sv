module pc_counter #(
    parameter int WIDTH = 32
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             step_en,

    input  logic             redirect_en,
    input  logic [WIDTH-1:0] redirect_pc,

    output logic             valid,
    output logic [WIDTH-1:0] current_pc
);

    logic [WIDTH-1:0] pc_q;
    logic [WIDTH-1:0] pc_n;

    always_comb begin
        if (redirect_en) begin
            pc_n = redirect_pc;
        end else begin
            pc_n = pc_q + WIDTH'(32'd4);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q <= '0;
        end else if (step_en) begin
            pc_q <= pc_n;
        end
    end

    assign current_pc = redirect_en ? redirect_pc : pc_q;
    assign valid      = rst_n;

endmodule
