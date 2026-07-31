`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend long stress.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_long_stress;

    import defines_pkg::*;

    localparam int IMEM_DEPTH_BYTES = 65536;
    localparam int DMEM_WORDS = 16384;
    localparam int MAX_CYCLES = 1000000;
    localparam int DEADLOCK_CYCLES = 10000;

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
    retire_trace_t retire_trace0;
    retire_trace_t retire_trace1;

    logic [31:0] expected_gpr [0:31];
    logic [31:0] architectural_gpr [0:31];
    logic [63:0] expected_retire [0:(IMEM_DEPTH_BYTES/4)-1];
    logic [63:0] expected_stream [0:(IMEM_DEPTH_BYTES/4)-1];
    reg [2047:0] program_path;
    reg [2047:0] expected_path;
    reg [2047:0] expected_retire_path;
    reg [2047:0] expected_stream_path;
    reg [2047:0] trace_path;
    integer probe_file;
    integer trace_file;
    integer cycle_count;
    integer retire_count;
    integer dual_retire_cycles;
    integer cycles_since_retire;
    integer fail_count;
    integer displayed_mismatches;
    integer retire_word_index;
    integer i;
    logic test_done;

    top_packet_backend #(
        .ENABLE_2WIDE(1'b1),
        .IMEM_DEPTH_BYTES(IMEM_DEPTH_BYTES),
        .DMEM_WORDS(DMEM_WORDS),
        .DMEM_BASE_ADDR(32'h00002000)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .software_irq(1'b0),
        .timer_irq(1'b0),
        .external_irq(1'b0),
        .load_en(load_en),
        .load_addr(load_addr),
        .load_instr_byte(load_instr_byte),
        .issue_valid(issue_valid),
        .issue_fu_type(issue_fu_type),
        .issue_pc(issue_pc),
        .issue_imm(issue_imm),
        .rob_head_valid(rob_head_valid),
        .rob_head_complete(rob_head_complete),
        .rob_head_rd(rob_head_rd),
        .retire_trace0(retire_trace0),
        .retire_trace1(retire_trace1)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task locate_program_file;
        begin
            probe_file = 0;
            if ($value$plusargs("STRESS_PROGRAM=%s", program_path)) begin
                probe_file = $fopen(program_path, "r");
            end
            if (probe_file == 0) begin
                program_path = "tests/stress/generated/rv32i_long_stress.hex";
                probe_file = $fopen(program_path, "r");
            end
            if (probe_file == 0) begin
                program_path = "../tests/stress/generated/rv32i_long_stress.hex";
                probe_file = $fopen(program_path, "r");
            end
            if (probe_file == 0) begin
                program_path = "../../../../tests/stress/generated/rv32i_long_stress.hex";
                probe_file = $fopen(program_path, "r");
            end
            if (probe_file == 0) begin
                $display("[FAIL] unable to locate stress program; use +STRESS_PROGRAM=<path>");
                $fatal;
            end
            $fclose(probe_file);
        end
    endtask

    task locate_expected_file;
        begin
            probe_file = 0;
            if ($value$plusargs("STRESS_EXPECTED=%s", expected_path)) begin
                probe_file = $fopen(expected_path, "r");
            end
            if (probe_file == 0) begin
                expected_path = "tests/stress/generated/rv32i_long_stress_expected_gpr.hex";
                probe_file = $fopen(expected_path, "r");
            end
            if (probe_file == 0) begin
                expected_path = "../tests/stress/generated/rv32i_long_stress_expected_gpr.hex";
                probe_file = $fopen(expected_path, "r");
            end
            if (probe_file == 0) begin
                expected_path = "../../../../tests/stress/generated/rv32i_long_stress_expected_gpr.hex";
                probe_file = $fopen(expected_path, "r");
            end
            if (probe_file == 0) begin
                $display("[FAIL] unable to locate expected GPR image; use +STRESS_EXPECTED=<path>");
                $fatal;
            end
            $fclose(probe_file);
        end
    endtask

    task locate_expected_retire_file;
        begin
            probe_file = 0;
            if ($value$plusargs("STRESS_RETIRE_EXPECTED=%s", expected_retire_path)) begin
                probe_file = $fopen(expected_retire_path, "r");
            end
            if (probe_file == 0) begin
                expected_retire_path =
                    "tests/stress/generated/rv32i_long_stress_expected_retire.hex";
                probe_file = $fopen(expected_retire_path, "r");
            end
            if (probe_file == 0) begin
                expected_retire_path =
                    "../tests/stress/generated/rv32i_long_stress_expected_retire.hex";
                probe_file = $fopen(expected_retire_path, "r");
            end
            if (probe_file == 0) begin
                expected_retire_path =
                    "../../../../tests/stress/generated/rv32i_long_stress_expected_retire.hex";
                probe_file = $fopen(expected_retire_path, "r");
            end
            if (probe_file == 0) begin
                $display(
                    "[FAIL] unable to locate expected retirement image; use +STRESS_RETIRE_EXPECTED=<path>"
                );
                $fatal;
            end
            $fclose(probe_file);
        end
    endtask

    task locate_expected_stream_file;
        begin
            probe_file = 0;
            if ($value$plusargs("STRESS_STREAM_EXPECTED=%s", expected_stream_path)) begin
                probe_file = $fopen(expected_stream_path, "r");
            end
            if (probe_file == 0) begin
                expected_stream_path =
                    "tests/stress/generated/rv32i_long_stress_expected_stream.hex";
                probe_file = $fopen(expected_stream_path, "r");
            end
            if (probe_file == 0) begin
                expected_stream_path =
                    "../tests/stress/generated/rv32i_long_stress_expected_stream.hex";
                probe_file = $fopen(expected_stream_path, "r");
            end
            if (probe_file == 0) begin
                expected_stream_path =
                    "../../../../tests/stress/generated/rv32i_long_stress_expected_stream.hex";
                probe_file = $fopen(expected_stream_path, "r");
            end
            if (probe_file == 0) begin
                $display(
                    "[FAIL] unable to locate expected retirement stream; use +STRESS_STREAM_EXPECTED=<path>"
                );
                $fatal;
            end
            $fclose(probe_file);
        end
    endtask

    task record_trace;
        input retire_trace_t trace;
        begin
            if (trace.valid) begin
                $fdisplay(
                    trace_file,
                    "%0d,%0d,%08x,%08x,%0d,%0d,%0d,%08x,%02x,%0d,%0d,%0d",
                    cycle_count,
                    trace.order,
                    trace.pc,
                    trace.instr,
                    trace.rd_wen,
                    trace.rd_is_fp,
                    trace.rd,
                    trace.rd_wdata,
                    trace.fp_flags,
                    trace.is_store,
                    trace.is_branch,
                    trace.rob_tag
                );
                if ({trace.pc, trace.instr} !== expected_stream[retire_count]) begin
                    fail_count = fail_count + 1;
                    if (displayed_mismatches < 12) begin
                        $display(
                            "[RETIRE_ORDER_MISMATCH] order=%0d rtl_pc=%08x rtl_instr=%08x expected_pc=%08x expected_instr=%08x",
                            trace.order,
                            trace.pc,
                            trace.instr,
                            expected_stream[retire_count][63:32],
                            expected_stream[retire_count][31:0]
                        );
                        displayed_mismatches = displayed_mismatches + 1;
                    end
                end
                retire_word_index = trace.pc >> 2;
                if (expected_retire[retire_word_index][63]) begin
                    if (!trace.rd_wen ||
                        trace.rd_is_fp ||
                        (trace.rd !== expected_retire[retire_word_index][36:32]) ||
                        (trace.rd_wdata !== expected_retire[retire_word_index][31:0])) begin
                        fail_count = fail_count + 1;
                        if (displayed_mismatches < 12) begin
                            $display(
                                "[RETIRE_MISMATCH] order=%0d pc=%08x instr=%08x rtl=x%0d/0x%08x expected=x%0d/0x%08x",
                                trace.order,
                                trace.pc,
                                trace.instr,
                                trace.rd,
                                trace.rd_wdata,
                                expected_retire[retire_word_index][36:32],
                                expected_retire[retire_word_index][31:0]
                            );
                            displayed_mismatches = displayed_mismatches + 1;
                        end
                    end
                end else if (trace.rd_wen) begin
                    fail_count = fail_count + 1;
                    if (displayed_mismatches < 12) begin
                        $display(
                            "[RETIRE_MISMATCH] order=%0d pc=%08x unexpected register write x%0d=0x%08x",
                            trace.order,
                            trace.pc,
                            trace.rd,
                            trace.rd_wdata
                        );
                        displayed_mismatches = displayed_mismatches + 1;
                    end
                end
                if (trace.rd_wen && !trace.rd_is_fp && (trace.rd != 0)) begin
                    architectural_gpr[trace.rd] = trace.rd_wdata;
                end
                retire_count = retire_count + 1;
            end
        end
    endtask

    task compare_architectural_state;
        begin
            architectural_gpr[0] = 32'b0;
            for (i = 0; i < 32; i = i + 1) begin
                if (architectural_gpr[i] !== expected_gpr[i]) begin
                    fail_count = fail_count + 1;
                    if (displayed_mismatches < 12) begin
                        $display(
                            "[MISMATCH] x%0d rtl=0x%08x expected=0x%08x",
                            i,
                            architectural_gpr[i],
                            expected_gpr[i]
                        );
                        displayed_mismatches = displayed_mismatches + 1;
                    end
                end
            end
        end
    endtask

    always @(negedge clk) begin
        if (rst_n && !test_done) begin
            cycle_count = cycle_count + 1;
            if (retire_trace0.valid || retire_trace1.valid) begin
                cycles_since_retire = 0;
            end else begin
                cycles_since_retire = cycles_since_retire + 1;
            end
            if (retire_trace0.valid && retire_trace1.valid) begin
                dual_retire_cycles = dual_retire_cycles + 1;
            end

            record_trace(retire_trace0);
            record_trace(retire_trace1);

            if ((retire_trace0.valid && retire_trace0.rd_wen &&
                 !retire_trace0.rd_is_fp && (retire_trace0.rd == 31)) ||
                (retire_trace1.valid && retire_trace1.rd_wen &&
                 !retire_trace1.rd_is_fp && (retire_trace1.rd == 31))) begin
                if (architectural_gpr[31] !== 32'd1) begin
                    $display("[FAIL] completion register x31=0x%08x", architectural_gpr[31]);
                    fail_count = fail_count + 1;
                end
                compare_architectural_state();
                test_done = 1'b1;
            end

            if ((cycles_since_retire >= DEADLOCK_CYCLES) && !test_done) begin
                $display(
                    "[DEADLOCK] no retirement for %0d cycles at cycle=%0d retired=%0d",
                    cycles_since_retire,
                    cycle_count,
                    retire_count
                );
                $display(
                    "[STATE] fetch_pc=%08x issue=%0d/%0d issue_pc=%08x rob_head=%0d/%0d rd=x%0d rob_count=%0d",
                    dut.u_fetch.pc_q,
                    issue_valid,
                    dut.issue_if.ready,
                    issue_pc,
                    rob_head_valid,
                    rob_head_complete,
                    rob_head_rd,
                    dut.u_dispatch_packet.u_rob_2w.count_q
                );
                for (i = 0; i < RS_DEPTH; i = i + 1) begin
                    if (dut.u_dispatch_packet.u_rs_alu.used[i]) begin
                        $display(
                            "[ALU_RS] idx=%0d pc=%08x instr=%08x tag=%0d src1p=%0d ready1=%0d value1=%08x src2p=%0d ready2=%0d value2=%08x",
                            i,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.pc,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.instr,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.rob_tag,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.src_reg_1p,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].src1_ready,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.src1_value,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.src_reg_2p,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].src2_ready,
                            dut.u_dispatch_packet.u_rs_alu.entries[i].datapath.src2_value
                        );
                    end
                end
                $display(
                    "[LSU] req_ready=%0d pending=%0d sent=%0d blocking=%0d tag=%0d store_mask=%b drain=%0d drain_wait=%0d mem_req=%0d/%0d mem_resp=%0d",
                    dut.u_execution.u_lsu.req_ready,
                    dut.u_execution.u_lsu.pending_valid,
                    dut.u_execution.u_lsu.pending_mem_req_sent,
                    dut.u_execution.u_lsu.pending_store_blocking,
                    dut.u_execution.u_lsu.pending_datapath.rob_tag,
                    dut.u_execution.u_lsu.store_buf_valid_mask,
                    dut.u_execution.u_lsu.store_drain_valid,
                    dut.u_execution.u_lsu.store_drain_wait_q,
                    dut.u_execution.u_lsu.mem_req_valid,
                    dut.u_execution.u_lsu.mem_req_ready,
                    dut.u_execution.u_lsu.mem_resp_valid
                );
                for (i = 0; i < 8; i = i + 1) begin
                    if (dut.u_execution.u_lsu.store_buf_valid[i]) begin
                        $display(
                            "[STORE_BUF] idx=%0d tag=%0d committed=%0d sent=%0d squashed=%0d pc=%08x",
                            i,
                            dut.u_execution.u_lsu.store_buf_datapath[i].rob_tag,
                            dut.u_execution.u_lsu.store_buf_committed[i],
                            dut.u_execution.u_lsu.store_buf_mem_req_sent[i],
                            dut.u_execution.u_lsu.store_buf_squashed[i],
                            dut.u_execution.u_lsu.store_buf_datapath[i].pc
                        );
                    end
                end
                fail_count = fail_count + 1;
                test_done = 1'b1;
            end
        end
    end

    initial begin
        rst_n = 1'b0;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        cycle_count = 0;
        retire_count = 0;
        dual_retire_cycles = 0;
        cycles_since_retire = 0;
        fail_count = 0;
        displayed_mismatches = 0;
        test_done = 1'b0;
        trace_path = "rv32i_long_stress_retire.csv";
        for (i = 0; i < 32; i = i + 1) begin
            architectural_gpr[i] = '0;
            expected_gpr[i] = '0;
        end

        locate_program_file();
        locate_expected_file();
        locate_expected_retire_file();
        locate_expected_stream_file();
        trace_file = $fopen(trace_path, "w");
        if (trace_file == 0) begin
            $display("[FAIL] unable to create retirement trace CSV");
            $fatal;
        end
        $fdisplay(
            trace_file,
            "cycle,order,pc,instr,rd_wen,rd_is_fp,rd,rd_wdata,fp_flags,is_store,is_branch,rob_tag"
        );

        repeat (3) @(posedge clk);
        @(negedge clk);
        $readmemh(program_path, dut.u_fetch.mem);
        $readmemh(expected_path, expected_gpr);
        $readmemh(expected_retire_path, expected_retire);
        $readmemh(expected_stream_path, expected_stream);
        rst_n = 1'b1;

        while (!test_done && (cycle_count < MAX_CYCLES)) begin
            @(posedge clk);
        end
        if (!test_done) begin
            $display(
                "[TIMEOUT] cycle limit=%0d retired=%0d rob_head=%0d/%0d",
                MAX_CYCLES,
                retire_count,
                rob_head_valid,
                rob_head_complete
            );
            fail_count = fail_count + 1;
        end

        $fclose(trace_file);
        $display(
            "[SUMMARY] cycles=%0d retired=%0d ipc=%0f dual_retire_cycles=%0d signature=0x%08x trace=%0s",
            cycle_count,
            retire_count,
            (cycle_count == 0) ? 0.0 : (1.0 * retire_count / cycle_count),
            dual_retire_cycles,
            architectural_gpr[30],
            trace_path
        );
        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_long_stress PASS ====");
        end else begin
            $display(
                "==== tb_top_packet_backend_long_stress FAIL (%0d errors) ====",
                fail_count
            );
        end
        $finish;
    end

endmodule
