module rs #(
    parameter type T = defines_pkg::alu_rs_t,
    parameter logic [1:0] OPERATION = defines_pkg::FU_ALU
)(
    input  logic                           wb_valid,
    input  defines_pkg::preg_t             wb_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,

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

    logic [$clog2(RS_DEPTH)-1:0] free_idx;
    logic [$clog2(RS_DEPTH)-1:0] issue_idx;
    T enqueue_entry;

    always_comb begin
        for (int i = 0; i < RS_DEPTH; i++) begin
            free_vec[i]  = !used[i];
            ready_vec[i] = used[i] && entries[i].src1_ready && entries[i].src2_ready;
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

    assign in_if.ready  = free_valid;
    assign out_if.valid = ready_valid;
    assign out_if.data  = ready_valid ? entries[issue_idx] : '0;

    always_comb begin
        enqueue_entry = in_if.data;

        // Handle the common case where a source wakes up in the same cycle
        // that the instruction is inserted into the RS.
        if (wb_valid) begin
            if (!enqueue_entry.src1_ready &&
                enqueue_entry.datapath.src_reg_1p == wb_preg) begin
                enqueue_entry.src1_ready = 1'b1;
                enqueue_entry.datapath.src1_value = wb_result;
            end

            if (!enqueue_entry.src2_ready &&
                enqueue_entry.datapath.src_reg_2p == wb_preg) begin
                enqueue_entry.src2_ready = 1'b1;
                enqueue_entry.datapath.src2_value = wb_result;
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
                            entries[i].datapath.src_reg_1p == wb_preg) begin
                            entries[i].src1_ready <= 1'b1;
                            entries[i].datapath.src1_value <= wb_result;
                        end

                        if (!entries[i].src2_ready &&
                            entries[i].datapath.src_reg_2p == wb_preg) begin
                            entries[i].src2_ready <= 1'b1;
                            entries[i].datapath.src2_value <= wb_result;
                        end
                    end
                end
            end

            if (out_if.valid && out_if.ready && fu_sel == OPERATION) begin
                used[issue_idx] <= 1'b0;
            end
        end
    end

endmodule
