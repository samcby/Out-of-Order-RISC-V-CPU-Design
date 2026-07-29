`timescale 1ns / 1ps

// Decoder for the RV32F opcode space.
//
// Identifies floating-point sources/destinations, memory operations, fused
// three-source operations, conversions, comparisons, moves, and rounding-mode
// requirements. The result is a compact fp_decode_t description consumed by
// the main decode controller. Invalid funct combinations are reported through
// the `illegal` field rather than silently becoming a no-op.
module fp_decode (
    input  logic [31:0]                 instr,
    output fp_defines_pkg::fp_decode_t  decoded
);

    import fp_defines_pkg::*;

    logic [6:0] opcode;
    logic [6:0] funct7;
    logic [2:0] funct3;
    logic [4:0] rs1;
    logic [4:0] rs2;
    logic [4:0] rs3;
    logic [4:0] rd;

    function automatic logic rounding_mode_legal(input logic [2:0] rm);
    begin
        rounding_mode_legal = (rm <= 3'b100) || (rm == 3'b111);
    end
    endfunction

    task automatic set_fp_binary(input logic [4:0] operation);
    begin
        decoded.operation  = operation;
        decoded.fp_rs1_valid = 1'b1;
        decoded.fp_rs2_valid = 1'b1;
        decoded.fp_rd_valid  = 1'b1;
    end
    endtask

    always_comb begin
        opcode = instr[6:0];
        funct7 = instr[31:25];
        funct3 = instr[14:12];
        rs1    = instr[19:15];
        rs2    = instr[24:20];
        rs3    = instr[31:27];
        rd     = instr[11:7];

        decoded = '0;
        decoded.int_rs1 = rs1;
        decoded.int_rd  = rd;
        decoded.fp_rs1  = rs1;
        decoded.fp_rs2  = rs2;
        decoded.fp_rs3  = rs3;
        decoded.fp_rd   = rd;
        decoded.rounding_mode = funct3;

        unique case (opcode)
            7'b0000111: begin // FLW
                decoded.valid = 1'b1;
                decoded.illegal = (funct3 != 3'b010);
                if (funct3 == 3'b010) begin
                    decoded.operation = FP_OP_LOAD;
                    decoded.mem_read = 1'b1;
                    decoded.int_rs1_valid = 1'b1;
                    decoded.fp_rd_valid = 1'b1;
                end
            end

            7'b0100111: begin // FSW
                decoded.valid = 1'b1;
                decoded.illegal = (funct3 != 3'b010);
                if (funct3 == 3'b010) begin
                    decoded.operation = FP_OP_STORE;
                    decoded.mem_write = 1'b1;
                    decoded.int_rs1_valid = 1'b1;
                    decoded.fp_rs2_valid = 1'b1;
                end
            end

            7'b1000011,
            7'b1000111,
            7'b1001011,
            7'b1001111: begin
                decoded.valid = 1'b1;
                decoded.uses_rounding_mode = 1'b1;
                decoded.illegal = (instr[26:25] != 2'b00) ||
                                  !rounding_mode_legal(funct3);
                if (!decoded.illegal) begin
                    unique case (opcode)
                        7'b1000011: decoded.operation = FP_OP_MADD;
                        7'b1000111: decoded.operation = FP_OP_MSUB;
                        7'b1001011: decoded.operation = FP_OP_NMSUB;
                        default:    decoded.operation = FP_OP_NMADD;
                    endcase
                    decoded.fp_rs1_valid = 1'b1;
                    decoded.fp_rs2_valid = 1'b1;
                    decoded.fp_rs3_valid = 1'b1;
                    decoded.fp_rd_valid  = 1'b1;
                end
            end

            7'b1010011: begin
                decoded.valid = 1'b1;
                decoded.illegal = 1'b0;

                unique case (funct7)
                    7'b0000000: begin
                        set_fp_binary(FP_OP_ADD);
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                    end
                    7'b0000100: begin
                        set_fp_binary(FP_OP_SUB);
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                    end
                    7'b0001000: begin
                        set_fp_binary(FP_OP_MUL);
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                    end
                    7'b0001100: begin
                        set_fp_binary(FP_OP_DIV);
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                    end
                    7'b0101100: begin
                        decoded.operation = FP_OP_SQRT;
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.fp_rd_valid = 1'b1;
                        decoded.illegal = (rs2 != 5'd0) ||
                                          !rounding_mode_legal(funct3);
                    end
                    7'b0010000: begin
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.fp_rs2_valid = 1'b1;
                        decoded.fp_rd_valid = 1'b1;
                        unique case (funct3)
                            3'b000: decoded.operation = FP_OP_SGNJ;
                            3'b001: decoded.operation = FP_OP_SGNJN;
                            3'b010: decoded.operation = FP_OP_SGNJX;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b0010100: begin
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.fp_rs2_valid = 1'b1;
                        decoded.fp_rd_valid = 1'b1;
                        unique case (funct3)
                            3'b000: decoded.operation = FP_OP_MIN;
                            3'b001: decoded.operation = FP_OP_MAX;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b1100000: begin
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.int_rd_valid = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                        unique case (rs2)
                            5'd0: decoded.operation = FP_OP_CVT_W_S;
                            5'd1: decoded.operation = FP_OP_CVT_WU_S;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b1110000: begin
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.int_rd_valid = 1'b1;
                        decoded.illegal = (rs2 != 5'd0);
                        unique case (funct3)
                            3'b000: decoded.operation = FP_OP_MV_X_W;
                            3'b001: decoded.operation = FP_OP_CLASS;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b1010000: begin
                        decoded.fp_rs1_valid = 1'b1;
                        decoded.fp_rs2_valid = 1'b1;
                        decoded.int_rd_valid = 1'b1;
                        unique case (funct3)
                            3'b010: decoded.operation = FP_OP_EQ;
                            3'b001: decoded.operation = FP_OP_LT;
                            3'b000: decoded.operation = FP_OP_LE;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b1101000: begin
                        decoded.uses_rounding_mode = 1'b1;
                        decoded.int_rs1_valid = 1'b1;
                        decoded.fp_rd_valid = 1'b1;
                        decoded.illegal = !rounding_mode_legal(funct3);
                        unique case (rs2)
                            5'd0: decoded.operation = FP_OP_CVT_S_W;
                            5'd1: decoded.operation = FP_OP_CVT_S_WU;
                            default: decoded.illegal = 1'b1;
                        endcase
                    end
                    7'b1111000: begin
                        decoded.operation = FP_OP_MV_W_X;
                        decoded.int_rs1_valid = 1'b1;
                        decoded.fp_rd_valid = 1'b1;
                        decoded.illegal = (rs2 != 5'd0) ||
                                          (funct3 != 3'b000);
                    end
                    default: decoded.illegal = 1'b1;
                endcase
            end

            default: begin
                decoded.valid = 1'b0;
                decoded.illegal = 1'b0;
            end
        endcase

        if (decoded.illegal) begin
            decoded.operation = FP_OP_NONE;
            decoded.mem_read = 1'b0;
            decoded.mem_write = 1'b0;
            decoded.int_rs1_valid = 1'b0;
            decoded.int_rd_valid = 1'b0;
            decoded.fp_rs1_valid = 1'b0;
            decoded.fp_rs2_valid = 1'b0;
            decoded.fp_rs3_valid = 1'b0;
            decoded.fp_rd_valid = 1'b0;
        end
    end

endmodule
