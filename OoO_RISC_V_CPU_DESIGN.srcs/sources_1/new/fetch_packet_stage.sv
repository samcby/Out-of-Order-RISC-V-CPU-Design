// Active two-wide frontend for the packet backend.
//
// The stage selects a fetch PC, reads two adjacent 32-bit instructions from an
// internal instruction RAM, attaches prediction metadata, and emits one
// ordered packet. Lane 0 is at fetch_pc and lane 1 is at fetch_pc + 4. A
// predicted-taken lane-0 control-flow instruction suppresses the sequential
// lane 1 because that instruction is no longer on the predicted path.
//
// Redirect priority is architectural recovery/trap first, prediction second,
// and sequential advancement last. BHT, BTB, and JALR-target-cache state is
// trained by resolved branches from execution. Output data remains stable
// under downstream backpressure according to the pip_if contract.
module fetch_packet_stage #(
    parameter int WIDTH = 32,
    parameter logic [WIDTH-1:0] BASE_ADDR = '0,
    parameter int DEPTH_BYTES = 4096,
    parameter bit ENABLE_ACCESS_FAULTS = 1'b0,
    parameter bit ENABLE_PMP = 1'b0,
    parameter bit ENABLE_2WIDE = 1'b1
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
    input  logic [1:0]       current_privilege,
    input  logic [defines_pkg::PMP_ENTRY_COUNT*8-1:0] pmpcfg_values,
    input  logic [defines_pkg::PMP_ENTRY_COUNT*WIDTH-1:0] pmpaddr_values,

    pip_if.producer out_if
);

    import defines_pkg::*;

    localparam int WORDS = DEPTH_BYTES / 4;
    localparam int WORD_AW = $clog2(WORDS);
    localparam int BHT_ENTRIES = 64;
    localparam int BHT_W = $clog2(BHT_ENTRIES);
    localparam int BTB_ENTRIES = 64;
    localparam int BTB_W = $clog2(BTB_ENTRIES);
    localparam int JALR_ENTRIES = 32;
    localparam int JALR_W = $clog2(JALR_ENTRIES);

    logic [31:0] mem [0:WORDS-1];

    logic start_q;
    logic redirect_hold_q;
    logic pred_redirect_pending_q;
    logic [WIDTH-1:0] pred_redirect_target_q;
    logic jalr_wait_q;
    logic [WIDTH-1:0] pc_q;
    logic [WIDTH-1:0] fetch_pc;
    logic [WIDTH-1:0] lane0_pc;
    logic [WIDTH-1:0] lane1_pc;
    logic [WIDTH-1:0] lane0_instr;
    logic [WIDTH-1:0] lane1_instr;
    logic [WIDTH-1:0] lane0_mem_offset;
    logic [WIDTH-1:0] lane1_mem_offset;
    logic lane0_access_fault;
    logic lane1_access_fault;
    logic lane0_pmp_allowed;
    logic lane1_pmp_allowed;

    logic [WORD_AW-1:0] load_word_idx;
    logic [WORD_AW-1:0] lane0_word_idx;
    logic [WORD_AW-1:0] lane1_word_idx;
    logic [1:0]         load_byte_off;

    logic lane0_is_control;
    logic lane1_is_control;
    logic lane1_is_jalr;
    logic [6:0] lane0_opcode;
    logic [6:0] lane1_opcode;
    logic [WIDTH-1:0] lane0_imm_b;
    logic [WIDTH-1:0] lane0_imm_j;
    logic [WIDTH-1:0] lane1_imm_b;
    logic [WIDTH-1:0] lane1_imm_j;
    logic fetch_fire;
    logic lane1_valid;
    logic pred_taken;
    logic [WIDTH-1:0] pred_target;
    logic lane0_pred_taken;
    logic [WIDTH-1:0] lane0_pred_target;
    logic lane1_pred_taken;
    logic [WIDTH-1:0] lane1_pred_target;
    logic pred_redirect_fire;
    logic jalr_miss_fire;

    logic [1:0] bht [0:BHT_ENTRIES-1];
    logic [BHT_W-1:0] fetch_bht_idx;
    logic [BHT_W-1:0] lane1_bht_idx;
    logic [BHT_W-1:0] update_bht_idx;
    logic [BTB_W-1:0] fetch_btb_idx;
    logic [BTB_W-1:0] lane1_btb_idx;
    logic [BTB_W-1:0] update_btb_idx;
    logic [WIDTH-BTB_W-3:0] fetch_btb_tag;
    logic [WIDTH-BTB_W-3:0] lane1_btb_tag;
    logic [WIDTH-BTB_W-3:0] update_btb_tag;
    logic btb_hit;
    logic lane1_btb_hit;
    logic btb_valid [0:BTB_ENTRIES-1];
    logic [WIDTH-BTB_W-3:0] btb_tag [0:BTB_ENTRIES-1];
    logic [WIDTH-1:0] btb_target [0:BTB_ENTRIES-1];

    logic [JALR_W-1:0] fetch_jalr_idx;
    logic [JALR_W-1:0] lane1_jalr_idx;
    logic [JALR_W-1:0] update_jalr_idx;
    logic [WIDTH-JALR_W-3:0] fetch_jalr_tag;
    logic [WIDTH-JALR_W-3:0] lane1_jalr_tag;
    logic [WIDTH-JALR_W-3:0] update_jalr_tag;
    logic jalr_hit;
    logic lane1_jalr_hit;
    logic jalr_valid [0:JALR_ENTRIES-1];
    logic [WIDTH-JALR_W-3:0] jalr_tag [0:JALR_ENTRIES-1];
    logic [WIDTH-1:0] jalr_target [0:JALR_ENTRIES-1];

    assign load_word_idx  = load_addr[WORD_AW+1:2];
    assign load_byte_off  = load_addr[1:0];
    assign fetch_pc       = pc_src ? pc_branch :
                            pred_redirect_pending_q ? pred_redirect_target_q :
                            pc_q;
    assign lane0_pc       = fetch_pc;
    assign lane1_pc       = fetch_pc + WIDTH'(32'd4);
    assign lane0_mem_offset = lane0_pc - BASE_ADDR;
    assign lane1_mem_offset = lane1_pc - BASE_ADDR;
    assign lane0_word_idx = lane0_mem_offset[WORD_AW+1:2];
    assign lane1_word_idx = lane1_mem_offset[WORD_AW+1:2];
    assign lane0_pmp_allowed = pmp_access_allowed(
        current_privilege, pmpcfg_values, pmpaddr_values, lane0_pc,
        3'd3, 1'b0, 1'b0, 1'b1);
    assign lane1_pmp_allowed = pmp_access_allowed(
        current_privilege, pmpcfg_values, pmpaddr_values, lane1_pc,
        3'd3, 1'b0, 1'b0, 1'b1);
    assign lane0_access_fault =
        (ENABLE_ACCESS_FAULTS &&
         ((lane0_pc < BASE_ADDR) ||
          ({1'b0, lane0_pc} + 33'd3 >=
           ({1'b0, BASE_ADDR} + DEPTH_BYTES)))) ||
        (ENABLE_PMP && !lane0_pmp_allowed);
    assign lane1_access_fault =
        (ENABLE_ACCESS_FAULTS &&
         ((lane1_pc < BASE_ADDR) ||
          ({1'b0, lane1_pc} + 33'd3 >=
           ({1'b0, BASE_ADDR} + DEPTH_BYTES)))) ||
        (ENABLE_PMP && !lane1_pmp_allowed);
    assign lane0_instr = (start_q && !lane0_access_fault) ?
                         mem[lane0_word_idx] : '0;
    assign lane1_instr = (start_q && !lane1_access_fault) ?
                         mem[lane1_word_idx] : '0;

    assign lane0_opcode = lane0_instr[6:0];
    assign lane1_opcode = lane1_instr[6:0];
    assign lane0_imm_b  = {{19{lane0_instr[31]}}, lane0_instr[31], lane0_instr[7],
                           lane0_instr[30:25], lane0_instr[11:8], 1'b0};
    assign lane0_imm_j  = {{11{lane0_instr[31]}}, lane0_instr[31], lane0_instr[19:12],
                           lane0_instr[20], lane0_instr[30:21], 1'b0};
    assign lane1_imm_b  = {{19{lane1_instr[31]}}, lane1_instr[31], lane1_instr[7],
                           lane1_instr[30:25], lane1_instr[11:8], 1'b0};
    assign lane1_imm_j  = {{11{lane1_instr[31]}}, lane1_instr[31], lane1_instr[19:12],
                           lane1_instr[20], lane1_instr[30:21], 1'b0};

    assign fetch_bht_idx  = lane0_pc[BHT_W+1:2];
    assign lane1_bht_idx  = lane1_pc[BHT_W+1:2];
    assign update_bht_idx = bp_update_pc[BHT_W+1:2];
    assign fetch_btb_idx  = lane0_pc[BTB_W+1:2];
    assign lane1_btb_idx  = lane1_pc[BTB_W+1:2];
    assign update_btb_idx = bp_update_pc[BTB_W+1:2];
    assign fetch_btb_tag  = lane0_pc[WIDTH-1:BTB_W+2];
    assign lane1_btb_tag  = lane1_pc[WIDTH-1:BTB_W+2];
    assign update_btb_tag = bp_update_pc[WIDTH-1:BTB_W+2];
    assign fetch_jalr_idx  = lane0_pc[JALR_W+1:2];
    assign lane1_jalr_idx  = lane1_pc[JALR_W+1:2];
    assign update_jalr_idx = bp_update_pc[JALR_W+1:2];
    assign fetch_jalr_tag  = lane0_pc[WIDTH-1:JALR_W+2];
    assign lane1_jalr_tag  = lane1_pc[WIDTH-1:JALR_W+2];
    assign update_jalr_tag = bp_update_pc[WIDTH-1:JALR_W+2];

    assign btb_hit = btb_valid[fetch_btb_idx] &&
                     (btb_tag[fetch_btb_idx] == fetch_btb_tag);
    assign lane1_btb_hit = btb_valid[lane1_btb_idx] &&
                           (btb_tag[lane1_btb_idx] == lane1_btb_tag);
    assign jalr_hit = jalr_valid[fetch_jalr_idx] &&
                      (jalr_tag[fetch_jalr_idx] == fetch_jalr_tag);
    assign lane1_jalr_hit = jalr_valid[lane1_jalr_idx] &&
                            (jalr_tag[lane1_jalr_idx] == lane1_jalr_tag);

    always_comb begin
        lane0_pred_taken  = 1'b0;
        lane0_pred_target = '0;

        unique case (lane0_opcode)
            7'b1100011: begin
                lane0_pred_taken  = bht[fetch_bht_idx][1] && btb_hit;
                lane0_pred_target = btb_target[fetch_btb_idx];
            end
            7'b1101111: begin
                lane0_pred_taken  = 1'b1;
                lane0_pred_target = btb_hit ? btb_target[fetch_btb_idx] : (lane0_pc + lane0_imm_j);
            end
            7'b1100111: begin
                lane0_pred_taken  = jalr_hit;
                lane0_pred_target = jalr_target[fetch_jalr_idx];
            end
            default: begin
                lane0_pred_taken  = 1'b0;
                lane0_pred_target = '0;
            end
        endcase
    end

    always_comb begin
        lane1_pred_taken  = 1'b0;
        lane1_pred_target = '0;

        unique case (lane1_opcode)
            7'b1100011: begin
                lane1_pred_taken  = bht[lane1_bht_idx][1] && lane1_btb_hit;
                lane1_pred_target = btb_target[lane1_btb_idx];
            end
            7'b1101111: begin
                lane1_pred_taken  = 1'b1;
                lane1_pred_target = lane1_btb_hit ? btb_target[lane1_btb_idx] :
                                                       (lane1_pc + lane1_imm_j);
            end
            7'b1100111: begin
                lane1_pred_taken  = lane1_jalr_hit;
                lane1_pred_target = jalr_target[lane1_jalr_idx];
            end
            default: begin
                lane1_pred_taken  = 1'b0;
                lane1_pred_target = '0;
            end
        endcase
    end

    assign lane0_is_control = (lane0_opcode == 7'b1100011) ||
                              (lane0_opcode == 7'b1101111) ||
                              (lane0_opcode == 7'b1100111);
    assign lane1_is_control = (lane1_opcode == 7'b1100011) ||
                              (lane1_opcode == 7'b1101111) ||
                              (lane1_opcode == 7'b1100111);
    assign lane1_is_jalr = lane1_opcode == 7'b1100111;

    // A lane1 control-flow instruction is the youngest instruction in the
    // packet, so it can redirect without invalidating lane0.
    assign lane1_valid = ENABLE_2WIDE &&
                         !lane0_is_control &&
                         !lane0_access_fault;

    always_comb begin
        pred_taken = 1'b0;
        pred_target = '0;

        if (lane0_is_control) begin
            pred_taken = lane0_pred_taken;
            pred_target = lane0_pred_target;
        end else if (lane1_valid && lane1_is_control) begin
            pred_taken = lane1_pred_taken;
            pred_target = lane1_pred_target;
        end
    end

    assign out_if.valid = start_q && !load_en &&
                          !pc_src && !redirect_hold_q &&
                          !pred_redirect_pending_q && !jalr_wait_q;

    always_comb begin
        out_if.data = '0;

        out_if.data.lane0.valid = out_if.valid;
        out_if.data.lane0.data.pc = lane0_pc;
        out_if.data.lane0.data.instr = lane0_instr;
        out_if.data.lane0.data.pred_taken = lane0_pred_taken;
        out_if.data.lane0.data.pred_target = lane0_pred_target;
        out_if.data.lane0.data.exception_valid = lane0_access_fault;
        out_if.data.lane0.data.exception_cause = MCAUSE_INSTR_ACCESS_FAULT;
        out_if.data.lane0.data.exception_tval = lane0_pc;

        out_if.data.lane1.valid = out_if.valid && lane1_valid;
        out_if.data.lane1.data.pc = lane1_pc;
        out_if.data.lane1.data.instr = lane1_instr;
        out_if.data.lane1.data.pred_taken = lane1_pred_taken;
        out_if.data.lane1.data.pred_target = lane1_pred_target;
        out_if.data.lane1.data.exception_valid = lane1_access_fault;
        out_if.data.lane1.data.exception_cause = MCAUSE_INSTR_ACCESS_FAULT;
        out_if.data.lane1.data.exception_tval = lane1_pc;
    end

    assign fetch_fire = out_if.valid && out_if.ready;
    assign pred_redirect_fire = fetch_fire && pred_taken;
    assign jalr_miss_fire = fetch_fire &&
                            (((lane0_opcode == 7'b1100111) && !jalr_hit) ||
                             (lane1_valid && lane1_is_jalr && !lane1_jalr_hit));

 /*  上面的内容主要是：
 取到 lane0、lane1
│
├─ lane0 是 control？
│  ├─ 是：只输出 lane0，并采用 lane0 的预测
│  └─ 否
│      ├─ lane1 是 control？
│      │  ├─ 是：输出两条，并采用 lane1 的预测
│      │  └─ 否：顺序取两条
│
└─ 当前 packet 只有在 valid && ready 后才真正推进 PC
 */


    always_ff @(posedge out_if.clk or negedge out_if.rst_n) begin
        if (!out_if.rst_n) begin
            start_q <= 1'b0;
            redirect_hold_q <= 1'b0;
            pred_redirect_pending_q <= 1'b0;
            pred_redirect_target_q <= '0;
            jalr_wait_q <= 1'b0;
            pc_q    <= '0;
`ifndef SYNTHESIS
            for (int i = 0; i < WORDS; i++) begin
                mem[i] <= '0;
            end
`endif
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
            start_q <= 1'b1;
            redirect_hold_q <= pc_src;

            if (pc_src) begin
                pred_redirect_pending_q <= 1'b0;
                jalr_wait_q <= 1'b0;
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

            if (load_en) begin
                unique case (load_byte_off)
                    2'd0: mem[load_word_idx][7:0]   <= load_instr_byte;
                    2'd1: mem[load_word_idx][15:8]  <= load_instr_byte;
                    2'd2: mem[load_word_idx][23:16] <= load_instr_byte;
                    2'd3: mem[load_word_idx][31:24] <= load_instr_byte;
                    default: ;
                endcase
            end else if (pc_src) begin
                pc_q <= pc_branch;
            end else if (pred_redirect_pending_q) begin
                pc_q <= pred_redirect_target_q;
            end else if (fetch_fire) begin
                pc_q <= pred_redirect_fire ? pred_target :
                        pc_q + (lane1_valid ? WIDTH'(32'd8) : WIDTH'(32'd4));
            end
        end
    end

endmodule
