`timescale 1ns/1ps

// Simulation-only top-level integration testbench for top trap smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_trap_smoke;

    import defines_pkg::*;

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
    int drain_cycles;
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] mtvec_value;
    logic [31:0] mepc_value;
    logic [31:0] mcause_value;
    logic [31:0] mstatus_value;

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

    initial begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Main program:
        //   mtvec = 0x7f0; ecall; after mret, set a0 = 0x55.
        // The handler is placed far away so normal fall-through cannot reach
        // it before this directed smoke test samples final state.
        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00000073); // ecall
        write_word(32'd12, 32'h05500513); // addi  x10,x0,0x55

        // Trap handler at 0x7f0:
        //   read mepc, advance it past ecall, read mcause into a1, return.
        write_word(32'd2032, 32'h34102173); // csrrs x2,mepc,x0
        write_word(32'd2036, 32'h00410113); // addi  x2,x2,4
        write_word(32'd2040, 32'h34111073); // csrrw x0,mepc,x2
        write_word(32'd2044, 32'h342021f3); // csrrs x3,mcause,x0
        write_word(32'd2048, 32'h00018593); // addi  x11,x3,0
        write_word(32'd2052, 32'h30200073); // mret

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch.u_rob.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        a0_preg      = dut.u_rename.u_rat.rat[10];
        a1_preg      = dut.u_rename.u_rat.rat[11];
        a0_value     = dut.u_prf.regs[a0_preg];
        a1_value     = dut.u_prf.regs[a1_preg];
        mtvec_value  = dut.u_execution.u_csr_file.mtvec_q;
        mepc_value   = dut.u_execution.u_csr_file.mepc_q;
        mcause_value = dut.u_execution.u_csr_file.mcause_q;
        mstatus_value = dut.u_execution.u_csr_file.mstatus_q;

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) mtvec=0x%08h mepc=0x%08h mcause=0x%08h mstatus=0x%08h rob_empty=%0b drain_cycles=%0d",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 mtvec_value,
                 mepc_value,
                 mcause_value,
                 mstatus_value,
                 dut.u_dispatch.u_rob.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, "ROB drained after trap smoke program");
        check_ok(a0_value == 32'h00000055, "Trap smoke returned from handler and executed post-ecall instruction");
        check_ok(a1_value == 32'h0000000b, "Trap smoke a1(x11) captured ECALL mcause 11");
        check_ok(mtvec_value == 32'h000007f0, "Trap smoke mtvec retains handler address 0x7f0");
        check_ok(mepc_value == 32'h0000000c, "Trap smoke handler advanced mepc to 0x0c");
        check_ok(mcause_value == 32'h0000000b, "Trap smoke mcause records machine ECALL");
        check_ok(mstatus_value == 32'h00000080, "Trap smoke mret set MPIE and restored disabled MIE");

        if (fail_count == 0) begin
            $display("==== tb_top_trap_smoke PASS ====");
        end else begin
            $display("==== tb_top_trap_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
