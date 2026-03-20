module alu (
    input  defines_pkg::alu_control_t      control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    output logic [defines_pkg::WIDTH-1:0]  result
);
    import defines_pkg::*;

    logic [WIDTH-1:0] op1;
    logic [WIDTH-1:0] op2;

    assign op1 = datapath.src1_value;
    assign op2 = control_signal.alu_src ? datapath.imm : datapath.src2_value;

    always_comb begin
        unique case (control_signal.alu_op)
            ALU_ADD:  result = op1 + op2;
            ALU_SUB:  result = op1 - op2;
            ALU_AND:  result = op1 & op2;
            ALU_OR:   result = op1 | op2;
            ALU_SLTU: result = (op1 < op2) ? 32'd1 : 32'd0;
            ALU_SRA:  result = $signed(op1) >>> op2[4:0];
            ALU_LUI:  result = datapath.imm;
            default:  result = '0;
        endcase
    end

endmodule
