module free_pool (
    input  logic clk,
    input  logic rst_n,

    input  logic push,
    input  logic pop,
    input  defines_pkg::preg_t push_data,
    output defines_pkg::preg_t pop_data,

    input  logic checkpoint_save,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] checkpoint_id_save,
    input  logic restore_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] restore_checkpoint_id,

    output logic full,
    output logic empty
);
    import defines_pkg::*;

    localparam int FREE_DEPTH = PREG_NUM - AREG_NUM;

    logic [PREG_NUM-1:0] free_bitmap_q;
    logic [PREG_NUM-1:0] free_bitmap_n;
    logic [PREG_NUM-1:0] checkpoints [0:defines_pkg::CHECKPOINT_NUM-1];

    logic [FREE_DEPTH-1:0] free_candidates;
    logic                  alloc_valid;
    logic [$clog2(FREE_DEPTH)-1:0] alloc_idx;
    preg_t                 alloc_preg;
    logic [PREG_NUM-1:0]   checkpoint_bitmap;

    genvar g;
    generate
        for (g = 0; g < FREE_DEPTH; g++) begin : GEN_FREE_CANDIDATES
            assign free_candidates[g] = free_bitmap_q[AREG_NUM + g];
        end
    endgenerate

    priority_decoder #(
        .WIDTH(FREE_DEPTH)
    ) u_alloc_dec (
        .in   (free_candidates),
        .valid(alloc_valid),
        .idx  (alloc_idx)
    );

    assign alloc_preg = preg_t'(AREG_NUM + alloc_idx);
    assign pop_data   = alloc_preg;

    assign empty = !alloc_valid;
    assign full  = &free_candidates;

    always_comb begin
        free_bitmap_n = free_bitmap_q;

        if (pop && alloc_valid) begin
            free_bitmap_n[alloc_preg] = 1'b0;
        end

        if (push && (push_data != '0)) begin
            free_bitmap_n[push_data] = 1'b1;
        end

        checkpoint_bitmap = free_bitmap_n;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PREG_NUM; i++) begin
                free_bitmap_q[i] <= (i >= AREG_NUM);
            end

            for (int cp = 0; cp < defines_pkg::CHECKPOINT_NUM; cp++) begin
                for (int i = 0; i < PREG_NUM; i++) begin
                    checkpoints[cp][i] <= (i >= AREG_NUM);
                end
            end
        end else begin
            if (restore_en) begin
                free_bitmap_q <= checkpoints[restore_checkpoint_id];
                if (push && (push_data != '0)) begin
                    free_bitmap_q[push_data] <= 1'b1;
                end
            end else begin
                free_bitmap_q <= free_bitmap_n;
            end

            if (push && (push_data != '0)) begin
                for (int cp = 0; cp < defines_pkg::CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][push_data] <= 1'b1;
                end
            end

            if (checkpoint_save) begin
                checkpoints[checkpoint_id_save] <= checkpoint_bitmap;
            end
        end
    end

endmodule
