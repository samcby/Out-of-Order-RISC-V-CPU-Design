module decode_controller (
    input  logic [6:0] op_code,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,

    output logic       reg_write,
    output logic       alu_src,
    output logic       branch,
    output logic       mem_read,
    output logic       mem_write,
    output logic       jump,
    output logic       jump_reg,
    output logic [3:0] alu_op,
    output logic [1:0] fu_type,
    output logic       rename
);

    import defines_pkg::*;

    always_comb begin
        reg_write = 1'b0;
        alu_src   = 1'b0;
        branch    = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        jump      = 1'b0;
        jump_reg  = 1'b0;
        alu_op    = ALU_NOP;
        fu_type   = FU_NOP;
        rename    = 1'b0;

        unique case (op_code)
            7'b0110011: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                fu_type   = FU_ALU;
                rename    = 1'b1;

                unique case ({funct7, funct3})
                    {7'b0000000, 3'b111}: alu_op = ALU_AND;
                    {7'b0100000, 3'b000}: alu_op = ALU_SUB;
                    {7'b0100000, 3'b101}: alu_op = ALU_SRA;
                    default:              alu_op = ALU_NOP;
                endcase
            end

            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                fu_type   = FU_ALU;
                rename    = 1'b1;

                unique case (funct3)
                    3'b000: alu_op = ALU_ADD;   // ADDI
                    3'b110: alu_op = ALU_OR;    // ORI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    default: alu_op = ALU_NOP;
                endcase
            end

            7'b0100011: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b0;
                alu_op    = ALU_ADD;
            end

            7'b0000011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_read  = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b1;
                alu_op    = ALU_ADD;
            end

            7'b1100011: begin
                branch  = 1'b1;
                fu_type = FU_BRANCH;
                rename  = 1'b0;
                alu_op  = ALU_SUB;
            end

            7'b1100111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jump      = 1'b1;
                jump_reg  = 1'b1;
                fu_type   = FU_BRANCH;
                rename    = 1'b1;
                alu_op    = ALU_ADD;
            end

            7'b1101111: begin
                reg_write = 1'b1;
                jump      = 1'b1;
                jump_reg  = 1'b0;
                fu_type   = FU_BRANCH;
                rename    = 1'b1;
                alu_op    = ALU_ADD;
            end

            7'b0110111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                fu_type   = FU_ALU;
                rename    = 1'b1;
                alu_op    = ALU_LUI;
            end

            default: begin
            end
        endcase
    end

endmodule
