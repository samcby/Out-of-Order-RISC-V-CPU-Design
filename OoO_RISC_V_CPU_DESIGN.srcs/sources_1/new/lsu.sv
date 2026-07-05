module lsu #(
    parameter int MEM_WORDS = 256,
    parameter int DATA_CACHE_LINES = 8,
    parameter int DATA_CACHE_WAYS = 2,
    parameter int DATA_CACHE_WORDS_PER_LINE = 4,
    parameter int DATA_MEM_RESPONSE_LATENCY = 2
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           req_valid,
    output logic                           req_ready,
    input  logic                           squash_en,
    input  defines_pkg::cp_id_t            squash_checkpoint_id,
    input  logic                           resolve_en,
    input  defines_pkg::cp_id_t            resolve_checkpoint_id,
    input  logic                           commit_store_valid0,
    input  defines_pkg::rob_tag_t          commit_store_tag0,
    input  logic                           commit_store_valid1,
    input  defines_pkg::rob_tag_t          commit_store_tag1,
    input  defines_pkg::lsu_control_t      control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    output logic                           resp_valid,
    output defines_pkg::rob_tag_t          resp_tag,
    output defines_pkg::preg_t             resp_preg,
    output logic                           resp_reg_write,
    output logic                           resp_dest_is_fp,
    output logic [defines_pkg::WIDTH-1:0]  resp_result
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);
    localparam int STORE_BUF_DEPTH = 8;
    localparam int STORE_BUF_IDX_W = $clog2(STORE_BUF_DEPTH);
    localparam int STORE_BUF_AGE_W = 16;
    localparam int COMMIT_REPLAY_DEPTH = 4;
    localparam int COMMIT_REPLAY_IDX_W = $clog2(COMMIT_REPLAY_DEPTH);
    localparam int COMMIT_REPLAY_AGE_W = 4;
    localparam int COMMIT_TAG_COUNT = (1 << ROB_TAG_W);

    logic             pending_valid;
    logic             pending_mem_req_sent;
    lsu_control_t     pending_control;
    rs_datapath_t     pending_datapath;
    logic [WIDTH-1:0] eff_addr;
    logic [ADDR_W-1:0] word_addr;
    logic [1:0] byte_off;
    logic [WIDTH-1:0] curr_word;
    logic [7:0] load_byte;
    logic [15:0] load_half;
    logic [WIDTH-1:0] load_result_comb;
    logic [WIDTH-1:0] req_eff_addr;
    logic [WIDTH-1:0] pending_eff_addr;
    logic [1:0]       pending_byte_off;
    logic [3:0]       pending_load_byte_mask;
    logic [STORE_BUF_DEPTH-1:0] load_dep_mask_comb;
    logic [3:0]       pending_forward_coverage;
    logic [WIDTH-1:0] pending_forward_word;
    logic             pending_forward_valid;
    logic             pending_forward_byte_valid [0:3];
    logic [STORE_BUF_AGE_W-1:0] pending_forward_byte_age [0:3];
    logic [3:0] store_wmask;
    logic [WIDTH-1:0] store_wdata;
    logic             pending_squashed;
    cp_mask_t         pending_spec_mask_next;
    logic             store_buf_valid [0:STORE_BUF_DEPTH-1];
    logic             store_buf_committed [0:STORE_BUF_DEPTH-1];
    logic             store_buf_mem_req_sent [0:STORE_BUF_DEPTH-1];
    logic [STORE_BUF_AGE_W-1:0] store_buf_age [0:STORE_BUF_DEPTH-1];
    lsu_control_t     store_buf_control [0:STORE_BUF_DEPTH-1];
    rs_datapath_t     store_buf_datapath [0:STORE_BUF_DEPTH-1];
    logic [STORE_BUF_AGE_W-1:0] store_age_q;
    logic             store_buf_full;
    logic             store_buf_any_valid;
    logic [STORE_BUF_DEPTH-1:0] store_buf_valid_mask;
    logic [STORE_BUF_DEPTH-1:0] pending_store_dep_mask;
    logic             pending_store_blocking;
    logic             store_drain_valid;
    logic             store_drain_wait_q;
    logic [STORE_BUF_IDX_W-1:0] store_drain_idx;
    logic [STORE_BUF_IDX_W-1:0] store_alloc_idx;
    logic             store_alloc_valid;
    logic             store_alloc_commit_match;
    logic             store_commit_match [0:STORE_BUF_DEPTH-1];
    logic             store_commit_hit0;
    logic             store_commit_hit1;
    logic             store_buf_squashed [0:STORE_BUF_DEPTH-1];
    cp_mask_t         store_buf_spec_mask_next [0:STORE_BUF_DEPTH-1];
    logic             commit_replay_valid [0:COMMIT_REPLAY_DEPTH-1];
    rob_tag_t         commit_replay_tag [0:COMMIT_REPLAY_DEPTH-1];
    logic [COMMIT_REPLAY_AGE_W-1:0] commit_replay_age [0:COMMIT_REPLAY_DEPTH-1];
    logic [COMMIT_REPLAY_IDX_W-1:0] commit_replay_ptr_q;
    logic [COMMIT_REPLAY_IDX_W-1:0] commit_replay_idx1;
    logic             commit_replay_hit;
    logic             commit_seen_valid [0:COMMIT_TAG_COUNT-1];
    logic             commit_seen_hit;
    lsu_control_t     active_control;
    rs_datapath_t     active_datapath;
    logic [WIDTH-1:0] active_eff_addr;
    logic             mem_req_valid;
    logic             mem_req_ready;
    logic             mem_resp_valid;
    logic [WIDTH-1:0] mem_resp_rdata;
    logic [WIDTH-1:0] store_buf_eff_addr [0:STORE_BUF_DEPTH-1];
    logic [3:0]       store_buf_byte_mask [0:STORE_BUF_DEPTH-1];
    logic [WIDTH-1:0] store_buf_aligned_data [0:STORE_BUF_DEPTH-1];

    function automatic logic [3:0] access_byte_mask(
        input logic [2:0] funct3,
        input logic [1:0] offset
    );
        begin
            access_byte_mask = 4'b0000;
            unique case (funct3)
                3'b000, 3'b100: access_byte_mask = 4'b0001 << offset;
                3'b001, 3'b101: begin
                    unique case (offset)
                        2'd0: access_byte_mask = 4'b0011;
                        2'd1: access_byte_mask = 4'b0110;
                        2'd2: access_byte_mask = 4'b1100;
                        default: access_byte_mask = 4'b0000;
                    endcase
                end
                3'b010: access_byte_mask = 4'b1111;
                default: access_byte_mask = 4'b0000;
            endcase
        end
    endfunction

    function automatic logic [WIDTH-1:0] align_store_data(
        input logic [2:0] funct3,
        input logic [1:0] offset,
        input logic [WIDTH-1:0] data
    );
        begin
            align_store_data = '0;
            unique case (funct3)
                3'b000: align_store_data = {24'b0, data[7:0]} << (offset * 8);
                3'b001: align_store_data = {16'b0, data[15:0]} << (offset * 8);
                3'b010: align_store_data = data;
                default: align_store_data = '0;
            endcase
        end
    endfunction

    generate
        for (genvar store_idx = 0; store_idx < STORE_BUF_DEPTH; store_idx++) begin : gen_store_metadata
            assign store_buf_eff_addr[store_idx] =
                store_buf_datapath[store_idx].src1_value +
                store_buf_datapath[store_idx].imm;
            assign store_buf_byte_mask[store_idx] =
                access_byte_mask(store_buf_control[store_idx].funct3,
                                 store_buf_eff_addr[store_idx][1:0]);
            assign store_buf_aligned_data[store_idx] =
                align_store_data(store_buf_control[store_idx].funct3,
                                 store_buf_eff_addr[store_idx][1:0],
                                 store_buf_datapath[store_idx].src2_value);
        end
    endgenerate

    assign pending_spec_mask_next =
        resolve_en ? (pending_datapath.speculation_mask & ~(cp_mask_t'(1'b1) << resolve_checkpoint_id)) :
                     pending_datapath.speculation_mask;
    assign pending_squashed =
        squash_en && pending_datapath.speculation_mask[squash_checkpoint_id];

    always_comb begin
        store_buf_full = 1'b1;
        store_buf_any_valid = 1'b0;
        store_buf_valid_mask = '0;
        store_alloc_valid = 1'b0;
        store_alloc_idx = '0;
        store_drain_valid = 1'b0;
        store_drain_idx = '0;
        store_commit_hit0 = 1'b0;
        store_commit_hit1 = 1'b0;
        commit_replay_hit = 1'b0;
        commit_seen_hit = commit_seen_valid[datapath.rob_tag];

        for (int i = 0; i < COMMIT_REPLAY_DEPTH; i++) begin
            if (commit_replay_valid[i] && (commit_replay_tag[i] == datapath.rob_tag)) begin
                commit_replay_hit = 1'b1;
            end
        end

        for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
            store_buf_spec_mask_next[i] =
                resolve_en ? (store_buf_datapath[i].speculation_mask &
                              ~(cp_mask_t'(1'b1) << resolve_checkpoint_id)) :
                             store_buf_datapath[i].speculation_mask;
            store_buf_squashed[i] =
                store_buf_valid[i] &&
                !store_buf_committed[i] &&
                squash_en &&
                store_buf_datapath[i].speculation_mask[squash_checkpoint_id];
            store_commit_match[i] =
                store_buf_valid[i] &&
                !store_buf_committed[i] &&
                (commit_seen_valid[store_buf_datapath[i].rob_tag] ||
                 (commit_store_valid0 &&
                  (commit_store_tag0 == store_buf_datapath[i].rob_tag)) ||
                 (commit_store_valid1 &&
                  (commit_store_tag1 == store_buf_datapath[i].rob_tag)));
            if (store_buf_valid[i] &&
                !store_buf_committed[i] &&
                commit_store_valid0 &&
                (commit_store_tag0 == store_buf_datapath[i].rob_tag)) begin
                store_commit_hit0 = 1'b1;
            end
            if (store_buf_valid[i] &&
                !store_buf_committed[i] &&
                commit_store_valid1 &&
                (commit_store_tag1 == store_buf_datapath[i].rob_tag)) begin
                store_commit_hit1 = 1'b1;
            end

            if (store_buf_valid[i]) begin
                store_buf_any_valid = 1'b1;
                if (!store_buf_squashed[i]) begin
                    store_buf_valid_mask[i] = 1'b1;
                end
            end else begin
                store_buf_full = 1'b0;
                if (!store_alloc_valid) begin
                    store_alloc_valid = 1'b1;
                    store_alloc_idx = i[STORE_BUF_IDX_W-1:0];
                end
            end

            if (store_buf_valid[i] && store_buf_committed[i]) begin
                if (!store_drain_valid ||
                    (store_buf_age[i] < store_buf_age[store_drain_idx])) begin
                    store_drain_valid = 1'b1;
                    store_drain_idx = i[STORE_BUF_IDX_W-1:0];
                end
            end
        end
    end

    assign req_eff_addr = datapath.src1_value + datapath.imm;
    assign pending_eff_addr = pending_datapath.src1_value + pending_datapath.imm;
    assign pending_byte_off = pending_eff_addr[1:0];
    assign pending_load_byte_mask =
        access_byte_mask(pending_control.funct3, pending_byte_off);

    always_comb begin
        load_dep_mask_comb = '0;
        for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
            if (store_buf_valid_mask[i] &&
                (store_buf_eff_addr[i][WIDTH-1:2] == req_eff_addr[WIDTH-1:2]) &&
                (|(store_buf_byte_mask[i] &
                   access_byte_mask(control_signal.funct3, req_eff_addr[1:0])))) begin
                load_dep_mask_comb[i] = 1'b1;
            end
        end
    end

    always_comb begin
        pending_forward_coverage = '0;
        pending_forward_word = '0;
        for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
            pending_forward_byte_valid[byte_idx] = 1'b0;
            pending_forward_byte_age[byte_idx] = '0;
        end

        for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
            if (pending_store_dep_mask[i] &&
                store_buf_valid_mask[i] &&
                (store_buf_eff_addr[i][WIDTH-1:2] == pending_eff_addr[WIDTH-1:2])) begin
                for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
                    if (pending_load_byte_mask[byte_idx] &&
                        store_buf_byte_mask[i][byte_idx] &&
                        (!pending_forward_byte_valid[byte_idx] ||
                         (store_buf_age[i] > pending_forward_byte_age[byte_idx]))) begin
                        pending_forward_byte_valid[byte_idx] = 1'b1;
                        pending_forward_byte_age[byte_idx] = store_buf_age[i];
                        pending_forward_word[byte_idx*8 +: 8] =
                            store_buf_aligned_data[i][byte_idx*8 +: 8];
                    end
                end
            end
        end

        for (int byte_idx = 0; byte_idx < 4; byte_idx++) begin
            pending_forward_coverage[byte_idx] =
                pending_forward_byte_valid[byte_idx];
        end
    end

    assign pending_forward_valid =
        pending_valid &&
        pending_control.mem_read &&
        (pending_load_byte_mask != 4'b0000) &&
        ((pending_forward_coverage & pending_load_byte_mask) ==
         pending_load_byte_mask);
    assign pending_store_blocking =
        |(pending_store_dep_mask & store_buf_valid_mask) &&
        !pending_forward_valid;
    assign commit_replay_idx1 =
        commit_replay_ptr_q + (commit_store_valid0 && !store_commit_hit0 ? 1'b1 : 1'b0);
    assign store_alloc_commit_match =
        req_valid &&
        req_ready &&
        control_signal.mem_write &&
        (((commit_store_valid0 && (commit_store_tag0 == datapath.rob_tag)) ||
          (commit_store_valid1 && (commit_store_tag1 == datapath.rob_tag))) ||
         commit_replay_hit ||
         commit_seen_hit);

    assign active_control = store_drain_valid ? store_buf_control[store_drain_idx] : pending_control;
    assign active_datapath = store_drain_valid ? store_buf_datapath[store_drain_idx] : pending_datapath;
    assign active_eff_addr = active_datapath.src1_value + active_datapath.imm;
    assign eff_addr  = active_eff_addr;
    assign word_addr = active_eff_addr[ADDR_W+1:2];
    assign byte_off  = active_eff_addr[1:0];
    assign req_ready = control_signal.mem_write ?
                       (!pending_valid && !resp_valid && store_alloc_valid) :
                       (!pending_valid && !resp_valid);
    assign mem_req_valid =
        !mem_resp_valid &&
        ((pending_valid && !pending_store_blocking &&
         !pending_forward_valid &&
         !store_drain_wait_q &&
         !pending_squashed && !pending_mem_req_sent) ||
        (store_drain_valid &&
         !store_buf_squashed[store_drain_idx] &&
         !store_buf_mem_req_sent[store_drain_idx]));
    assign curr_word = pending_forward_valid ? pending_forward_word : mem_resp_rdata;

    data_cache #(
        .MEM_WORDS(MEM_WORDS),
        .LINE_COUNT(DATA_CACHE_LINES),
        .WAY_COUNT(DATA_CACHE_WAYS),
        .WORDS_PER_LINE(DATA_CACHE_WORDS_PER_LINE),
        .MEMORY_RESPONSE_LATENCY(DATA_MEM_RESPONSE_LATENCY)
    ) u_data_cache (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (mem_req_valid),
        .req_ready    (mem_req_ready),
        .req_write    (store_drain_valid),
        .req_word_addr(word_addr),
        .req_wmask    (store_wmask),
        .req_wdata    (store_wdata),
        .resp_valid   (mem_resp_valid),
        .resp_rdata   (mem_resp_rdata)
    );

    always_comb begin
        unique case (pending_byte_off)
            2'd0: load_byte = curr_word[7:0];
            2'd1: load_byte = curr_word[15:8];
            2'd2: load_byte = curr_word[23:16];
            default: load_byte = curr_word[31:24];
        endcase
    end

    always_comb begin
        unique case (pending_byte_off)
            2'd0: load_half = curr_word[15:0];
            2'd1: load_half = curr_word[23:8];
            2'd2: load_half = curr_word[31:16];
            default: load_half = 16'h0;
        endcase
    end

    always_comb begin
        load_result_comb = '0;
        if (pending_control.mem_read) begin
            unique case (pending_control.funct3)
                3'b000: load_result_comb = {{24{load_byte[7]}}, load_byte}; // LB
                3'b001: load_result_comb = {{16{load_half[15]}}, load_half}; // LH
                3'b010: load_result_comb = curr_word;                       // LW
                3'b100: load_result_comb = {24'h0, load_byte};              // LBU
                3'b101: load_result_comb = {16'h0, load_half};              // LHU
                default: load_result_comb = '0;
            endcase
        end
    end

    always_comb begin
        store_wmask = 4'b0000;
        store_wdata = '0;
        if (active_control.mem_write) begin
            unique case (active_control.funct3)
                3'b000: begin                            // SB
                    unique case (byte_off)
                        2'd0: store_wmask = 4'b0001;
                        2'd1: store_wmask = 4'b0010;
                        2'd2: store_wmask = 4'b0100;
                        default: store_wmask = 4'b1000;
                    endcase
                    store_wdata = {4{active_datapath.src2_value[7:0]}} << (byte_off * 8);
                end
                3'b001: begin                            // SH
                    unique case (byte_off)
                        2'd0: store_wmask = 4'b0011;
                        2'd1: store_wmask = 4'b0110;
                        2'd2: store_wmask = 4'b1100;
                        default: store_wmask = 4'b0000;
                    endcase
                    store_wdata = {16'b0, active_datapath.src2_value[15:0]} << (byte_off * 8);
                end
                3'b010: begin                            // SW
                    store_wmask = 4'b1111;
                    store_wdata = active_datapath.src2_value;
                end
                default: begin
                    store_wmask = 4'b0000;
                    store_wdata = '0;
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_valid  <= 1'b0;
            pending_mem_req_sent <= 1'b0;
            pending_store_dep_mask <= '0;
            pending_control <= '0;
            pending_datapath <= '0;
            commit_replay_ptr_q <= '0;
            for (int i = 0; i < COMMIT_REPLAY_DEPTH; i++) begin
                commit_replay_valid[i] <= 1'b0;
                commit_replay_tag[i] <= '0;
                commit_replay_age[i] <= '0;
            end
            for (int i = 0; i < COMMIT_TAG_COUNT; i++) begin
                commit_seen_valid[i] <= 1'b0;
            end
            store_age_q <= '0;
            store_drain_wait_q <= 1'b0;
            for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
                store_buf_valid[i] <= 1'b0;
                store_buf_committed[i] <= 1'b0;
                store_buf_mem_req_sent[i] <= 1'b0;
                store_buf_age[i] <= '0;
                store_buf_control[i] <= '0;
                store_buf_datapath[i] <= '0;
            end
            resp_valid     <= 1'b0;
            resp_tag       <= '0;
            resp_preg      <= '0;
            resp_reg_write <= 1'b0;
            resp_dest_is_fp <= 1'b0;
            resp_result    <= '0;
        end else begin
            resp_valid     <= 1'b0;
            resp_tag       <= '0;
            resp_preg      <= '0;
            resp_reg_write <= 1'b0;
            resp_dest_is_fp <= 1'b0;
            resp_result    <= '0;
            store_drain_wait_q <= 1'b0;

            for (int i = 0; i < COMMIT_REPLAY_DEPTH; i++) begin
                if (commit_replay_valid[i]) begin
                    if (&commit_replay_age[i]) begin
                        commit_replay_valid[i] <= 1'b0;
                        commit_replay_tag[i] <= '0;
                        commit_replay_age[i] <= '0;
                    end else begin
                        commit_replay_age[i] <= commit_replay_age[i] + 1'b1;
                    end
                end
            end

            if (commit_store_valid0 && !store_commit_hit0) begin
                commit_seen_valid[commit_store_tag0] <= 1'b1;
                commit_replay_valid[commit_replay_ptr_q] <= 1'b1;
                commit_replay_tag[commit_replay_ptr_q] <= commit_store_tag0;
                commit_replay_age[commit_replay_ptr_q] <= '0;
                commit_replay_ptr_q <= commit_replay_ptr_q + 1'b1;
            end
            if (commit_store_valid1 && !store_commit_hit1) begin
                commit_seen_valid[commit_store_tag1] <= 1'b1;
                commit_replay_valid[commit_replay_idx1] <= 1'b1;
                commit_replay_tag[commit_replay_idx1] <= commit_store_tag1;
                commit_replay_age[commit_replay_idx1] <= '0;
                commit_replay_ptr_q <= commit_replay_idx1 + 1'b1;
            end

            if (pending_valid && pending_squashed) begin
                pending_valid <= 1'b0;
                pending_mem_req_sent <= 1'b0;
                pending_store_dep_mask <= '0;
                pending_control <= '0;
                pending_datapath <= '0;
            end else if (mem_resp_valid) begin
                if (store_drain_valid && store_buf_mem_req_sent[store_drain_idx]) begin
                    store_buf_valid[store_drain_idx] <= 1'b0;
                    store_buf_committed[store_drain_idx] <= 1'b0;
                    store_buf_mem_req_sent[store_drain_idx] <= 1'b0;
                    store_buf_age[store_drain_idx] <= '0;
                    store_buf_control[store_drain_idx] <= '0;
                    store_buf_datapath[store_drain_idx] <= '0;
                    store_drain_wait_q <= 1'b1;
                end else if (pending_valid) begin
                    resp_valid     <= 1'b1;
                    resp_tag       <= pending_datapath.rob_tag;
                    resp_preg      <= pending_datapath.new_des_preg;
                    resp_reg_write <= pending_control.mem_read &&
                                      (pending_datapath.dest_is_fp ||
                                       (pending_datapath.new_des_preg != '0));
                    resp_dest_is_fp <= pending_datapath.dest_is_fp;
                    resp_result    <= pending_control.mem_read ? load_result_comb : '0;

                    pending_valid <= 1'b0;
                    pending_mem_req_sent <= 1'b0;
                    pending_store_dep_mask <= '0;
                    pending_control <= '0;
                    pending_datapath <= '0;
                end
            end else if (pending_forward_valid) begin
                resp_valid     <= 1'b1;
                resp_tag       <= pending_datapath.rob_tag;
                resp_preg      <= pending_datapath.new_des_preg;
                resp_reg_write <= pending_datapath.dest_is_fp ||
                                  (pending_datapath.new_des_preg != '0);
                resp_dest_is_fp <= pending_datapath.dest_is_fp;
                resp_result    <= load_result_comb;

                pending_valid <= 1'b0;
                pending_mem_req_sent <= 1'b0;
                pending_store_dep_mask <= '0;
                pending_control <= '0;
                pending_datapath <= '0;
            end else if (mem_req_valid && mem_req_ready) begin
                if (store_drain_valid) begin
                    store_buf_mem_req_sent[store_drain_idx] <= 1'b1;
                end else begin
                    pending_mem_req_sent <= 1'b1;
                end
            end

            if (req_valid && req_ready) begin
                if (control_signal.mem_write) begin
                    store_buf_valid[store_alloc_idx] <= 1'b1;
                    store_buf_committed[store_alloc_idx] <= store_alloc_commit_match;
                    store_buf_mem_req_sent[store_alloc_idx] <= 1'b0;
                    store_buf_age[store_alloc_idx] <= store_age_q;
                    store_buf_control[store_alloc_idx] <= control_signal;
                    store_buf_datapath[store_alloc_idx] <= datapath;
                    store_age_q <= store_age_q + 1'b1;
                    if (store_alloc_commit_match) begin
                        commit_seen_valid[datapath.rob_tag] <= 1'b0;
                    end
                    if (commit_replay_hit) begin
                        for (int i = 0; i < COMMIT_REPLAY_DEPTH; i++) begin
                            if (commit_replay_valid[i] &&
                                (commit_replay_tag[i] == datapath.rob_tag)) begin
                                commit_replay_valid[i] <= 1'b0;
                                commit_replay_tag[i] <= '0;
                                commit_replay_age[i] <= '0;
                            end
                        end
                    end

                    resp_valid     <= 1'b1;
                    resp_tag       <= datapath.rob_tag;
                    resp_preg      <= '0;
                    resp_reg_write <= 1'b0;
                    resp_result    <= '0;
                end else begin
                    pending_valid <= 1'b1;
                    pending_mem_req_sent <= 1'b0;
                    pending_store_dep_mask <= load_dep_mask_comb;
                    pending_control <= control_signal;
                    pending_datapath <= datapath;
                end
            end else if (pending_valid && resolve_en) begin
                pending_datapath.speculation_mask <= pending_spec_mask_next;
            end

            for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
                if (store_buf_squashed[i]) begin
                    store_buf_valid[i] <= 1'b0;
                    store_buf_committed[i] <= 1'b0;
                    store_buf_mem_req_sent[i] <= 1'b0;
                    store_buf_age[i] <= '0;
                    store_buf_control[i] <= '0;
                    store_buf_datapath[i] <= '0;
                end else begin
                    if (resolve_en && store_buf_valid[i]) begin
                        store_buf_datapath[i].speculation_mask <= store_buf_spec_mask_next[i];
                    end
                    if (store_commit_match[i]) begin
                        store_buf_committed[i] <= 1'b1;
                        commit_seen_valid[store_buf_datapath[i].rob_tag] <= 1'b0;
                    end
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n === 1'b1) begin
            assert (!resp_reg_write || resp_valid)
                else $error("[ASSERT:LSU] register write lacks valid response");
            assert (!store_drain_valid ||
                    (store_buf_valid[store_drain_idx] &&
                     store_buf_committed[store_drain_idx] &&
                     !store_buf_squashed[store_drain_idx]))
                else $error("[ASSERT:LSU] draining uncommitted or squashed store");
            assert (!(mem_req_valid && store_drain_valid) ||
                    store_buf_committed[store_drain_idx])
                else $error("[ASSERT:LSU] memory write issued before store commit");

            for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
                assert (!store_buf_committed[i] || store_buf_valid[i])
                    else $error("[ASSERT:LSU] committed bit set on invalid store");
                assert (!store_buf_mem_req_sent[i] ||
                        (store_buf_valid[i] && store_buf_committed[i]))
                    else $error("[ASSERT:LSU] uncommitted store reached memory");
                assert (!store_buf_squashed[i] || !store_buf_committed[i])
                    else $error("[ASSERT:LSU] committed store selected for squash");
            end
        end
    end
`endif

endmodule
