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
    input  defines_pkg::lsu_control_t      control_signal,
    input  defines_pkg::rs_datapath_t      datapath,
    output logic                           resp_valid,
    output defines_pkg::rob_tag_t          resp_tag,
    output defines_pkg::preg_t             resp_preg,
    output logic                           resp_reg_write,
    output logic [defines_pkg::WIDTH-1:0]  resp_result
);
    import defines_pkg::*;

    localparam int ADDR_W = $clog2(MEM_WORDS);

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
    logic [3:0] store_wmask;
    logic [WIDTH-1:0] store_wdata;
    logic             pending_squashed;
    cp_mask_t         pending_spec_mask_next;
    logic             mem_req_valid;
    logic             mem_req_ready;
    logic             mem_resp_valid;
    logic [WIDTH-1:0] mem_resp_rdata;

    assign pending_spec_mask_next =
        resolve_en ? (pending_datapath.speculation_mask & ~(cp_mask_t'(1'b1) << resolve_checkpoint_id)) :
                     pending_datapath.speculation_mask;
    assign pending_squashed =
        squash_en && pending_spec_mask_next[squash_checkpoint_id];

    assign eff_addr  = pending_datapath.src1_value + pending_datapath.imm;
    assign word_addr = eff_addr[ADDR_W+1:2];
    assign byte_off  = eff_addr[1:0];
    assign req_ready = !pending_valid && !resp_valid;
    assign mem_req_valid = pending_valid &&
                           !pending_squashed &&
                           !pending_mem_req_sent;
    assign curr_word = mem_resp_rdata;

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
        .req_write    (pending_control.mem_write),
        .req_word_addr(word_addr),
        .req_wmask    (store_wmask),
        .req_wdata    (store_wdata),
        .resp_valid   (mem_resp_valid),
        .resp_rdata   (mem_resp_rdata)
    );

    always_comb begin
        unique case (byte_off)
            2'd0: load_byte = curr_word[7:0];
            2'd1: load_byte = curr_word[15:8];
            2'd2: load_byte = curr_word[23:16];
            default: load_byte = curr_word[31:24];
        endcase
    end

    always_comb begin
        unique case (byte_off)
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
        if (pending_control.mem_write) begin
            unique case (pending_control.funct3)
                3'b000: begin                            // SB
                    unique case (byte_off)
                        2'd0: store_wmask = 4'b0001;
                        2'd1: store_wmask = 4'b0010;
                        2'd2: store_wmask = 4'b0100;
                        default: store_wmask = 4'b1000;
                    endcase
                    store_wdata = {4{pending_datapath.src2_value[7:0]}} << (byte_off * 8);
                end
                3'b001: begin                            // SH
                    unique case (byte_off)
                        2'd0: store_wmask = 4'b0011;
                        2'd1: store_wmask = 4'b0110;
                        2'd2: store_wmask = 4'b1100;
                        default: store_wmask = 4'b0000;
                    endcase
                    store_wdata = {16'b0, pending_datapath.src2_value[15:0]} << (byte_off * 8);
                end
                3'b010: begin                            // SW
                    store_wmask = 4'b1111;
                    store_wdata = pending_datapath.src2_value;
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
            pending_control <= '0;
            pending_datapath <= '0;
            resp_valid     <= 1'b0;
            resp_tag       <= '0;
            resp_preg      <= '0;
            resp_reg_write <= 1'b0;
            resp_result    <= '0;
        end else begin
            resp_valid     <= 1'b0;
            resp_tag       <= '0;
            resp_preg      <= '0;
            resp_reg_write <= 1'b0;
            resp_result    <= '0;

            if (pending_valid && pending_squashed) begin
                pending_valid <= 1'b0;
                pending_mem_req_sent <= 1'b0;
                pending_control <= '0;
                pending_datapath <= '0;
            end else if (mem_resp_valid) begin
                if (pending_valid) begin
                    resp_valid     <= 1'b1;
                    resp_tag       <= pending_datapath.rob_tag;
                    resp_preg      <= pending_datapath.new_des_preg;
                    resp_reg_write <= pending_control.mem_read &&
                                      (pending_datapath.new_des_preg != '0);
                    resp_result    <= pending_control.mem_read ? load_result_comb : '0;

                    pending_valid <= 1'b0;
                    pending_mem_req_sent <= 1'b0;
                    pending_control <= '0;
                    pending_datapath <= '0;
                end
            end else if (mem_req_valid && mem_req_ready) begin
                pending_mem_req_sent <= 1'b1;
            end

            if (req_valid && req_ready) begin
                pending_valid <= 1'b1;
                pending_mem_req_sent <= 1'b0;
                pending_control <= control_signal;
                pending_datapath <= datapath;
            end else if (pending_valid && resolve_en) begin
                pending_datapath.speculation_mask <= pending_spec_mask_next;
            end
        end
    end

endmodule
