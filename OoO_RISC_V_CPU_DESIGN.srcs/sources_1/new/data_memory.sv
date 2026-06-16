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
    output logic [defines_pkg::WIDTH-1:0] resp_rdata
);
    import defines_pkg::*;

    localparam int LATENCY_W = (RESPONSE_LATENCY <= 1) ? 1 : $clog2(RESPONSE_LATENCY);
    localparam int LATENCY_COUNT_INIT = (RESPONSE_LATENCY <= 1) ? 0 : (RESPONSE_LATENCY - 2);

    logic [WIDTH-1:0] mem [0:MEM_WORDS-1];
    logic busy_q;
    logic [LATENCY_W-1:0] latency_q;
    logic pending_write_q;
    logic [$clog2(MEM_WORDS)-1:0] pending_word_addr_q;
    logic [3:0] pending_wmask_q;
    logic [WIDTH-1:0] pending_wdata_q;

    assign req_ready = !busy_q;

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
            for (int i = 0; i < MEM_WORDS; i++) begin
                mem[i] <= '0;
            end
        end else begin
            resp_valid <= 1'b0;
            resp_rdata <= '0;

            if (busy_q) begin
                if (latency_q == '0) begin
                    resp_valid <= 1'b1;
                    resp_rdata <= mem[pending_word_addr_q];

                    if (pending_write_q) begin
                        for (int b = 0; b < 4; b++) begin
                            if (pending_wmask_q[b]) begin
                                mem[pending_word_addr_q][b*8 +: 8] <= pending_wdata_q[b*8 +: 8];
                            end
                        end
                    end

                    busy_q <= 1'b0;
                    latency_q <= '0;
                    pending_write_q <= 1'b0;
                    pending_word_addr_q <= '0;
                    pending_wmask_q <= '0;
                    pending_wdata_q <= '0;
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
                                mem[req_word_addr][b*8 +: 8] <= req_wdata[b*8 +: 8];
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
        end
    end

endmodule
