// Two-bank set-associative write-back, write-allocate data cache.
//
// Requests are steered by the low set-index bit. Different banks have
// independent miss state machines and backing-memory channels, so two hits or
// two misses may progress concurrently. Same-bank requests are serialized with
// deterministic port-0 priority. The tag/data arrays retain their historical
// hierarchy names for verification compatibility.
module data_cache #(
    parameter int MEM_WORDS = 256,
    parameter int LINE_COUNT = 8,
    parameter int WAY_COUNT = 2,
    parameter int WORDS_PER_LINE = 4,
    parameter int MEMORY_RESPONSE_LATENCY = 2
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          req_valid,
    output logic                          req_ready,
    input  logic                          req_write,
    input  logic [$clog2(MEM_WORDS)-1:0]  req_word_addr,
    input  logic [3:0]                    req_wmask,
    input  logic [defines_pkg::WIDTH-1:0] req_wdata,
    output logic                          resp_valid,
    output logic [defines_pkg::WIDTH-1:0] resp_rdata,

    input  logic                          req1_valid,
    output logic                          req1_ready,
    input  logic                          req1_write,
    input  logic [$clog2(MEM_WORDS)-1:0]  req1_word_addr,
    input  logic [3:0]                    req1_wmask,
    input  logic [defines_pkg::WIDTH-1:0] req1_wdata,
    output logic                          resp1_valid,
    output logic [defines_pkg::WIDTH-1:0] resp1_rdata
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);
    localparam int SET_COUNT = LINE_COUNT / WAY_COUNT;
    localparam int OFFSET_W = $clog2(WORDS_PER_LINE);
    localparam int INDEX_W = $clog2(SET_COUNT);
    localparam int TAG_W = ADDR_W - INDEX_W - OFFSET_W;
    localparam int WAY_W = (WAY_COUNT <= 1) ? 1 : $clog2(WAY_COUNT);
    localparam int BANK_COUNT = 2;

    typedef enum logic [2:0] {
        DCACHE_IDLE,
        DCACHE_WRITEBACK_REQ,
        DCACHE_WRITEBACK_WAIT,
        DCACHE_REFILL_REQ,
        DCACHE_REFILL_WAIT
    } dcache_state_t;

    logic [WIDTH-1:0] line_data
        [0:SET_COUNT-1][0:WAY_COUNT-1][0:WORDS_PER_LINE-1];
    logic [TAG_W-1:0] line_tag [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic             line_valid [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic             line_dirty [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic [WAY_W-1:0] replace_way [0:SET_COUNT-1];

    dcache_state_t bank_state_q [0:BANK_COUNT-1];
    logic [ADDR_W-1:0] bank_pending_line_base_q [0:BANK_COUNT-1];
    logic [OFFSET_W-1:0] bank_pending_offset_q [0:BANK_COUNT-1];
    logic [INDEX_W-1:0] bank_pending_index_q [0:BANK_COUNT-1];
    logic [TAG_W-1:0] bank_pending_tag_q [0:BANK_COUNT-1];
    logic [WAY_W-1:0] bank_pending_way_q [0:BANK_COUNT-1];
    logic bank_pending_is_store_q [0:BANK_COUNT-1];
    logic [3:0] bank_pending_wmask_q [0:BANK_COUNT-1];
    logic [WIDTH-1:0] bank_pending_wdata_q [0:BANK_COUNT-1];
    logic bank_pending_owner_q [0:BANK_COUNT-1];
    logic [ADDR_W-1:0] bank_victim_line_base_q [0:BANK_COUNT-1];
    logic [OFFSET_W-1:0] bank_line_word_q [0:BANK_COUNT-1];
    logic bank_mem_req_sent_q [0:BANK_COUNT-1];

    logic req1_valid_safe;
    logic [OFFSET_W-1:0] req_offset0;
    logic [INDEX_W-1:0] req_index0;
    logic [TAG_W-1:0] req_tag0;
    logic req_bank0;
    logic req_hit0;
    logic [WAY_W-1:0] hit_way0;
    logic [WAY_W-1:0] victim_way0;
    logic victim_dirty0;

    logic [OFFSET_W-1:0] req_offset1;
    logic [INDEX_W-1:0] req_index1;
    logic [TAG_W-1:0] req_tag1;
    logic req_bank1;
    logic req_hit1;
    logic [WAY_W-1:0] hit_way1;
    logic [WAY_W-1:0] victim_way1;
    logic victim_dirty1;

    logic accept0;
    logic accept1;
    logic bank_accept [0:BANK_COUNT-1];
    logic bank_req_owner [0:BANK_COUNT-1];
    logic bank_req_write [0:BANK_COUNT-1];
    logic [ADDR_W-1:0] bank_req_word_addr [0:BANK_COUNT-1];
    logic [3:0] bank_req_wmask [0:BANK_COUNT-1];
    logic [WIDTH-1:0] bank_req_wdata [0:BANK_COUNT-1];
    logic [OFFSET_W-1:0] bank_req_offset [0:BANK_COUNT-1];
    logic [INDEX_W-1:0] bank_req_index [0:BANK_COUNT-1];
    logic [TAG_W-1:0] bank_req_tag [0:BANK_COUNT-1];
    logic bank_req_hit [0:BANK_COUNT-1];
    logic [WAY_W-1:0] bank_hit_way [0:BANK_COUNT-1];
    logic [WAY_W-1:0] bank_victim_way [0:BANK_COUNT-1];
    logic bank_victim_dirty [0:BANK_COUNT-1];

    logic mem_req_valid [0:BANK_COUNT-1];
    logic mem_req_ready [0:BANK_COUNT-1];
    logic mem_req_write [0:BANK_COUNT-1];
    logic [ADDR_W-1:0] mem_req_word_addr [0:BANK_COUNT-1];
    logic [3:0] mem_req_wmask [0:BANK_COUNT-1];
    logic [WIDTH-1:0] mem_req_wdata [0:BANK_COUNT-1];
    logic mem_resp_valid [0:BANK_COUNT-1];
    logic [WIDTH-1:0] mem_resp_rdata [0:BANK_COUNT-1];

    logic [31:0] hit_count;
    logic [31:0] miss_count;
    logic [31:0] writeback_count;
    logic [31:0] bank_conflict_count;

    // Legacy bank-0 aliases keep useful waveform names stable.
    dcache_state_t state_q;
    logic [ADDR_W-1:0] pending_line_base_q;
    logic [OFFSET_W-1:0] pending_offset_q;
    logic [INDEX_W-1:0] pending_index_q;
    logic [TAG_W-1:0] pending_tag_q;
    logic [WAY_W-1:0] pending_way_q;
    logic pending_is_store_q;
    logic [3:0] pending_wmask_q;
    logic [WIDTH-1:0] pending_wdata_q;
    logic [ADDR_W-1:0] victim_line_base_q;
    logic [OFFSET_W-1:0] line_word_q;
    logic refill_started_q;

    assign state_q = bank_state_q[0];
    assign pending_line_base_q = bank_pending_line_base_q[0];
    assign pending_offset_q = bank_pending_offset_q[0];
    assign pending_index_q = bank_pending_index_q[0];
    assign pending_tag_q = bank_pending_tag_q[0];
    assign pending_way_q = bank_pending_way_q[0];
    assign pending_is_store_q = bank_pending_is_store_q[0];
    assign pending_wmask_q = bank_pending_wmask_q[0];
    assign pending_wdata_q = bank_pending_wdata_q[0];
    assign victim_line_base_q = bank_victim_line_base_q[0];
    assign line_word_q = bank_line_word_q[0];
    assign refill_started_q = bank_mem_req_sent_q[0];

    function automatic logic [WIDTH-1:0] merge_word(
        input logic [WIDTH-1:0] base_word,
        input logic [WIDTH-1:0] write_data,
        input logic [3:0] write_mask
    );
        logic [WIDTH-1:0] merged;
    begin
        merged = base_word;
        for (int b = 0; b < 4; b++) begin
            if (write_mask[b]) begin
                merged[b*8 +: 8] = write_data[b*8 +: 8];
            end
        end
        merge_word = merged;
    end
    endfunction

    assign req1_valid_safe = (req1_valid === 1'b1);
    assign req_offset0 = req_word_addr[OFFSET_W-1:0];
    assign req_index0 = req_word_addr[OFFSET_W +: INDEX_W];
    assign req_tag0 = req_word_addr[ADDR_W-1:OFFSET_W+INDEX_W];
    assign req_bank0 = req_index0[0];
    assign req_offset1 = req1_word_addr[OFFSET_W-1:0];
    assign req_index1 = req1_word_addr[OFFSET_W +: INDEX_W];
    assign req_tag1 = req1_word_addr[ADDR_W-1:OFFSET_W+INDEX_W];
    assign req_bank1 = req_index1[0];

    always_comb begin
        req_hit0 = 1'b0;
        hit_way0 = '0;
        victim_way0 = replace_way[req_index0];
        for (int w = 0; w < WAY_COUNT; w++) begin
            if (line_valid[req_index0][w] &&
                (line_tag[req_index0][w] == req_tag0)) begin
                req_hit0 = 1'b1;
                hit_way0 = w;
            end
            if (!line_valid[req_index0][w]) begin
                victim_way0 = w;
            end
        end
        victim_dirty0 = line_valid[req_index0][victim_way0] &&
                        line_dirty[req_index0][victim_way0];

        req_hit1 = 1'b0;
        hit_way1 = '0;
        victim_way1 = replace_way[req_index1];
        for (int w = 0; w < WAY_COUNT; w++) begin
            if (line_valid[req_index1][w] &&
                (line_tag[req_index1][w] == req_tag1)) begin
                req_hit1 = 1'b1;
                hit_way1 = w;
            end
            if (!line_valid[req_index1][w]) begin
                victim_way1 = w;
            end
        end
        victim_dirty1 = line_valid[req_index1][victim_way1] &&
                        line_dirty[req_index1][victim_way1];
    end

    assign req_ready = (bank_state_q[req_bank0] == DCACHE_IDLE);
    assign accept0 = req_valid && req_ready;
    assign req1_ready =
        (bank_state_q[req_bank1] == DCACHE_IDLE) &&
        !(req_valid && req_ready && (req_bank0 == req_bank1));
    assign accept1 = req1_valid_safe && req1_ready;

    always_comb begin
        for (int b = 0; b < BANK_COUNT; b++) begin
            bank_accept[b] = 1'b0;
            bank_req_owner[b] = 1'b0;
            bank_req_write[b] = 1'b0;
            bank_req_word_addr[b] = '0;
            bank_req_wmask[b] = '0;
            bank_req_wdata[b] = '0;
            bank_req_offset[b] = '0;
            bank_req_index[b] = '0;
            bank_req_tag[b] = '0;
            bank_req_hit[b] = 1'b0;
            bank_hit_way[b] = '0;
            bank_victim_way[b] = '0;
            bank_victim_dirty[b] = 1'b0;
        end

        if (accept0) begin
            bank_accept[req_bank0] = 1'b1;
            bank_req_owner[req_bank0] = 1'b0;
            bank_req_write[req_bank0] = req_write;
            bank_req_word_addr[req_bank0] = req_word_addr;
            bank_req_wmask[req_bank0] = req_wmask;
            bank_req_wdata[req_bank0] = req_wdata;
            bank_req_offset[req_bank0] = req_offset0;
            bank_req_index[req_bank0] = req_index0;
            bank_req_tag[req_bank0] = req_tag0;
            bank_req_hit[req_bank0] = req_hit0;
            bank_hit_way[req_bank0] = hit_way0;
            bank_victim_way[req_bank0] = victim_way0;
            bank_victim_dirty[req_bank0] = victim_dirty0;
        end
        if (accept1) begin
            bank_accept[req_bank1] = 1'b1;
            bank_req_owner[req_bank1] = 1'b1;
            bank_req_write[req_bank1] = req1_write;
            bank_req_word_addr[req_bank1] = req1_word_addr;
            bank_req_wmask[req_bank1] = req1_wmask;
            bank_req_wdata[req_bank1] = req1_wdata;
            bank_req_offset[req_bank1] = req_offset1;
            bank_req_index[req_bank1] = req_index1;
            bank_req_tag[req_bank1] = req_tag1;
            bank_req_hit[req_bank1] = req_hit1;
            bank_hit_way[req_bank1] = hit_way1;
            bank_victim_way[req_bank1] = victim_way1;
            bank_victim_dirty[req_bank1] = victim_dirty1;
        end
    end

    generate
        for (genvar b = 0; b < BANK_COUNT; b++) begin : gen_mem_request
            assign mem_req_valid[b] =
                ((bank_state_q[b] == DCACHE_WRITEBACK_REQ) ||
                 (bank_state_q[b] == DCACHE_REFILL_REQ)) &&
                !bank_mem_req_sent_q[b];
            assign mem_req_write[b] =
                (bank_state_q[b] == DCACHE_WRITEBACK_REQ);
            assign mem_req_word_addr[b] =
                mem_req_write[b] ?
                (bank_victim_line_base_q[b] + bank_line_word_q[b]) :
                (bank_pending_line_base_q[b] + bank_line_word_q[b]);
            assign mem_req_wmask[b] =
                mem_req_write[b] ? 4'b1111 : 4'b0000;
            assign mem_req_wdata[b] =
                mem_req_write[b] ?
                line_data[bank_pending_index_q[b]]
                         [bank_pending_way_q[b]]
                         [bank_line_word_q[b]] : '0;
        end
    endgenerate

    data_memory #(
        .MEM_WORDS(MEM_WORDS),
        .RESPONSE_LATENCY(MEMORY_RESPONSE_LATENCY)
    ) u_data_memory (
        .clk           (clk),
        .rst_n         (rst_n),
        .req_valid     (mem_req_valid[0]),
        .req_ready     (mem_req_ready[0]),
        .req_write     (mem_req_write[0]),
        .req_word_addr (mem_req_word_addr[0]),
        .req_wmask     (mem_req_wmask[0]),
        .req_wdata     (mem_req_wdata[0]),
        .resp_valid    (mem_resp_valid[0]),
        .resp_rdata    (mem_resp_rdata[0]),
        .req1_valid    (mem_req_valid[1]),
        .req1_ready    (mem_req_ready[1]),
        .req1_write    (mem_req_write[1]),
        .req1_word_addr(mem_req_word_addr[1]),
        .req1_wmask    (mem_req_wmask[1]),
        .req1_wdata    (mem_req_wdata[1]),
        .resp1_valid   (mem_resp_valid[1]),
        .resp1_rdata   (mem_resp_rdata[1])
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            resp1_valid <= 1'b0;
            resp1_rdata <= '0;
            hit_count <= '0;
            miss_count <= '0;
            writeback_count <= '0;
            bank_conflict_count <= '0;

            for (int b = 0; b < BANK_COUNT; b++) begin
                bank_state_q[b] <= DCACHE_IDLE;
                bank_pending_line_base_q[b] <= '0;
                bank_pending_offset_q[b] <= '0;
                bank_pending_index_q[b] <= '0;
                bank_pending_tag_q[b] <= '0;
                bank_pending_way_q[b] <= '0;
                bank_pending_is_store_q[b] <= 1'b0;
                bank_pending_wmask_q[b] <= '0;
                bank_pending_wdata_q[b] <= '0;
                bank_pending_owner_q[b] <= 1'b0;
                bank_victim_line_base_q[b] <= '0;
                bank_line_word_q[b] <= '0;
                bank_mem_req_sent_q[b] <= 1'b0;
            end

            for (int s = 0; s < SET_COUNT; s++) begin
                replace_way[s] <= '0;
                for (int w = 0; w < WAY_COUNT; w++) begin
                    line_valid[s][w] <= 1'b0;
                    line_dirty[s][w] <= 1'b0;
                    line_tag[s][w] <= '0;
                    for (int o = 0; o < WORDS_PER_LINE; o++) begin
                        line_data[s][w][o] <= '0;
                    end
                end
            end
        end else begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            resp1_valid <= 1'b0;
            resp1_rdata <= '0;

            hit_count <= hit_count +
                (bank_accept[0] && bank_req_hit[0]) +
                (bank_accept[1] && bank_req_hit[1]);
            miss_count <= miss_count +
                (bank_accept[0] && !bank_req_hit[0]) +
                (bank_accept[1] && !bank_req_hit[1]);
            writeback_count <= writeback_count +
                ((bank_state_q[0] == DCACHE_WRITEBACK_WAIT) &&
                 mem_resp_valid[0] &&
                 (bank_line_word_q[0] == WORDS_PER_LINE-1)) +
                ((bank_state_q[1] == DCACHE_WRITEBACK_WAIT) &&
                 mem_resp_valid[1] &&
                 (bank_line_word_q[1] == WORDS_PER_LINE-1));
            if (req_valid && req1_valid_safe &&
                (req_bank0 == req_bank1)) begin
                bank_conflict_count <= bank_conflict_count + 1'b1;
            end

            for (int b = 0; b < BANK_COUNT; b++) begin
                unique case (bank_state_q[b])
                    DCACHE_IDLE: begin
                        bank_mem_req_sent_q[b] <= 1'b0;
                        bank_line_word_q[b] <= '0;

                        if (bank_accept[b]) begin
                            if (bank_req_hit[b]) begin
                                replace_way[bank_req_index[b]] <=
                                    bank_hit_way[b] + 1'b1;
                                if (bank_req_write[b]) begin
                                    line_data[bank_req_index[b]]
                                             [bank_hit_way[b]]
                                             [bank_req_offset[b]] <=
                                        merge_word(
                                            line_data[bank_req_index[b]]
                                                     [bank_hit_way[b]]
                                                     [bank_req_offset[b]],
                                            bank_req_wdata[b],
                                            bank_req_wmask[b]);
                                    line_dirty[bank_req_index[b]]
                                              [bank_hit_way[b]] <= 1'b1;
                                    if (bank_req_owner[b]) begin
                                        resp1_valid <= 1'b1;
                                        resp1_rdata <= '0;
                                    end else begin
                                        resp_valid <= 1'b1;
                                        resp_rdata <= '0;
                                    end
                                end else if (bank_req_owner[b]) begin
                                    resp1_valid <= 1'b1;
                                    resp1_rdata <=
                                        line_data[bank_req_index[b]]
                                                 [bank_hit_way[b]]
                                                 [bank_req_offset[b]];
                                end else begin
                                    resp_valid <= 1'b1;
                                    resp_rdata <=
                                        line_data[bank_req_index[b]]
                                                 [bank_hit_way[b]]
                                                 [bank_req_offset[b]];
                                end
                            end else begin
                                bank_pending_line_base_q[b] <=
                                    {bank_req_word_addr[b][ADDR_W-1:OFFSET_W],
                                     {OFFSET_W{1'b0}}};
                                bank_pending_offset_q[b] <= bank_req_offset[b];
                                bank_pending_index_q[b] <= bank_req_index[b];
                                bank_pending_tag_q[b] <= bank_req_tag[b];
                                bank_pending_way_q[b] <= bank_victim_way[b];
                                bank_pending_is_store_q[b] <=
                                    bank_req_write[b];
                                bank_pending_wmask_q[b] <= bank_req_wmask[b];
                                bank_pending_wdata_q[b] <= bank_req_wdata[b];
                                bank_pending_owner_q[b] <= bank_req_owner[b];
                                bank_victim_line_base_q[b] <=
                                    {line_tag[bank_req_index[b]]
                                             [bank_victim_way[b]],
                                     bank_req_index[b],
                                     {OFFSET_W{1'b0}}};
                                bank_state_q[b] <= bank_victim_dirty[b] ?
                                    DCACHE_WRITEBACK_REQ :
                                    DCACHE_REFILL_REQ;
                            end
                        end
                    end

                    DCACHE_WRITEBACK_REQ: begin
                        if (mem_req_valid[b] && mem_req_ready[b]) begin
                            bank_mem_req_sent_q[b] <= 1'b1;
                            bank_state_q[b] <= DCACHE_WRITEBACK_WAIT;
                        end
                    end

                    DCACHE_WRITEBACK_WAIT: begin
                        if (mem_resp_valid[b]) begin
                            bank_mem_req_sent_q[b] <= 1'b0;
                            if (bank_line_word_q[b] == WORDS_PER_LINE-1) begin
                                bank_line_word_q[b] <= '0;
                                bank_state_q[b] <= DCACHE_REFILL_REQ;
                            end else begin
                                bank_line_word_q[b] <=
                                    bank_line_word_q[b] + 1'b1;
                                bank_state_q[b] <= DCACHE_WRITEBACK_REQ;
                            end
                        end
                    end

                    DCACHE_REFILL_REQ: begin
                        if (mem_req_valid[b] && mem_req_ready[b]) begin
                            bank_mem_req_sent_q[b] <= 1'b1;
                            bank_state_q[b] <= DCACHE_REFILL_WAIT;
                        end
                    end

                    DCACHE_REFILL_WAIT: begin
                        if (mem_resp_valid[b]) begin
                            bank_mem_req_sent_q[b] <= 1'b0;
                            line_data[bank_pending_index_q[b]]
                                     [bank_pending_way_q[b]]
                                     [bank_line_word_q[b]] <=
                                mem_resp_rdata[b];

                            if (bank_line_word_q[b] == WORDS_PER_LINE-1) begin
                                line_valid[bank_pending_index_q[b]]
                                          [bank_pending_way_q[b]] <= 1'b1;
                                line_tag[bank_pending_index_q[b]]
                                        [bank_pending_way_q[b]] <=
                                    bank_pending_tag_q[b];
                                replace_way[bank_pending_index_q[b]] <=
                                    bank_pending_way_q[b] + 1'b1;

                                if (bank_pending_is_store_q[b]) begin
                                    line_data[bank_pending_index_q[b]]
                                             [bank_pending_way_q[b]]
                                             [bank_pending_offset_q[b]] <=
                                        merge_word(
                                            (bank_line_word_q[b] ==
                                             bank_pending_offset_q[b]) ?
                                                mem_resp_rdata[b] :
                                                line_data[
                                                    bank_pending_index_q[b]]
                                                    [bank_pending_way_q[b]]
                                                    [bank_pending_offset_q[b]],
                                            bank_pending_wdata_q[b],
                                            bank_pending_wmask_q[b]);
                                    line_dirty[bank_pending_index_q[b]]
                                              [bank_pending_way_q[b]] <= 1'b1;
                                    if (bank_pending_owner_q[b]) begin
                                        resp1_valid <= 1'b1;
                                        resp1_rdata <= '0;
                                    end else begin
                                        resp_valid <= 1'b1;
                                        resp_rdata <= '0;
                                    end
                                end else begin
                                    line_dirty[bank_pending_index_q[b]]
                                              [bank_pending_way_q[b]] <= 1'b0;
                                    if (bank_pending_owner_q[b]) begin
                                        resp1_valid <= 1'b1;
                                        resp1_rdata <=
                                            (bank_line_word_q[b] ==
                                             bank_pending_offset_q[b]) ?
                                                mem_resp_rdata[b] :
                                                line_data[
                                                    bank_pending_index_q[b]]
                                                    [bank_pending_way_q[b]]
                                                    [bank_pending_offset_q[b]];
                                    end else begin
                                        resp_valid <= 1'b1;
                                        resp_rdata <=
                                            (bank_line_word_q[b] ==
                                             bank_pending_offset_q[b]) ?
                                                mem_resp_rdata[b] :
                                                line_data[
                                                    bank_pending_index_q[b]]
                                                    [bank_pending_way_q[b]]
                                                    [bank_pending_offset_q[b]];
                                    end
                                end

                                bank_line_word_q[b] <= '0;
                                bank_state_q[b] <= DCACHE_IDLE;
                            end else begin
                                bank_line_word_q[b] <=
                                    bank_line_word_q[b] + 1'b1;
                                bank_state_q[b] <= DCACHE_REFILL_REQ;
                            end
                        end
                    end

                    default: bank_state_q[b] <= DCACHE_IDLE;
                endcase
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        assert ((SET_COUNT >= BANK_COUNT) &&
                ((SET_COUNT % BANK_COUNT) == 0))
            else $error("[ASSERT:DCACHE] two-bank cache requires an even set count");
    end

    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (!(accept0 && accept1 && (req_bank0 == req_bank1)))
                else $error("[ASSERT:DCACHE] accepted two requests into one bank");
        end
    end
`endif

endmodule
