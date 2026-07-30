`timescale 1ns / 1ps

// Main RV32I/RV32F instruction-control decoder.
//
// Converts opcode/funct fields into orthogonal controls for the ALU, branch
// unit, LSU, CSR/system path, and floating-point units. Defaults describe a
// side-effect-free operation; every legal instruction explicitly enables only
// the resources it needs. Unsupported or malformed encodings are marked as
// illegal so execution can raise a precise illegal-instruction trap.
//
// This module does not read registers or calculate immediates. It describes
// instruction intent; decode_lane combines that intent with extracted fields
// and imm_gen output to build the dynamic pipeline payload.
module decode_controller (
    input  logic [31:0] instr,
    input  logic [6:0] op_code,
    input  logic [2:0] funct3,
    input  logic [6:0] funct7,
    input  logic [11:0] system_imm12,
    input  logic [4:0] system_rs1,
    input  logic [4:0] system_rd,

    output logic       reg_write,
    output logic       alu_src,
    output logic       branch,
    output logic       mem_read,
    output logic       mem_write,
    output logic       jump,
    output logic       jump_reg,
    output logic       csr_en,
    output logic       csr_use_imm,
    output logic [1:0] csr_op,
    output logic       sys_en,
    output logic [2:0] sys_op,
    output logic [3:0] alu_op,
    output logic       fp_en,
    output logic [4:0] fp_op,
    output logic [1:0] fu_type,
    output logic       rename,
    output logic       src1_is_fp,
    output logic       src2_is_fp,
    output logic       src3_is_fp,
    output logic       dest_is_fp
);

    import defines_pkg::*;
    import fp_defines_pkg::*;

    task automatic mark_illegal;
    begin
        reg_write   = 1'b0;
        alu_src     = 1'b0;
        branch      = 1'b0;
        mem_read    = 1'b0;
        mem_write   = 1'b0;
        jump        = 1'b0;
        jump_reg    = 1'b0;
        csr_en      = 1'b0;
        csr_use_imm = 1'b0;
        csr_op      = '0;
        sys_en      = 1'b1;
        sys_op      = SYS_ILLEGAL;
        alu_op      = ALU_NOP;
        fp_en       = 1'b0;
        fp_op       = FP_OP_NONE;
        fu_type     = FU_ALU;
        rename      = 1'b0;
        src1_is_fp  = 1'b0;
        src2_is_fp  = 1'b0;
        src3_is_fp  = 1'b0;
        dest_is_fp  = 1'b0;
    end
    endtask

    function automatic logic csr_addr_implemented(input logic [11:0] addr);
    begin
        unique case (addr)
            CSR_FFLAGS,
            CSR_FRM,
            CSR_FCSR,
            CSR_MSTATUS,
            CSR_MIE,
            CSR_MTVEC,
            CSR_MEPC,
            CSR_MCAUSE,
            CSR_MTVAL,
            CSR_MIP,
            CSR_MHARTID: csr_addr_implemented = 1'b1;
            default: begin
                csr_addr_implemented =
                    ((addr >= CSR_PMPCFG0) && (addr <= CSR_PMPCFG3)) ||
                    ((addr >= CSR_PMPADDR0) && (addr <= CSR_PMPADDR15));
            end
        endcase
    end
    endfunction

    function automatic logic csr_addr_read_only(input logic [11:0] addr);
    begin
        csr_addr_read_only = (addr[11:10] == 2'b11);
    end
    endfunction

    function automatic logic csr_write_attempt(
        input logic [2:0] csr_funct3,
        input logic [4:0] csr_rs1_or_zimm
    );
    begin
        unique case (csr_funct3[1:0])
            2'b01: csr_write_attempt = 1'b1; // CSRRW/CSRRWI always write.
            2'b10,
            2'b11: csr_write_attempt = (csr_rs1_or_zimm != 5'd0);
            default: csr_write_attempt = 1'b0;
        endcase
    end
    endfunction

    always_comb begin
        reg_write = 1'b0;
        alu_src   = 1'b0;
        branch    = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        jump      = 1'b0;
        jump_reg  = 1'b0;
        csr_en    = 1'b0;
        csr_use_imm = 1'b0;
        csr_op    = '0;
        sys_en    = 1'b0;
        sys_op    = '0;
        alu_op    = ALU_NOP;
        fp_en     = 1'b0;
        fp_op     = FP_OP_NONE;
        fu_type   = FU_NOP;
        rename    = 1'b0;
        src1_is_fp = 1'b0;
        src2_is_fp = 1'b0;
        src3_is_fp = 1'b0;
        dest_is_fp = 1'b0;      //默认：不写寄存器、不访问内存、不跳转、不分配物理寄存器、不派发给执行单元。

        unique case (op_code)
            7'b1000011,
            7'b1000111,
            7'b1001011,
            7'b1001111: begin // Fused single-precision multiply-add family.
                reg_write = 1'b1;
                fu_type = FU_ALU;
                rename = 1'b1;
                fp_en = 1'b1;
                src1_is_fp = 1'b1;
                src2_is_fp = 1'b1;
                src3_is_fp = 1'b1;
                dest_is_fp = 1'b1;

                unique case (op_code)
                    7'b1000011: fp_op = FP_OP_MADD;
                    7'b1000111: fp_op = FP_OP_MSUB;
                    7'b1001011: fp_op = FP_OP_NMSUB;
                    default:    fp_op = FP_OP_NMADD;
                endcase

                if ((instr[26:25] != 2'b00) ||
                    !((funct3 <= 3'b100) ||
                      (funct3 == 3'b111))) begin
                    mark_illegal();
                end
            end

            7'b0110011: begin
                reg_write = 1'b1;
                alu_src   = 1'b0;
                fu_type   = FU_ALU;
                rename    = 1'b1;

                unique case ({funct7, funct3})
                    {7'b0000000, 3'b000}: alu_op = ALU_ADD;
                    {7'b0100000, 3'b000}: alu_op = ALU_SUB;
                    {7'b0000000, 3'b001}: alu_op = ALU_SLL;
                    {7'b0000000, 3'b010}: alu_op = ALU_SLT;
                    {7'b0000000, 3'b011}: alu_op = ALU_SLTU;
                    {7'b0000000, 3'b100}: alu_op = ALU_XOR;
                    {7'b0000000, 3'b101}: alu_op = ALU_SRL;
                    {7'b0100000, 3'b101}: alu_op = ALU_SRA;
                    {7'b0000000, 3'b110}: alu_op = ALU_OR;
                    {7'b0000000, 3'b111}: alu_op = ALU_AND;
                    default: begin
                        mark_illegal();
                    end
                endcase
            end

            7'b0010011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                fu_type   = FU_ALU;
                rename    = 1'b1;

                unique case (funct3)
                    3'b000: alu_op = ALU_ADD;   // ADDI
                    3'b010: alu_op = ALU_SLT;   // SLTI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    3'b100: alu_op = ALU_XOR;   // XORI
                    3'b110: alu_op = ALU_OR;    // ORI
                    3'b111: alu_op = ALU_AND;   // ANDI
                    3'b001: begin               // SLLI
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SLL;
                        end else begin
                            mark_illegal();
                        end
                    end
                    3'b101: begin
                        unique case (funct7)
                            7'b0000000: alu_op = ALU_SRL; // SRLI
                            7'b0100000: alu_op = ALU_SRA; // SRAI
                            default: begin
                                mark_illegal();
                            end
                        endcase
                    end
                    default: begin
                        mark_illegal();
                    end
                endcase
            end

            7'b0100011: begin
                alu_src   = 1'b1;
                mem_write = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b0;
                alu_op    = ALU_ADD;

                if (!((funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010))) begin
                    mark_illegal();
                end
            end

            7'b0000011: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_read  = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b1;
                alu_op    = ALU_ADD;

                if (!((funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010) ||
                      (funct3 == 3'b100) || (funct3 == 3'b101))) begin
                    mark_illegal();
                end
            end

            7'b0000111: begin // FLW
                reg_write = 1'b1;
                alu_src   = 1'b1;
                mem_read  = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b1;
                dest_is_fp = 1'b1;
                alu_op    = ALU_ADD;

                if (funct3 != 3'b010) begin
                    mark_illegal();
                end
            end

            7'b0100111: begin // FSW
                alu_src   = 1'b1;
                mem_write = 1'b1;
                fu_type   = FU_MEM;
                rename    = 1'b0;
                src2_is_fp = 1'b1;
                alu_op    = ALU_ADD;

                if (funct3 != 3'b010) begin
                    mark_illegal();
                end
            end

            7'b1010011: begin // Exact RV32F ALU operations.
                reg_write = 1'b1;
                fu_type   = FU_ALU;
                rename    = 1'b1;
                fp_en     = 1'b1;

                unique case (funct7)
                    7'b0000000: begin // FADD.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_ADD;
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b0000100: begin // FSUB.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_SUB;
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b0001000: begin // FMUL.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_MUL;
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b0001100: begin // FDIV.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_DIV;
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b0101100: begin // FSQRT.S
                        src1_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_SQRT;
                        if ((instr[24:20] != 5'd0) ||
                            !((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b0010000: begin // FSGNJ.S/FSGNJN.S/FSGNJX.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        unique case (funct3)
                            3'b000: fp_op = FP_OP_SGNJ;
                            3'b001: fp_op = FP_OP_SGNJN;
                            3'b010: fp_op = FP_OP_SGNJX;
                            default: mark_illegal();
                        endcase
                    end

                    7'b0010100: begin // FMIN.S/FMAX.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        dest_is_fp = 1'b1;
                        unique case (funct3)
                            3'b000: fp_op = FP_OP_MIN;
                            3'b001: fp_op = FP_OP_MAX;
                            default: mark_illegal();
                        endcase
                    end

                    7'b1100000: begin // FCVT.W.S/FCVT.WU.S
                        src1_is_fp = 1'b1;
                        unique case (instr[24:20])
                            5'd0: fp_op = FP_OP_CVT_W_S;
                            5'd1: fp_op = FP_OP_CVT_WU_S;
                            default: mark_illegal();
                        endcase
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b1010000: begin // FEQ.S/FLT.S/FLE.S
                        src1_is_fp = 1'b1;
                        src2_is_fp = 1'b1;
                        unique case (funct3)
                            3'b010: fp_op = FP_OP_EQ;
                            3'b001: fp_op = FP_OP_LT;
                            3'b000: fp_op = FP_OP_LE;
                            default: mark_illegal();
                        endcase
                    end

                    7'b1101000: begin // FCVT.S.W/FCVT.S.WU
                        dest_is_fp = 1'b1;
                        unique case (instr[24:20])
                            5'd0: fp_op = FP_OP_CVT_S_W;
                            5'd1: fp_op = FP_OP_CVT_S_WU;
                            default: mark_illegal();
                        endcase
                        if (!((funct3 <= 3'b100) ||
                              (funct3 == 3'b111))) begin
                            mark_illegal();
                        end
                    end

                    7'b1110000: begin // FMV.X.W/FCLASS.S
                        src1_is_fp = 1'b1;
                        if (instr[24:20] != 5'd0) begin
                            mark_illegal();
                        end else begin
                            unique case (funct3)
                                3'b000: fp_op = FP_OP_MV_X_W;
                                3'b001: fp_op = FP_OP_CLASS;
                                default: mark_illegal();
                            endcase
                        end
                    end

                    7'b1111000: begin // FMV.W.X
                        dest_is_fp = 1'b1;
                        fp_op = FP_OP_MV_W_X;
                        if ((instr[24:20] != 5'd0) ||
                            (funct3 != 3'b000)) begin
                            mark_illegal();
                        end
                    end

                    default: mark_illegal();
                endcase
            end

            7'b1100011: begin
                branch  = 1'b1;
                fu_type = FU_BRANCH;
                rename  = 1'b0;
                alu_op  = ALU_SUB;

                if (!((funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b100) ||
                      (funct3 == 3'b101) || (funct3 == 3'b110) || (funct3 == 3'b111))) begin
                    mark_illegal();
                end
            end

            7'b1100111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                jump      = 1'b1;
                jump_reg  = 1'b1;
                fu_type   = FU_BRANCH;
                rename    = 1'b1;
                alu_op    = ALU_ADD;

                if (funct3 != 3'b000) begin
                    mark_illegal();
                end
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

            7'b0010111: begin
                reg_write = 1'b1;
                alu_src   = 1'b1;
                fu_type   = FU_ALU;
                rename    = 1'b1;
                alu_op    = ALU_AUIPC;
            end

            7'b0001111: begin
                // FENCE and FENCE.I share the serialized system path. The
                // backend drains older work and the LSU before completing
                // either instruction. This core has no instruction cache, so
                // FENCE.I needs no additional cache invalidation operation.
                // RV32I reserves the remaining fields for future fence
                // extensions. Base implementations must ignore them.
                if ((funct3 == 3'b000) || (funct3 == 3'b001)) begin
                    sys_en  = 1'b1;
                    sys_op  = SYS_FENCE;
                    fu_type = FU_ALU;
                    rename  = 1'b0;
                end else begin
                    mark_illegal();
                end
            end

            7'b1110011: begin
                if (funct3 != 3'b000) begin
                    reg_write   = 1'b1;
                    alu_src     = 1'b0;
                    csr_en      = 1'b1;
                    csr_use_imm = funct3[2];
                    fu_type     = FU_ALU;
                    rename      = 1'b1;
                    alu_op      = ALU_NOP;

                    unique case (funct3[1:0])
                        2'b01: csr_op = CSR_RW;
                        2'b10: csr_op = CSR_RS;
                        2'b11: csr_op = CSR_RC;
                        default: begin
                            mark_illegal();
                        end
                    endcase

                    if (!csr_addr_implemented(system_imm12) ||
                        (csr_addr_read_only(system_imm12) &&
                         csr_write_attempt(funct3, system_rs1))) begin
                        mark_illegal();
                    end
                end else begin
                    unique case (system_imm12)
                        12'h000: begin // ECALL
                            if (system_rs1 == 5'd0 && system_rd == 5'd0) begin
                                sys_en  = 1'b1;
                                sys_op  = SYS_ECALL;
                                fu_type = FU_ALU;
                                rename  = 1'b0;
                            end else begin
                                mark_illegal();
                            end
                        end
                        12'h001: begin // EBREAK
                            if (system_rs1 == 5'd0 && system_rd == 5'd0) begin
                                sys_en  = 1'b1;
                                sys_op  = SYS_EBREAK;
                                fu_type = FU_ALU;
                                rename  = 1'b0;
                            end else begin
                                mark_illegal();
                            end
                        end
                        12'h302: begin // MRET
                            if (system_rs1 == 5'd0 && system_rd == 5'd0) begin
                                sys_en  = 1'b1;
                                sys_op  = SYS_MRET;
                                fu_type = FU_ALU;
                                rename  = 1'b0;
                            end else begin
                                mark_illegal();
                            end
                        end
                        12'h105: begin // WFI
                            if (system_rs1 == 5'd0 && system_rd == 5'd0) begin
                                sys_en  = 1'b1;
                                sys_op  = SYS_WFI;
                                fu_type = FU_ALU;
                                rename  = 1'b0;
                            end else begin
                                mark_illegal();
                            end
                        end
                        default: begin
                            mark_illegal();
                        end
                    endcase
                end
            end

            default: begin
                if (instr != 32'b0) begin
                    mark_illegal();
                end
            end
        endcase
    end

endmodule
