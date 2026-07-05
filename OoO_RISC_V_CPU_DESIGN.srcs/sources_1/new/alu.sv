module alu (
    input  defines_pkg::alu_control_t      control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    input  logic [2:0]                     fp_frm,
    output logic [defines_pkg::WIDTH-1:0]  result,
    output logic [4:0]                     fp_flags
);
    import defines_pkg::*;
    import fp_defines_pkg::*;

    logic [WIDTH-1:0] op1;
    logic [WIDTH-1:0] op2;
    logic [WIDTH-1:0] fp_result;
    logic [4:0] fp_result_flags;

    assign op1 = datapath.src1_value;
    assign op2 = control_signal.alu_src ? datapath.imm : datapath.src2_value;

    fp_simple_unit u_fp_simple_unit (
        .operation(control_signal.fp_op),
        .operand_a(datapath.src1_value),
        .operand_b(datapath.src2_value),
        .result   (fp_result),
        .flags    (fp_result_flags)
    );

    always_comb begin
        if (control_signal.fp_en) begin
            result = fp_result;
            fp_flags = fp_result_flags;
        end else begin
        fp_flags = '0;
        unique case (control_signal.alu_op)
            ALU_ADD:  result = op1 + op2;
            ALU_SUB:  result = op1 - op2;
            ALU_AND:  result = op1 & op2;
            ALU_OR:   result = op1 | op2;
            ALU_SLTU: result = (op1 < op2) ? 32'd1 : 32'd0;
            ALU_SRA:  result = $signed(op1) >>> op2[4:0];
            ALU_LUI:  result = datapath.imm;
            ALU_XOR:  result = op1 ^ op2;
            ALU_SLL:  result = op1 << op2[4:0];
            ALU_SRL:  result = op1 >> op2[4:0];
            ALU_SLT:  result = ($signed(op1) < $signed(op2)) ? 32'd1 : 32'd0;
            ALU_AUIPC: result = datapath.pc + datapath.imm;
            default:  result = '0;
        endcase
        end
    end

endmodule
