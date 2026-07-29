// Packet firewall between rename and dispatch.
//
// Rename can create two ordered instructions in one cycle, but not every pair
// can safely consume the downstream resources together. This module detects
// incompatible combinations (for example competing memory/branch resources,
// CSR serialization, and selected same-packet dependencies) and sends lane 0
// first while retaining lane 1 in a one-entry pending register. It preserves
// program order and never duplicates a lane across the two output transfers.
//
// `flush` discards a pending younger lane. This boundary is deliberately after
// rename: a split changes dispatch timing, not the RAT allocation already made.
module rat_dis_packet_splitter (
    input logic flush,
    pip_if.consumer in_if,
    pip_if.producer out_if
);
    import defines_pkg::*;

    rat_dis_lane_t pending_lane_q;
    logic pending_valid_q;

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
    logic split_packet;
    logic consume_input;

    assign lane0_valid = in_if.valid && in_if.data.lane0.valid;
    assign lane1_valid = in_if.valid && in_if.data.lane1.valid;

    assign lane0_nop = lane0_valid &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_NOP);
    assign lane1_nop = lane1_valid &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_NOP);
    assign lane0_alu = lane0_valid && !lane0_nop &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_ALU);
    assign lane1_alu = lane1_valid && !lane1_nop &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_ALU);
    assign lane0_lsu = lane0_valid && !lane0_nop &&
                       (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_MEM);
    assign lane1_lsu = lane1_valid && !lane1_nop &&
                       (in_if.data.lane1.data.rs_entry.control_signal.fu_type == FU_MEM);
    assign lane0_branch = lane0_valid && !lane0_nop &&
                          (in_if.data.lane0.data.rs_entry.control_signal.fu_type == FU_BRANCH);
    assign lane1_branch = lane1_valid && !lane1_nop &&
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
                                 in_if.data.lane0.data.rs_entry.datapath.new_des_preg)));

    assign alu_pair_speculative = lane0_alu && lane1_alu &&
                                  ((in_if.data.lane0.data.rs_entry.datapath.speculation_mask != '0) ||
                                   (in_if.data.lane1.data.rs_entry.datapath.speculation_mask != '0));

    assign duplicate_fu = (lane0_lsu && lane1_lsu) ||
                          (lane0_branch && lane1_branch) ||
                          alu_pair_raw_dep ||
                          alu_pair_speculative;

    // The ALU RS has two enqueue ports; LSU/branch remain single-enqueue.
    // Keep CSR/system side effects, dependent ALU pairs, and speculative ALU
    // pairs serialized until the backend grows full intra-packet forwarding.
    assign split_packet = lane0_valid && lane1_valid &&
                          (duplicate_fu || lane0_csr || lane1_csr);

    assign out_if.valid = !flush && (pending_valid_q || in_if.valid);
    assign in_if.ready  = !flush && !pending_valid_q && out_if.ready;
    assign consume_input = in_if.valid && in_if.ready;

    always_comb begin
        out_if.data = '0;

        if (pending_valid_q) begin
            out_if.data.lane1 = pending_lane_q;
        end else if (split_packet) begin
            out_if.data.lane0 = in_if.data.lane0;
        end else begin
            out_if.data = in_if.data;
        end
    end

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            pending_valid_q <= 1'b0;
            pending_lane_q <= '0;
        end else begin
            if (pending_valid_q && out_if.ready) begin
                pending_valid_q <= 1'b0;
                pending_lane_q <= '0;
            end

            if (consume_input && split_packet) begin
                pending_valid_q <= 1'b1;
                pending_lane_q <= in_if.data.lane1;
            end
        end
    end

endmodule
