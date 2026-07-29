// Two-wide integer physical-register allocator with checkpoint recovery.
//
// The free bitmap covers physical registers not currently owned by an active
// architectural/speculative mapping. Up to two lowest-index registers are
// proposed combinationally and removed atomically only when pop_commit fires.
// Up to two old mappings may be returned by retirement in the same cycle.
//
// Branch checkpoints snapshot the allocation state. A misprediction restores
// the selected snapshot while preserving architecturally retired reclamations,
// preventing wrong-path allocations from leaking physical registers. Integer
// p0 and the initial x0-x31 mappings are never offered as new allocations.
module free_pool_2w (
    input  logic clk,
    input  logic rst_n,

    input  logic [1:0] push,
    input  logic [1:0] pop,
    input  logic       pop_commit,
    input  defines_pkg::preg_t push_data0,
    input  defines_pkg::preg_t push_data1,
    input  logic [defines_pkg::PREG_NUM-1:0] mapped_bitmap,
    output defines_pkg::preg_t pop_data0,
    output defines_pkg::preg_t pop_data1,
    output logic pop_valid0,
    output logic pop_valid1,

    input  logic checkpoint_save,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] checkpoint_id_save,
    input  logic restore_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] restore_checkpoint_id,

    output logic full,
    output logic empty,
    output logic has_free_1,
    output logic has_free_2
);
    import defines_pkg::*;

    localparam int FREE_DEPTH = PREG_NUM - AREG_NUM;

    logic [PREG_NUM-1:0] free_bitmap_q;
    logic [PREG_NUM-1:0] free_bitmap_n;
    logic [PREG_NUM-1:0] alloc_bitmap;
    logic [PREG_NUM-1:0] checkpoints [0:CHECKPOINT_NUM-1];
    logic [PREG_NUM-1:0] search_bitmap;
    logic [PREG_NUM-1:0] checkpoint_bitmap;
    logic [FREE_DEPTH-1:0] free_candidates;
    logic [$clog2(FREE_DEPTH+1)-1:0] free_count;

    genvar g;
    generate
        for (g = 0; g < FREE_DEPTH; g++) begin : GEN_FREE_CANDIDATES
            assign free_candidates[g] = alloc_bitmap[AREG_NUM + g];
        end
    endgenerate

    always_comb begin
        alloc_bitmap = free_bitmap_q;
        for (int i = 0; i < PREG_NUM; i++) begin
            if (mapped_bitmap[i] === 1'b1) begin
                alloc_bitmap[i] = 1'b0;
            end
        end
        // A register retired on this edge becomes allocatable next cycle.
        // Excluding it here also prevents a stale checkpoint bit from making
        // the same physical register both allocated and freed on one edge.
        if (push[0] && (push_data0 != '0)) begin
            alloc_bitmap[push_data0] = 1'b0;
        end
        if (push[1] && (push_data1 != '0)) begin
            alloc_bitmap[push_data1] = 1'b0;
        end
    end

    always_comb begin
        free_count = '0;
        for (int i = 0; i < FREE_DEPTH; i++) begin
            if (free_candidates[i]) begin
                free_count = free_count + 1'b1;
            end
        end
    end

    assign empty      = (free_count == '0);
    assign full       = &free_candidates;
    assign has_free_1 = (free_count >= 1);
    assign has_free_2 = (free_count >= 2);

    always_comb begin
        pop_data0     = '0;
        pop_data1     = '0;
        pop_valid0    = 1'b0;
        pop_valid1    = 1'b0;
        search_bitmap = alloc_bitmap;

        if (pop[0]) begin
            for (int i = AREG_NUM; i < PREG_NUM; i++) begin
                if (!pop_valid0 && search_bitmap[i]) begin
                    pop_valid0    = 1'b1;
                    pop_data0     = preg_t'(i);
                    search_bitmap[i] = 1'b0;
                end
            end
        end

        if (pop[1]) begin
            for (int i = AREG_NUM; i < PREG_NUM; i++) begin
                if (!pop_valid1 && search_bitmap[i]) begin
                    pop_valid1    = 1'b1;
                    pop_data1     = preg_t'(i);
                    search_bitmap[i] = 1'b0;
                end
            end
        end

        free_bitmap_n = free_bitmap_q;

        if (pop_commit && pop[0] && pop_valid0) begin
            free_bitmap_n[pop_data0] = 1'b0;
        end
        if (pop_commit && pop[1] && pop_valid1) begin
            free_bitmap_n[pop_data1] = 1'b0;
        end

        if (push[0] && (push_data0 != '0)) begin
            free_bitmap_n[push_data0] = 1'b1;
        end
        if (push[1] && (push_data1 != '0)) begin
            free_bitmap_n[push_data1] = 1'b1;
        end

        for (int i = 0; i < PREG_NUM; i++) begin
            if (mapped_bitmap[i] === 1'b1) begin
                free_bitmap_n[i] = 1'b0;
            end
        end

        checkpoint_bitmap = free_bitmap_n;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PREG_NUM; i++) begin
                free_bitmap_q[i] <= (i >= AREG_NUM);
            end

            for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                for (int i = 0; i < PREG_NUM; i++) begin
                    checkpoints[cp][i] <= (i >= AREG_NUM);
                end
            end
        end else begin
            if (restore_en) begin
                free_bitmap_q <= checkpoints[restore_checkpoint_id];
                if (push[0] && (push_data0 != '0)) begin
                    free_bitmap_q[push_data0] <= 1'b1;
                end
                if (push[1] && (push_data1 != '0)) begin
                    free_bitmap_q[push_data1] <= 1'b1;
                end
                for (int i = 0; i < PREG_NUM; i++) begin
                    if (mapped_bitmap[i] === 1'b1) begin
                        free_bitmap_q[i] <= 1'b0;
                    end
                end
            end else begin
                free_bitmap_q <= free_bitmap_n;
            end

            if (push[0] && (push_data0 != '0)) begin
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][push_data0] <= 1'b1;
                end
            end
            if (push[1] && (push_data1 != '0)) begin
                for (int cp = 0; cp < CHECKPOINT_NUM; cp++) begin
                    checkpoints[cp][push_data1] <= 1'b1;
                end
            end

            if (checkpoint_save) begin
                checkpoints[checkpoint_id_save] <= checkpoint_bitmap;
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n === 1'b1) begin
            assert (free_count <= FREE_DEPTH)
                else $error("[ASSERT:FREE_POOL] free count exceeds pool depth");
            assert (!pop_valid0 || pop[0])
                else $error("[ASSERT:FREE_POOL] lane0 allocation without request");
            assert (!pop_valid1 || pop[1])
                else $error("[ASSERT:FREE_POOL] lane1 allocation without request");
            assert (!pop_valid0 || ($unsigned(pop_data0) >= AREG_NUM))
                else $error("[ASSERT:FREE_POOL] lane0 returned architectural preg");
            assert (!pop_valid1 || ($unsigned(pop_data1) >= AREG_NUM))
                else $error("[ASSERT:FREE_POOL] lane1 returned architectural preg");
            assert (!(pop_valid0 && pop_valid1) || (pop_data0 != pop_data1))
                else $error("[ASSERT:FREE_POOL] dual allocation returned duplicate preg");
            assert (!(pop_commit && pop[0]) || pop_valid0)
                else $error("[ASSERT:FREE_POOL] committed invalid lane0 allocation");
            assert (!(pop_commit && pop[1]) || pop_valid1)
                else $error("[ASSERT:FREE_POOL] committed invalid lane1 allocation");
            assert ((alloc_bitmap & mapped_bitmap) == '0)
                else $error("[ASSERT:FREE_POOL] mapped preg is allocatable");
            if (!restore_en) begin
                assert ((free_bitmap_q & mapped_bitmap) == '0)
                    else $error("[ASSERT:FREE_POOL] mapped preg is marked free");
            end
        end
    end
`endif

endmodule
