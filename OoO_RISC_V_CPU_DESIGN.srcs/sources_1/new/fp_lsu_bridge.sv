`timescale 1ns / 1ps

// Adapter between decoded FP load/store intent and the integer-address LSU.
//
// FP memory operations still use an integer base address and immediate, but a
// load result must be written to the FP PRF and a store source comes from the
// FP register namespace. This bridge repackages those domain details without
// changing byte addressing, masks, or memory ordering semantics.
module fp_lsu_bridge #(
    parameter int MEM_WORDS = 256,
    parameter int DATA_CACHE_LINES = 8,
    parameter int DATA_CACHE_WAYS = 2,
    parameter int DATA_CACHE_WORDS_PER_LINE = 4,
    parameter int DATA_MEM_RESPONSE_LATENCY = 2
)(
    input  logic clk,
    input  logic rst_n,
    input  logic req_valid,
    output logic req_ready,
    input  logic req_store,
    input  logic [31:0] base_value,
    input  logic [31:0] store_value,
    input  logic [31:0] immediate,
    input  defines_pkg::rob_tag_t rob_tag,
    input  fp_defines_pkg::fp_preg_t dest_preg,
    input  defines_pkg::cp_mask_t speculation_mask,

    input  logic squash_en,
    input  defines_pkg::cp_id_t squash_checkpoint_id,
    input  logic resolve_en,
    input  defines_pkg::cp_id_t resolve_checkpoint_id,
    input  logic commit_store_valid0,
    input  defines_pkg::rob_tag_t commit_store_tag0,
    input  logic commit_store_valid1,
    input  defines_pkg::rob_tag_t commit_store_tag1,

    output logic resp_valid,
    output defines_pkg::rob_tag_t resp_tag,
    output fp_defines_pkg::fp_preg_t resp_preg,
    output logic resp_reg_write,
    output logic resp_dest_is_fp,
    output logic [31:0] resp_result
);

    import defines_pkg::*;
    import fp_defines_pkg::*;

    lsu_control_t control_signal;
    rs_datapath_t datapath;
    preg_t integer_preg;

    always_comb begin
        control_signal = '0;
        control_signal.reg_write = !req_store;
        control_signal.mem_read = !req_store;
        control_signal.mem_write = req_store;
        control_signal.funct3 = 3'b010;

        datapath = '0;
        datapath.src1_value = base_value;
        datapath.src2_value = store_value;
        datapath.new_des_preg = preg_t'(dest_preg);
        datapath.dest_is_fp = !req_store;
        datapath.rob_tag = rob_tag;
        datapath.imm = immediate;
        datapath.speculation_mask = speculation_mask;
    end

    lsu #(
        .MEM_WORDS                (MEM_WORDS),
        .DATA_CACHE_LINES         (DATA_CACHE_LINES),
        .DATA_CACHE_WAYS          (DATA_CACHE_WAYS),
        .DATA_CACHE_WORDS_PER_LINE(DATA_CACHE_WORDS_PER_LINE),
        .DATA_MEM_RESPONSE_LATENCY(DATA_MEM_RESPONSE_LATENCY)
    ) u_lsu (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .req_valid             (req_valid),
        .req_ready             (req_ready),
        .squash_en             (squash_en),
        .squash_checkpoint_id  (squash_checkpoint_id),
        .resolve_en            (resolve_en),
        .resolve_checkpoint_id (resolve_checkpoint_id),
        .commit_store_valid0   (commit_store_valid0),
        .commit_store_tag0     (commit_store_tag0),
        .commit_store_valid1   (commit_store_valid1),
        .commit_store_tag1     (commit_store_tag1),
        .control_signal        (control_signal),
        .datapath              (datapath),
        .resp_valid            (resp_valid),
        .resp_tag              (resp_tag),
        .resp_preg             (integer_preg),
        .resp_reg_write        (resp_reg_write),
        .resp_dest_is_fp       (resp_dest_is_fp),
        .resp_result           (resp_result)
    );

    assign resp_preg = fp_preg_t'(integer_preg);

endmodule
