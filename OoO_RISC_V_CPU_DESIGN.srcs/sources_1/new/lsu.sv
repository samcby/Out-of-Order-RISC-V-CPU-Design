module lsu #(
    parameter int MEM_WORDS = 256
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  defines_pkg::lsu_control_t      control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    output logic [defines_pkg::WIDTH-1:0]  load_result
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);

    logic [WIDTH-1:0] mem [0:MEM_WORDS-1];
    logic [WIDTH-1:0] eff_addr;
    logic [ADDR_W-1:0] word_addr;
    logic [1:0] byte_off;
    logic [WIDTH-1:0] curr_word;
    logic [7:0] load_byte;
    logic [WIDTH-1:0] next_word;

    assign eff_addr  = datapath.src1_value + datapath.imm;
    assign word_addr = eff_addr[ADDR_W+1:2];
    assign byte_off  = eff_addr[1:0];
    assign curr_word = mem[word_addr];

    always_comb begin
        unique case (byte_off)
            2'd0: load_byte = curr_word[7:0];
            2'd1: load_byte = curr_word[15:8];
            2'd2: load_byte = curr_word[23:16];
            default: load_byte = curr_word[31:24];
        endcase
    end

    always_comb begin
        load_result = '0;
        if (control_signal.mem_read) begin
            unique case (control_signal.funct3)
                3'b010: load_result = curr_word;                  // LW
                3'b100: load_result = {24'h0, load_byte};         // LBU
                default: load_result = '0;
            endcase
        end
    end

    always_comb begin
        next_word = curr_word;
        if (control_signal.mem_write) begin
            unique case (control_signal.funct3)
                3'b010: next_word = datapath.src2_value; // SW
                3'b001: begin                            // SH
                    unique case (byte_off)
                        2'd0: next_word[15:0]  = datapath.src2_value[15:0];
                        2'd1: next_word[23:8]  = datapath.src2_value[15:0];
                        2'd2: next_word[31:16] = datapath.src2_value[15:0];
                        default: next_word = curr_word;
                    endcase
                end
                default: next_word = curr_word;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MEM_WORDS; i++) begin
                mem[i] <= '0;
            end
        end else if (control_signal.mem_write) begin
            mem[word_addr] <= next_word;
        end
    end

endmodule
