`timescale 1ns / 1ps

module rs #(
    parameter type T = defines_pkg::alu_rs_t,
    parameter logic [1:0] OPERATION = defines_pkg::FU_ALU,
    parameter bit SINGLE_ENTRY = 1'b0
)(
    input  logic                           wb_valid,
    input  logic                           wb_is_fp,
    input  defines_pkg::preg_t             wb_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           wb1_valid,
    input  logic                           wb1_is_fp,
    input  defines_pkg::preg_t             wb1_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb1_result,

    input  logic [1:0]                     fu_sel,

    input  logic flush,
    input  logic squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    pip_if.consumer in_if,
    pip_if.producer out_if
);
    import defines_pkg::*;

    T     entries [0:RS_DEPTH-1];
    logic used    [0:RS_DEPTH-1];

    logic [RS_DEPTH-1:0] free_vec;
    logic [RS_DEPTH-1:0] ready_vec;

    logic free_valid;
    logic ready_valid;
    logic any_used;

    logic [$clog2(RS_DEPTH)-1:0] free_idx;
    logic [$clog2(RS_DEPTH)-1:0] issue_idx;
    T enqueue_entry;

    function automatic logic domain_match(
        input logic writeback_is_fp,
        input logic source_is_fp
    );
    begin
        domain_match =
            ((source_is_fp === 1'b1) ? 1'b1 : 1'b0) ==
            ((writeback_is_fp === 1'b1) ? 1'b1 : 1'b0);
    end
    endfunction

    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            free_vec[i]  = !used[i];
            ready_vec[i] = used[i] &&
                           entries[i].src1_ready &&
                           entries[i].src2_ready &&
                           (entries[i].src3_ready ||
                            !entries[i].datapath.src3_is_fp);
        end
    end

    priority_decoder #(
        .WIDTH(RS_DEPTH)
    ) u_free_dec (
        .in   (free_vec),
        .valid(free_valid),
        .idx  (free_idx)
    );

    priority_decoder #(
        .WIDTH(RS_DEPTH)
    ) u_issue_dec (
        .in   (ready_vec),
        .valid(ready_valid),
        .idx  (issue_idx)
    );

    assign in_if.ready  = SINGLE_ENTRY ? !any_used : free_valid;

    // Use a statically expanded mux instead of dynamically indexing a packed
    // struct array. XSim 2019.1 can otherwise retain the previous entry when
    // only issue_idx changes, duplicating one issue while deleting another.
    always_comb begin
        out_if.valid = ready_valid;
        out_if.data  = '0;

        // Descending order lets the lowest ready index win without using a
        // dynamic array subscript in the data path.
        for (int i = RS_DEPTH-1; i >= 0; i--) begin
            if (ready_vec[i]) begin
                out_if.data = entries[i];
            end
        end
    end

    always_comb begin
        any_used = 1'b0;
        for (int i = 0; i < RS_DEPTH; i++) begin
            any_used = any_used || used[i];
        end
    end

    always_comb begin
        enqueue_entry = in_if.data;

        // Handle the common case where a source wakes up in the same cycle
        // that the instruction is inserted into the RS.
        if (wb_valid) begin
            if (!enqueue_entry.src1_ready &&
                domain_match(wb_is_fp, enqueue_entry.datapath.src1_is_fp) &&
                enqueue_entry.datapath.src_reg_1p == wb_preg) begin
                enqueue_entry.src1_ready = 1'b1;
                enqueue_entry.datapath.src1_value = wb_result;
            end

            if (!enqueue_entry.src2_ready &&
                domain_match(wb_is_fp, enqueue_entry.datapath.src2_is_fp) &&
                enqueue_entry.datapath.src_reg_2p == wb_preg) begin
                enqueue_entry.src2_ready = 1'b1;
                enqueue_entry.datapath.src2_value = wb_result;
            end

            if (!enqueue_entry.src3_ready &&
                domain_match(wb_is_fp, enqueue_entry.datapath.src3_is_fp) &&
                enqueue_entry.datapath.src_reg_3p == wb_preg) begin
                enqueue_entry.src3_ready = 1'b1;
                enqueue_entry.datapath.src3_value = wb_result;
            end
        end

        if (wb1_valid) begin
            if (!enqueue_entry.src1_ready &&
                domain_match(wb1_is_fp, enqueue_entry.datapath.src1_is_fp) &&
                enqueue_entry.datapath.src_reg_1p == wb1_preg) begin
                enqueue_entry.src1_ready = 1'b1;
                enqueue_entry.datapath.src1_value = wb1_result;
            end

            if (!enqueue_entry.src2_ready &&
                domain_match(wb1_is_fp, enqueue_entry.datapath.src2_is_fp) &&
                enqueue_entry.datapath.src_reg_2p == wb1_preg) begin
                enqueue_entry.src2_ready = 1'b1;
                enqueue_entry.datapath.src2_value = wb1_result;
            end

            if (!enqueue_entry.src3_ready &&
                domain_match(wb1_is_fp, enqueue_entry.datapath.src3_is_fp) &&
                enqueue_entry.datapath.src_reg_3p == wb1_preg) begin
                enqueue_entry.src3_ready = 1'b1;
                enqueue_entry.datapath.src3_value = wb1_result;
            end
        end
    end

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                entries[i] <= '0;
                used[i]    <= 1'b0;
            end
        end else begin
            if (squash_en) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (used[i] &&
                        entries[i].datapath.speculation_mask[squash_checkpoint_id]) begin
                        used[i] <= 1'b0;
                    end
                end
            end

            if (resolve_en) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (used[i]) begin
                        entries[i].datapath.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                    end
                end
            end

            if (in_if.valid && in_if.ready) begin
                entries[free_idx] <= enqueue_entry;
                used[free_idx]    <= 1'b1;
            end

            if (wb_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (used[i]) begin
                        if (!entries[i].src1_ready &&
                            domain_match(wb_is_fp, entries[i].datapath.src1_is_fp) &&
                            entries[i].datapath.src_reg_1p == wb_preg) begin
                            entries[i].src1_ready <= 1'b1;
                            entries[i].datapath.src1_value <= wb_result;
                        end

                        if (!entries[i].src2_ready &&
                            domain_match(wb_is_fp, entries[i].datapath.src2_is_fp) &&
                            entries[i].datapath.src_reg_2p == wb_preg) begin
                            entries[i].src2_ready <= 1'b1;
                            entries[i].datapath.src2_value <= wb_result;
                        end

                        if (!entries[i].src3_ready &&
                            domain_match(wb_is_fp, entries[i].datapath.src3_is_fp) &&
                            entries[i].datapath.src_reg_3p == wb_preg) begin
                            entries[i].src3_ready <= 1'b1;
                            entries[i].datapath.src3_value <= wb_result;
                        end
                    end
                end
            end

            if (wb1_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (used[i]) begin
                        if (!entries[i].src1_ready &&
                            domain_match(wb1_is_fp, entries[i].datapath.src1_is_fp) &&
                            entries[i].datapath.src_reg_1p == wb1_preg) begin
                            entries[i].src1_ready <= 1'b1;
                            entries[i].datapath.src1_value <= wb1_result;
                        end

                        if (!entries[i].src2_ready &&
                            domain_match(wb1_is_fp, entries[i].datapath.src2_is_fp) &&
                            entries[i].datapath.src_reg_2p == wb1_preg) begin
                            entries[i].src2_ready <= 1'b1;
                            entries[i].datapath.src2_value <= wb1_result;
                        end

                        if (!entries[i].src3_ready &&
                            domain_match(wb1_is_fp, entries[i].datapath.src3_is_fp) &&
                            entries[i].datapath.src_reg_3p == wb1_preg) begin
                            entries[i].src3_ready <= 1'b1;
                            entries[i].datapath.src3_value <= wb1_result;
                        end
                    end
                end
            end

            if (out_if.valid && out_if.ready) begin
                // A same-cycle enqueue may immediately reuse the issuing
                // slot. Preserve the newly written entry in that case.
                if (!(in_if.valid && in_if.ready &&
                      (free_idx == issue_idx))) begin
                    used[issue_idx] <= 1'b0;
                end
            end
        end
    end

endmodule
