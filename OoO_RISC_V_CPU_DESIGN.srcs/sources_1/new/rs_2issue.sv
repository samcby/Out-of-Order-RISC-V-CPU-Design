module rs_2issue #(
    parameter type T = defines_pkg::alu_rs_t
)(
    input  logic                           wb_valid,
    input  defines_pkg::preg_t             wb_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb_result,
    input  logic                           wb1_valid,
    input  defines_pkg::preg_t             wb1_preg,
    input  logic [defines_pkg::WIDTH-1:0]  wb1_result,

    input  logic flush,
    input  logic squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    pip_if.consumer in_if,
    pip_if.consumer in1_if,
    pip_if.producer out0_if,
    pip_if.producer out1_if
);
    import defines_pkg::*;

    localparam int RS_IDX_W = $clog2(RS_DEPTH);
    localparam int AGE_W    = 32;

    T     entries [0:RS_DEPTH-1];
    logic used    [0:RS_DEPTH-1];
    logic [AGE_W-1:0] age [0:RS_DEPTH-1];
    logic [AGE_W-1:0] next_age_q;

    logic [RS_DEPTH-1:0] free_vec;
    logic [RS_DEPTH-1:0] ready_vec;
    logic free_valid;
    logic free1_valid;
    logic ready0_valid;
    logic ready1_valid;
    logic [RS_IDX_W-1:0] free_idx;
    logic [RS_IDX_W-1:0] free1_idx;
    logic [RS_IDX_W-1:0] issue0_idx;
    logic [RS_IDX_W-1:0] issue1_idx;
    logic [AGE_W-1:0] issue0_age;
    logic [AGE_W-1:0] issue1_age;
    T enqueue_entry0;
    T enqueue_entry1;
    logic push_fire0;
    logic push_fire1;

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

    always_comb begin
        free1_valid = 1'b0;
        free1_idx = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (free_vec[i] && (i[RS_IDX_W-1:0] != free_idx) && !free1_valid) begin
                free1_valid = 1'b1;
                free1_idx = i[RS_IDX_W-1:0];
            end
        end
    end

    always_comb begin
        ready0_valid = 1'b0;
        ready1_valid = 1'b0;
        issue0_idx = '0;
        issue1_idx = '0;
        issue0_age = '0;
        issue1_age = '0;

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (ready_vec[i] && (!ready0_valid || (age[i] < issue0_age))) begin
                ready0_valid = 1'b1;
                issue0_idx = i[RS_IDX_W-1:0];
                issue0_age = age[i];
            end
        end

        for (int i = 0; i < RS_DEPTH; i++) begin
            if (ready_vec[i] &&
                (i[RS_IDX_W-1:0] != issue0_idx) &&
                (!ready1_valid || (age[i] < issue1_age))) begin
                ready1_valid = 1'b1;
                issue1_idx = i[RS_IDX_W-1:0];
                issue1_age = age[i];
            end
        end
    end

    assign out0_if.valid = ready0_valid;
    assign out0_if.data  = ready0_valid ? entries[issue0_idx] : '0;
    assign out1_if.valid = ready1_valid;
    assign out1_if.data  = ready1_valid ? entries[issue1_idx] : '0;
    assign in_if.ready   = free_valid;
    assign in1_if.ready  = free1_valid;
    assign push_fire0 = in_if.valid && in_if.ready;
    assign push_fire1 = in1_if.valid && in1_if.ready;

    always_comb begin
        enqueue_entry0 = in_if.data;
        enqueue_entry1 = in1_if.data;

        if (wb_valid) begin
            if (!enqueue_entry0.src1_ready &&
                enqueue_entry0.datapath.src_reg_1p == wb_preg) begin
                enqueue_entry0.src1_ready = 1'b1;
                enqueue_entry0.datapath.src1_value = wb_result;
            end

            if (!enqueue_entry0.src2_ready &&
                enqueue_entry0.datapath.src_reg_2p == wb_preg) begin
                enqueue_entry0.src2_ready = 1'b1;
                enqueue_entry0.datapath.src2_value = wb_result;
            end

            if (!enqueue_entry1.src1_ready &&
                enqueue_entry1.datapath.src_reg_1p == wb_preg) begin
                enqueue_entry1.src1_ready = 1'b1;
                enqueue_entry1.datapath.src1_value = wb_result;
            end

            if (!enqueue_entry1.src2_ready &&
                enqueue_entry1.datapath.src_reg_2p == wb_preg) begin
                enqueue_entry1.src2_ready = 1'b1;
                enqueue_entry1.datapath.src2_value = wb_result;
            end
        end

        if (wb1_valid) begin
            if (!enqueue_entry0.src1_ready &&
                enqueue_entry0.datapath.src_reg_1p == wb1_preg) begin
                enqueue_entry0.src1_ready = 1'b1;
                enqueue_entry0.datapath.src1_value = wb1_result;
            end

            if (!enqueue_entry0.src2_ready &&
                enqueue_entry0.datapath.src_reg_2p == wb1_preg) begin
                enqueue_entry0.src2_ready = 1'b1;
                enqueue_entry0.datapath.src2_value = wb1_result;
            end

            if (!enqueue_entry1.src1_ready &&
                enqueue_entry1.datapath.src_reg_1p == wb1_preg) begin
                enqueue_entry1.src1_ready = 1'b1;
                enqueue_entry1.datapath.src1_value = wb1_result;
            end

            if (!enqueue_entry1.src2_ready &&
                enqueue_entry1.datapath.src_reg_2p == wb1_preg) begin
                enqueue_entry1.src2_ready = 1'b1;
                enqueue_entry1.datapath.src2_value = wb1_result;
            end
        end
    end

    always_ff @(posedge in_if.clk or negedge in_if.rst_n) begin
        if (!in_if.rst_n || flush) begin
            for (int i = 0; i < RS_DEPTH; i++) begin
                entries[i] <= '0;
                used[i]    <= 1'b0;
                age[i]     <= '0;
            end
            next_age_q <= '0;
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

            if (push_fire0) begin
                entries[free_idx] <= enqueue_entry0;
                used[free_idx]    <= 1'b1;
                age[free_idx]     <= next_age_q;
            end
            if (push_fire1) begin
                entries[free1_idx] <= enqueue_entry1;
                used[free1_idx]    <= 1'b1;
                age[free1_idx]     <= push_fire0 ? (next_age_q + 1) : next_age_q;
            end
            if (push_fire0 && push_fire1) begin
                next_age_q <= next_age_q + 2;
            end else if (push_fire0 || push_fire1) begin
                next_age_q <= next_age_q + 1;
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

            if (wb1_valid) begin
                for (int i = 0; i < RS_DEPTH; i++) begin
                    if (used[i]) begin
                        if (!entries[i].src1_ready &&
                            entries[i].datapath.src_reg_1p == wb1_preg) begin
                            entries[i].src1_ready <= 1'b1;
                            entries[i].datapath.src1_value <= wb1_result;
                        end

                        if (!entries[i].src2_ready &&
                            entries[i].datapath.src_reg_2p == wb1_preg) begin
                            entries[i].src2_ready <= 1'b1;
                            entries[i].datapath.src2_value <= wb1_result;
                        end
                    end
                end
            end

            if (out0_if.valid && out0_if.ready) begin
                used[issue0_idx] <= 1'b0;
            end
            if (out1_if.valid && out1_if.ready) begin
                used[issue1_idx] <= 1'b0;
            end
        end
    end

endmodule
