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
    output logic [1:0] fu_type,
    output logic       rename
);

    import defines_pkg::*;

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
        fu_type     = FU_ALU;
        rename      = 1'b0;
    end
    endtask

    function automatic logic csr_addr_implemented(input logic [11:0] addr);
    begin
        unique case (addr)
            CSR_MSTATUS,
            CSR_MIE,
            CSR_MTVEC,
            CSR_MEPC,
            CSR_MCAUSE,
            CSR_MTVAL,
            CSR_MIP: csr_addr_implemented = 1'b1;
            default: csr_addr_implemented = 1'b0;
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
        fu_type   = FU_NOP;
        rename    = 1'b0;

        unique case (op_code)
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
                fu_type = FU_NOP;
                rename  = 1'b0;
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
