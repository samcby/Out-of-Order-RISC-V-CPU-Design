module dispatch_logic (
    pip_if.consumer in_if,

    input  logic src1_ready,
    input  logic src2_ready,
    input  logic [defines_pkg::WIDTH-1:0] src1_value,
    input  logic [defines_pkg::WIDTH-1:0] src2_value,
    input  logic branch_pending,
    input  logic [defines_pkg::CHECKPOINT_NUM-1:0] active_checkpoint_mask,

    pip_if.producer rob_if,
    pip_if.producer alu_if,
    pip_if.producer lsu_if,
    pip_if.producer branch_if
);
    import defines_pkg::*;

    rat_dis_t instr;

    logic sel_alu;
    logic sel_lsu;
    logic sel_branch;
    logic sel_nop;

    logic ready_rs;
    logic dispatch_ready;
    assign sel_alu    = (in_if.data.rs_entry.control_signal.fu_type == FU_ALU);
    assign sel_lsu    = (in_if.data.rs_entry.control_signal.fu_type == FU_MEM);
    assign sel_branch = (in_if.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    assign sel_nop    = (in_if.data.rs_entry.control_signal.fu_type == FU_NOP);

    always_comb begin
        instr = in_if.data;
        instr.rs_entry.src1_ready = src1_ready;
        instr.rs_entry.src2_ready = src2_ready;
        instr.rs_entry.datapath.src1_value = src1_value;
        instr.rs_entry.datapath.src2_value = src2_value;
    end

    assign ready_rs = (sel_alu    && alu_if.ready)    ||
                      (sel_lsu    && lsu_if.ready)    ||
                      (sel_branch && branch_if.ready);

    // Default/illegal instructions should drain through the front-end
    // without allocating ROB/RS state.
    assign dispatch_ready = sel_nop ? 1'b1 : (rob_if.ready && ready_rs);

    assign in_if.ready = dispatch_ready;

    assign rob_if.valid = in_if.valid && dispatch_ready && !sel_nop;
    assign rob_if.data  = instr.rob_entry;

    assign alu_if.valid = in_if.valid && dispatch_ready && sel_alu;
    assign alu_if.data.control_signal = instr.rs_entry.control_signal.alu_control_signal;
    assign alu_if.data.datapath       = instr.rs_entry.datapath;
    assign alu_if.data.src1_ready     = instr.rs_entry.src1_ready;
    assign alu_if.data.src2_ready     = instr.rs_entry.src2_ready;

    assign lsu_if.valid = in_if.valid && dispatch_ready && sel_lsu;
    assign lsu_if.data.control_signal = instr.rs_entry.control_signal.lsu_control_signal;
    assign lsu_if.data.datapath       = instr.rs_entry.datapath;
    assign lsu_if.data.src1_ready     = instr.rs_entry.src1_ready;
    assign lsu_if.data.src2_ready     = instr.rs_entry.src2_ready;

    assign branch_if.valid = in_if.valid && dispatch_ready && sel_branch;
    assign branch_if.data.control_signal = instr.rs_entry.control_signal.branch_control_signal;
    assign branch_if.data.datapath       = instr.rs_entry.datapath;
    assign branch_if.data.src1_ready     = instr.rs_entry.src1_ready;
    assign branch_if.data.src2_ready     = instr.rs_entry.src2_ready;

endmodule
