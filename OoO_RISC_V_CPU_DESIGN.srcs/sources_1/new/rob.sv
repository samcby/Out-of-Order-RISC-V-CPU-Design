module rob (
    pip_if.consumer rob_if_in,

    input  logic                           complete_en0,
    input  defines_pkg::rob_tag_t          complete_tag0,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result0,
    input  logic                           complete_en1,
    input  defines_pkg::rob_tag_t          complete_tag1,
    input  logic [defines_pkg::WIDTH-1:0]  complete_result1,

    input  logic                           commit_en,

    input  logic flush,
    input  logic squash_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] squash_checkpoint_id,
    input  logic resolve_en,
    input  logic [defines_pkg::CHECKPOINT_W-1:0] resolve_checkpoint_id,

    output defines_pkg::rob_t              head_entry,
    output logic                           head_valid,
    output logic                           head_complete,
    output logic                           full,
    output logic                           empty
);
    import defines_pkg::*;

    rob_t  entries [0:ROB_DEPTH-1];
    logic  valid_bits [0:ROB_DEPTH-1];

    logic [$clog2(ROB_DEPTH)-1:0] head_q, tail_q;
    logic [$clog2(ROB_DEPTH+1)-1:0] count_q;

    logic [$clog2(ROB_DEPTH)-1:0] complete_idx0;
    logic                         complete_hit0;
    logic [$clog2(ROB_DEPTH)-1:0] complete_idx1;
    logic                         complete_hit1;

    logic push_fire;
    logic pop_fire;
    logic [ROB_DEPTH-1:0] survive_vec;
    logic [$clog2(ROB_DEPTH+1)-1:0] survive_count;
    logic [$clog2(ROB_DEPTH)-1:0] tail_after_squash;

    assign empty = (count_q == 0);
    assign full  = (count_q == ROB_DEPTH);

    assign rob_if_in.ready = !full;

    assign head_valid    = !empty;
    assign head_entry    = !empty ? entries[head_q] : '0;
    assign head_complete = !empty ? entries[head_q].datapath.complete : 1'b0;

    assign push_fire = rob_if_in.valid && rob_if_in.ready;
    assign pop_fire  = commit_en && head_valid && head_complete;

    always_comb begin
        complete_hit0 = 1'b0;
        complete_idx0 = '0;
        complete_hit1 = 1'b0;
        complete_idx1 = '0;
        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (valid_bits[i] && entries[i].datapath.rob_tag == complete_tag0) begin
                complete_hit0 = 1'b1;
                complete_idx0 = i[$clog2(ROB_DEPTH)-1:0];
            end
            if (valid_bits[i] && entries[i].datapath.rob_tag == complete_tag1) begin
                complete_hit1 = 1'b1;
                complete_idx1 = i[$clog2(ROB_DEPTH)-1:0];
            end
        end
    end

    always_comb begin
        survive_count = '0;
        tail_after_squash = head_q;

        for (int i = 0; i < ROB_DEPTH; i++) begin
            survive_vec[i] = valid_bits[i] &&
                             !(squash_en &&
                               entries[i].datapath.speculation_mask[squash_checkpoint_id]);
            if (survive_vec[i]) begin
                survive_count = survive_count + 1'b1;
            end
        end

        if (survive_count == 0) begin
            tail_after_squash = head_q;
        end else begin
            tail_after_squash = head_q;
            for (int step = 0; step < ROB_DEPTH; step++) begin
                int idx;
                idx = (head_q + step) % ROB_DEPTH;
                if (survive_vec[idx]) begin
                    tail_after_squash = (idx == ROB_DEPTH-1) ? '0 : (idx + 1'b1);
                end
            end
        end
    end

    always_ff @(posedge rob_if_in.clk or negedge rob_if_in.rst_n) begin
        if (!rob_if_in.rst_n || flush) begin
            head_q  <= '0;
            tail_q  <= '0;
            count_q <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                entries[i]    <= '0;
                valid_bits[i] <= 1'b0;
            end
        end else begin
            if (push_fire) begin
                entries[tail_q] <= rob_if_in.data;
                valid_bits[tail_q] <= 1'b1;
                tail_q <= (tail_q == ROB_DEPTH-1) ? '0 : (tail_q + 1'b1);
            end

            if (complete_en0 && complete_hit0) begin
                entries[complete_idx0].datapath.complete <= 1'b1;
                entries[complete_idx0].datapath.result   <= complete_result0;
            end

            if (complete_en1 && complete_hit1) begin
                entries[complete_idx1].datapath.complete <= 1'b1;
                entries[complete_idx1].datapath.result   <= complete_result1;
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
                tail_q  <= tail_after_squash;
                count_q <= survive_count;
            end else begin
                if (pop_fire) begin
                    valid_bits[head_q] <= 1'b0;
                    head_q <= (head_q == ROB_DEPTH-1) ? '0 : (head_q + 1'b1);
                end

                case ({push_fire, pop_fire})
                    2'b10: count_q <= count_q + 1'b1;
                    2'b01: count_q <= count_q - 1'b1;
                    default: count_q <= count_q;
                endcase
            end
        end
    end

endmodule
