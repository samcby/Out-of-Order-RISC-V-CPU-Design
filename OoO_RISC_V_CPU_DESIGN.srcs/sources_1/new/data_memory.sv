// Dual-channel backing memory model behind the banked data cache.
//
// Each ready/valid channel owns one independent outstanding transaction slot.
// The storage array is shared, so two requests to different words may progress
// concurrently. The cache prevents conflicting same-bank accesses; a simulation
// assertion catches unsupported same-word writes from both channels.
module data_memory #(
    parameter int MEM_WORDS = 256,
    parameter int RESPONSE_LATENCY = 1
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

    localparam int LATENCY_W =
        (RESPONSE_LATENCY <= 1) ? 1 : $clog2(RESPONSE_LATENCY);
    localparam int LATENCY_COUNT_INIT =
        (RESPONSE_LATENCY <= 1) ? 0 : (RESPONSE_LATENCY - 2);

    logic [WIDTH-1:0] mem [0:MEM_WORDS-1];

    // Port-0 names are retained for compatibility with existing hierarchy
    // probes and focused single-port tests.
    logic busy_q;
    logic [LATENCY_W-1:0] latency_q;
    logic pending_write_q;
    logic [$clog2(MEM_WORDS)-1:0] pending_word_addr_q;
    logic [3:0] pending_wmask_q;
    logic [WIDTH-1:0] pending_wdata_q;

    logic busy1_q;
    logic [LATENCY_W-1:0] latency1_q;
    logic pending1_write_q;
    logic [$clog2(MEM_WORDS)-1:0] pending1_word_addr_q;
    logic [3:0] pending1_wmask_q;
    logic [WIDTH-1:0] pending1_wdata_q;

    logic req1_valid_safe;
    logic port0_write_now;
    logic [$clog2(MEM_WORDS)-1:0] port0_write_addr;
    logic port1_write_now;
    logic [$clog2(MEM_WORDS)-1:0] port1_write_addr;

    assign req1_valid_safe = (req1_valid === 1'b1);
    assign req_ready = !busy_q;
    assign req1_ready = !busy1_q;

    assign port0_write_now =
        (busy_q && (latency_q == '0) && pending_write_q) ||
        (!busy_q && req_valid && req_ready &&
         (RESPONSE_LATENCY <= 1) && req_write);
    assign port0_write_addr =
        busy_q ? pending_word_addr_q : req_word_addr;
    assign port1_write_now =
        (busy1_q && (latency1_q == '0) && pending1_write_q) ||
        (!busy1_q && req1_valid_safe && req1_ready &&
         (RESPONSE_LATENCY <= 1) && req1_write);
    assign port1_write_addr =
        busy1_q ? pending1_word_addr_q : req1_word_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            busy_q <= 1'b0;
            latency_q <= '0;
            pending_write_q <= 1'b0;
            pending_word_addr_q <= '0;
            pending_wmask_q <= '0;
            pending_wdata_q <= '0;

            resp1_valid <= 1'b0;
            resp1_rdata <= '0;
            busy1_q <= 1'b0;
            latency1_q <= '0;
            pending1_write_q <= 1'b0;
            pending1_word_addr_q <= '0;
            pending1_wmask_q <= '0;
            pending1_wdata_q <= '0;

            for (int i = 0; i < MEM_WORDS; i++) begin
                mem[i] <= '0;
            end
        end else begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            resp1_valid <= 1'b0;
            resp1_rdata <= '0;

            if (busy_q) begin
                if (latency_q == '0) begin
                    resp_valid <= 1'b1;
                    resp_rdata <= mem[pending_word_addr_q];
                    if (pending_write_q) begin
                        for (int b = 0; b < 4; b++) begin
                            if (pending_wmask_q[b]) begin
                                mem[pending_word_addr_q][b*8 +: 8] <=
                                    pending_wdata_q[b*8 +: 8];
                            end
                        end
                    end
                    busy_q <= 1'b0;
                    pending_write_q <= 1'b0;
                end else begin
                    latency_q <= latency_q - 1'b1;
                end
            end else if (req_valid && req_ready) begin
                if (RESPONSE_LATENCY <= 1) begin
                    resp_valid <= 1'b1;
                    resp_rdata <= mem[req_word_addr];
                    if (req_write) begin
                        for (int b = 0; b < 4; b++) begin
                            if (req_wmask[b]) begin
                                mem[req_word_addr][b*8 +: 8] <=
                                    req_wdata[b*8 +: 8];
                            end
                        end
                    end
                end else begin
                    busy_q <= 1'b1;
                    latency_q <= LATENCY_COUNT_INIT;
                    pending_write_q <= req_write;
                    pending_word_addr_q <= req_word_addr;
                    pending_wmask_q <= req_wmask;
                    pending_wdata_q <= req_wdata;
                end
            end

            if (busy1_q) begin
                if (latency1_q == '0) begin
                    resp1_valid <= 1'b1;
                    resp1_rdata <= mem[pending1_word_addr_q];
                    if (pending1_write_q) begin
                        for (int b = 0; b < 4; b++) begin
                            if (pending1_wmask_q[b]) begin
                                mem[pending1_word_addr_q][b*8 +: 8] <=
                                    pending1_wdata_q[b*8 +: 8];
                            end
                        end
                    end
                    busy1_q <= 1'b0;
                    pending1_write_q <= 1'b0;
                end else begin
                    latency1_q <= latency1_q - 1'b1;
                end
            end else if (req1_valid_safe && req1_ready) begin
                if (RESPONSE_LATENCY <= 1) begin
                    resp1_valid <= 1'b1;
                    resp1_rdata <= mem[req1_word_addr];
                    if (req1_write) begin
                        for (int b = 0; b < 4; b++) begin
                            if (req1_wmask[b]) begin
                                mem[req1_word_addr][b*8 +: 8] <=
                                    req1_wdata[b*8 +: 8];
                            end
                        end
                    end
                end else begin
                    busy1_q <= 1'b1;
                    latency1_q <= LATENCY_COUNT_INIT;
                    pending1_write_q <= req1_write;
                    pending1_word_addr_q <= req1_word_addr;
                    pending1_wmask_q <= req1_wmask;
                    pending1_wdata_q <= req1_wdata;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n) begin
            assert (!(port0_write_now && port1_write_now &&
                      (port0_write_addr == port1_write_addr)))
                else $error("[ASSERT:DMEM] simultaneous writes target one word");
        end
    end
`endif

endmodule
