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
    output logic [defines_pkg::WIDTH-1:0] resp_rdata
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);
    localparam int SET_COUNT = LINE_COUNT / WAY_COUNT;
    localparam int OFFSET_W = $clog2(WORDS_PER_LINE);
    localparam int INDEX_W = $clog2(SET_COUNT);
    localparam int TAG_W = ADDR_W - INDEX_W - OFFSET_W;
    localparam int WAY_W = (WAY_COUNT <= 1) ? 1 : $clog2(WAY_COUNT);

    typedef enum logic [2:0] {
        DCACHE_IDLE,
        DCACHE_WRITEBACK_REQ,
        DCACHE_WRITEBACK_WAIT,
        DCACHE_REFILL_REQ,
        DCACHE_REFILL_WAIT
    } dcache_state_t;

    dcache_state_t state_q;
    logic [WIDTH-1:0] line_data [0:SET_COUNT-1][0:WAY_COUNT-1][0:WORDS_PER_LINE-1];
    logic [TAG_W-1:0] line_tag [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic             line_valid [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic             line_dirty [0:SET_COUNT-1][0:WAY_COUNT-1];
    logic [WAY_W-1:0] replace_way [0:SET_COUNT-1];

    logic [OFFSET_W-1:0] req_offset;
    logic [INDEX_W-1:0]  req_index;
    logic [TAG_W-1:0]    req_tag;
    logic                req_hit;
    logic [WAY_W-1:0]    hit_way;
    logic [WAY_W-1:0]    victim_way;
    logic                victim_dirty;

    logic [$clog2(MEM_WORDS)-1:0] pending_line_base_q;
    logic [OFFSET_W-1:0]          pending_offset_q;
    logic [INDEX_W-1:0]           pending_index_q;
    logic [TAG_W-1:0]             pending_tag_q;
    logic [WAY_W-1:0]             pending_way_q;
    logic                         pending_is_store_q;
    logic [3:0]                   pending_wmask_q;
    logic [WIDTH-1:0]             pending_wdata_q;
    logic [$clog2(MEM_WORDS)-1:0] victim_line_base_q;

    logic [OFFSET_W-1:0]          line_word_q;
    logic                         refill_started_q;

    logic                         mem_req_valid;
    logic                         mem_req_ready;
    logic                         mem_req_write;
    logic [$clog2(MEM_WORDS)-1:0] mem_req_word_addr;
    logic [3:0]                   mem_req_wmask;
    logic [WIDTH-1:0]             mem_req_wdata;
    logic                         mem_resp_valid;
    logic [WIDTH-1:0]             mem_resp_rdata;

    logic [31:0] hit_count;
    logic [31:0] miss_count;
    logic [31:0] writeback_count;

    assign req_offset = req_word_addr[OFFSET_W-1:0];
    assign req_index = req_word_addr[OFFSET_W +: INDEX_W];
    assign req_tag = req_word_addr[ADDR_W-1:OFFSET_W+INDEX_W];
    assign req_ready = (state_q == DCACHE_IDLE);

    assign mem_req_valid = ((state_q == DCACHE_WRITEBACK_REQ) ||
                            (state_q == DCACHE_REFILL_REQ)) &&
                           !refill_started_q;
    assign mem_req_write = (state_q == DCACHE_WRITEBACK_REQ);
    assign mem_req_word_addr = mem_req_write ? (victim_line_base_q + line_word_q) :
                                               (pending_line_base_q + line_word_q);
    assign mem_req_wmask = mem_req_write ? 4'b1111 : 4'b0000;
    assign mem_req_wdata = mem_req_write ? line_data[pending_index_q][pending_way_q][line_word_q] : '0;

    data_memory #(
        .MEM_WORDS(MEM_WORDS),
        .RESPONSE_LATENCY(MEMORY_RESPONSE_LATENCY)
    ) u_data_memory (
        .clk          (clk),
        .rst_n        (rst_n),
        .req_valid    (mem_req_valid),
        .req_ready    (mem_req_ready),
        .req_write    (mem_req_write),
        .req_word_addr(mem_req_word_addr),
        .req_wmask    (mem_req_wmask),
        .req_wdata    (mem_req_wdata),
        .resp_valid   (mem_resp_valid),
        .resp_rdata   (mem_resp_rdata)
    );

    function automatic logic [WIDTH-1:0] merge_word;
        input logic [WIDTH-1:0] base_word;
        input logic [WIDTH-1:0] write_data;
        input logic [3:0]       write_mask;
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

    always_comb begin
        req_hit = 1'b0;
        hit_way = '0;
        for (int w = 0; w < WAY_COUNT; w++) begin
            if (line_valid[req_index][w] && (line_tag[req_index][w] == req_tag)) begin
                req_hit = 1'b1;
                hit_way = w;
            end
        end
    end

    always_comb begin
        victim_way = replace_way[req_index];
        for (int w = 0; w < WAY_COUNT; w++) begin
            if (!line_valid[req_index][w]) begin
                victim_way = w;
            end
        end
        victim_dirty = line_valid[req_index][victim_way] && line_dirty[req_index][victim_way];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= DCACHE_IDLE;
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            pending_line_base_q <= '0;
            pending_offset_q <= '0;
            pending_index_q <= '0;
            pending_tag_q <= '0;
            pending_way_q <= '0;
            pending_is_store_q <= 1'b0;
            pending_wmask_q <= '0;
            pending_wdata_q <= '0;
            victim_line_base_q <= '0;
            line_word_q <= '0;
            refill_started_q <= 1'b0;
            hit_count <= '0;
            miss_count <= '0;
            writeback_count <= '0;
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

            unique case (state_q)
                DCACHE_IDLE: begin
                    refill_started_q <= 1'b0;
                    line_word_q <= '0;

                    if (req_valid && req_ready) begin
                        if (req_hit) begin
                            hit_count <= hit_count + 1'b1;
                            replace_way[req_index] <= ~hit_way;
                            if (req_write) begin
                                line_data[req_index][hit_way][req_offset] <=
                                    merge_word(line_data[req_index][hit_way][req_offset], req_wdata, req_wmask);
                                line_dirty[req_index][hit_way] <= 1'b1;
                                resp_valid <= 1'b1;
                                resp_rdata <= '0;
                            end else begin
                                resp_valid <= 1'b1;
                                resp_rdata <= line_data[req_index][hit_way][req_offset];
                            end
                        end else begin
                            miss_count <= miss_count + 1'b1;
                            pending_line_base_q <= {req_word_addr[ADDR_W-1:OFFSET_W], {OFFSET_W{1'b0}}};
                            pending_offset_q <= req_offset;
                            pending_index_q <= req_index;
                            pending_tag_q <= req_tag;
                            pending_way_q <= victim_way;
                            pending_is_store_q <= req_write;
                            pending_wmask_q <= req_wmask;
                            pending_wdata_q <= req_wdata;
                            victim_line_base_q <= {line_tag[req_index][victim_way], req_index, {OFFSET_W{1'b0}}};
                            line_word_q <= '0;
                            refill_started_q <= 1'b0;

                            if (victim_dirty) begin
                                state_q <= DCACHE_WRITEBACK_REQ;
                            end else begin
                                state_q <= DCACHE_REFILL_REQ;
                            end
                        end
                    end
                end

                DCACHE_WRITEBACK_REQ: begin
                    if (mem_req_ready) begin
                        refill_started_q <= 1'b1;
                        state_q <= DCACHE_WRITEBACK_WAIT;
                    end
                end

                DCACHE_WRITEBACK_WAIT: begin
                    if (mem_resp_valid) begin
                        refill_started_q <= 1'b0;
                        if (line_word_q == (WORDS_PER_LINE - 1)) begin
                            writeback_count <= writeback_count + 1'b1;
                            line_word_q <= '0;
                            state_q <= DCACHE_REFILL_REQ;
                        end else begin
                            line_word_q <= line_word_q + 1'b1;
                            state_q <= DCACHE_WRITEBACK_REQ;
                        end
                    end
                end

                DCACHE_REFILL_REQ: begin
                    if (mem_req_ready) begin
                        refill_started_q <= 1'b1;
                        state_q <= DCACHE_REFILL_WAIT;
                    end
                end

                DCACHE_REFILL_WAIT: begin
                    if (mem_resp_valid) begin
                        refill_started_q <= 1'b0;
                        line_data[pending_index_q][pending_way_q][line_word_q] <= mem_resp_rdata;

                        if (line_word_q == (WORDS_PER_LINE - 1)) begin
                            line_valid[pending_index_q][pending_way_q] <= 1'b1;
                            line_tag[pending_index_q][pending_way_q] <= pending_tag_q;
                            replace_way[pending_index_q] <= ~pending_way_q;

                            if (pending_is_store_q) begin
                                line_data[pending_index_q][pending_way_q][pending_offset_q] <=
                                    merge_word(
                                        (line_word_q == pending_offset_q) ? mem_resp_rdata :
                                                                            line_data[pending_index_q][pending_way_q][pending_offset_q],
                                        pending_wdata_q,
                                        pending_wmask_q
                                    );
                                line_dirty[pending_index_q][pending_way_q] <= 1'b1;
                                resp_valid <= 1'b1;
                                resp_rdata <= '0;
                            end else begin
                                line_dirty[pending_index_q][pending_way_q] <= 1'b0;
                                resp_valid <= 1'b1;
                                resp_rdata <= (line_word_q == pending_offset_q) ? mem_resp_rdata :
                                                                                   line_data[pending_index_q][pending_way_q][pending_offset_q];
                            end

                            line_word_q <= '0;
                            state_q <= DCACHE_IDLE;
                        end else begin
                            line_word_q <= line_word_q + 1'b1;
                            state_q <= DCACHE_REFILL_REQ;
                        end
                    end
                end

                default: begin
                    state_q <= DCACHE_IDLE;
                end
            endcase
        end
    end

endmodule
