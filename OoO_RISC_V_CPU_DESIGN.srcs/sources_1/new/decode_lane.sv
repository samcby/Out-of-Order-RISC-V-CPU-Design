// Combinational decoder for one ordered packet lane.
//
// Extracts architectural register indices and instruction fields, invokes the
// immediate generator and control decoder, and assembles the control/datapath
// structures expected by rename. Source-valid information is format-aware so
// later stages do not create false dependencies on unused instruction bits.
// The lane contains no storage; packet-level valid/ready policy is handled by
// decode_packet_stage and the surrounding skid buffers.
module decode_lane #(
    parameter int WIDTH = 32
)(
    input  defines_pkg::fetch_decode_t in_data,
    output defines_pkg::decode_rat_t    out_data
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
    logic       fp_en;
    logic [4:0] fp_op;
    logic [1:0] fu_type;
    logic       rename;
    logic       src1_is_fp;
    logic       src2_is_fp;
    logic       src3_is_fp;
    logic       dest_is_fp;

    logic [WIDTH-1:0] imm;

    assign op_code = in_data.instr[6:0];
    assign funct3  = in_data.instr[14:12];
    assign funct7  = in_data.instr[31:25];

    always_comb begin
        out_data = '0;

        out_data.datapath.pc          = in_data.pc;
        out_data.datapath.rd          = in_data.instr[11:7];
        out_data.datapath.src1_is_fp  = src1_is_fp;
        out_data.datapath.src2_is_fp  = src2_is_fp;
        out_data.datapath.src3_is_fp  = src3_is_fp;
        out_data.datapath.dest_is_fp  = dest_is_fp;
        out_data.datapath.imm         = imm;
        out_data.datapath.instr       = in_data.instr;
        out_data.datapath.pred_taken  = in_data.pred_taken;
        out_data.datapath.pred_target = in_data.pred_target;

        unique case (op_code)
            7'b1000011, // FMADD
            7'b1000111, // FMSUB
            7'b1001011, // FNMSUB
            7'b1001111: begin       // FNMADD
                out_data.datapath.rs1 = in_data.instr[19:15];
                out_data.datapath.rs2 = in_data.instr[24:20];
                out_data.datapath.rs3 = in_data.instr[31:27];
            end

            7'b0110011, // OP
            7'b1010011: begin       // OP-FP
                out_data.datapath.rs1 = in_data.instr[19:15];
                out_data.datapath.rs2 = in_data.instr[24:20];
                out_data.datapath.rs3 = '0;
            end

            7'b0010011,     // OP-IMM
            7'b0000011,     // LOAD
            7'b0000111,     // LOAD-FP
            7'b1100111: begin       // JALR
                out_data.datapath.rs1 = in_data.instr[19:15];
                out_data.datapath.rs2 = '0;
                out_data.datapath.rs3 = '0;
            end

            7'b0100011,     // STORE
            7'b0100111,     // STORE-FP
            7'b1100011: begin       // BRANCH
                out_data.datapath.rs1 = in_data.instr[19:15];
                out_data.datapath.rs2 = in_data.instr[24:20];
                out_data.datapath.rs3 = '0;
            end

            7'b1110011: begin
                // CSR immediate forms use zimm, not the integer rs1 value.
                out_data.datapath.rs1 = (funct3 != 3'b000 && !funct3[2]) ?
                                        in_data.instr[19:15] : '0;
                out_data.datapath.rs2 = '0;
                out_data.datapath.rs3 = '0;
            end

            default: begin
                out_data.datapath.rs1 = '0;
                out_data.datapath.rs2 = '0;
                out_data.datapath.rs3 = '0;
            end
        endcase

        out_data.control_signal.rs_control_signal.fu_type = fu_type;
        out_data.control_signal.rs_control_signal.rename  = rename;

        out_data.control_signal.rs_control_signal.alu_control_signal.reg_write   = reg_write;
        out_data.control_signal.rs_control_signal.alu_control_signal.alu_src     = alu_src;
        out_data.control_signal.rs_control_signal.alu_control_signal.fp_en       = fp_en;
        out_data.control_signal.rs_control_signal.alu_control_signal.fp_op       = fp_op;
        out_data.control_signal.rs_control_signal.alu_control_signal.fp_rm       = funct3;
        out_data.control_signal.rs_control_signal.alu_control_signal.csr_en      = csr_en;
        out_data.control_signal.rs_control_signal.alu_control_signal.csr_use_imm = csr_use_imm;
        out_data.control_signal.rs_control_signal.alu_control_signal.csr_op      = csr_op;
        out_data.control_signal.rs_control_signal.alu_control_signal.csr_zimm    = in_data.instr[19:15];
        out_data.control_signal.rs_control_signal.alu_control_signal.csr_addr    = in_data.instr[31:20];
        out_data.control_signal.rs_control_signal.alu_control_signal.sys_en      = sys_en;
        out_data.control_signal.rs_control_signal.alu_control_signal.sys_op      = sys_op;
        out_data.control_signal.rs_control_signal.alu_control_signal.alu_op      = alu_op;

        out_data.control_signal.rs_control_signal.lsu_control_signal.reg_write = reg_write;
        out_data.control_signal.rs_control_signal.lsu_control_signal.mem_read  = mem_read;
        out_data.control_signal.rs_control_signal.lsu_control_signal.mem_write = mem_write;
        out_data.control_signal.rs_control_signal.lsu_control_signal.funct3    = funct3;

        out_data.control_signal.rs_control_signal.branch_control_signal.branch   = branch;
        out_data.control_signal.rs_control_signal.branch_control_signal.jump     = jump;
        out_data.control_signal.rs_control_signal.branch_control_signal.jump_reg = jump_reg;
        out_data.control_signal.rs_control_signal.branch_control_signal.funct3   = funct3;

        out_data.control_signal.rob_control_signal.branch = branch;
        out_data.control_signal.rob_control_signal.store  = mem_write;
    end

    imm_gen #(
        .WIDTH(WIDTH)
    ) u_imm_gen (
        .instr_in(in_data.instr),
        .op_code (op_code),
        .imm     (imm)
    );

    decode_controller u_decode_controller (
        .instr       (in_data.instr),
        .op_code     (op_code),
        .funct3      (funct3),
        .funct7      (funct7),
        .system_imm12(in_data.instr[31:20]),
        .system_rs1  (in_data.instr[19:15]),
        .system_rd   (in_data.instr[11:7]),
        .reg_write   (reg_write),
        .alu_src     (alu_src),
        .branch      (branch),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .jump        (jump),
        .jump_reg    (jump_reg),
        .csr_en      (csr_en),
        .csr_use_imm (csr_use_imm),
        .csr_op      (csr_op),
        .sys_en      (sys_en),
        .sys_op      (sys_op),
        .alu_op      (alu_op),
        .fp_en       (fp_en),
        .fp_op       (fp_op),
        .fu_type     (fu_type),
        .rename      (rename),
        .src1_is_fp  (src1_is_fp),
        .src2_is_fp  (src2_is_fp),
        .src3_is_fp  (src3_is_fp),
        .dest_is_fp  (dest_is_fp)
    );

endmodule
