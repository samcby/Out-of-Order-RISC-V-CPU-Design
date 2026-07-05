module dispatch_packet_logic (
    pip_if.consumer in_if,

    input logic lane0_src1_ready,
    input logic lane0_src2_ready,
    input logic lane0_src3_ready,
    input logic [defines_pkg::WIDTH-1:0] lane0_src1_value,
    input logic [defines_pkg::WIDTH-1:0] lane0_src2_value,
    input logic [defines_pkg::WIDTH-1:0] lane0_src3_value,
    input logic lane1_src1_ready,
    input logic lane1_src2_ready,
    input logic lane1_src3_ready,
    input logic [defines_pkg::WIDTH-1:0] lane1_src1_value,
    input logic [defines_pkg::WIDTH-1:0] lane1_src2_value,
    input logic [defines_pkg::WIDTH-1:0] lane1_src3_value,
    input logic csr_pending,

    pip_if.producer rob_packet_if,
    pip_if.producer alu_if,
    pip_if.producer alu1_if,
    pip_if.producer lsu_if,
    pip_if.producer branch_if
);
    import defines_pkg::*;

    rat_dis_t lane0_instr;
    rat_dis_t lane1_instr;

    logic lane0_valid;
    logic lane1_valid;
    logic lane0_nop;
    logic lane1_nop;
    logic lane0_alu;
    logic lane1_alu;
    logic lane0_lsu;
    logic lane1_lsu;
    logic lane0_branch;
    logic lane1_branch;
    logic lane0_csr;
    logic lane1_csr;
    logic alu_pair_raw_dep;
    logic alu_pair_speculative;
    logic duplicate_fu;
    logic csr_blocked;
    logic lane0_rs_ready;
    logic lane1_rs_ready;
    logic packet_has_work;
    logic dispatch_ready;

    assign lane0_valid = in_if.valid && in_if.data.lane0.valid;
    assign lane1_valid = in_if.valid && in_if.data.lane1.valid;

    assign lane0_nop = lane0_valid &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_NOP);
    assign lane1_nop = lane1_valid &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_NOP);
    assign lane0_alu = lane0_valid &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_ALU);
    assign lane1_alu = lane1_valid &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_ALU);
    assign lane0_lsu = lane0_valid &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_MEM);
    assign lane1_lsu = lane1_valid &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_MEM);
    assign lane0_branch = lane0_valid &&
                          (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    assign lane1_branch = lane1_valid &&
                          (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_BRANCH);

    assign lane0_csr = lane0_alu &&
                       (in_if.data.lane0.data.rs_entry.control_signal.alu_control_signal.csr_en ||
                        in_if.data.lane0.data.rs_entry.control_signal.alu_control_signal.sys_en);
    assign lane1_csr = lane1_alu &&
                       (in_if.data.lane1.data.rs_entry.control_signal.alu_control_signal.csr_en ||
                        in_if.data.lane1.data.rs_entry.control_signal.alu_control_signal.sys_en);

    assign alu_pair_raw_dep = lane0_alu && lane1_alu &&
                              (in_if.data.lane0.data.rs_entry.datapath.dest_is_fp ||
                               (in_if.data.lane0.data.rs_entry.datapath.new_des_preg != '0)) &&
                              (((in_if.data.lane1.data.rs_entry.datapath.src1_is_fp ==
                                 in_if.data.lane0.data.rs_entry.datapath.dest_is_fp) &&
                                (in_if.data.lane1.data.rs_entry.datapath.src_reg_1p ==
                                 in_if.data.lane0.data.rs_entry.datapath.new_des_preg)) ||
                               ((in_if.data.lane1.data.rs_entry.datapath.src2_is_fp ==
                                 in_if.data.lane0.data.rs_entry.datapath.dest_is_fp) &&
                                (in_if.data.lane1.data.rs_entry.datapath.src_reg_2p ==
                                 in_if.data.lane0.data.rs_entry.datapath.new_des_preg)) ||
                               ((in_if.data.lane1.data.rs_entry.datapath.src3_is_fp ==
                                 in_if.data.lane0.data.rs_entry.datapath.dest_is_fp) &&
                                (in_if.data.lane1.data.rs_entry.datapath.src_reg_3p ==
                                 in_if.data.lane0.data.rs_entry.datapath.new_des_preg)));

    assign alu_pair_speculative = lane0_alu && lane1_alu &&
                                  ((in_if.data.lane0.data.rs_entry.datapath.speculation_mask != '0) ||
                                   (in_if.data.lane1.data.rs_entry.datapath.speculation_mask != '0));

    assign duplicate_fu = (lane0_lsu && lane1_lsu) ||
                          (lane0_branch && lane1_branch) ||
                          alu_pair_raw_dep ||
                          alu_pair_speculative;

    // CSR/system operations are serialized until CSR completion tracking is
    // widened. This keeps the architectural side effects precise.
    assign csr_blocked = (lane0_csr || lane1_csr) &&
                         (csr_pending ||
                          ((lane0_csr && lane1_valid && !lane1_nop) ||
                           (lane1_csr && lane0_valid && !lane0_nop)));

    always_comb begin
        lane0_instr = in_if.data.lane0.data;
        lane1_instr = in_if.data.lane1.data;

        lane0_instr.rs_entry.src1_ready = lane0_src1_ready;
        lane0_instr.rs_entry.src2_ready = lane0_src2_ready;
        lane0_instr.rs_entry.src3_ready =
            !lane0_instr.rs_entry.datapath.src3_is_fp || lane0_src3_ready;
        lane0_instr.rs_entry.datapath.src1_value = lane0_src1_value;
        lane0_instr.rs_entry.datapath.src2_value = lane0_src2_value;
        lane0_instr.rs_entry.datapath.src3_value = lane0_src3_value;

        lane1_instr.rs_entry.src1_ready = lane1_src1_ready;
        lane1_instr.rs_entry.src2_ready = lane1_src2_ready;
        lane1_instr.rs_entry.src3_ready =
            !lane1_instr.rs_entry.datapath.src3_is_fp || lane1_src3_ready;
        lane1_instr.rs_entry.datapath.src1_value = lane1_src1_value;
        lane1_instr.rs_entry.datapath.src2_value = lane1_src2_value;
        lane1_instr.rs_entry.datapath.src3_value = lane1_src3_value;
    end

    assign lane0_rs_ready = lane0_nop ||
                            (lane0_alu && alu_if.ready) ||
                            (lane0_lsu && lsu_if.ready) ||
                            (lane0_branch && branch_if.ready);
    assign lane1_rs_ready = lane1_nop ||
                            (lane1_alu && (lane0_alu ? alu1_if.ready : alu_if.ready)) ||
                            (lane1_lsu && lsu_if.ready) ||
                            (lane1_branch && branch_if.ready);
    assign packet_has_work = (lane0_valid && !lane0_nop) ||
                             (lane1_valid && !lane1_nop);

    assign dispatch_ready = (!packet_has_work || rob_packet_if.ready) &&
                            (!lane0_valid || lane0_rs_ready) &&
                            (!lane1_valid || lane1_rs_ready) &&
                            !duplicate_fu &&
                            !csr_blocked;

    assign in_if.ready = dispatch_ready;

    assign rob_packet_if.valid = in_if.valid && dispatch_ready && packet_has_work;
    assign rob_packet_if.data.lane0.valid = lane0_valid && !lane0_nop;
    assign rob_packet_if.data.lane0.data = lane0_instr;
    assign rob_packet_if.data.lane1.valid = lane1_valid && !lane1_nop;
    assign rob_packet_if.data.lane1.data = lane1_instr;

    assign alu_if.valid = in_if.valid && dispatch_ready && (lane0_alu || lane1_alu);
    assign alu_if.data.control_signal =
        lane0_alu ? lane0_instr.rs_entry.control_signal.alu_control_signal :
                    lane1_instr.rs_entry.control_signal.alu_control_signal;
    assign alu_if.data.datapath =
        lane0_alu ? lane0_instr.rs_entry.datapath : lane1_instr.rs_entry.datapath;
    assign alu_if.data.src1_ready =
        lane0_alu ? lane0_instr.rs_entry.src1_ready : lane1_instr.rs_entry.src1_ready;
    assign alu_if.data.src2_ready =
        lane0_alu ? lane0_instr.rs_entry.src2_ready : lane1_instr.rs_entry.src2_ready;
    assign alu_if.data.src3_ready =
        lane0_alu ? lane0_instr.rs_entry.src3_ready : lane1_instr.rs_entry.src3_ready;

    assign alu1_if.valid = in_if.valid && dispatch_ready && lane0_alu && lane1_alu;
    assign alu1_if.data.control_signal = lane1_instr.rs_entry.control_signal.alu_control_signal;
    assign alu1_if.data.datapath = lane1_instr.rs_entry.datapath;
    assign alu1_if.data.src1_ready = lane1_instr.rs_entry.src1_ready;
    assign alu1_if.data.src2_ready = lane1_instr.rs_entry.src2_ready;
    assign alu1_if.data.src3_ready = lane1_instr.rs_entry.src3_ready;

    assign lsu_if.valid = in_if.valid && dispatch_ready && (lane0_lsu || lane1_lsu);
    assign lsu_if.data.control_signal =
        lane0_lsu ? lane0_instr.rs_entry.control_signal.lsu_control_signal :
                    lane1_instr.rs_entry.control_signal.lsu_control_signal;
    assign lsu_if.data.datapath =
        lane0_lsu ? lane0_instr.rs_entry.datapath : lane1_instr.rs_entry.datapath;
    assign lsu_if.data.src1_ready =
        lane0_lsu ? lane0_instr.rs_entry.src1_ready : lane1_instr.rs_entry.src1_ready;
    assign lsu_if.data.src2_ready =
        lane0_lsu ? lane0_instr.rs_entry.src2_ready : lane1_instr.rs_entry.src2_ready;
    assign lsu_if.data.src3_ready = 1'b1;

    assign branch_if.valid = in_if.valid && dispatch_ready && (lane0_branch || lane1_branch);
    assign branch_if.data.control_signal =
        lane0_branch ? lane0_instr.rs_entry.control_signal.branch_control_signal :
                       lane1_instr.rs_entry.control_signal.branch_control_signal;
    assign branch_if.data.datapath =
        lane0_branch ? lane0_instr.rs_entry.datapath : lane1_instr.rs_entry.datapath;
    assign branch_if.data.src1_ready =
        lane0_branch ? lane0_instr.rs_entry.src1_ready : lane1_instr.rs_entry.src1_ready;
    assign branch_if.data.src2_ready =
        lane0_branch ? lane0_instr.rs_entry.src2_ready : lane1_instr.rs_entry.src2_ready;
    assign branch_if.data.src3_ready = 1'b1;

endmodule
