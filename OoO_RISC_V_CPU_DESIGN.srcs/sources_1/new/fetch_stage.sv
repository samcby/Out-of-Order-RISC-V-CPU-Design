module fetch_stage #(
    parameter int WIDTH = 32
)(
    input  logic             load_en,
    input  logic [WIDTH-1:0] load_addr,
    input  logic [7:0]       load_instr_byte,

    input  logic             pc_src,
    input  logic [WIDTH-1:0] pc_branch,
    input  logic             bp_update_valid,
    input  logic [WIDTH-1:0] bp_update_pc,
    input  logic             bp_update_taken,
    input  logic             bp_update_is_jalr,
    input  logic [WIDTH-1:0] bp_update_target,

    pip_if.producer out_if
);

    import defines_pkg::*;

    localparam int BHT_ENTRIES = 64;
    localparam int BHT_W = $clog2(BHT_ENTRIES);
    localparam int BTB_ENTRIES = 64;
    localparam int BTB_W = $clog2(BTB_ENTRIES);
    localparam int JALR_ENTRIES = 32;
    localparam int JALR_W = $clog2(JALR_ENTRIES);

    logic start;
    logic fetch_valid;
    logic [WIDTH-1:0] fetch_pc;
    logic [WIDTH-1:0] fetch_instr;

    logic redirect_hold_q;
    logic pc_step_en;
    logic pred_redirect_pending_q;
    logic [WIDTH-1:0] pred_redirect_target_q;
    logic jalr_wait_q;

    logic [1:0] bht [0:BHT_ENTRIES-1];
    logic [BHT_W-1:0] fetch_bht_idx;
    logic [BHT_W-1:0] update_bht_idx;
    logic [BTB_W-1:0] fetch_btb_idx;
    logic [BTB_W-1:0] update_btb_idx;

    logic [6:0] fetch_opcode;
    logic [WIDTH-1:0] fetch_imm_b;
    logic [WIDTH-1:0] fetch_imm_j;
    logic pred_taken;
    logic [WIDTH-1:0] pred_target;
    logic pred_redirect_fire;
    logic jalr_miss_fire;
    logic redirect_en_int;
    logic [WIDTH-1:0] redirect_pc_int;
    logic [JALR_W-1:0] fetch_jalr_idx;
    logic [JALR_W-1:0] update_jalr_idx;
    logic [WIDTH-JALR_W-3:0] fetch_jalr_tag;
    logic [WIDTH-JALR_W-3:0] update_jalr_tag;
    logic                    jalr_hit;
    logic                    jalr_valid [0:JALR_ENTRIES-1];
    logic [WIDTH-JALR_W-3:0] jalr_tag   [0:JALR_ENTRIES-1];
    logic [WIDTH-1:0]        jalr_target[0:JALR_ENTRIES-1];
    logic [WIDTH-BTB_W-3:0]  fetch_btb_tag;
    logic [WIDTH-BTB_W-3:0]  update_btb_tag;
    logic                    btb_hit;
    logic                    btb_valid [0:BTB_ENTRIES-1];
    logic [WIDTH-BTB_W-3:0]  btb_tag   [0:BTB_ENTRIES-1];
    logic [WIDTH-1:0]        btb_target[0:BTB_ENTRIES-1];

    always_ff @(posedge out_if.clk or negedge out_if.rst_n) begin
        if (!out_if.rst_n) begin
            start <= 1'b0;
        end else begin
            start <= 1'b1;
        end
    end

    // Hold the redirected PC for one extra cycle so the target instruction
    // survives the same-cycle front-end flush.
    always_ff @(posedge out_if.clk or negedge out_if.rst_n) begin
        if (!out_if.rst_n) begin
            redirect_hold_q <= 1'b0;
        end else begin
            if (pc_src) begin
                redirect_hold_q <= 1'b1;
            end else begin
                redirect_hold_q <= 1'b0;
            end
        end
    end

    always_ff @(posedge out_if.clk or negedge out_if.rst_n) begin
        if (!out_if.rst_n) begin
            pred_redirect_pending_q <= 1'b0;
            pred_redirect_target_q  <= '0;
            jalr_wait_q             <= 1'b0;
            for (int i = 0; i < BHT_ENTRIES; i++) begin
                bht[i] <= 2'b01;
            end
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                btb_valid[i]  <= 1'b0;
                btb_tag[i]    <= '0;
                btb_target[i] <= '0;
            end
            for (int i = 0; i < JALR_ENTRIES; i++) begin
                jalr_valid[i]  <= 1'b0;
                jalr_tag[i]    <= '0;
                jalr_target[i] <= '0;
            end
        end else begin
            if (pc_src || bp_update_valid) begin
                pred_redirect_pending_q <= 1'b0;
                jalr_wait_q             <= 1'b0;
            end else begin
                pred_redirect_pending_q <= pred_redirect_fire;
                if (pred_redirect_fire) begin
                    pred_redirect_target_q <= pred_target;
                end

                if (jalr_miss_fire) begin
                    jalr_wait_q <= 1'b1;
                end
            end

            if (bp_update_valid) begin
                if (bp_update_is_jalr && bp_update_taken) begin
                    jalr_valid[update_jalr_idx]  <= 1'b1;
                    jalr_tag[update_jalr_idx]    <= update_jalr_tag;
                    jalr_target[update_jalr_idx] <= bp_update_target;
                end else begin
                    if (bp_update_taken) begin
                        btb_valid[update_btb_idx]  <= 1'b1;
                        btb_tag[update_btb_idx]    <= update_btb_tag;
                        btb_target[update_btb_idx] <= bp_update_target;
                    end

                    unique case ({bp_update_taken, bht[update_bht_idx]})
                        3'b0_00: bht[update_bht_idx] <= 2'b00;
                        3'b0_01: bht[update_bht_idx] <= 2'b00;
                        3'b0_10: bht[update_bht_idx] <= 2'b01;
                        3'b0_11: bht[update_bht_idx] <= 2'b10;
                        3'b1_00: bht[update_bht_idx] <= 2'b01;
                        3'b1_01: bht[update_bht_idx] <= 2'b10;
                        3'b1_10: bht[update_bht_idx] <= 2'b11;
                        3'b1_11: bht[update_bht_idx] <= 2'b11;
                        default: bht[update_bht_idx] <= 2'b01;
                    endcase
                end
            end
        end
    end

    assign fetch_opcode  = fetch_instr[6:0];
    assign fetch_imm_b   = {{19{fetch_instr[31]}}, fetch_instr[31], fetch_instr[7], fetch_instr[30:25], fetch_instr[11:8], 1'b0};
    assign fetch_imm_j   = {{11{fetch_instr[31]}}, fetch_instr[31], fetch_instr[19:12], fetch_instr[20], fetch_instr[30:21], 1'b0};
    assign fetch_bht_idx = fetch_pc[BHT_W+1:2];
    assign update_bht_idx = bp_update_pc[BHT_W+1:2];
    assign fetch_btb_idx = fetch_pc[BTB_W+1:2];
    assign update_btb_idx = bp_update_pc[BTB_W+1:2];
    assign fetch_jalr_idx = fetch_pc[JALR_W+1:2];
    assign update_jalr_idx = bp_update_pc[JALR_W+1:2];
    assign fetch_btb_tag = fetch_pc[WIDTH-1:BTB_W+2];
    assign update_btb_tag = bp_update_pc[WIDTH-1:BTB_W+2];
    assign fetch_jalr_tag = fetch_pc[WIDTH-1:JALR_W+2];
    assign update_jalr_tag = bp_update_pc[WIDTH-1:JALR_W+2];
    assign btb_hit = btb_valid[fetch_btb_idx] &&
                     (btb_tag[fetch_btb_idx] == fetch_btb_tag);
    assign jalr_hit = jalr_valid[fetch_jalr_idx] &&
                      (jalr_tag[fetch_jalr_idx] == fetch_jalr_tag);

    always_comb begin
        pred_taken  = 1'b0;
        pred_target = '0;

        unique case (fetch_opcode)
            7'b1100011: begin
                pred_taken  = bht[fetch_bht_idx][1] && btb_hit;
                pred_target = btb_target[fetch_btb_idx];
            end
            7'b1101111: begin
                pred_taken  = 1'b1;
                pred_target = btb_hit ? btb_target[fetch_btb_idx] : (fetch_pc + fetch_imm_j);
            end
            7'b1100111: begin
                pred_taken  = jalr_hit;
                pred_target = jalr_target[fetch_jalr_idx];
            end
            default: begin
                pred_taken  = 1'b0;
                pred_target = '0;
            end
        endcase
    end

    assign pred_redirect_fire = fetch_valid && !load_en && out_if.ready &&
                                !pc_src && !redirect_hold_q &&
                                !pred_redirect_pending_q && !jalr_wait_q &&
                                pred_taken;

    assign jalr_miss_fire = fetch_valid && !load_en && out_if.ready &&
                            !pc_src && !redirect_hold_q &&
                            !pred_redirect_pending_q && !jalr_wait_q &&
                            (fetch_opcode == 7'b1100111) && !jalr_hit;

    assign redirect_en_int = pc_src || pred_redirect_pending_q;
    assign redirect_pc_int = pc_src ? pc_branch : pred_redirect_target_q;

    assign pc_step_en = !load_en &&
                        (redirect_en_int || (out_if.ready && !redirect_hold_q &&
                                             !pred_redirect_pending_q && !jalr_wait_q));

    pc_counter #(
        .WIDTH(WIDTH)
    ) u_pc_counter (
        .clk        (out_if.clk),
        .rst_n      (out_if.rst_n),
        .step_en    (pc_step_en),
        .redirect_en(redirect_en_int),
        .redirect_pc(redirect_pc_int),
        .valid      (fetch_valid),
        .current_pc (fetch_pc)
    );

    icache #(
        .WIDTH(WIDTH),
        .DEPTH_BYTES(ICACHE_BYTES)
    ) u_icache (
        .clk            (out_if.clk),
        .rst_n          (out_if.rst_n),
        .start          (start),
        .load_en        (load_en),
        .load_addr      (load_addr),
        .load_instr_byte(load_instr_byte),
        .addr           (fetch_pc),
        .instr          (fetch_instr)
    );

    assign out_if.valid            = fetch_valid && !load_en &&
                                     !pc_src && !redirect_hold_q &&
                                     !pred_redirect_pending_q &&
                                     !jalr_wait_q;
    assign out_if.data.pc          = fetch_pc;
    assign out_if.data.instr       = fetch_instr;
    assign out_if.data.pred_taken  = pred_taken;
    assign out_if.data.pred_target = pred_target;

endmodule
