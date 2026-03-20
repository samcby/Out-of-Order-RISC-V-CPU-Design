module imm_gen #(
    parameter int WIDTH = 32
)(
    input  logic [WIDTH-1:0] instr_in,
    input  logic [6:0]       op_code,
    output logic [WIDTH-1:0] imm
);

    logic [WIDTH-1:0] imm_i;
    logic [WIDTH-1:0] imm_s;
    logic [WIDTH-1:0] imm_b;
    logic [WIDTH-1:0] imm_u;
    logic [WIDTH-1:0] imm_j;

    always_comb begin
        imm_i = {{20{instr_in[31]}}, instr_in[31:20]};
        imm_s = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
        imm_b = {{19{instr_in[31]}}, instr_in[31], instr_in[7], instr_in[30:25], instr_in[11:8], 1'b0};
        imm_u = {instr_in[31:12], 12'b0};
        imm_j = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};

        unique case (op_code)
            7'b0010011, // OP-IMM
            7'b0000011, // LOAD
            7'b1100111: // JALR
                imm = imm_i;

            7'b0100011: // STORE
                imm = imm_s;

            7'b1100011: // BRANCH
                imm = imm_b;

            7'b0110111: // LUI
                imm = imm_u;

            7'b1101111: // JAL
                imm = imm_j;

            default:
                imm = '0;
        endcase
    end

endmodule
