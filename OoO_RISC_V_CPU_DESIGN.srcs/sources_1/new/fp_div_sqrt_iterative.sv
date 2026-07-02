`timescale 1ns / 1ps

module fp_div_sqrt_iterative #(
    parameter int DIV_LATENCY = 16,
    parameter int SQRT_LATENCY = 24
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
    output logic [4:0]                    out_flags,
    output logic                          busy
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
    } fp_long_entry_t;

    fp_long_entry_t entry_q;
    logic out_valid_q;
    integer cycles_left_q;
    logic [2:0] effective_rounding_mode;
    logic [31:0] computed_result;
    logic [4:0] computed_flags;
    logic input_squashed;
    logic entry_squashed;

    assign effective_rounding_mode =
        (in_control.fp_rm == 3'b111) ? fp_frm : in_control.fp_rm;

    fp_div_sqrt_unit u_numeric_core (
        .operation    (in_control.fp_op),
        .rounding_mode(effective_rounding_mode),
        .operand_a    (in_datapath.src1_value),
        .operand_b    (in_datapath.src2_value),
        .result       (computed_result),
        .flags        (computed_flags)
    );

    assign input_squashed =
        squash_en && in_datapath.speculation_mask[squash_checkpoint_id];
    assign entry_squashed =
        squash_en && entry_q.speculation_mask[squash_checkpoint_id];
    assign busy = (cycles_left_q != 0);
    assign in_ready = !busy && (!out_valid_q || out_ready);
    assign out_valid = out_valid_q && !entry_squashed;
    assign out_tag = entry_q.tag;
    assign out_preg = entry_q.preg;
    assign out_dest_is_fp = entry_q.dest_is_fp;
    assign out_reg_write = entry_q.reg_write;
    assign out_result = entry_q.result;
    assign out_flags = entry_q.flags;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            entry_q <= '0;
            out_valid_q <= 1'b0;
            cycles_left_q <= 0;
        end else begin
            if (out_valid_q && out_ready) begin
                out_valid_q <= 1'b0;
            end

            if (entry_squashed) begin
                entry_q <= '0;
                out_valid_q <= 1'b0;
                cycles_left_q <= 0;
            end else begin
                if (resolve_en) begin
                    entry_q.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                end

                if (cycles_left_q > 1) begin
                    cycles_left_q <= cycles_left_q - 1;
                end else if (cycles_left_q == 1) begin
                    cycles_left_q <= 0;
                    out_valid_q <= 1'b1;
                end

                if (in_valid && in_ready && !input_squashed) begin
                    entry_q.tag <= in_datapath.rob_tag;
                    entry_q.preg <= in_datapath.new_des_preg;
                    entry_q.dest_is_fp <= in_datapath.dest_is_fp;
                    entry_q.reg_write <= in_control.reg_write;
                    entry_q.speculation_mask <= in_datapath.speculation_mask;
                    entry_q.result <= computed_result;
                    entry_q.flags <= computed_flags;
                    if (resolve_en) begin
                        entry_q.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                    end
                    cycles_left_q <=
                        (in_control.fp_op == FP_OP_SQRT) ?
                        SQRT_LATENCY : DIV_LATENCY;
                    out_valid_q <= 1'b0;
                end
            end
        end
    end

endmodule
