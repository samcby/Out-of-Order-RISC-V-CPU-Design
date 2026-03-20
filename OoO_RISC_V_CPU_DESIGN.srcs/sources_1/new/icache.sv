module icache #(
    parameter int WIDTH = 32,
    parameter int DEPTH_BYTES = 4096
)(
    input  logic             clk,
    input  logic             rst_n,
    input  logic             start,

    input  logic             load_en,
    input  logic [WIDTH-1:0] load_addr,
    input  logic [7:0]       load_instr_byte,

    input  logic [WIDTH-1:0] addr,
    output logic [WIDTH-1:0] instr
);

    localparam int WORDS = DEPTH_BYTES / 4;
    localparam int WORD_AW = $clog2(WORDS);

    (* ram_style = "block" *) logic [31:0] mem [0:WORDS-1];

    logic [WORD_AW-1:0] load_word_idx;
    logic [1:0]         load_byte_off;
    logic [WORD_AW-1:0] read_word_idx;

    assign load_word_idx = load_addr[WORD_AW+1:2];
    assign load_byte_off = load_addr[1:0];
    assign read_word_idx = addr[WORD_AW+1:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < WORDS; i++) begin
                mem[i] <= '0;
            end
        end else if (load_en) begin
            case (load_byte_off)
                2'd0: mem[load_word_idx][7:0]   <= load_instr_byte;
                2'd1: mem[load_word_idx][15:8]  <= load_instr_byte;
                2'd2: mem[load_word_idx][23:16] <= load_instr_byte;
                2'd3: mem[load_word_idx][31:24] <= load_instr_byte;
                default: ;
            endcase
        end
    end

    assign instr = start ? mem[read_word_idx] : '0;

endmodule
