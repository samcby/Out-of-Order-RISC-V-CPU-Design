`timescale 1ns / 1ps

module fp_execution_pipeline #(
    parameter int LATENCY = 3
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,
    input  logic                          squash_en,
    input  defines_pkg::cp_id_t           squash_checkpoint_id,
    input  logic                          resolve_en,
    input  defines_pkg::cp_id_t           resolve_checkpoint_id,

    input  logic                          in_valid,
    output logic                          in_ready,
    input  defines_pkg::alu_control_t      in_control,
    input  defines_pkg::rs_datapath_t      in_datapath,
    input  logic [2:0]                    fp_frm,

    output logic                          out_valid,
    input  logic                          out_ready,
    output defines_pkg::rob_tag_t         out_tag,
    output defines_pkg::preg_t            out_preg,
    output logic                          out_dest_is_fp,
    output logic                          out_reg_write,
    output logic [31:0]                   out_result,
    output logic [4:0]                    out_flags
);
    import defines_pkg::*;
    import fp_defines_pkg::*;

    typedef struct packed {
        rob_tag_t   tag;
        preg_t      preg;
        logic       dest_is_fp;
        logic       reg_write;
        cp_mask_t   speculation_mask;
        logic [31:0] result;
        logic [4:0] flags;
    } fp_pipe_entry_t;

    logic valid_q [0:LATENCY-1];
    fp_pipe_entry_t entry_q [0:LATENCY-1];
    logic stall;
    logic input_squashed;
    logic output_squashed;
    logic [2:0] effective_rounding_mode;
    logic [31:0] add_sub_result;
    logic [4:0] add_sub_flags;
    logic [31:0] mul_result;
    logic [4:0] mul_flags;
    logic [31:0] convert_result;
    logic [4:0] convert_flags;
    logic [31:0] fma_result;
    logic [4:0] fma_flags;
    logic [31:0] selected_result;
    logic [4:0] selected_flags;

    assign effective_rounding_mode =
        (in_control.fp_rm == 3'b111) ? fp_frm : in_control.fp_rm;

    fp_add_sub_unit u_add_sub (
        .subtract     (in_control.fp_op == FP_OP_SUB),
        .rounding_mode(effective_rounding_mode),
        .operand_a    (in_datapath.src1_value),
        .operand_b    (in_datapath.src2_value),
        .result       (add_sub_result),
        .flags        (add_sub_flags)
    );

    fp_mul_unit u_mul (
        .rounding_mode(effective_rounding_mode),
        .operand_a    (in_datapath.src1_value),
        .operand_b    (in_datapath.src2_value),
        .result       (mul_result),
        .flags        (mul_flags)
    );

    fp_convert_unit u_convert (
        .operation    (in_control.fp_op),
        .rounding_mode(effective_rounding_mode),
        .operand      (in_datapath.src1_value),
        .result       (convert_result),
        .flags        (convert_flags)
    );

    fp_fma_unit u_fma (
        .operation    (in_control.fp_op),
        .rounding_mode(effective_rounding_mode),
        .operand_a    (in_datapath.src1_value),
        .operand_b    (in_datapath.src2_value),
        .operand_c    (in_datapath.src3_value),
        .result       (fma_result),
        .flags        (fma_flags)
    );

    always_comb begin
        unique case (in_control.fp_op)
            FP_OP_MUL: begin
                selected_result = mul_result;
                selected_flags = mul_flags;
            end
            FP_OP_CVT_W_S,
            FP_OP_CVT_WU_S,
            FP_OP_CVT_S_W,
            FP_OP_CVT_S_WU: begin
                selected_result = convert_result;
                selected_flags = convert_flags;
            end
            FP_OP_MADD,
            FP_OP_MSUB,
            FP_OP_NMSUB,
            FP_OP_NMADD: begin
                selected_result = fma_result;
                selected_flags = fma_flags;
            end
            default: begin
                selected_result = add_sub_result;
                selected_flags = add_sub_flags;
            end
        endcase
    end

    assign input_squashed =
        squash_en && in_datapath.speculation_mask[squash_checkpoint_id];
    assign output_squashed =
        squash_en &&
        entry_q[LATENCY-1].speculation_mask[squash_checkpoint_id];
    assign out_valid = valid_q[LATENCY-1] && !output_squashed;
    assign stall = out_valid && !out_ready;
    assign in_ready = !stall;

    assign out_tag = entry_q[LATENCY-1].tag;
    assign out_preg = entry_q[LATENCY-1].preg;
    assign out_dest_is_fp = entry_q[LATENCY-1].dest_is_fp;
    assign out_reg_write = entry_q[LATENCY-1].reg_write;
    assign out_result = entry_q[LATENCY-1].result;
    assign out_flags = entry_q[LATENCY-1].flags;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            for (int stage_idx = 0; stage_idx < LATENCY; stage_idx++) begin
                valid_q[stage_idx] <= 1'b0;
                entry_q[stage_idx] <= '0;
            end
        end else if (stall) begin
            for (int stage_idx = 0; stage_idx < LATENCY; stage_idx++) begin
                if (squash_en &&
                    entry_q[stage_idx].speculation_mask[squash_checkpoint_id]) begin
                    valid_q[stage_idx] <= 1'b0;
                end
                if (resolve_en) begin
                    entry_q[stage_idx].speculation_mask[resolve_checkpoint_id] <= 1'b0;
                end
            end
        end else begin
            for (int stage_idx = LATENCY-1; stage_idx > 0; stage_idx--) begin
                valid_q[stage_idx] <=
                    valid_q[stage_idx-1] &&
                    !(squash_en &&
                      entry_q[stage_idx-1].speculation_mask[squash_checkpoint_id]);
                entry_q[stage_idx] <= entry_q[stage_idx-1];
                if (resolve_en) begin
                    entry_q[stage_idx].speculation_mask[resolve_checkpoint_id] <= 1'b0;
                end
            end

            valid_q[0] <= in_valid && in_ready && !input_squashed;
            if (in_valid && in_ready) begin
                entry_q[0].tag <= in_datapath.rob_tag;
                entry_q[0].preg <= in_datapath.new_des_preg;
                entry_q[0].dest_is_fp <= in_datapath.dest_is_fp;
                entry_q[0].reg_write <= in_control.reg_write;
                entry_q[0].speculation_mask <= in_datapath.speculation_mask;
                entry_q[0].result <= selected_result;
                entry_q[0].flags <= selected_flags;
                if (resolve_en) begin
                    entry_q[0].speculation_mask[resolve_checkpoint_id] <= 1'b0;
                end
            end else begin
                entry_q[0] <= '0;
            end
        end
    end

endmodule
