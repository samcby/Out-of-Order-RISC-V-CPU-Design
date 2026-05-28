module decode_stage #(
    parameter int WIDTH = 32
)(
    pip_if.consumer in_if,
    pip_if.producer out_if
);

    import defines_pkg::*;

    logic [6:0] op_code;
    logic [2:0] funct3;
    logic [6:0] funct7;

    logic       reg_write;
    logic       alu_src;
    logic       branch;
    logic       mem_read;
    logic       mem_write;
    logic       jump;
    logic       jump_reg;
    logic       csr_en;
    logic       csr_use_imm;
    logic [1:0] csr_op;
    logic       sys_en;
    logic [2:0] sys_op;
    logic [3:0] alu_op;
    logic [1:0] fu_type;
    logic       rename;

    logic [WIDTH-1:0] imm;

    assign op_code = in_if.data.instr[6:0];
    assign funct3  = in_if.data.instr[14:12];
    assign funct7  = in_if.data.instr[31:25];

    assign in_if.ready  = out_if.ready;
    assign out_if.valid = in_if.valid;

    always_comb begin
        out_if.data.datapath.pc  = in_if.data.pc;
        out_if.data.datapath.rd  = in_if.data.instr[11:7];
        out_if.data.datapath.imm = imm;
        out_if.data.datapath.instr = in_if.data.instr;
        out_if.data.datapath.pred_taken  = in_if.data.pred_taken;
        out_if.data.datapath.pred_target = in_if.data.pred_target;
    
        out_if.data.datapath.rs1 = '0;
        out_if.data.datapath.rs2 = '0;
    
        unique case (op_code)
            7'b0110011: begin
                // R-type: rs1, rs2 both used
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = in_if.data.instr[24:20];
            end
    
            7'b0010011: begin
                // I-type ALU: only rs1 used
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = '0;
            end
    
            7'b0000011: begin
                // LOAD: only rs1(base) used
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = '0;
            end
    
            7'b0100011: begin
                // STORE: rs1(base), rs2(store data)
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = in_if.data.instr[24:20];
            end
    
            7'b1100011: begin
                // BRANCH: rs1, rs2 both used
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = in_if.data.instr[24:20];
            end
    
            7'b1100111: begin
                // JALR: only rs1 used
                out_if.data.datapath.rs1 = in_if.data.instr[19:15];
                out_if.data.datapath.rs2 = '0;
            end
    
            7'b0110111, 7'b0010111: begin
                // LUI/AUIPC: no source register used
                out_if.data.datapath.rs1 = '0;
                out_if.data.datapath.rs2 = '0;
            end

            7'b1101111: begin
                // JAL: no source register used
                out_if.data.datapath.rs1 = '0;
                out_if.data.datapath.rs2 = '0;
            end

            7'b1110011: begin
                // CSR immediate forms use zimm, not the integer rs1 value.
                out_if.data.datapath.rs1 = (funct3 != 3'b000 && !funct3[2]) ?
                                           in_if.data.instr[19:15] : '0;
                out_if.data.datapath.rs2 = '0;
            end
    
            default: begin
                out_if.data.datapath.rs1 = '0;
                out_if.data.datapath.rs2 = '0;
            end
        endcase
    end

    assign out_if.data.control_signal.rs_control_signal.fu_type = fu_type;
    assign out_if.data.control_signal.rs_control_signal.rename  = rename;

    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.reg_write = reg_write;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.alu_src   = alu_src;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.csr_en    = csr_en;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.csr_use_imm = csr_use_imm;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.csr_op    = csr_op;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.csr_zimm  = in_if.data.instr[19:15];
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.csr_addr  = in_if.data.instr[31:20];
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.sys_en    = sys_en;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.sys_op    = sys_op;
    assign out_if.data.control_signal.rs_control_signal.alu_control_signal.alu_op    = alu_op;

    assign out_if.data.control_signal.rs_control_signal.lsu_control_signal.reg_write = reg_write;
    assign out_if.data.control_signal.rs_control_signal.lsu_control_signal.mem_read  = mem_read;
    assign out_if.data.control_signal.rs_control_signal.lsu_control_signal.mem_write = mem_write;
    assign out_if.data.control_signal.rs_control_signal.lsu_control_signal.funct3    = funct3;

    assign out_if.data.control_signal.rs_control_signal.branch_control_signal.branch = branch;
    assign out_if.data.control_signal.rs_control_signal.branch_control_signal.jump   = jump;
    assign out_if.data.control_signal.rs_control_signal.branch_control_signal.jump_reg = jump_reg;
    assign out_if.data.control_signal.rs_control_signal.branch_control_signal.funct3 = funct3;    

    assign out_if.data.control_signal.rob_control_signal.branch = branch;

    imm_gen #(
        .WIDTH(WIDTH)
    ) u_imm_gen (
        .instr_in(in_if.data.instr),
        .op_code (op_code),
        .imm     (imm)
    );

    decode_controller u_decode_controller (
        .instr    (in_if.data.instr),
        .op_code  (op_code),
        .funct3   (funct3),
        .funct7   (funct7),
        .system_imm12(in_if.data.instr[31:20]),
        .system_rs1(in_if.data.instr[19:15]),
        .system_rd (in_if.data.instr[11:7]),
        .reg_write(reg_write),
        .alu_src  (alu_src),
        .branch   (branch),
        .mem_read (mem_read),
        .mem_write(mem_write),
        .jump     (jump),
        .jump_reg (jump_reg),
        .csr_en   (csr_en),
        .csr_use_imm(csr_use_imm),
        .csr_op   (csr_op),
        .sys_en   (sys_en),
        .sys_op   (sys_op),
        .alu_op   (alu_op),
        .fu_type  (fu_type),
        .rename   (rename)
    );

endmodule
