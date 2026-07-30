`timescale 1ns/1ps

// End-to-end FENCE/FENCE.I serialization and memory-drain test.
module tb_top_packet_backend_fence_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic load_en;
    logic [31:0] load_addr;
    logic [7:0] load_instr_byte;
    logic issue_valid;
    logic [1:0] issue_fu_type;
    logic [31:0] issue_pc;
    logic [31:0] issue_imm;
    logic rob_head_valid;
    logic rob_head_complete;
    logic [4:0] rob_head_rd;

    int fail_count;
    int fence_dispatch_count;
    int fence_issue_count;
    int fence_retire_count;
    int bad_dispatch_count;
    int bad_issue_count;
    int trap_count;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] cache_word_way0;
    logic [31:0] cache_word_way1;

    top_packet_backend dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .software_irq     (1'b0),
        .timer_irq        (1'b0),
        .external_irq     (1'b0),
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fence_dispatch_count <= 0;
            fence_issue_count <= 0;
            fence_retire_count <= 0;
            bad_dispatch_count <= 0;
            bad_issue_count <= 0;
            trap_count <= 0;
        end else begin
            if (dut.pipe_rd_pkt_d.valid &&
                dut.pipe_rd_pkt_d.ready &&
                dut.pipe_rd_pkt_d.data.lane0.valid &&
                dut.pipe_rd_pkt_d.data.lane0.data.rs_entry.control_signal
                    .alu_control_signal.sys_en &&
                (dut.pipe_rd_pkt_d.data.lane0.data.rs_entry.control_signal
                    .alu_control_signal.sys_op == SYS_FENCE)) begin
                fence_dispatch_count <= fence_dispatch_count + 1;
                if (!dut.rob_empty_i) begin
                    bad_dispatch_count <= bad_dispatch_count + 1;
                end
            end
            if (dut.pipe_rd_pkt_d.valid &&
                dut.pipe_rd_pkt_d.ready &&
                dut.pipe_rd_pkt_d.data.lane1.valid &&
                dut.pipe_rd_pkt_d.data.lane1.data.rs_entry.control_signal
                    .alu_control_signal.sys_en &&
                (dut.pipe_rd_pkt_d.data.lane1.data.rs_entry.control_signal
                    .alu_control_signal.sys_op == SYS_FENCE)) begin
                fence_dispatch_count <= fence_dispatch_count + 1;
                if (!dut.rob_empty_i) begin
                    bad_dispatch_count <= bad_dispatch_count + 1;
                end
            end

            if (dut.issue_if.valid &&
                dut.issue_if.ready &&
                (dut.issue_if.data.fu_sel == FU_ALU) &&
                dut.issue_if.data.control_signal.alu.sys_en &&
                (dut.issue_if.data.control_signal.alu.sys_op == SYS_FENCE)) begin
                fence_issue_count <= fence_issue_count + 1;
                if (!dut.memory_quiescent) begin
                    bad_issue_count <= bad_issue_count + 1;
                end
                if ((dut.issue_if.data.datapath.pc == 32'd12) &&
                    (dut.u_execution.u_lsu.u_data_cache.line_data[0][0][0] !=
                     32'h00000055) &&
                    (dut.u_execution.u_lsu.u_data_cache.line_data[0][1][0] !=
                     32'h00000055)) begin
                    bad_issue_count <= bad_issue_count + 1;
                end
            end

            if (dut.retire_trace0.valid &&
                ((dut.retire_trace0.instr == 32'h0330000f) ||
                 (dut.retire_trace0.instr == 32'h0000100f))) begin
                fence_retire_count <= fence_retire_count + 1;
            end
            if (dut.retire_trace1.valid &&
                ((dut.retire_trace1.instr == 32'h0330000f) ||
                 (dut.retire_trace1.instr == 32'h0000100f))) begin
                fence_retire_count <= fence_retire_count + 1;
            end

            if (dut.trap_commit) begin
                trap_count <= trap_count + 1;
            end
        end
    end

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
        input [7:0] data_byte;
    begin
        load_en = 1'b1;
        load_addr = byte_addr;
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

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h00010437); // lui      x8,0x10
        write_word(32'd4,  32'h05500293); // addi     x5,x0,0x55
        write_word(32'd8,  32'h00542023); // sw       x5,0(x8)
        write_word(32'd12, 32'h0330000f); // fence    rw,rw
        write_word(32'd16, 32'h00042503); // lw       x10,0(x8)
        write_word(32'd20, 32'h0000100f); // fence.i
        write_word(32'd24, 32'h06600593); // addi     x11,x0,0x66
        write_word(32'd28, 32'h0000006f); // jal      x0,0

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (320) step_clk;

        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];
        cache_word_way0 =
            dut.u_execution.u_lsu.u_data_cache.line_data[0][0][0];
        cache_word_way1 =
            dut.u_execution.u_lsu.u_data_cache.line_data[0][1][0];

        $display("[SUMMARY] dispatch=%0d issue=%0d retire=%0d bad_dispatch=%0d bad_issue=%0d traps=%0d a0=0x%08h a1=0x%08h cache0=0x%08h cache1=0x%08h",
                 fence_dispatch_count,
                 fence_issue_count,
                 fence_retire_count,
                 bad_dispatch_count,
                 bad_issue_count,
                 trap_count,
                 a0_value,
                 a1_value,
                 cache_word_way0,
                 cache_word_way1);

        check_ok(fence_dispatch_count == 2,
                 "FENCE and FENCE.I both entered the serialized backend");
        check_ok(bad_dispatch_count == 0,
                 "each fence dispatched only after older ROB work drained");
        check_ok(fence_issue_count == 2,
                 "FENCE and FENCE.I both executed exactly once");
        check_ok(bad_issue_count == 0,
                 "fences executed only after the LSU and cache became quiescent");
        check_ok(fence_retire_count == 2,
                 "both fences retired normally in program order");
        check_ok(trap_count == 0,
                 "legal fence encodings did not raise exceptions");
        check_ok(a0_value == 32'h00000055,
                 "load after FENCE observed the committed store");
        check_ok(a1_value == 32'h00000066,
                 "instruction after FENCE.I completed");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_fence_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fence_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
