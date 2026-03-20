module branch_unit (
    input  defines_pkg::branch_control_t   control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    output logic                           branch_taken,
    output logic [defines_pkg::WIDTH-1:0]  branch_target,
    output logic [defines_pkg::WIDTH-1:0]  link_result
);
    import defines_pkg::*;

    always_comb begin
        branch_taken  = 1'b0;
        branch_target = '0;
        link_result   = datapath.pc + 32'd4;

        if (control_signal.jump) begin
            branch_taken  = 1'b1;
            if (control_signal.jump_reg) begin
                branch_target = (datapath.src1_value + datapath.imm) & 32'hFFFF_FFFE;
            end else begin
                branch_target = datapath.pc + datapath.imm;
            end
        end else if (control_signal.branch) begin
            unique case (control_signal.funct3)
                3'b000: branch_taken = (datapath.src1_value == datapath.src2_value); // BEQ
                3'b001: branch_taken = (datapath.src1_value != datapath.src2_value); // BNE
                3'b100: branch_taken = ($signed(datapath.src1_value) <  $signed(datapath.src2_value));
                3'b101: branch_taken = ($signed(datapath.src1_value) >= $signed(datapath.src2_value));
                3'b110: branch_taken = (datapath.src1_value <  datapath.src2_value);
                3'b111: branch_taken = (datapath.src1_value >= datapath.src2_value);
                default: branch_taken = 1'b0;
            endcase
            branch_target = datapath.pc + datapath.imm;
        end
    end

endmodule
