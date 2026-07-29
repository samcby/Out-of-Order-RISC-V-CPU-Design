`timescale 1ns / 1ps

// Conservative memory-order queue for renamed Load and Store instructions.
//
// The queue tracks source readiness and age, then exposes only its oldest ready
// memory operation to the LSU. This intentionally limits memory-level
// speculation: address disambiguation and store-to-load forwarding happen in
// the LSU, while the MOQ keeps issue order simple and deterministic. A small
// registered head stage decouples queue selection from the LSU handshake.
//
// Like other backend queues, entries wake on PRF writeback and are selectively
// removed/updated by branch checkpoint squash and resolve events.
module memory_order_queue #(
    parameter int DEPTH = defines_pkg::RS_DEPTH
)(
    input  logic                           wb_valid,
    input  logic                           wb_is_fp,
    input  defines_pkg::preg_t             wb_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           wb1_valid,
    input  logic                           wb1_is_fp,
    input  defines_pkg::preg_t             wb1_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb1_result,

    input  logic                           flush,
    input  logic                           squash_en,
    input  defines_pkg::cp_id_t            squash_checkpoint_id,
    input  logic                           resolve_en,
    input  defines_pkg::cp_id_t            resolve_checkpoint_id,

    pip_if.consumer in_if,
    pip_if.producer out_if
);
    import defines_pkg::*;

    localparam int IDX_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH);
    localparam int AGE_W = 32;

    lsu_rs_t entries [0:DEPTH-1];
    logic used [0:DEPTH-1];
    logic [AGE_W-1:0] age [0:DEPTH-1];
    logic [AGE_W-1:0] next_age_q;

    logic free_valid;
    logic [IDX_W-1:0] free_idx;
    logic oldest_valid;
    logic [IDX_W-1:0] oldest_idx;
    logic [AGE_W-1:0] oldest_age;
    lsu_rs_t oldest_entry;

    logic head_occupied_q;
    lsu_rs_t head_entry_q;
    lsu_rs_t head_entry_view;
    logic head_ready;
    logic head_killed;
    logic head_pop;
    logic head_slot_available;

    logic input_survives;
    logic push_fire;
    logic direct_fire;
    logic queue_push_fire;
    logic queue_to_head_fire;
    lsu_rs_t enqueue_entry;

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
        free_valid = 1'b0;
        free_idx = '0;
        oldest_valid = 1'b0;
        oldest_idx = '0;
        oldest_age = '0;
        oldest_entry = '0;

        for (int i = 0; i < DEPTH; i++) begin
            if (!used[i] && !free_valid) begin
                free_valid = 1'b1;
                free_idx = i[IDX_W-1:0];
            end

            if (used[i] &&
                !(squash_en &&
                  entries[i].datapath.speculation_mask[squash_checkpoint_id]) &&
                (!oldest_valid || (age[i] < oldest_age))) begin
                oldest_valid = 1'b1;
                oldest_idx = i[IDX_W-1:0];
                oldest_age = age[i];
            end
        end

        if (oldest_valid) begin
            for (int i = 0; i < DEPTH; i++) begin
                if (oldest_idx == i[IDX_W-1:0]) begin
                    oldest_entry = entries[i];
                end
            end

            if (wb_valid) begin
                if (!oldest_entry.src1_ready &&
                    domain_match(wb_is_fp, oldest_entry.datapath.src1_is_fp) &&
                    oldest_entry.datapath.src_reg_1p == wb_preg) begin
                    oldest_entry.src1_ready = 1'b1;
                    oldest_entry.datapath.src1_value = wb_result;
                end
                if (!oldest_entry.src2_ready &&
                    domain_match(wb_is_fp, oldest_entry.datapath.src2_is_fp) &&
                    oldest_entry.datapath.src_reg_2p == wb_preg) begin
                    oldest_entry.src2_ready = 1'b1;
                    oldest_entry.datapath.src2_value = wb_result;
                end
            end

            if (wb1_valid) begin
                if (!oldest_entry.src1_ready &&
                    domain_match(wb1_is_fp, oldest_entry.datapath.src1_is_fp) &&
                    oldest_entry.datapath.src_reg_1p == wb1_preg) begin
                    oldest_entry.src1_ready = 1'b1;
                    oldest_entry.datapath.src1_value = wb1_result;
                end
                if (!oldest_entry.src2_ready &&
                    domain_match(wb1_is_fp, oldest_entry.datapath.src2_is_fp) &&
                    oldest_entry.datapath.src_reg_2p == wb1_preg) begin
                    oldest_entry.src2_ready = 1'b1;
                    oldest_entry.datapath.src2_value = wb1_result;
                end
            end

            if (resolve_en) begin
                oldest_entry.datapath.speculation_mask[resolve_checkpoint_id] = 1'b0;
            end
        end
    end

    always_comb begin
        enqueue_entry = in_if.data;

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
        end

        if (resolve_en) begin
            enqueue_entry.datapath.speculation_mask[resolve_checkpoint_id] = 1'b0;
        end
    end

    always_comb begin
        head_entry_view = head_entry_q;
        if (resolve_en) begin
            head_entry_view.datapath.speculation_mask[resolve_checkpoint_id] = 1'b0;
        end
    end

    assign head_killed = head_occupied_q && squash_en &&
                         head_entry_q.datapath.speculation_mask[squash_checkpoint_id];
    assign head_ready = head_occupied_q &&
                        head_entry_q.src1_ready &&
                        head_entry_q.src2_ready &&
                        !head_killed;
    assign out_if.valid = head_ready;
    assign out_if.data = head_ready ? head_entry_view : '0;
    assign head_pop = out_if.valid && out_if.ready;
    assign head_slot_available = !head_occupied_q || head_pop || head_killed;

    assign in_if.ready = free_valid;
    assign input_survives = !(squash_en &&
                              in_if.data.datapath.speculation_mask[squash_checkpoint_id]);
    assign push_fire = in_if.valid && in_if.ready && input_survives;
    assign queue_to_head_fire = head_slot_available && oldest_valid;
    assign direct_fire = head_slot_available && !oldest_valid && push_fire;
    assign queue_push_fire = push_fire && !direct_fire;

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            for (int i = 0; i < DEPTH; i++) begin
                entries[i] <= '0;
                used[i] <= 1'b0;
                age[i] <= '0;
            end
            next_age_q <= '0;
            head_occupied_q <= 1'b0;
            head_entry_q <= '0;
        end else begin
            if (squash_en) begin
                for (int i = 0; i < DEPTH; i++) begin
                    if (used[i] &&
                        entries[i].datapath.speculation_mask[squash_checkpoint_id]) begin
                        used[i] <= 1'b0;
                    end
                end
            end

            if (resolve_en) begin
                for (int i = 0; i < DEPTH; i++) begin
                    if (used[i]) begin
                        entries[i].datapath.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                    end
                end
                if (head_occupied_q) begin
                    head_entry_q.datapath.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                end
            end

            if (queue_push_fire) begin
                entries[free_idx] <= enqueue_entry;
                used[free_idx] <= 1'b1;
                age[free_idx] <= next_age_q;
            end
            if (push_fire) begin
                next_age_q <= next_age_q + 1'b1;
            end

            if (wb_valid) begin
                for (int i = 0; i < DEPTH; i++) begin
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
                    end
                end

                if (head_occupied_q) begin
                    if (!head_entry_q.src1_ready &&
                        domain_match(wb_is_fp, head_entry_q.datapath.src1_is_fp) &&
                        head_entry_q.datapath.src_reg_1p == wb_preg) begin
                        head_entry_q.src1_ready <= 1'b1;
                        head_entry_q.datapath.src1_value <= wb_result;
                    end
                    if (!head_entry_q.src2_ready &&
                        domain_match(wb_is_fp, head_entry_q.datapath.src2_is_fp) &&
                        head_entry_q.datapath.src_reg_2p == wb_preg) begin
                        head_entry_q.src2_ready <= 1'b1;
                        head_entry_q.datapath.src2_value <= wb_result;
                    end
                end
            end

            if (wb1_valid) begin
                for (int i = 0; i < DEPTH; i++) begin
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
                    end
                end

                if (head_occupied_q) begin
                    if (!head_entry_q.src1_ready &&
                        domain_match(wb1_is_fp, head_entry_q.datapath.src1_is_fp) &&
                        head_entry_q.datapath.src_reg_1p == wb1_preg) begin
                        head_entry_q.src1_ready <= 1'b1;
                        head_entry_q.datapath.src1_value <= wb1_result;
                    end
                    if (!head_entry_q.src2_ready &&
                        domain_match(wb1_is_fp, head_entry_q.datapath.src2_is_fp) &&
                        head_entry_q.datapath.src_reg_2p == wb1_preg) begin
                        head_entry_q.src2_ready <= 1'b1;
                        head_entry_q.datapath.src2_value <= wb1_result;
                    end
                end
            end

            if (head_killed || head_pop) begin
                head_occupied_q <= 1'b0;
                head_entry_q <= '0;
            end

            // Loading the registered head has final priority over wakeup and
            // pop assignments because it installs a different instruction.
            if (queue_to_head_fire) begin
                head_occupied_q <= 1'b1;
                head_entry_q <= oldest_entry;
                used[oldest_idx] <= 1'b0;
            end else if (direct_fire) begin
                head_occupied_q <= 1'b1;
                head_entry_q <= enqueue_entry;
            end
        end
    end

endmodule
