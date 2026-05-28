`timescale 1ns/1ps

module tb_trace_25test;

    import defines_pkg::*;

    localparam bit TRACE_VERBOSE = 1'b0;
    localparam int MAX_RUNTIME_CYCLES = 4000;

    logic clk;
    logic rst_n;

    logic        load_en;
    logic [31:0] load_addr;
    logic [7:0]  load_instr_byte;

    logic        issue_valid;
    logic [1:0]  issue_fu_type;
    logic [31:0] issue_pc;
    logic [31:0] issue_imm;

    logic        rob_head_valid;
    logic        rob_head_complete;
    logic [4:0]  rob_head_rd;

    int fail_count;
    int issue_count;
    int wb_count;
    int commit_count;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t x8_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] x8_value;
    logic [31:0] mem_word_12;
    logic [31:0] mem_word_16;
    logic [31:0] mem_word_20;
    logic pass_seen;
    int pass_commit_count;
    logic [31:0] pass_a0_value;
    logic [31:0] pass_a1_value;
    logic issue_valid_q;
    logic [1:0] issue_fu_type_q;
    logic [31:0] issue_pc_q;
    logic wb_valid_q;
    logic [PREG_W-1:0] wb_preg_q;
    logic [ROB_TAG_W-1:0] wb_tag_q;
    logic [31:0] wb_result_q;
    logic retire_valid_q;
    logic [4:0] retire_rd_q;
    logic branch_complete_valid_q;
    logic [ROB_TAG_W-1:0] branch_complete_tag_q;
    logic branch_resolve_q;
    logic [CHECKPOINT_W-1:0] resolve_checkpoint_id_q;
    logic pc_src_q;
    logic [31:0] pc_branch_q;
    logic bp_update_valid_q;
    logic [31:0] bp_update_pc_q;
    logic bp_update_taken_q;
    logic bp_update_is_jalr_q;
    logic [31:0] bp_update_target_q;

    top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .load_en          (load_en),
        .load_addr        (load_addr),
        .load_instr_byte  (load_instr_byte),
        .issue_valid      (issue_valid),
        .issue_fu_type    (issue_fu_type),
        .issue_pc         (issue_pc),
        .issue_imm        (issue_imm),
        .rob_head_valid   (rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head_rd      (rob_head_rd)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok;
        input logic cond;
        input string msg;
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic write_byte;
        input [31:0] byte_addr;
        input [7:0]  data_byte;
    begin
        load_en         = 1'b1;
        load_addr       = byte_addr;
        load_instr_byte = data_byte;
        step_clk;
    end
    endtask

    task automatic write_word;
        input [31:0] byte_addr;
        input [31:0] data_word;
    begin
        write_byte(byte_addr + 0, data_word[7:0]);
        write_byte(byte_addr + 1, data_word[15:8]);
        write_byte(byte_addr + 2, data_word[23:16]);
        write_byte(byte_addr + 3, data_word[31:24]);
    end
    endtask

    always @(posedge clk) begin
        issue_valid_q   <= issue_valid;
        issue_fu_type_q <= issue_fu_type;
        issue_pc_q      <= issue_pc;
        wb_valid_q      <= dut.wb_valid;
        wb_preg_q       <= dut.wb_preg;
        wb_tag_q        <= dut.wb_tag;
        wb_result_q     <= dut.wb_result;
        retire_valid_q  <= dut.retire_valid;
        retire_rd_q     <= dut.rob_head.datapath.rd;
        branch_complete_valid_q <= dut.branch_complete_valid;
        branch_complete_tag_q   <= dut.branch_complete_tag;
        branch_resolve_q        <= dut.branch_resolve_exe;
        resolve_checkpoint_id_q <= dut.resolve_checkpoint_id_exe;
        pc_src_q                <= dut.pc_src_exe;
        pc_branch_q             <= dut.pc_branch_exe;
        bp_update_valid_q       <= dut.bp_update_valid_exe;
        bp_update_pc_q          <= dut.bp_update_pc_exe;
        bp_update_taken_q       <= dut.bp_update_taken_exe;
        bp_update_is_jalr_q     <= dut.bp_update_is_jalr_exe;
        bp_update_target_q      <= dut.bp_update_target_exe;
    end

    always @(negedge clk) begin
        if (rst_n && issue_valid_q) begin
            if (TRACE_VERBOSE) begin
                $display("[ISSUE] idx=%0d fu=%0d pc=%08h", issue_count, issue_fu_type_q, issue_pc_q);
            end
            issue_count = issue_count + 1;
        end

        if (rst_n && wb_valid_q) begin
            if (TRACE_VERBOSE) begin
                $display("[WB] idx=%0d preg=%0d tag=%0d result=%08h", wb_count, wb_preg_q, wb_tag_q, wb_result_q);
            end
            wb_count = wb_count + 1;
        end

        if (rst_n && retire_valid_q) begin
            if (TRACE_VERBOSE) begin
                $display("[COMMIT] idx=%0d rd=x%0d", commit_count, retire_rd_q);
            end
            commit_count = commit_count + 1;
        end

        if (TRACE_VERBOSE && rst_n && branch_complete_valid_q) begin
            $display("[BRC] tag=%0d resolve=%0b cp_id=%0d pc_src=%0b pc_branch=%08h bp_upd=%0b bp_pc=%08h bp_taken=%0b bp_jalr=%0b bp_target=%08h",
                     branch_complete_tag_q,
                     branch_resolve_q,
                     resolve_checkpoint_id_q,
                     pc_src_q,
                     pc_branch_q,
                     bp_update_valid_q,
                     bp_update_pc_q,
                     bp_update_taken_q,
                     bp_update_is_jalr_q,
                     bp_update_target_q);
        end

        if (rst_n && !pass_seen) begin
            preg_t a0_preg_now;
            preg_t a1_preg_now;
            logic [31:0] a0_value_now;
            logic [31:0] a1_value_now;

            a0_preg_now  = dut.u_rename.u_rat.rat[10];
            a1_preg_now  = dut.u_rename.u_rat.rat[11];
            a0_value_now = dut.u_prf.regs[a0_preg_now];
            a1_value_now = dut.u_prf.regs[a1_preg_now];

            if (a0_value_now == 32'h00000003 && a1_value_now == 32'h00000001) begin
                pass_seen         = 1'b1;
                pass_commit_count = commit_count;
                pass_a0_value     = a0_value_now;
                pass_a1_value     = a1_value_now;
                $display("[MATCH] observed expected architectural state at commit_count=%0d a0=%08h a1=%08h",
                         commit_count, a0_value_now, a1_value_now);
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;
        issue_count = 0;
        wb_count = 0;
        commit_count = 0;
        issue_valid_q = 1'b0;
        issue_fu_type_q = '0;
        issue_pc_q = '0;
        wb_valid_q = 1'b0;
        wb_preg_q = '0;
        wb_tag_q = '0;
        wb_result_q = '0;
        retire_valid_q = 1'b0;
        retire_rd_q = '0;
        branch_complete_valid_q = 1'b0;
        branch_complete_tag_q = '0;
        branch_resolve_q = 1'b0;
        resolve_checkpoint_id_q = '0;
        pc_src_q = 1'b0;
        pc_branch_q = '0;
        bp_update_valid_q = 1'b0;
        bp_update_pc_q = '0;
        bp_update_taken_q = 1'b0;
        bp_update_is_jalr_q = 1'b0;
        bp_update_target_q = '0;
        pass_seen = 1'b0;
        pass_commit_count = 0;
        pass_a0_value = '0;
        pass_a1_value = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // 25test.txt
        write_word(32'd0,   32'h00010437);
        write_word(32'd4,   32'h04040413);
        write_word(32'd8,   32'h000204B7);
        write_word(32'd12,  32'hFE048493);
        write_word(32'd16,  32'hFF00F2B7);
        write_word(32'd20,  32'hF002E293);
        write_word(32'd24,  32'h00542023);
        write_word(32'd28,  32'hFFF00313);
        write_word(32'd32,  32'h00642223);
        write_word(32'd36,  32'h07F00393);
        write_word(32'd40,  32'h00741423);
        write_word(32'd44,  32'h00100E13);
        write_word(32'd48,  32'h01C41523);
        write_word(32'd52,  32'h00344E83);
        write_word(32'd56,  32'h00444F03);
        write_word(32'd60,  32'h00042F83);
        write_word(32'd64,  32'h006FFBB3);
        write_word(32'd68,  32'h01742623);
        write_word(32'd72,  32'h01D41723);
        write_word(32'd76,  32'h00C42C03);
        write_word(32'd80,  32'h00F44C83);
        write_word(32'd84,  32'h00600913);
        write_word(32'd88,  32'h00000993);
        write_word(32'd92,  32'h0129F9B3);
        write_word(32'd96,  32'h41C9D9B3);
        write_word(32'd100, 32'h0039BA13);
        write_word(32'd104, 32'h000A1663);
        write_word(32'd108, 32'h00598993);
        write_word(32'd112, 32'hFE0016E3);
        write_word(32'd116, 32'hFFF90913);
        write_word(32'd120, 32'hFE0912E3);
        write_word(32'd124, 32'h00000EB7);
        write_word(32'd128, 32'h0A4E8E93);
        write_word(32'd132, 32'h000E80E7);
        write_word(32'd136, 32'h00000EB7);
        write_word(32'd140, 32'h0C8E8E93);
        write_word(32'd144, 32'h000E80E7);
        write_word(32'd148, 32'h00000EB7);
        write_word(32'd152, 32'h0FCE8E93);
        write_word(32'd156, 32'h000E80E7);
        write_word(32'd160, 32'h00008067);
        write_word(32'd164, 32'h00042283);
        write_word(32'd168, 32'h00442303);
        write_word(32'd172, 32'h0062F3B3);
        write_word(32'd176, 32'h41C3D3B3);
        write_word(32'd180, 32'h4003BE13);
        write_word(32'd184, 32'h000E1463);
        write_word(32'd188, 32'hC0038393);
        write_word(32'd192, 32'h00742823);
        write_word(32'd196, 32'h00008067);
        write_word(32'd200, 32'h00944E83);
        write_word(32'd204, 32'h00A44F03);
        write_word(32'd208, 32'h01EEFFB3);
        write_word(32'd212, 32'h01F00B93);
        write_word(32'd216, 32'h417FDFB3);
        write_word(32'd220, 32'h001FBC13);
        write_word(32'd224, 32'h000C1663);
        write_word(32'd228, 32'h00000F93);
        write_word(32'd232, 32'h00001463);
        write_word(32'd236, 32'h00100F93);
        write_word(32'd240, 32'h01F41923);
        write_word(32'd244, 32'h01F42A23);
        write_word(32'd248, 32'h00008067);
        write_word(32'd252, 32'h01042283);
        write_word(32'd256, 32'h01442303);
        write_word(32'd260, 32'h0062F533);
        write_word(32'd264, 32'h00E44383);
        write_word(32'd268, 32'h00F44E03);
        write_word(32'd272, 32'h41C38EB3);
        write_word(32'd276, 32'h080EBF13);
        write_word(32'd280, 32'h000F1463);
        write_word(32'd284, 32'hF80E8E93);
        write_word(32'd288, 32'h006EF5B3);
        write_word(32'd292, 32'h003E0513);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        for (int cycle = 0; cycle < MAX_RUNTIME_CYCLES; cycle++) begin
            step_clk;
            if (pass_seen) begin
                break;
            end
        end

        a0_preg  = dut.u_rename.u_rat.rat[10];
        a1_preg  = dut.u_rename.u_rat.rat[11];
        x8_preg  = dut.u_rename.u_rat.rat[8];
        a0_value = dut.u_prf.regs[a0_preg];
        a1_value = dut.u_prf.regs[a1_preg];
        x8_value = dut.u_prf.regs[x8_preg];
        mem_word_12 = dut.u_execution.u_lsu.mem[(x8_value + 32'd12) >> 2];
        mem_word_16 = dut.u_execution.u_lsu.mem[(x8_value + 32'd16) >> 2];
        mem_word_20 = dut.u_execution.u_lsu.mem[(x8_value + 32'd20) >> 2];

        $display("[SUMMARY] issue_count=%0d wb_count=%0d commit_count=%0d a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) rob_empty=%0b rob_head_valid=%0b rob_head_complete=%0b rob_head_rd=%0d",
                 issue_count, wb_count, commit_count,
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 dut.u_dispatch.u_rob.empty,
                 dut.rob_head_valid, dut.rob_head_complete, dut.rob_head_rd);

        $display("[STATE] active_cp_mask=%b fetch_pc=%08h fetch_instr=%08h jalr_wait=%0b pred_pending=%0b head_q=%0d tail_q=%0d count_q=%0d",
                 dut.active_checkpoint_mask_q,
                 dut.u_fetch.fetch_pc,
                 dut.u_fetch.fetch_instr,
                 dut.u_fetch.jalr_wait_q,
                 dut.u_fetch.pred_redirect_pending_q,
                 dut.u_dispatch.u_rob.head_q,
                 dut.u_dispatch.u_rob.tail_q,
                 dut.u_dispatch.u_rob.count_q);

        $display("[DATA] x8_preg=%0d x8=%08h mem12=%08h mem16=%08h mem20=%08h",
                 x8_preg, x8_value, mem_word_12, mem_word_16, mem_word_20);
        $display("[MATCH_STATE] seen=%0b commit_count=%0d a0=%08h a1=%08h",
                 pass_seen, pass_commit_count, pass_a0_value, pass_a1_value);

        for (int i = 0; i < ROB_DEPTH; i++) begin
            if (dut.u_dispatch.u_rob.valid_bits[i]) begin
                $display("[ROB] idx=%0d complete=%0b tag=%0d rd=x%0d new_p=%0d old_p=%0d cp_id=%0d spec_mask=%b result=%08h",
                         i,
                         dut.u_dispatch.u_rob.entries[i].datapath.complete,
                         dut.u_dispatch.u_rob.entries[i].datapath.rob_tag,
                         dut.u_dispatch.u_rob.entries[i].datapath.rd,
                         dut.u_dispatch.u_rob.entries[i].datapath.new_des_preg,
                         dut.u_dispatch.u_rob.entries[i].datapath.old_des_preg,
                         dut.u_dispatch.u_rob.entries[i].datapath.checkpoint_id,
                         dut.u_dispatch.u_rob.entries[i].datapath.speculation_mask,
                         dut.u_dispatch.u_rob.entries[i].datapath.result);
            end
        end

        check_ok(pass_seen, "25test observed expected a0(x10)=3 and a1(x11)=1 during execution");

        if (fail_count == 0) begin
            $display("==== tb_trace_25test PASS ====");
        end else begin
            $display("==== tb_trace_25test FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
