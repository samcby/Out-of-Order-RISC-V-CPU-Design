`timescale 1ns / 1ps

// Split load/store issue queue with two-wide enqueue and dequeue.
//
// Loads remain resident after issue until retirement. This retained history
// lets the queue detect a younger load that executed before an older store
// resolved its address. A detected alias requests a full backend replay from
// the load PC; the top-level recovery path restores the committed rename map.
module load_store_queue #(
    parameter int LOAD_DEPTH = defines_pkg::RS_DEPTH,
    parameter int STORE_DEPTH = defines_pkg::RS_DEPTH
)(
    input  logic                           wb_valid,
    input  logic                           wb_is_fp,
    input  defines_pkg::preg_t             wb_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           wb1_valid,
    input  logic                           wb1_is_fp,
    input  defines_pkg::preg_t             wb1_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb1_result,

    input  logic                           complete_valid0,
    input  defines_pkg::rob_tag_t          complete_tag0,
    input  logic                           complete_valid1,
    input  defines_pkg::rob_tag_t          complete_tag1,
    input  logic                           commit_valid0,
    input  defines_pkg::rob_tag_t          commit_tag0,
    input  logic                           commit_valid1,
    input  defines_pkg::rob_tag_t          commit_tag1,

    input  logic                           flush,
    input  logic                           squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic                           resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    pip_if.consumer in0_if,
    pip_if.consumer in1_if,
    pip_if.producer out0_if,
    pip_if.producer out1_if,

    output logic                           replay_valid,
    output defines_pkg::rob_tag_t          replay_tag,
    output logic [defines_pkg::WIDTH-1:0]  replay_pc,
    output defines_pkg::cp_mask_t          replay_speculation_mask
);
    import defines_pkg::*;

    localparam int LOAD_IDX_W =
        (LOAD_DEPTH <= 1) ? 1 : $clog2(LOAD_DEPTH);
    localparam int STORE_IDX_W =
        (STORE_DEPTH <= 1) ? 1 : $clog2(STORE_DEPTH);

    lsu_rs_t load_entry [0:LOAD_DEPTH-1];
    logic    load_valid [0:LOAD_DEPTH-1];
    logic    load_issued [0:LOAD_DEPTH-1];
    logic    load_completed [0:LOAD_DEPTH-1];
    logic    load_violation [0:LOAD_DEPTH-1];
    logic    load_violation_now [0:LOAD_DEPTH-1];
    logic [STORE_DEPTH-1:0] load_unknown_store_mask [0:LOAD_DEPTH-1];

    lsu_rs_t store_entry [0:STORE_DEPTH-1];
    logic    store_valid [0:STORE_DEPTH-1];

    mem_seq_t next_mem_seq_q;

    logic load_free0_valid;
    logic load_free1_valid;
    logic [LOAD_IDX_W-1:0] load_free0_idx;
    logic [LOAD_IDX_W-1:0] load_free1_idx;
    logic store_free0_valid;
    logic store_free1_valid;
    logic [STORE_IDX_W-1:0] store_free0_idx;
    logic [STORE_IDX_W-1:0] store_free1_idx;

    logic in0_is_load;
    logic in0_is_store;
    logic in1_is_load;
    logic in1_is_store;
    logic pair_needs_two_loads;
    logic pair_needs_two_stores;
    logic in0_capacity;
    logic in1_capacity;

    logic sel0_valid;
    logic sel0_is_load;
    logic [LOAD_IDX_W-1:0] sel0_load_idx;
    logic [STORE_IDX_W-1:0] sel0_store_idx;
    mem_seq_t sel0_seq;
    logic sel1_valid;
    logic sel1_is_load;
    logic [LOAD_IDX_W-1:0] sel1_load_idx;
    logic [STORE_IDX_W-1:0] sel1_store_idx;
    mem_seq_t sel1_seq;

    logic [STORE_DEPTH-1:0] sel0_unknown_mask;
    logic [STORE_DEPTH-1:0] sel1_unknown_mask;
    mem_seq_t replay_seq;

    function automatic logic seq_older(
        input mem_seq_t lhs,
        input mem_seq_t rhs
    );
        seq_older = $signed(lhs - rhs) < 0;
    endfunction

    function automatic logic domain_match(
        input logic writeback_is_fp,
        input logic source_is_fp
    );
        domain_match = (writeback_is_fp == source_is_fp);
    endfunction

    function automatic logic entry_ready(input lsu_rs_t entry);
        entry_ready = entry.src1_ready &&
                      (!entry.control_signal.mem_write || entry.src2_ready);
    endfunction

    function automatic logic [WIDTH-1:0] effective_addr(
        input lsu_rs_t entry
    );
        effective_addr = entry.datapath.src1_value + entry.datapath.imm;
    endfunction

    function automatic logic [2:0] access_bytes_minus1(
        input lsu_control_t control_signal
    );
        unique case (control_signal.funct3)
            3'b001,
            3'b101: access_bytes_minus1 = 3'd1;
            3'b010: access_bytes_minus1 = 3'd3;
            default: access_bytes_minus1 = 3'd0;
        endcase
    endfunction

    function automatic logic entries_overlap(
        input lsu_rs_t older_store,
        input lsu_rs_t younger_load
    );
        logic [WIDTH:0] store_first;
        logic [WIDTH:0] store_last;
        logic [WIDTH:0] load_first;
        logic [WIDTH:0] load_last;
    begin
        store_first = {1'b0, effective_addr(older_store)};
        store_last = store_first +
                     access_bytes_minus1(older_store.control_signal);
        load_first = {1'b0, effective_addr(younger_load)};
        load_last = load_first +
                    access_bytes_minus1(younger_load.control_signal);
        entries_overlap = (store_first <= load_last) &&
                          (load_first <= store_last);
    end
    endfunction

    always_comb begin
        load_free0_valid = 1'b0;
        load_free1_valid = 1'b0;
        load_free0_idx = '0;
        load_free1_idx = '0;
        for (int i = 0; i < LOAD_DEPTH; i++) begin
            if (!load_valid[i]) begin
                if (!load_free0_valid) begin
                    load_free0_valid = 1'b1;
                    load_free0_idx = i;
                end else if (!load_free1_valid) begin
                    load_free1_valid = 1'b1;
                    load_free1_idx = i;
                end
            end
        end

        store_free0_valid = 1'b0;
        store_free1_valid = 1'b0;
        store_free0_idx = '0;
        store_free1_idx = '0;
        for (int i = 0; i < STORE_DEPTH; i++) begin
            if (!store_valid[i]) begin
                if (!store_free0_valid) begin
                    store_free0_valid = 1'b1;
                    store_free0_idx = i;
                end else if (!store_free1_valid) begin
                    store_free1_valid = 1'b1;
                    store_free1_idx = i;
                end
            end
        end
    end

    // Capacity is an upstream promise and must not depend on valid. Dispatch
    // presents the candidate payload before asserting valid, so classifying
    // that payload here breaks the ready/valid feedback path while preserving
    // atomic two-lane admission.
    assign in0_is_load =
        (in0_if.data.control_signal.mem_read === 1'b1);
    assign in0_is_store =
        (in0_if.data.control_signal.mem_write === 1'b1);
    assign in1_is_load =
        (in1_if.data.control_signal.mem_read === 1'b1);
    assign in1_is_store =
        (in1_if.data.control_signal.mem_write === 1'b1);
    assign pair_needs_two_loads = in0_is_load && in1_is_load;
    assign pair_needs_two_stores = in0_is_store && in1_is_store;

    assign in0_capacity =
        in0_is_load ?
            (pair_needs_two_loads ? load_free1_valid : load_free0_valid) :
        in0_is_store ?
            (pair_needs_two_stores ? store_free1_valid : store_free0_valid) :
            1'b1;
    assign in1_capacity =
        in1_is_load ?
            (pair_needs_two_loads ? load_free1_valid : load_free0_valid) :
        in1_is_store ?
            (pair_needs_two_stores ? store_free1_valid : store_free0_valid) :
            1'b1;

    // Packet lanes share one acceptance decision. Both ready signals therefore
    // make the same atomic capacity promise to dispatch.
    assign in0_if.ready = in0_capacity && in1_capacity;
    assign in1_if.ready = in0_capacity && in1_capacity;

    always_comb begin
        sel0_valid = 1'b0;
        sel0_is_load = 1'b0;
        sel0_load_idx = '0;
        sel0_store_idx = '0;
        sel0_seq = '0;

        for (int i = 0; i < LOAD_DEPTH; i++) begin
            if (load_valid[i] && !load_issued[i] &&
                entry_ready(load_entry[i]) &&
                (!sel0_valid ||
                 seq_older(load_entry[i].datapath.mem_seq, sel0_seq))) begin
                sel0_valid = 1'b1;
                sel0_is_load = 1'b1;
                sel0_load_idx = i;
                sel0_store_idx = '0;
                sel0_seq = load_entry[i].datapath.mem_seq;
            end
        end
        for (int i = 0; i < STORE_DEPTH; i++) begin
            if (store_valid[i] && entry_ready(store_entry[i]) &&
                (!sel0_valid ||
                 seq_older(store_entry[i].datapath.mem_seq, sel0_seq))) begin
                sel0_valid = 1'b1;
                sel0_is_load = 1'b0;
                sel0_load_idx = '0;
                sel0_store_idx = i;
                sel0_seq = store_entry[i].datapath.mem_seq;
            end
        end

        sel1_valid = 1'b0;
        sel1_is_load = 1'b0;
        sel1_load_idx = '0;
        sel1_store_idx = '0;
        sel1_seq = '0;

        for (int i = 0; i < LOAD_DEPTH; i++) begin
            if (load_valid[i] && !load_issued[i] &&
                entry_ready(load_entry[i]) &&
                !(sel0_valid && sel0_is_load &&
                  (sel0_load_idx == i)) &&
                (!sel1_valid ||
                 seq_older(load_entry[i].datapath.mem_seq, sel1_seq))) begin
                sel1_valid = 1'b1;
                sel1_is_load = 1'b1;
                sel1_load_idx = i;
                sel1_store_idx = '0;
                sel1_seq = load_entry[i].datapath.mem_seq;
            end
        end
        for (int i = 0; i < STORE_DEPTH; i++) begin
            if (store_valid[i] && entry_ready(store_entry[i]) &&
                !(sel0_valid && !sel0_is_load &&
                  (sel0_store_idx == i)) &&
                (!sel1_valid ||
                 seq_older(store_entry[i].datapath.mem_seq, sel1_seq))) begin
                sel1_valid = 1'b1;
                sel1_is_load = 1'b0;
                sel1_load_idx = '0;
                sel1_store_idx = i;
                sel1_seq = store_entry[i].datapath.mem_seq;
            end
        end
    end

    always_comb begin
        sel0_unknown_mask = '0;
        sel1_unknown_mask = '0;
        for (int i = 0; i < STORE_DEPTH; i++) begin
            if (store_valid[i] &&
                !entry_ready(store_entry[i])) begin
                if (sel0_valid && sel0_is_load &&
                    seq_older(store_entry[i].datapath.mem_seq, sel0_seq)) begin
                    sel0_unknown_mask[i] = 1'b1;
                end
                if (sel1_valid && sel1_is_load &&
                    seq_older(store_entry[i].datapath.mem_seq, sel1_seq)) begin
                    sel1_unknown_mask[i] = 1'b1;
                end
            end
        end
    end

    always_comb begin
        out0_if.valid = sel0_valid;
        out0_if.data = '0;
        if (sel0_valid) begin
            out0_if.data = sel0_is_load ?
                           load_entry[sel0_load_idx] :
                           store_entry[sel0_store_idx];
        end

        out1_if.valid = sel1_valid && sel0_valid;
        out1_if.data = '0;
        if (sel1_valid) begin
            out1_if.data = sel1_is_load ?
                           load_entry[sel1_load_idx] :
                           store_entry[sel1_store_idx];
        end
    end

    always_comb begin
        for (int l = 0; l < LOAD_DEPTH; l++) begin
            load_violation_now[l] = 1'b0;
            for (int s = 0; s < STORE_DEPTH; s++) begin
                if (load_valid[l] && load_issued[l] &&
                    load_unknown_store_mask[l][s] &&
                    store_valid[s] && entry_ready(store_entry[s]) &&
                    entries_overlap(store_entry[s], load_entry[l])) begin
                    load_violation_now[l] = 1'b1;
                end
            end
        end
    end

    // A violation is sticky until the load leaves the queue. This prevents a
    // younger replay already pending at the backend from consuming the only
    // cycle in which an older store resolves and exposes a second violation.
    always_comb begin
        replay_valid = 1'b0;
        replay_tag = '0;
        replay_pc = '0;
        replay_speculation_mask = '0;
        replay_seq = '0;
        // Keep raw detection independent of global flush. The top level
        // registers a replay before it may drive flush; feeding flush back
        // here would create a zero-delay replay/retirement recovery loop.
        for (int l = 0; l < LOAD_DEPTH; l++) begin
            if (load_valid[l] && load_issued[l] &&
                (load_violation[l] || load_violation_now[l]) &&
                (!replay_valid ||
                 seq_older(load_entry[l].datapath.mem_seq,
                           replay_seq))) begin
                replay_valid = 1'b1;
                replay_tag = load_entry[l].datapath.rob_tag;
                replay_pc = load_entry[l].datapath.pc;
                replay_speculation_mask =
                    load_entry[l].datapath.speculation_mask;
                replay_seq = load_entry[l].datapath.mem_seq;
            end
        end
    end

    always_ff @(posedge in0_if.clk or negedge in0_if.rst_n) begin
        if (!in0_if.rst_n || flush) begin
            next_mem_seq_q <= '0;
            for (int i = 0; i < LOAD_DEPTH; i++) begin
                load_entry[i] <= '0;
                load_valid[i] <= 1'b0;
                load_issued[i] <= 1'b0;
                load_completed[i] <= 1'b0;
                load_violation[i] <= 1'b0;
                load_unknown_store_mask[i] <= '0;
            end
            for (int i = 0; i < STORE_DEPTH; i++) begin
                store_entry[i] <= '0;
                store_valid[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < LOAD_DEPTH; i++) begin
                if (load_valid[i]) begin
                    if (load_violation_now[i]) begin
                        load_violation[i] <= 1'b1;
                    end
                    if (wb_valid) begin
                        if (!load_entry[i].src1_ready &&
                            domain_match(
                                wb_is_fp,
                                load_entry[i].datapath.src1_is_fp) &&
                            (load_entry[i].datapath.src_reg_1p == wb_preg)) begin
                            load_entry[i].src1_ready <= 1'b1;
                            load_entry[i].datapath.src1_value <= wb_result;
                        end
                        if (!load_entry[i].src2_ready &&
                            domain_match(
                                wb_is_fp,
                                load_entry[i].datapath.src2_is_fp) &&
                            (load_entry[i].datapath.src_reg_2p == wb_preg)) begin
                            load_entry[i].src2_ready <= 1'b1;
                            load_entry[i].datapath.src2_value <= wb_result;
                        end
                    end
                    if (wb1_valid) begin
                        if (!load_entry[i].src1_ready &&
                            domain_match(
                                wb1_is_fp,
                                load_entry[i].datapath.src1_is_fp) &&
                            (load_entry[i].datapath.src_reg_1p == wb1_preg)) begin
                            load_entry[i].src1_ready <= 1'b1;
                            load_entry[i].datapath.src1_value <= wb1_result;
                        end
                        if (!load_entry[i].src2_ready &&
                            domain_match(
                                wb1_is_fp,
                                load_entry[i].datapath.src2_is_fp) &&
                            (load_entry[i].datapath.src_reg_2p == wb1_preg)) begin
                            load_entry[i].src2_ready <= 1'b1;
                            load_entry[i].datapath.src2_value <= wb1_result;
                        end
                    end

                    if (complete_valid0 &&
                        (load_entry[i].datapath.rob_tag == complete_tag0)) begin
                        load_completed[i] <= 1'b1;
                    end
                    if (complete_valid1 &&
                        (load_entry[i].datapath.rob_tag == complete_tag1)) begin
                        load_completed[i] <= 1'b1;
                    end
                    if ((commit_valid0 &&
                         (load_entry[i].datapath.rob_tag == commit_tag0)) ||
                        (commit_valid1 &&
                         (load_entry[i].datapath.rob_tag == commit_tag1))) begin
                        load_entry[i] <= '0;
                        load_valid[i] <= 1'b0;
                        load_issued[i] <= 1'b0;
                        load_completed[i] <= 1'b0;
                        load_violation[i] <= 1'b0;
                        load_unknown_store_mask[i] <= '0;
                    end

                    if (squash_en &&
                        load_entry[i].datapath.speculation_mask[
                            squash_checkpoint_id]) begin
                        load_entry[i] <= '0;
                        load_valid[i] <= 1'b0;
                        load_issued[i] <= 1'b0;
                        load_completed[i] <= 1'b0;
                        load_violation[i] <= 1'b0;
                        load_unknown_store_mask[i] <= '0;
                    end else if (resolve_en) begin
                        load_entry[i].datapath.speculation_mask[
                            resolve_checkpoint_id] <= 1'b0;
                    end

                    for (int s = 0; s < STORE_DEPTH; s++) begin
                        if (load_unknown_store_mask[i][s] &&
                            (!store_valid[s] ||
                             entry_ready(store_entry[s]))) begin
                            load_unknown_store_mask[i][s] <= 1'b0;
                        end
                    end
                end
            end

            for (int i = 0; i < STORE_DEPTH; i++) begin
                if (store_valid[i]) begin
                    if (wb_valid) begin
                        if (!store_entry[i].src1_ready &&
                            domain_match(
                                wb_is_fp,
                                store_entry[i].datapath.src1_is_fp) &&
                            (store_entry[i].datapath.src_reg_1p == wb_preg)) begin
                            store_entry[i].src1_ready <= 1'b1;
                            store_entry[i].datapath.src1_value <= wb_result;
                        end
                        if (!store_entry[i].src2_ready &&
                            domain_match(
                                wb_is_fp,
                                store_entry[i].datapath.src2_is_fp) &&
                            (store_entry[i].datapath.src_reg_2p == wb_preg)) begin
                            store_entry[i].src2_ready <= 1'b1;
                            store_entry[i].datapath.src2_value <= wb_result;
                        end
                    end
                    if (wb1_valid) begin
                        if (!store_entry[i].src1_ready &&
                            domain_match(
                                wb1_is_fp,
                                store_entry[i].datapath.src1_is_fp) &&
                            (store_entry[i].datapath.src_reg_1p == wb1_preg)) begin
                            store_entry[i].src1_ready <= 1'b1;
                            store_entry[i].datapath.src1_value <= wb1_result;
                        end
                        if (!store_entry[i].src2_ready &&
                            domain_match(
                                wb1_is_fp,
                                store_entry[i].datapath.src2_is_fp) &&
                            (store_entry[i].datapath.src_reg_2p == wb1_preg)) begin
                            store_entry[i].src2_ready <= 1'b1;
                            store_entry[i].datapath.src2_value <= wb1_result;
                        end
                    end

                    if (squash_en &&
                        store_entry[i].datapath.speculation_mask[
                            squash_checkpoint_id]) begin
                        store_entry[i] <= '0;
                        store_valid[i] <= 1'b0;
                    end else if (resolve_en) begin
                        store_entry[i].datapath.speculation_mask[
                            resolve_checkpoint_id] <= 1'b0;
                    end
                end
            end

            if (out0_if.valid && out0_if.ready) begin
                if (sel0_is_load) begin
                    load_issued[sel0_load_idx] <= 1'b1;
                    load_unknown_store_mask[sel0_load_idx] <=
                        sel0_unknown_mask;
                end else begin
                    store_entry[sel0_store_idx] <= '0;
                    store_valid[sel0_store_idx] <= 1'b0;
                end
            end
            if (out1_if.valid && out1_if.ready) begin
                if (sel1_is_load) begin
                    load_issued[sel1_load_idx] <= 1'b1;
                    load_unknown_store_mask[sel1_load_idx] <=
                        sel1_unknown_mask;
                end else begin
                    store_entry[sel1_store_idx] <= '0;
                    store_valid[sel1_store_idx] <= 1'b0;
                end
            end

            if (in0_if.valid && in0_if.ready) begin
                if (in0_is_load) begin
                    load_entry[load_free0_idx] <= in0_if.data;
                    load_entry[load_free0_idx].datapath.mem_seq <=
                        next_mem_seq_q;
                    load_valid[load_free0_idx] <= 1'b1;
                    load_issued[load_free0_idx] <= 1'b0;
                    load_completed[load_free0_idx] <= 1'b0;
                    load_violation[load_free0_idx] <= 1'b0;
                    load_unknown_store_mask[load_free0_idx] <= '0;
                end else if (in0_is_store) begin
                    store_entry[store_free0_idx] <= in0_if.data;
                    store_entry[store_free0_idx].datapath.mem_seq <=
                        next_mem_seq_q;
                    store_valid[store_free0_idx] <= 1'b1;
                end
            end

            if (in1_if.valid && in1_if.ready) begin
                if (in1_is_load) begin
                    load_entry[pair_needs_two_loads ?
                               load_free1_idx : load_free0_idx] <= in1_if.data;
                    load_entry[pair_needs_two_loads ?
                               load_free1_idx : load_free0_idx].datapath.mem_seq <=
                        next_mem_seq_q +
                        ((in0_if.valid && in0_if.ready) ? 1'b1 : 1'b0);
                    load_valid[pair_needs_two_loads ?
                               load_free1_idx : load_free0_idx] <= 1'b1;
                    load_issued[pair_needs_two_loads ?
                                load_free1_idx : load_free0_idx] <= 1'b0;
                    load_completed[pair_needs_two_loads ?
                                   load_free1_idx : load_free0_idx] <= 1'b0;
                    load_violation[pair_needs_two_loads ?
                                   load_free1_idx : load_free0_idx] <= 1'b0;
                    load_unknown_store_mask[pair_needs_two_loads ?
                                            load_free1_idx :
                                            load_free0_idx] <= '0;
                end else if (in1_is_store) begin
                    store_entry[pair_needs_two_stores ?
                                store_free1_idx : store_free0_idx] <= in1_if.data;
                    store_entry[pair_needs_two_stores ?
                                store_free1_idx : store_free0_idx].datapath.mem_seq <=
                        next_mem_seq_q +
                        ((in0_if.valid && in0_if.ready) ? 1'b1 : 1'b0);
                    store_valid[pair_needs_two_stores ?
                                store_free1_idx : store_free0_idx] <= 1'b1;
                end
            end

            if ((in0_if.valid && in0_if.ready) ||
                (in1_if.valid && in1_if.ready)) begin
                next_mem_seq_q <= next_mem_seq_q +
                    ((in0_if.valid && in0_if.ready) ? 1'b1 : 1'b0) +
                    ((in1_if.valid && in1_if.ready) ? 1'b1 : 1'b0);
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge in0_if.clk) begin
        if (in0_if.rst_n) begin
            assert (!(out1_if.valid && !out0_if.valid))
                else $error("LSQ: slot1 issued without slot0");
        end
    end
`endif

endmodule
