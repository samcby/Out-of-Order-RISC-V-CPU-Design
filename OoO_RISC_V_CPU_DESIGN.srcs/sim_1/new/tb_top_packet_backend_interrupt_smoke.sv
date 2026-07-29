`timescale 1ns/1ps

// Simulation-only integration-level packet-backend testbench for top packet backend interrupt smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_interrupt_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic external_irq;

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
    int csr_system_issue_count;
    int csr_system_pair_count;
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t a2_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] a2_value;
    logic [31:0] mtvec_value;
    logic [31:0] mepc_value;
    logic [31:0] mcause_value;
    logic [31:0] mie_value;
    logic [31:0] mstatus_value;
    logic [31:0] mip_value;

    top_packet_backend dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .software_irq     (1'b0),
        .timer_irq        (1'b0),
        .external_irq     (external_irq),
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
            csr_system_issue_count <= 0;
            csr_system_pair_count  <= 0;
        end else begin
            #1;
            if (dut.issue_if.valid && dut.issue_if.ready &&
                (dut.issue_if.data.fu_sel == FU_ALU) &&
                (dut.issue_if.data.control_signal.alu.csr_en ||
                 dut.issue_if.data.control_signal.alu.sys_en)) begin
                csr_system_issue_count <= csr_system_issue_count + 1;
                if (dut.issue1_if.valid && dut.issue1_if.ready) begin
                    csr_system_pair_count <= csr_system_pair_count + 1;
                end
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
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        fail_count = 0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Main program:
        //   mtvec = 0xf00
        //   mstatus.MIE = 1
        //   mie.MEIE = 1
        //   a0 = 0x22
        write_word(32'd0,  32'h000010b7); // lui   x1,0x1
        write_word(32'd4,  32'hf0008093); // addi  x1,x1,-256 -> 0xf00
        write_word(32'd8,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd12, 32'h00800113); // addi  x2,x0,8
        write_word(32'd16, 32'h30011073); // csrrw x0,mstatus,x2
        write_word(32'd20, 32'h00100193); // addi  x3,x0,1
        write_word(32'd24, 32'h00b19193); // slli  x3,x3,11
        write_word(32'd28, 32'h30419073); // csrrw x0,mie,x3
        write_word(32'd32, 32'h02200513); // addi  x10,x0,0x22

        // Machine external interrupt handler at 0xf00:
        //   a2 = mstatus at trap entry
        //   a1 = mcause
        //   mret
        write_word(32'd3840, 32'h30002673); // csrrs x12,mstatus,x0
        write_word(32'd3844, 32'h342025f3); // csrrs x11,mcause,x0
        write_word(32'd3848, 32'h30200073); // mret

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        external_irq = 1'b1;
        step_clk;
        external_irq = 1'b0;

        repeat (220) step_clk;

        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch_packet.u_rob_2w.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        a0_preg       = dut.u_rename_packet.u_rat_2w.rat[10];
        a1_preg       = dut.u_rename_packet.u_rat_2w.rat[11];
        a2_preg       = dut.u_rename_packet.u_rat_2w.rat[12];
        a0_value      = dut.u_prf_2w.regs[a0_preg];
        a1_value      = dut.u_prf_2w.regs[a1_preg];
        a2_value      = dut.u_prf_2w.regs[a2_preg];
        mtvec_value   = dut.u_execution.u_csr_file.mtvec_q;
        mepc_value    = dut.u_execution.u_csr_file.mepc_q;
        mcause_value  = dut.u_execution.u_csr_file.mcause_q;
        mie_value     = dut.u_execution.u_csr_file.mie_q;
        mstatus_value = dut.u_execution.u_csr_file.mstatus_q;
        mip_value     = dut.u_execution.u_csr_file.mip_q;

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=0x%08h a2_preg=%0d a2=0x%08h mtvec=0x%08h mepc=0x%08h mcause=0x%08h mstatus=0x%08h mie=0x%08h mip=0x%08h csr_sys_issue=%0d csr_sys_pair=%0d rob_empty=%0b drain_cycles=%0d",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, a1_value,
                 a2_preg, a2_value,
                 mtvec_value,
                 mepc_value,
                 mcause_value,
                 mstatus_value,
                 mie_value,
                 mip_value,
                 csr_system_issue_count,
                 csr_system_pair_count,
                 dut.u_dispatch_packet.u_rob_2w.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch_packet.u_rob_2w.empty == 1'b1, "packet backend ROB drained after interrupt smoke program");
        check_ok(a0_value == 32'h00000022, "packet backend interrupt main program completed before interrupt");
        check_ok(a1_value == 32'h8000000b, "packet backend interrupt handler captured machine external interrupt mcause");
        check_ok(a2_value == 32'h00001880, "packet backend interrupt trap entry saved MIE into MPIE and set MPP=M");
        check_ok(mtvec_value == 32'h00000f00, "packet backend interrupt mtvec retains handler address 0xf00");
        check_ok(mstatus_value == 32'h00000088, "packet backend interrupt mret restored MIE from MPIE and cleared MPP");
        check_ok(mie_value[11] == 1'b1, "packet backend interrupt mie.MEIE remains enabled");
        check_ok(mcause_value == 32'h8000000b, "packet backend interrupt mcause records machine external interrupt");
        check_ok(csr_system_issue_count >= 1, "packet backend interrupt issued CSR/system operations");
        check_ok(csr_system_pair_count == 0, "packet backend interrupt kept CSR/system operations single-issue");

        if (fail_count == 0) begin
            $display("==== tb_top_packet_backend_interrupt_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_interrupt_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
