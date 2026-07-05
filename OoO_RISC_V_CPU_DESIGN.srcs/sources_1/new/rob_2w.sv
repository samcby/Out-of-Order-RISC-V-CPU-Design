module rob_2w (
    pip_if.consumer rob_packet_if,

    input  logic                           complete_en0,
    input  defines_pkg::rob_tag_t          complete_tag0,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result0,
    input  logic [4:0]                     complete_fp_flags0,
    input  logic                           complete_en1,
    input  defines_pkg::rob_tag_t          complete_tag1,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result1,
    input  logic [4:0]                     complete_fp_flags1,
    input  logic                           complete_en2,
    input  defines_pkg::rob_tag_t          complete_tag2,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result2,
    input  logic [4:0]                     complete_fp_flags2,

    input  logic                           commit_en0,
    input  logic                           commit_en1,

    input  logic flush,
    input  logic squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    output defines_pkg::rob_t              head_entry,
    output logic                           head_valid,
    output logic                           head_complete,
    output defines_pkg::rob_t              head1_entry,
    output logic                           head1_valid,
    output logic                           head1_complete,
    output logic                           full,
    output logic                           empty
);
    import defines_pkg::*;

    localparam int ROB_IDX_W = $clog2(ROB_DEPTH);
    localparam int ROB_COUNT_W = $clog2(ROB_DEPTH + 1);
    typedef logic [ROB_IDX_W-1:0] rob_idx_t;
    typedef logic [ROB_COUNT_W-1:0] rob_count_t;

    rob_t entries [0:ROB_DEPTH-1];
    logic valid_bits [0:ROB_DEPTH-1];

    rob_idx_t head_q;
    rob_idx_t tail_q;
    rob_count_t count_q;

    logic lane0_req;
    logic lane1_req;
    logic [1:0] push_req_count;
    logic [1:0] push_fire_count;
    rob_count_t free_slots;
    logic push_fire;
    logic push_fire0;
    logic push_fire1;
    logic pop_fire0;
    logic pop_fire1;
    logic [1:0] pop_fire_count;
    rob_idx_t tail_idx0;
    rob_idx_t tail_idx1;
    rob_idx_t tail_next;
    rob_idx_t head_idx1;
    rob_idx_t head_next;
    rob_idx_t head_after_pop;

    rob_idx_t complete_idx0;
    logic complete_hit0;
    rob_idx_t complete_idx1;
    logic complete_hit1;
    rob_idx_t complete_idx2;
    logic complete_hit2;

    logic [ROB_DEPTH-1:0] survive_vec;
    rob_count_t survive_count;
    rob_idx_t tail_after_squash;

    function automatic logic [4:0] known_flags(input logic [4:0] flags);
    begin
        for (int bit_idx = 0; bit_idx < 5; bit_idx++) begin
            known_flags[bit_idx] = (flags[bit_idx] === 1'b1);
        end
    end
    endfunction

    // Capacity must be computed from the offered packet shape, independent
    // of the valid/ready handshake. Including rob_packet_if.valid here forms
    // a combinational loop through dispatch_ready when only one ROB slot is
    // free and the producer offers a two-lane packet.
    assign lane0_req = rob_packet_if.data.lane0.valid;
    assign lane1_req = rob_packet_if.data.lane1.valid;
    assign push_req_count = {1'b0, lane0_req} + {1'b0, lane1_req};
    assign free_slots = rob_count_t'(ROB_DEPTH) - count_q;

    assign empty = (count_q == '0);
    assign full  = (count_q == rob_count_t'(ROB_DEPTH));
    assign rob_packet_if.ready = (free_slots >= rob_count_t'(push_req_count));

    assign push_fire  = rob_packet_if.valid && rob_packet_if.ready;
    assign push_fire0 = push_fire && rob_packet_if.data.lane0.valid;
    assign push_fire1 = push_fire && rob_packet_if.data.lane1.valid;
    assign push_fire_count = {1'b0, push_fire0} + {1'b0, push_fire1};
    assign head_idx1 = (head_q == ROB_DEPTH-1) ? '0 : (head_q + 1'b1);
    assign pop_fire0 = commit_en0 && head_valid && head_complete;
    assign pop_fire1 = pop_fire0 && commit_en1 && head1_valid && head1_complete;
    assign pop_fire_count = {1'b0, pop_fire0} + {1'b0, pop_fire1};
    assign head_after_pop = pop_fire0 ? head_next : head_q;

    always_comb begin
        int next_head_idx;

        next_head_idx = head_q + pop_fire_count;
        if (next_head_idx >= ROB_DEPTH) begin
            next_head_idx = next_head_idx - ROB_DEPTH;
        end
        head_next = next_head_idx[ROB_IDX_W-1:0];
    end

    always_comb begin
        head_valid    = !empty;
        head_entry    = '0;
        head_complete = 1'b0;
        head1_valid    = (count_q >= rob_count_t'(2));
        head1_entry    = '0;
        head1_complete = 1'b0;

        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (!empty && (head_q == i[ROB_IDX_W-1:0])) begin
                head_entry    = entries[i];
                head_complete = entries[i].datapath.complete;
            end
            if (head1_valid && (head_idx1 == i[ROB_IDX_W-1:0])) begin
                head1_entry    = entries[i];
                head1_complete = entries[i].datapath.complete;
            end
        end
    end

    always_comb begin
        int idx0;
        int idx1;
        int next_idx;

        idx0 = tail_q;
        idx1 = tail_q + (push_fire0 ? 1 : 0);
        if (idx1 >= ROB_DEPTH) begin
            idx1 = idx1 - ROB_DEPTH;
        end

        next_idx = tail_q + push_fire_count;
        if (next_idx >= ROB_DEPTH) begin
            next_idx = next_idx - ROB_DEPTH;
        end

        tail_idx0 = idx0[ROB_IDX_W-1:0];
        tail_idx1 = idx1[ROB_IDX_W-1:0];
        tail_next = next_idx[ROB_IDX_W-1:0];
    end

    always_comb begin
        complete_hit0 = 1'b0;
        complete_idx0 = '0;
        complete_hit1 = 1'b0;
        complete_idx1 = '0;
        complete_hit2 = 1'b0;
        complete_idx2 = '0;
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (valid_bits[i] && entries[i].datapath.rob_tag == complete_tag0) begin
                complete_hit0 = 1'b1;
                complete_idx0 = i[ROB_IDX_W-1:0];
            end
            if (valid_bits[i] && entries[i].datapath.rob_tag == complete_tag1) begin
                complete_hit1 = 1'b1;
                complete_idx1 = i[ROB_IDX_W-1:0];
            end
            if (valid_bits[i] && entries[i].datapath.rob_tag == complete_tag2) begin
                complete_hit2 = 1'b1;
                complete_idx2 = i[ROB_IDX_W-1:0];
            end
        end
    end

    always_comb begin
        survive_count = '0;
        tail_after_squash = head_after_pop;

        for (int i = 0; i < ROB_DEPTH; i++) begin
            survive_vec[i] = valid_bits[i] &&
                             !(pop_fire0 && (head_q == i[ROB_IDX_W-1:0])) &&
                             !(pop_fire1 && (head_idx1 == i[ROB_IDX_W-1:0])) &&
                             !(squash_en &&
                               entries[i].datapath.speculation_mask[squash_checkpoint_id]);
            if (survive_vec[i]) begin
                survive_count = survive_count + 1'b1;
            end
        end

        if (survive_count == 0) begin
            tail_after_squash = head_after_pop;
        end else begin
            tail_after_squash = head_after_pop;
            for (int step = 0; step < ROB_DEPTH; step++) begin
                int idx;
                idx = (head_after_pop + step) % ROB_DEPTH;
                if (survive_vec[idx]) begin
                    tail_after_squash = (idx == ROB_DEPTH-1) ? '0 : (idx + 1'b1);
                end
            end
        end
    end

    always_ff @(posedge rob_packet_if.clk or negedge rob_packet_if.rst_n) begin
        if (!rob_packet_if.rst_n || flush) begin
            head_q <= '0;
            tail_q <= '0;
            count_q <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entries[i] <= '0;
                valid_bits[i] <= 1'b0;
            end
        end else begin
            if (push_fire0) begin
                entries[tail_idx0] <= rob_packet_if.data.lane0.data.rob_entry;
                valid_bits[tail_idx0] <= 1'b1;
            end
            if (push_fire1) begin
                entries[tail_idx1] <= rob_packet_if.data.lane1.data.rob_entry;
                valid_bits[tail_idx1] <= 1'b1;
            end
            if (push_fire) begin
                tail_q <= tail_next;
            end

            if (complete_en0 && complete_hit0) begin
                entries[complete_idx0].datapath.complete <= 1'b1;
                entries[complete_idx0].datapath.result <= complete_result0;
                entries[complete_idx0].datapath.fp_flags <=
                    known_flags(complete_fp_flags0);
            end
            if (complete_en1 && complete_hit1) begin
                entries[complete_idx1].datapath.complete <= 1'b1;
                entries[complete_idx1].datapath.result <= complete_result1;
                entries[complete_idx1].datapath.fp_flags <=
                    known_flags(complete_fp_flags1);
            end
            if (complete_en2 && complete_hit2) begin
                entries[complete_idx2].datapath.complete <= 1'b1;
                entries[complete_idx2].datapath.result <= complete_result2;
                entries[complete_idx2].datapath.fp_flags <=
                    known_flags(complete_fp_flags2);
            end

            if (resolve_en) begin
                for (int i = 0; i < ROB_DEPTH; i++) begin
                    if (valid_bits[i]) begin
                        entries[i].datapath.speculation_mask[resolve_checkpoint_id] <= 1'b0;
                    end
                end
            end

            if (squash_en) begin
                for (int i = 0; i < ROB_DEPTH; i++) begin
                    valid_bits[i] <= survive_vec[i];
                end
                head_q <= head_after_pop;
                tail_q <= tail_after_squash;
                count_q <= survive_count;
            end else begin
                if (pop_fire0) begin
                    valid_bits[head_q] <= 1'b0;
                    if (pop_fire1) begin
                        valid_bits[head_idx1] <= 1'b0;
                    end
                    head_q <= head_next;
                end

                count_q <= count_q + rob_count_t'(push_fire_count) -
                           rob_count_t'(pop_fire_count);
            end
        end
    end

`ifndef SYNTHESIS
    integer assert_valid_count;

    always_comb begin
        assert_valid_count = 0;
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (valid_bits[i] === 1'b1) begin
                assert_valid_count = assert_valid_count + 1;
            end
        end
    end

    always_ff @(posedge rob_packet_if.clk) begin
        if ((rob_packet_if.rst_n === 1'b1) && !flush) begin
            assert ($unsigned(count_q) <= ROB_DEPTH)
                else $error("[ASSERT:ROB] count exceeds ROB_DEPTH");
            assert (assert_valid_count == count_q)
                else $error("[ASSERT:ROB] valid-bit count disagrees with count_q");
            assert (!head_valid || valid_bits[head_q])
                else $error("[ASSERT:ROB] non-empty ROB head is invalid");
            assert (!head1_valid || valid_bits[head_idx1])
                else $error("[ASSERT:ROB] second ROB head is invalid");
            assert (!commit_en0 || (head_valid && head_complete))
                else $error("[ASSERT:ROB] lane0 commit requested for incomplete head");
            assert (!commit_en1 ||
                    (commit_en0 && head1_valid && head1_complete))
                else $error("[ASSERT:ROB] lane1 commit violates in-order retirement");
            assert (push_fire_count <= free_slots)
                else $error("[ASSERT:ROB] accepted packet exceeds free slots");
            assert (!(push_fire0 && push_fire1) ||
                    (rob_packet_if.data.lane0.data.rob_entry.datapath.rob_tag !=
                     rob_packet_if.data.lane1.data.rob_entry.datapath.rob_tag))
                else $error("[ASSERT:ROB] packet lanes reuse one ROB tag");
        end
    end
`endif

endmodule
