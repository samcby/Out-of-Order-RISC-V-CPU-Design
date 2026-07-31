// Non-blocking two-request load/store unit.
//
// Loads wait in an eight-entry queue and may occupy one MSHR in each D-cache
// bank. Stores complete to the ROB after allocation, remain speculative in the
// store buffer, and become memory-visible only after an in-order commit tag.
// Byte-granular forwarding chooses the youngest older store for every byte.
//
// Program age comes from the LSQ mem_seq field. A local acceptance age breaks
// ties for legacy unit tests that directly inject requests without mem_seq.
module lsu #(
    parameter int MEM_WORDS = 256,
    parameter logic [defines_pkg::WIDTH-1:0] DATA_BASE_ADDR = '0,
    parameter int DATA_CACHE_LINES = 8,
    parameter int DATA_CACHE_WAYS = 2,
    parameter int DATA_CACHE_WORDS_PER_LINE = 4,
    parameter int DATA_MEM_RESPONSE_LATENCY = 2
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           req_valid,
    output logic                           req_ready,
    input  logic                           flush,
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
    output logic [defines_pkg::WIDTH-1:0]  resp_result,
    output logic                           idle,

    input  logic                           req1_valid,
    output logic                           req1_ready,
    input  defines_pkg::lsu_control_t      control_signal1,
    input  defines_pkg::rs_datapath_t      datapath1,
    output logic                           resp1_valid,
    output defines_pkg::rob_tag_t          resp1_tag,
    output defines_pkg::preg_t             resp1_preg,
    output logic                           resp1_reg_write,
    output logic                           resp1_dest_is_fp,
    output logic [defines_pkg::WIDTH-1:0]  resp1_result
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);
    localparam int CACHE_OFFSET_W = $clog2(DATA_CACHE_WORDS_PER_LINE);
    localparam int LOAD_DEPTH = 8;
    localparam int LOAD_IDX_W = $clog2(LOAD_DEPTH);
    localparam int STORE_BUF_DEPTH = 8;
    localparam int STORE_BUF_IDX_W = $clog2(STORE_BUF_DEPTH);
    localparam int STORE_BUF_AGE_W = MEM_SEQ_W;
    localparam int BANK_COUNT = 2;

    logic load_valid [0:LOAD_DEPTH-1];
    logic load_cache_sent [0:LOAD_DEPTH-1];
    logic load_killed [0:LOAD_DEPTH-1];
    logic load_result_ready [0:LOAD_DEPTH-1];
    logic [WIDTH-1:0] load_result [0:LOAD_DEPTH-1];
    logic [3:0] load_forward_mask_q [0:LOAD_DEPTH-1];
    logic [WIDTH-1:0] load_forward_word_q [0:LOAD_DEPTH-1];
    logic [STORE_BUF_AGE_W-1:0] load_age [0:LOAD_DEPTH-1];
    lsu_control_t load_control [0:LOAD_DEPTH-1];
    rs_datapath_t load_datapath [0:LOAD_DEPTH-1];

    // Historical store-buffer names are retained for testbench hierarchy.
    logic store_buf_valid [0:STORE_BUF_DEPTH-1];
    logic store_buf_committed [0:STORE_BUF_DEPTH-1];
    logic store_buf_mem_req_sent [0:STORE_BUF_DEPTH-1];
    logic store_buf_completion_pending [0:STORE_BUF_DEPTH-1];
    logic [STORE_BUF_AGE_W-1:0] store_buf_age [0:STORE_BUF_DEPTH-1];
    lsu_control_t store_buf_control [0:STORE_BUF_DEPTH-1];
    rs_datapath_t store_buf_datapath [0:STORE_BUF_DEPTH-1];
    logic [STORE_BUF_AGE_W-1:0] store_age_q;

    logic [WIDTH-1:0] store_buf_eff_addr [0:STORE_BUF_DEPTH-1];
    logic [3:0] store_buf_byte_mask [0:STORE_BUF_DEPTH-1];
    logic [WIDTH-1:0] store_buf_aligned_data [0:STORE_BUF_DEPTH-1];
    logic store_buf_squashed [0:STORE_BUF_DEPTH-1];
    logic store_commit_match [0:STORE_BUF_DEPTH-1];
    cp_mask_t store_buf_spec_mask_next [0:STORE_BUF_DEPTH-1];
    logic [STORE_BUF_DEPTH-1:0] store_buf_valid_mask;
    logic store_buf_any_valid;
    logic store_buf_full;

    logic [WIDTH-1:0] load_eff_addr [0:LOAD_DEPTH-1];
    logic [3:0] load_byte_mask [0:LOAD_DEPTH-1];
    logic [3:0] load_forward_mask [0:LOAD_DEPTH-1];
    logic [WIDTH-1:0] load_forward_word [0:LOAD_DEPTH-1];
    mem_seq_t load_forward_seq [0:LOAD_DEPTH-1][0:3];
    logic [STORE_BUF_AGE_W-1:0]
        load_forward_age [0:LOAD_DEPTH-1][0:3];
    logic load_full_forward [0:LOAD_DEPTH-1];
    logic load_overlap_older_store [0:LOAD_DEPTH-1];

    logic load_free0_valid;
    logic load_free1_valid;
    logic [LOAD_IDX_W-1:0] load_free0_idx;
    logic [LOAD_IDX_W-1:0] load_free1_idx;
    logic store_free0_valid;
    logic store_free1_valid;
    logic [STORE_BUF_IDX_W-1:0] store_free0_idx;
    logic [STORE_BUF_IDX_W-1:0] store_free1_idx;

    logic req1_valid_safe;
    logic req0_is_load;
    logic req0_is_store;
    logic req1_is_load;
    logic req1_is_store;
    logic req0_fire;
    logic req1_fire;
    logic req0_squashed_now;
    logic req1_squashed_now;

    logic drain_valid_bank [0:BANK_COUNT-1];
    logic [STORE_BUF_IDX_W-1:0] drain_idx_bank [0:BANK_COUNT-1];
    mem_seq_t drain_seq_bank [0:BANK_COUNT-1];
    logic [STORE_BUF_AGE_W-1:0] drain_age_bank [0:BANK_COUNT-1];
    logic load_req_valid_bank [0:BANK_COUNT-1];
    logic [LOAD_IDX_W-1:0] load_req_idx_bank [0:BANK_COUNT-1];
    mem_seq_t load_req_seq_bank [0:BANK_COUNT-1];
    logic [STORE_BUF_AGE_W-1:0] load_req_age_bank [0:BANK_COUNT-1];

    logic bank_owner_valid [0:BANK_COUNT-1];
    logic bank_owner_store [0:BANK_COUNT-1];
    logic [STORE_BUF_IDX_W-1:0] bank_owner_store_idx [0:BANK_COUNT-1];
    logic [LOAD_IDX_W-1:0] bank_owner_load_idx [0:BANK_COUNT-1];

    logic mem_req_valid;
    logic mem_req_ready;
    logic mem_req_write;
    logic [ADDR_W-1:0] mem_req_word_addr;
    logic [3:0] mem_req_wmask;
    logic [WIDTH-1:0] mem_req_wdata;
    logic mem_resp_valid;
    logic [WIDTH-1:0] mem_resp_rdata;
    logic mem1_req_valid;
    logic mem1_req_ready;
    logic mem1_req_write;
    logic [ADDR_W-1:0] mem1_req_word_addr;
    logic [3:0] mem1_req_wmask;
    logic [WIDTH-1:0] mem1_req_wdata;
    logic mem1_resp_valid;
    logic [WIDTH-1:0] mem1_resp_rdata;

    logic completion0_valid;
    logic completion0_is_load;
    logic [LOAD_IDX_W-1:0] completion0_load_idx;
    logic [STORE_BUF_IDX_W-1:0] completion0_store_idx;
    mem_seq_t completion0_seq;
    logic [STORE_BUF_AGE_W-1:0] completion0_age;
    logic completion1_valid;
    logic completion1_is_load;
    logic [LOAD_IDX_W-1:0] completion1_load_idx;
    logic [STORE_BUF_IDX_W-1:0] completion1_store_idx;
    mem_seq_t completion1_seq;
    logic [STORE_BUF_AGE_W-1:0] completion1_age;

    // Legacy single-pending waveform aliases now expose the oldest live load.
    logic pending_valid;
    logic pending_mem_req_sent;
    lsu_control_t pending_control;
    rs_datapath_t pending_datapath;
    logic [STORE_BUF_DEPTH-1:0] pending_store_dep_mask;
    logic pending_store_blocking;
    logic [STORE_BUF_AGE_W-1:0] pending_age;
    logic store_drain_valid;
    logic store_drain_wait_q;
    logic [STORE_BUF_IDX_W-1:0] store_drain_idx;

    function automatic logic [3:0] access_byte_mask(
        input logic [2:0] funct3,
        input logic [1:0] offset
    );
    begin
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
        unique case (funct3)
            3'b000: align_store_data =
                {24'b0, data[7:0]} << (offset * 8);
            3'b001: align_store_data =
                {16'b0, data[15:0]} << (offset * 8);
            3'b010: align_store_data = data;
            default: align_store_data = '0;
        endcase
    end
    endfunction

    function automatic logic [WIDTH-1:0] effective_addr(
        input rs_datapath_t dp
    );
        effective_addr = dp.src1_value + dp.imm;
    endfunction

    function automatic logic [ADDR_W-1:0] cache_word_addr(
        input rs_datapath_t dp
    );
        logic [WIDTH-1:0] byte_offset;
    begin
        byte_offset = effective_addr(dp) - DATA_BASE_ADDR;
        cache_word_addr = byte_offset[ADDR_W+1:2];
    end
    endfunction

    function automatic logic cache_bank(input rs_datapath_t dp);
        logic [ADDR_W-1:0] word_address;
    begin
        word_address = cache_word_addr(dp);
        cache_bank = word_address[CACHE_OFFSET_W];
    end
    endfunction

    function automatic logic operation_older(
        input mem_seq_t lhs_seq,
        input logic [STORE_BUF_AGE_W-1:0] lhs_age,
        input mem_seq_t rhs_seq,
        input logic [STORE_BUF_AGE_W-1:0] rhs_age
    );
    begin
        if (lhs_seq != rhs_seq) begin
            operation_older = $signed(lhs_seq - rhs_seq) < 0;
        end else begin
            operation_older = lhs_age < rhs_age;
        end
    end
    endfunction

    function automatic logic [WIDTH-1:0] merge_forwarded_bytes(
        input logic [WIDTH-1:0] cache_word,
        input logic [WIDTH-1:0] forward_word,
        input logic [3:0] forward_mask
    );
        logic [WIDTH-1:0] merged;
    begin
        merged = cache_word;
        for (int b = 0; b < 4; b++) begin
            if (forward_mask[b]) begin
                merged[b*8 +: 8] = forward_word[b*8 +: 8];
            end
        end
        merge_forwarded_bytes = merged;
    end
    endfunction

    function automatic logic [WIDTH-1:0] format_load(
        input lsu_control_t control,
        input logic [1:0] byte_offset,
        input logic [WIDTH-1:0] word
    );
        logic [7:0] byte_value;
        logic [15:0] half_value;
    begin
        unique case (byte_offset)
            2'd0: byte_value = word[7:0];
            2'd1: byte_value = word[15:8];
            2'd2: byte_value = word[23:16];
            default: byte_value = word[31:24];
        endcase
        unique case (byte_offset)
            2'd0: half_value = word[15:0];
            2'd1: half_value = word[23:8];
            2'd2: half_value = word[31:16];
            default: half_value = '0;
        endcase

        unique case (control.funct3)
            3'b000: format_load = {{24{byte_value[7]}}, byte_value};
            3'b001: format_load = {{16{half_value[15]}}, half_value};
            3'b010: format_load = word;
            3'b100: format_load = {24'h0, byte_value};
            3'b101: format_load = {16'h0, half_value};
            default: format_load = '0;
        endcase
    end
    endfunction

    generate
        for (genvar i = 0; i < STORE_BUF_DEPTH; i++) begin : gen_store_metadata
            assign store_buf_eff_addr[i] =
                effective_addr(store_buf_datapath[i]);
            assign store_buf_byte_mask[i] =
                access_byte_mask(store_buf_control[i].funct3,
                                 store_buf_eff_addr[i][1:0]);
            assign store_buf_aligned_data[i] =
                align_store_data(store_buf_control[i].funct3,
                                 store_buf_eff_addr[i][1:0],
                                 store_buf_datapath[i].src2_value);
        end
        for (genvar i = 0; i < LOAD_DEPTH; i++) begin : gen_load_metadata
            assign load_eff_addr[i] = effective_addr(load_datapath[i]);
            assign load_byte_mask[i] =
                access_byte_mask(load_control[i].funct3,
                                 load_eff_addr[i][1:0]);
        end
    endgenerate

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
        store_buf_any_valid = 1'b0;
        store_buf_full = 1'b1;
        store_buf_valid_mask = '0;
        for (int i = 0; i < STORE_BUF_DEPTH; i++) begin
            store_buf_spec_mask_next[i] =
                resolve_en ?
                (store_buf_datapath[i].speculation_mask &
                 ~(cp_mask_t'(1'b1) << resolve_checkpoint_id)) :
                store_buf_datapath[i].speculation_mask;
            store_buf_squashed[i] =
                store_buf_valid[i] &&
                !store_buf_committed[i] &&
                ((flush === 1'b1) ||
                 (squash_en &&
                  store_buf_datapath[i].speculation_mask[
                      squash_checkpoint_id]));
            store_commit_match[i] =
                store_buf_valid[i] &&
                !store_buf_committed[i] &&
                ((commit_store_valid0 &&
                  (commit_store_tag0 ==
                   store_buf_datapath[i].rob_tag)) ||
                 (commit_store_valid1 &&
                  (commit_store_tag1 ==
                   store_buf_datapath[i].rob_tag)));

            if (store_buf_valid[i]) begin
                store_buf_any_valid = 1'b1;
                if (!store_buf_squashed[i]) begin
                    store_buf_valid_mask[i] = 1'b1;
                end
            end else begin
                store_buf_full = 1'b0;
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

    // Forward each requested byte from the youngest older resident store.
    always_comb begin
        for (int l = 0; l < LOAD_DEPTH; l++) begin
            load_forward_mask[l] = '0;
            load_forward_word[l] = '0;
            load_overlap_older_store[l] = 1'b0;
            for (int b = 0; b < 4; b++) begin
                load_forward_seq[l][b] = '0;
                load_forward_age[l][b] = '0;
            end

            for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                if (store_buf_valid_mask[s] &&
                    operation_older(
                        store_buf_datapath[s].mem_seq,
                        store_buf_age[s],
                        load_datapath[l].mem_seq,
                        load_age[l]) &&
                    (store_buf_eff_addr[s][WIDTH-1:2] ==
                     load_eff_addr[l][WIDTH-1:2]) &&
                    (|(store_buf_byte_mask[s] &
                       load_byte_mask[l]))) begin
                    load_overlap_older_store[l] = 1'b1;
                    for (int b = 0; b < 4; b++) begin
                        if (load_byte_mask[l][b] &&
                            store_buf_byte_mask[s][b] &&
                            (!load_forward_mask[l][b] ||
                             operation_older(
                                load_forward_seq[l][b],
                                load_forward_age[l][b],
                                store_buf_datapath[s].mem_seq,
                                store_buf_age[s]))) begin
                            load_forward_mask[l][b] = 1'b1;
                            load_forward_seq[l][b] =
                                store_buf_datapath[s].mem_seq;
                            load_forward_age[l][b] =
                                store_buf_age[s];
                            load_forward_word[l][b*8 +: 8] =
                                store_buf_aligned_data[s][b*8 +: 8];
                        end
                    end
                end
            end

            load_full_forward[l] =
                load_valid[l] &&
                (load_byte_mask[l] != '0) &&
                ((load_forward_mask[l] & load_byte_mask[l]) ==
                 load_byte_mask[l]);
        end
    end

    // Select one committed store or one waiting load for each cache bank.
    always_comb begin
        for (int b = 0; b < BANK_COUNT; b++) begin
            drain_valid_bank[b] = 1'b0;
            drain_idx_bank[b] = '0;
            drain_seq_bank[b] = '0;
            drain_age_bank[b] = '0;
            load_req_valid_bank[b] = 1'b0;
            load_req_idx_bank[b] = '0;
            load_req_seq_bank[b] = '0;
            load_req_age_bank[b] = '0;

            for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                if (store_buf_valid[s] &&
                    store_buf_committed[s] &&
                    !store_buf_mem_req_sent[s] &&
                    !store_buf_completion_pending[s] &&
                    (cache_bank(store_buf_datapath[s]) == b[0]) &&
                    (!drain_valid_bank[b] ||
                     operation_older(
                        store_buf_datapath[s].mem_seq,
                        store_buf_age[s],
                        drain_seq_bank[b],
                        drain_age_bank[b]))) begin
                    drain_valid_bank[b] = 1'b1;
                    drain_idx_bank[b] = s;
                    drain_seq_bank[b] =
                        store_buf_datapath[s].mem_seq;
                    drain_age_bank[b] = store_buf_age[s];
                end
            end

            for (int l = 0; l < LOAD_DEPTH; l++) begin
                if (load_valid[l] &&
                    !load_cache_sent[l] &&
                    !load_killed[l] &&
                    !load_result_ready[l] &&
                    !load_full_forward[l] &&
                    !load_overlap_older_store[l] &&
                    (cache_bank(load_datapath[l]) == b[0]) &&
                    (!load_req_valid_bank[b] ||
                     operation_older(
                        load_datapath[l].mem_seq,
                        load_age[l],
                        load_req_seq_bank[b],
                        load_req_age_bank[b]))) begin
                    load_req_valid_bank[b] = 1'b1;
                    load_req_idx_bank[b] = l;
                    load_req_seq_bank[b] =
                        load_datapath[l].mem_seq;
                    load_req_age_bank[b] = load_age[l];
                end
            end
        end
    end

    assign mem_req_valid =
        !flush && !bank_owner_valid[0] &&
        (drain_valid_bank[0] ||
         (!drain_valid_bank[0] && load_req_valid_bank[0]));
    assign mem_req_write = drain_valid_bank[0];
    assign mem_req_word_addr =
        drain_valid_bank[0] ?
        cache_word_addr(store_buf_datapath[drain_idx_bank[0]]) :
        cache_word_addr(load_datapath[load_req_idx_bank[0]]);
    assign mem_req_wmask =
        drain_valid_bank[0] ?
        store_buf_byte_mask[drain_idx_bank[0]] : '0;
    assign mem_req_wdata =
        drain_valid_bank[0] ?
        store_buf_aligned_data[drain_idx_bank[0]] : '0;

    assign mem1_req_valid =
        !flush && !bank_owner_valid[1] &&
        (drain_valid_bank[1] ||
         (!drain_valid_bank[1] && load_req_valid_bank[1]));
    assign mem1_req_write = drain_valid_bank[1];
    assign mem1_req_word_addr =
        drain_valid_bank[1] ?
        cache_word_addr(store_buf_datapath[drain_idx_bank[1]]) :
        cache_word_addr(load_datapath[load_req_idx_bank[1]]);
    assign mem1_req_wmask =
        drain_valid_bank[1] ?
        store_buf_byte_mask[drain_idx_bank[1]] : '0;
    assign mem1_req_wdata =
        drain_valid_bank[1] ?
        store_buf_aligned_data[drain_idx_bank[1]] : '0;

    data_cache #(
        .MEM_WORDS(MEM_WORDS),
        .LINE_COUNT(DATA_CACHE_LINES),
        .WAY_COUNT(DATA_CACHE_WAYS),
        .WORDS_PER_LINE(DATA_CACHE_WORDS_PER_LINE),
        .MEMORY_RESPONSE_LATENCY(DATA_MEM_RESPONSE_LATENCY)
    ) u_data_cache (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_valid     (mem_req_valid),
        .req_ready     (mem_req_ready),
        .req_write     (mem_req_write),
        .req_word_addr (mem_req_word_addr),
        .req_wmask     (mem_req_wmask),
        .req_wdata     (mem_req_wdata),
        .resp_valid    (mem_resp_valid),
        .resp_rdata    (mem_resp_rdata),
        .req1_valid    (mem1_req_valid),
        .req1_ready    (mem1_req_ready),
        .req1_write    (mem1_req_write),
        .req1_word_addr(mem1_req_word_addr),
        .req1_wmask    (mem1_req_wmask),
        .req1_wdata    (mem1_req_wdata),
        .resp1_valid   (mem1_resp_valid),
        .resp1_rdata   (mem1_resp_rdata)
    );

    assign req1_valid_safe = (req1_valid === 1'b1);
    assign req0_is_load = control_signal.mem_read;
    assign req0_is_store = control_signal.mem_write;
    // Ready must not depend on valid: doing so closes a combinational loop
    // through the execution-stage ready/valid handshake. Case equality keeps
    // omitted legacy port-1 inputs benign without coupling capacity to valid.
    assign req1_is_load = (control_signal1.mem_read === 1'b1);
    assign req1_is_store = (control_signal1.mem_write === 1'b1);

    assign req_ready =
        !flush &&
        (req0_is_load ? load_free0_valid :
         req0_is_store ? store_free0_valid :
         (load_free0_valid || store_free0_valid));
    assign req0_fire = req_valid && req_ready;
    assign req1_ready =
        !flush &&
        ((req1_is_load &&
          ((req0_fire && req0_is_load) ?
           load_free1_valid : load_free0_valid)) ||
         (req1_is_store &&
          ((req0_fire && req0_is_store) ?
           store_free1_valid : store_free0_valid)));
    assign req1_fire = req1_valid_safe && req1_ready;
    assign req0_squashed_now =
        squash_en &&
        datapath.speculation_mask[squash_checkpoint_id];
    assign req1_squashed_now =
        squash_en &&
        datapath1.speculation_mask[squash_checkpoint_id];

    // Oldest pending completion wins slot 0; slot 1 receives the next oldest.
    always_comb begin
        completion0_valid = 1'b0;
        completion0_is_load = 1'b0;
        completion0_load_idx = '0;
        completion0_store_idx = '0;
        completion0_seq = '0;
        completion0_age = '0;

        for (int l = 0; l < LOAD_DEPTH; l++) begin
            if (load_valid[l] && load_result_ready[l] &&
                !load_killed[l] &&
                (!completion0_valid ||
                 operation_older(
                    load_datapath[l].mem_seq,
                    load_age[l],
                    completion0_seq,
                    completion0_age))) begin
                completion0_valid = 1'b1;
                completion0_is_load = 1'b1;
                completion0_load_idx = l;
                completion0_store_idx = '0;
                completion0_seq = load_datapath[l].mem_seq;
                completion0_age = load_age[l];
            end
        end
        for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
            if (store_buf_valid[s] &&
                store_buf_completion_pending[s] &&
                (!completion0_valid ||
                 operation_older(
                    store_buf_datapath[s].mem_seq,
                    store_buf_age[s],
                    completion0_seq,
                    completion0_age))) begin
                completion0_valid = 1'b1;
                completion0_is_load = 1'b0;
                completion0_load_idx = '0;
                completion0_store_idx = s;
                completion0_seq = store_buf_datapath[s].mem_seq;
                completion0_age = store_buf_age[s];
            end
        end

        completion1_valid = 1'b0;
        completion1_is_load = 1'b0;
        completion1_load_idx = '0;
        completion1_store_idx = '0;
        completion1_seq = '0;
        completion1_age = '0;

        for (int l = 0; l < LOAD_DEPTH; l++) begin
            if (load_valid[l] && load_result_ready[l] &&
                !load_killed[l] &&
                !(completion0_valid && completion0_is_load &&
                  (completion0_load_idx == l)) &&
                (!completion1_valid ||
                 operation_older(
                    load_datapath[l].mem_seq,
                    load_age[l],
                    completion1_seq,
                    completion1_age))) begin
                completion1_valid = 1'b1;
                completion1_is_load = 1'b1;
                completion1_load_idx = l;
                completion1_store_idx = '0;
                completion1_seq = load_datapath[l].mem_seq;
                completion1_age = load_age[l];
            end
        end
        for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
            if (store_buf_valid[s] &&
                store_buf_completion_pending[s] &&
                !(completion0_valid && !completion0_is_load &&
                  (completion0_store_idx == s)) &&
                (!completion1_valid ||
                 operation_older(
                    store_buf_datapath[s].mem_seq,
                    store_buf_age[s],
                    completion1_seq,
                    completion1_age))) begin
                completion1_valid = 1'b1;
                completion1_is_load = 1'b0;
                completion1_load_idx = '0;
                completion1_store_idx = s;
                completion1_seq = store_buf_datapath[s].mem_seq;
                completion1_age = store_buf_age[s];
            end
        end
    end

    always_comb begin
        resp_valid = completion0_valid && !flush;
        resp_tag = '0;
        resp_preg = '0;
        resp_reg_write = 1'b0;
        resp_dest_is_fp = 1'b0;
        resp_result = '0;
        if (completion0_valid) begin
            if (completion0_is_load) begin
                resp_tag =
                    load_datapath[completion0_load_idx].rob_tag;
                resp_preg =
                    load_datapath[completion0_load_idx].new_des_preg;
                resp_reg_write =
                    load_datapath[completion0_load_idx].dest_is_fp ||
                    (load_datapath[completion0_load_idx].new_des_preg != '0);
                resp_dest_is_fp =
                    load_datapath[completion0_load_idx].dest_is_fp;
                resp_result = load_result[completion0_load_idx];
            end else begin
                resp_tag =
                    store_buf_datapath[completion0_store_idx].rob_tag;
            end
        end

        resp1_valid = completion1_valid && !flush;
        resp1_tag = '0;
        resp1_preg = '0;
        resp1_reg_write = 1'b0;
        resp1_dest_is_fp = 1'b0;
        resp1_result = '0;
        if (completion1_valid) begin
            if (completion1_is_load) begin
                resp1_tag =
                    load_datapath[completion1_load_idx].rob_tag;
                resp1_preg =
                    load_datapath[completion1_load_idx].new_des_preg;
                resp1_reg_write =
                    load_datapath[completion1_load_idx].dest_is_fp ||
                    (load_datapath[completion1_load_idx].new_des_preg != '0);
                resp1_dest_is_fp =
                    load_datapath[completion1_load_idx].dest_is_fp;
                resp1_result = load_result[completion1_load_idx];
            end else begin
                resp1_tag =
                    store_buf_datapath[completion1_store_idx].rob_tag;
            end
        end
    end

    // Compatibility aliases select the oldest currently resident load/store.
    always_comb begin
        pending_valid = 1'b0;
        pending_mem_req_sent = 1'b0;
        pending_control = '0;
        pending_datapath = '0;
        pending_store_dep_mask = '0;
        pending_store_blocking = 1'b0;
        pending_age = '0;

        for (int l = 0; l < LOAD_DEPTH; l++) begin
            if (load_valid[l] &&
                (!pending_valid ||
                 operation_older(
                    load_datapath[l].mem_seq,
                    load_age[l],
                    pending_datapath.mem_seq,
                    pending_age))) begin
                pending_valid = 1'b1;
                pending_mem_req_sent = load_cache_sent[l];
                pending_control = load_control[l];
                pending_datapath = load_datapath[l];
                pending_age = load_age[l];
                pending_store_blocking =
                    load_overlap_older_store[l] &&
                    !load_full_forward[l] &&
                    !load_cache_sent[l];
                pending_store_dep_mask = '0;
                for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                    if (store_buf_valid_mask[s] &&
                        operation_older(
                            store_buf_datapath[s].mem_seq,
                            store_buf_age[s],
                            load_datapath[l].mem_seq,
                            load_age[l]) &&
                        (store_buf_eff_addr[s][WIDTH-1:2] ==
                         load_eff_addr[l][WIDTH-1:2]) &&
                        (|(store_buf_byte_mask[s] &
                           load_byte_mask[l]))) begin
                        pending_store_dep_mask[s] = 1'b1;
                    end
                end
            end
        end

        store_drain_valid =
            drain_valid_bank[0] || drain_valid_bank[1];
        store_drain_idx =
            drain_valid_bank[0] ? drain_idx_bank[0] :
                                  drain_idx_bank[1];
        store_drain_wait_q =
            (bank_owner_valid[0] && bank_owner_store[0]) ||
            (bank_owner_valid[1] && bank_owner_store[1]);
    end

    assign idle =
        !pending_valid &&
        !store_buf_any_valid &&
        !bank_owner_valid[0] &&
        !bank_owner_valid[1] &&
        !resp_valid &&
        !resp1_valid &&
        !mem_req_valid &&
        !mem1_req_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            store_age_q <= '0;
            for (int l = 0; l < LOAD_DEPTH; l++) begin
                load_valid[l] <= 1'b0;
                load_cache_sent[l] <= 1'b0;
                load_killed[l] <= 1'b0;
                load_result_ready[l] <= 1'b0;
                load_result[l] <= '0;
                load_forward_mask_q[l] <= '0;
                load_forward_word_q[l] <= '0;
                load_age[l] <= '0;
                load_control[l] <= '0;
                load_datapath[l] <= '0;
            end
            for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                store_buf_valid[s] <= 1'b0;
                store_buf_committed[s] <= 1'b0;
                store_buf_mem_req_sent[s] <= 1'b0;
                store_buf_completion_pending[s] <= 1'b0;
                store_buf_age[s] <= '0;
                store_buf_control[s] <= '0;
                store_buf_datapath[s] <= '0;
            end
            for (int b = 0; b < BANK_COUNT; b++) begin
                bank_owner_valid[b] <= 1'b0;
                bank_owner_store[b] <= 1'b0;
                bank_owner_store_idx[b] <= '0;
                bank_owner_load_idx[b] <= '0;
            end
        end else begin
            // Cache responses finish the MSHR owner. A killed load consumes the
            // response without generating architectural completion.
            if (mem_resp_valid && bank_owner_valid[0]) begin
                if (bank_owner_store[0]) begin
                    store_buf_valid[bank_owner_store_idx[0]] <= 1'b0;
                    store_buf_committed[bank_owner_store_idx[0]] <= 1'b0;
                    store_buf_mem_req_sent[bank_owner_store_idx[0]] <= 1'b0;
                    store_buf_completion_pending[
                        bank_owner_store_idx[0]] <= 1'b0;
                end else if (load_valid[bank_owner_load_idx[0]]) begin
                    if (!load_killed[bank_owner_load_idx[0]]) begin
                        load_result[bank_owner_load_idx[0]] <=
                            format_load(
                                load_control[bank_owner_load_idx[0]],
                                load_eff_addr[bank_owner_load_idx[0]][1:0],
                                merge_forwarded_bytes(
                                    mem_resp_rdata,
                                    load_forward_word_q[
                                        bank_owner_load_idx[0]],
                                    load_forward_mask_q[
                                        bank_owner_load_idx[0]]));
                        load_result_ready[
                            bank_owner_load_idx[0]] <= 1'b1;
                    end else begin
                        load_valid[bank_owner_load_idx[0]] <= 1'b0;
                    end
                    load_cache_sent[bank_owner_load_idx[0]] <= 1'b0;
                end
                bank_owner_valid[0] <= 1'b0;
            end

            if (mem1_resp_valid && bank_owner_valid[1]) begin
                if (bank_owner_store[1]) begin
                    store_buf_valid[bank_owner_store_idx[1]] <= 1'b0;
                    store_buf_committed[bank_owner_store_idx[1]] <= 1'b0;
                    store_buf_mem_req_sent[bank_owner_store_idx[1]] <= 1'b0;
                    store_buf_completion_pending[
                        bank_owner_store_idx[1]] <= 1'b0;
                end else if (load_valid[bank_owner_load_idx[1]]) begin
                    if (!load_killed[bank_owner_load_idx[1]]) begin
                        load_result[bank_owner_load_idx[1]] <=
                            format_load(
                                load_control[bank_owner_load_idx[1]],
                                load_eff_addr[bank_owner_load_idx[1]][1:0],
                                merge_forwarded_bytes(
                                    mem1_resp_rdata,
                                    load_forward_word_q[
                                        bank_owner_load_idx[1]],
                                    load_forward_mask_q[
                                        bank_owner_load_idx[1]]));
                        load_result_ready[
                            bank_owner_load_idx[1]] <= 1'b1;
                    end else begin
                        load_valid[bank_owner_load_idx[1]] <= 1'b0;
                    end
                    load_cache_sent[bank_owner_load_idx[1]] <= 1'b0;
                end
                bank_owner_valid[1] <= 1'b0;
            end

            if (resp_valid) begin
                if (completion0_is_load) begin
                    load_valid[completion0_load_idx] <= 1'b0;
                    load_result_ready[completion0_load_idx] <= 1'b0;
                end else begin
                    store_buf_completion_pending[
                        completion0_store_idx] <= 1'b0;
                end
            end
            if (resp1_valid) begin
                if (completion1_is_load) begin
                    load_valid[completion1_load_idx] <= 1'b0;
                    load_result_ready[completion1_load_idx] <= 1'b0;
                end else begin
                    store_buf_completion_pending[
                        completion1_store_idx] <= 1'b0;
                end
            end

            // Fully forwarded loads never consume an MSHR.
            for (int l = 0; l < LOAD_DEPTH; l++) begin
                if (load_valid[l] &&
                    !load_cache_sent[l] &&
                    !load_killed[l] &&
                    !load_result_ready[l] &&
                    load_full_forward[l]) begin
                    load_result[l] <=
                        format_load(
                            load_control[l],
                            load_eff_addr[l][1:0],
                            load_forward_word[l]);
                    load_result_ready[l] <= 1'b1;
                end
            end

            if (mem_req_valid && mem_req_ready) begin
                bank_owner_valid[0] <= 1'b1;
                bank_owner_store[0] <= drain_valid_bank[0];
                if (drain_valid_bank[0]) begin
                    bank_owner_store_idx[0] <= drain_idx_bank[0];
                    store_buf_mem_req_sent[drain_idx_bank[0]] <= 1'b1;
                end else begin
                    bank_owner_load_idx[0] <= load_req_idx_bank[0];
                    load_cache_sent[load_req_idx_bank[0]] <= 1'b1;
                    load_forward_mask_q[load_req_idx_bank[0]] <=
                        load_forward_mask[load_req_idx_bank[0]];
                    load_forward_word_q[load_req_idx_bank[0]] <=
                        load_forward_word[load_req_idx_bank[0]];
                end
            end
            if (mem1_req_valid && mem1_req_ready) begin
                bank_owner_valid[1] <= 1'b1;
                bank_owner_store[1] <= drain_valid_bank[1];
                if (drain_valid_bank[1]) begin
                    bank_owner_store_idx[1] <= drain_idx_bank[1];
                    store_buf_mem_req_sent[drain_idx_bank[1]] <= 1'b1;
                end else begin
                    bank_owner_load_idx[1] <= load_req_idx_bank[1];
                    load_cache_sent[load_req_idx_bank[1]] <= 1'b1;
                    load_forward_mask_q[load_req_idx_bank[1]] <=
                        load_forward_mask[load_req_idx_bank[1]];
                    load_forward_word_q[load_req_idx_bank[1]] <=
                        load_forward_word[load_req_idx_bank[1]];
                end
            end

            if (req0_fire && !req0_squashed_now) begin
                if (req0_is_store) begin
                    store_buf_valid[store_free0_idx] <= 1'b1;
                    store_buf_committed[store_free0_idx] <=
                        (commit_store_valid0 &&
                         (commit_store_tag0 == datapath.rob_tag)) ||
                        (commit_store_valid1 &&
                         (commit_store_tag1 == datapath.rob_tag));
                    store_buf_mem_req_sent[store_free0_idx] <= 1'b0;
                    store_buf_completion_pending[store_free0_idx] <= 1'b1;
                    store_buf_age[store_free0_idx] <= store_age_q;
                    store_buf_control[store_free0_idx] <= control_signal;
                    store_buf_datapath[store_free0_idx] <= datapath;
                end else if (req0_is_load) begin
                    load_valid[load_free0_idx] <= 1'b1;
                    load_cache_sent[load_free0_idx] <= 1'b0;
                    load_killed[load_free0_idx] <= 1'b0;
                    load_result_ready[load_free0_idx] <= 1'b0;
                    load_age[load_free0_idx] <= store_age_q;
                    load_control[load_free0_idx] <= control_signal;
                    load_datapath[load_free0_idx] <= datapath;
                end
            end

            if (req1_fire && !req1_squashed_now) begin
                if (req1_is_store) begin
                    store_buf_valid[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <= 1'b1;
                    store_buf_committed[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <=
                        (commit_store_valid0 &&
                         (commit_store_tag0 == datapath1.rob_tag)) ||
                        (commit_store_valid1 &&
                         (commit_store_tag1 == datapath1.rob_tag));
                    store_buf_mem_req_sent[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <= 1'b0;
                    store_buf_completion_pending[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <= 1'b1;
                    store_buf_age[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <=
                        store_age_q + (req0_fire ? 1'b1 : 1'b0);
                    store_buf_control[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <= control_signal1;
                    store_buf_datapath[
                        (req0_fire && req0_is_store) ?
                        store_free1_idx : store_free0_idx] <= datapath1;
                end else if (req1_is_load) begin
                    load_valid[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= 1'b1;
                    load_cache_sent[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= 1'b0;
                    load_killed[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= 1'b0;
                    load_result_ready[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= 1'b0;
                    load_age[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <=
                        store_age_q + (req0_fire ? 1'b1 : 1'b0);
                    load_control[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= control_signal1;
                    load_datapath[
                        (req0_fire && req0_is_load) ?
                        load_free1_idx : load_free0_idx] <= datapath1;
                end
            end

            if (req0_fire || req1_fire) begin
                store_age_q <= store_age_q +
                    (req0_fire ? 1'b1 : 1'b0) +
                    (req1_fire ? 1'b1 : 1'b0);
            end

            for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                if (store_buf_squashed[s]) begin
                    store_buf_valid[s] <= 1'b0;
                    store_buf_committed[s] <= 1'b0;
                    store_buf_mem_req_sent[s] <= 1'b0;
                    store_buf_completion_pending[s] <= 1'b0;
                end else begin
                    if (resolve_en && store_buf_valid[s]) begin
                        store_buf_datapath[s].speculation_mask <=
                            store_buf_spec_mask_next[s];
                    end
                    if (store_commit_match[s]) begin
                        store_buf_committed[s] <= 1'b1;
                    end
                end
            end

            for (int l = 0; l < LOAD_DEPTH; l++) begin
                if (load_valid[l] &&
                    ((flush === 1'b1) ||
                     (squash_en &&
                      load_datapath[l].speculation_mask[
                          squash_checkpoint_id]))) begin
                    if (load_cache_sent[l] &&
                        !((mem_resp_valid &&
                           bank_owner_valid[0] &&
                           !bank_owner_store[0] &&
                           (bank_owner_load_idx[0] == l)) ||
                          (mem1_resp_valid &&
                           bank_owner_valid[1] &&
                           !bank_owner_store[1] &&
                           (bank_owner_load_idx[1] == l)))) begin
                        load_killed[l] <= 1'b1;
                        load_result_ready[l] <= 1'b0;
                    end else begin
                        load_valid[l] <= 1'b0;
                        load_cache_sent[l] <= 1'b0;
                        load_result_ready[l] <= 1'b0;
                    end
                end else if (load_valid[l] && resolve_en) begin
                    load_datapath[l].speculation_mask[
                        resolve_checkpoint_id] <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (!(resp_valid && resp1_valid &&
                      (resp_tag == resp1_tag)))
                else $error("[ASSERT:LSU] duplicate completion tag");
            assert (!store_drain_valid ||
                    (store_buf_valid[store_drain_idx] &&
                     store_buf_committed[store_drain_idx]))
                else $error("[ASSERT:LSU] draining an uncommitted store");
            for (int s = 0; s < STORE_BUF_DEPTH; s++) begin
                assert (!store_buf_committed[s] || store_buf_valid[s])
                    else $error("[ASSERT:LSU] committed bit on invalid store");
                assert (!store_buf_mem_req_sent[s] ||
                        (store_buf_valid[s] &&
                         store_buf_committed[s]))
                    else $error("[ASSERT:LSU] speculative store reached cache");
            end
        end
    end
`endif

endmodule
