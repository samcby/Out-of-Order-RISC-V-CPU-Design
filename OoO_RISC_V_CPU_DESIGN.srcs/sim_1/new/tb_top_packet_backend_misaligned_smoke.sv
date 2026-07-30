`timescale 1ns/1ps

// Combined precise-misaligned-exception test for the packet backend.
module tb_top_packet_backend_misaligned_smoke;

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
    int drain_cycles;
    int precise_trap_count;
    int precise_trap_bad_count;
    int early_trap_write_count;
    int fault_retire_count;
    int fault_lsu_request_count;
    logic [31:0] expected_fault_instr;
    logic [31:0] expected_mcause;
    logic [31:0] expected_mtval;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;

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
            precise_trap_count      <= 0;
            precise_trap_bad_count  <= 0;
            early_trap_write_count  <= 0;
            fault_retire_count      <= 0;
            fault_lsu_request_count <= 0;
        end else begin
            if (dut.trap_commit) begin
                precise_trap_count <= precise_trap_count + 1;
                if (!dut.rob_head.datapath.exception_valid ||
                    (dut.rob_head.datapath.pc != 32'h00000008) ||
                    (dut.rob_head.datapath.exception_cause != expected_mcause) ||
                    (dut.rob_head.datapath.exception_tval != expected_mtval)) begin
                    precise_trap_bad_count <= precise_trap_bad_count + 1;
                end
            end

            if (dut.u_execution.csr_trap_write_en &&
                !dut.u_execution.commit_trap_fire &&
                !dut.u_execution.interrupt_take) begin
                early_trap_write_count <= early_trap_write_count + 1;
            end

            if ((dut.retire_trace0.valid &&
                 (dut.retire_trace0.instr == expected_fault_instr)) ||
                (dut.retire_trace1.valid &&
                 (dut.retire_trace1.instr == expected_fault_instr))) begin
                fault_retire_count <= fault_retire_count + 1;
            end

            if (dut.u_execution.lsu_req_valid &&
                (dut.u_execution.selected_mem_datapath.instr ==
                 expected_fault_instr)) begin
                fault_lsu_request_count <= fault_lsu_request_count + 1;
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

    task automatic load_handler;
    begin
        write_word(32'd2032, 32'h34102173); // csrrs x2,mepc,x0
        write_word(32'd2036, 32'h00410113); // addi  x2,x2,4
        write_word(32'd2040, 32'h34111073); // csrrw x0,mepc,x2
        write_word(32'd2044, 32'h342021f3); // csrrs x3,mcause,x0
        write_word(32'd2048, 32'h00018593); // addi  x11,x3,0
        write_word(32'd2052, 32'h30200073); // mret
    end
    endtask

    task automatic run_case;
        input string case_name;
        input logic [31:0] fault_instr;
        input logic [31:0] post_trap_instr;
        input logic [31:0] expected_a0;
        input logic [31:0] cause;
        input logic [31:0] tval;
    begin
        expected_fault_instr = fault_instr;
        expected_mcause = cause;
        expected_mtval = tval;
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        step_clk;
        rst_n = 1'b1;
        step_clk;

        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  fault_instr);
        write_word(32'd12, post_trap_instr);
        load_handler();

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        // Stop before sequential zero-filled fetch reaches the handler image
        // at 0x7f0 a second time after the directed program has completed.
        repeat (220) step_clk;
        for (drain_cycles = 0;
             drain_cycles < 500 &&
             dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        a0_preg = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg = dut.u_rename_packet.u_rat_2w.rat[11];
        a0_value = dut.u_prf_2w.regs[a0_preg];
        a1_value = dut.u_prf_2w.regs[a1_preg];

        $display("[SUMMARY:%s] a0=0x%08h a1=0x%08h mtvec=0x%08h mepc=0x%08h mcause=0x%08h mtval=0x%08h traps=%0d bad=%0d early=%0d retires=%0d lsu_reqs=%0d rob_empty=%0b",
                 case_name,
                 a0_value,
                 a1_value,
                 dut.u_execution.u_csr_file.mtvec_q,
                 dut.u_execution.u_csr_file.mepc_q,
                 dut.u_execution.u_csr_file.mcause_q,
                 dut.u_execution.u_csr_file.mtval_q,
                 precise_trap_count,
                 precise_trap_bad_count,
                 early_trap_write_count,
                 fault_retire_count,
                 fault_lsu_request_count,
                 dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1,
                 $sformatf("%s ROB drained", case_name));
        check_ok(a0_value == expected_a0,
                 $sformatf("%s returned and executed post-trap instruction", case_name));
        check_ok(a1_value == cause,
                 $sformatf("%s handler captured mcause", case_name));
        check_ok(dut.u_execution.u_csr_file.mtval_q == tval,
                 $sformatf("%s mtval CSR captured trap value", case_name));
        check_ok(dut.u_execution.u_csr_file.mepc_q == 32'h0000000c,
                 $sformatf("%s handler advanced mepc", case_name));
        check_ok(precise_trap_count == 1,
                 $sformatf("%s trapped exactly once at ROB head", case_name));
        check_ok(precise_trap_bad_count == 0,
                 $sformatf("%s ROB retained precise pc/cause/tval", case_name));
        check_ok(early_trap_write_count == 0,
                 $sformatf("%s did not update trap CSRs at execute", case_name));
        check_ok(fault_retire_count == 0,
                 $sformatf("%s faulting instruction did not retire normally", case_name));
        check_ok(fault_lsu_request_count == 0,
                 $sformatf("%s faulting memory operation did not enter LSU", case_name));
    end
    endtask

    initial begin
        fail_count = 0;
        rst_n = 1'b0;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;
        expected_fault_instr = '0;
        expected_mcause = '0;
        expected_mtval = '0;

        run_case(
            "load",
            32'h00202283, // lw x5,2(x0)
            32'h07700513, // addi x10,x0,0x77
            32'h00000077,
            MCAUSE_LOAD_ADDR_MISALIGNED,
            32'h00000002
        );

        run_case(
            "store",
            32'h00002123, // sw x0,2(x0)
            32'h07800513, // addi x10,x0,0x78
            32'h00000078,
            MCAUSE_STORE_ADDR_MISALIGNED,
            32'h00000002
        );

        run_case(
            "instruction",
            32'h00200067, // jalr x0,2(x0)
            32'h07900513, // addi x10,x0,0x79
            32'h00000079,
            MCAUSE_INSTR_ADDR_MISALIGNED,
            32'h00000002
        );

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_misaligned_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_misaligned_smoke FAIL (%0d errors) ====",
                     fail_count);
        end
        $finish;
    end

endmodule
