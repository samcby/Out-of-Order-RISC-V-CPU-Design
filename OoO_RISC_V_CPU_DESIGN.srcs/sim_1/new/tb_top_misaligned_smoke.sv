`timescale 1ns/1ps

module tb_top_misaligned_smoke;

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
    preg_t a2_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] a2_value;
    logic [31:0] mtvec_value;
    logic [31:0] mepc_value;
    logic [31:0] mcause_value;
    logic [31:0] mtval_value;
    logic [31:0] mstatus_value;

    top dut (
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

    task automatic drain_rob;
    begin
        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch.u_rob.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end
    end
    endtask

    task automatic load_shared_handler;
    begin
        // Handler at 0x7f0:
        //   advance mepc past the faulting instruction, copy mcause to a1,
        //   copy mtval to a2, then return.
        write_word(32'd2032, 32'h34102173); // csrrs x2,mepc,x0
        write_word(32'd2036, 32'h00410113); // addi  x2,x2,4
        write_word(32'd2040, 32'h34111073); // csrrw x0,mepc,x2
        write_word(32'd2044, 32'h342021f3); // csrrs x3,mcause,x0
        write_word(32'd2048, 32'h00018593); // addi  x11,x3,0
        write_word(32'd2052, 32'h34302273); // csrrs x4,mtval,x0
        write_word(32'd2056, 32'h00020613); // addi  x12,x4,0
        write_word(32'd2060, 32'h30200073); // mret
    end
    endtask

    task automatic reset_and_load_case;
        input logic [31:0] fault_instr;
        input logic [31:0] post_trap_instr;
    begin
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        // Shared main shape:
        //   mtvec = 0x7f0; faulting instruction; after mret, set a0.
        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  fault_instr);
        write_word(32'd12, post_trap_instr);
        load_shared_handler();

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (260) step_clk;
        drain_rob();
    end
    endtask

    task automatic sample_state;
    begin
        a0_preg       = dut.u_rename.u_rat.rat[10];
        a1_preg       = dut.u_rename.u_rat.rat[11];
        a2_preg       = dut.u_rename.u_rat.rat[12];
        a0_value      = dut.u_prf.regs[a0_preg];
        a1_value      = dut.u_prf.regs[a1_preg];
        a2_value      = dut.u_prf.regs[a2_preg];
        mtvec_value   = dut.u_execution.u_csr_file.mtvec_q;
        mepc_value    = dut.u_execution.u_csr_file.mepc_q;
        mcause_value  = dut.u_execution.u_csr_file.mcause_q;
        mtval_value   = dut.u_execution.u_csr_file.mtval_q;
        mstatus_value = dut.u_execution.u_csr_file.mstatus_q;
    end
    endtask

    task automatic run_misaligned_case;
        input string       case_name;
        input logic [31:0] fault_instr;
        input logic [31:0] post_trap_instr;
        input logic [31:0] expected_a0;
        input logic [31:0] expected_mcause;
        input logic [31:0] expected_mtval;
    begin
        reset_and_load_case(fault_instr, post_trap_instr);
        sample_state();

        $display("[SUMMARY:%s] a0=0x%08h a1=0x%08h a2=0x%08h mtvec=0x%08h mepc=0x%08h mcause=0x%08h mtval=0x%08h mstatus=0x%08h rob_empty=%0b drain_cycles=%0d",
                 case_name,
                 a0_value,
                 a1_value,
                 a2_value,
                 mtvec_value,
                 mepc_value,
                 mcause_value,
                 mtval_value,
                 mstatus_value,
                 dut.u_dispatch.u_rob.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, $sformatf("%s ROB drained", case_name));
        check_ok(a0_value == expected_a0, $sformatf("%s returned from handler and executed post-trap instruction", case_name));
        check_ok(a1_value == expected_mcause, $sformatf("%s a1(x11) captured expected mcause", case_name));
        check_ok(a2_value == expected_mtval, $sformatf("%s a2(x12) captured expected mtval", case_name));
        check_ok(mtvec_value == 32'h000007f0, $sformatf("%s mtvec retains handler address 0x7f0", case_name));
        check_ok(mepc_value == 32'h0000000c, $sformatf("%s handler advanced mepc to 0x0c", case_name));
        check_ok(mcause_value == expected_mcause, $sformatf("%s mcause CSR records expected exception", case_name));
        check_ok(mtval_value == expected_mtval, $sformatf("%s mtval CSR records expected trap value", case_name));
        check_ok(mstatus_value == 32'h00000080, $sformatf("%s mret set MPIE and restored disabled MIE", case_name));
    end
    endtask

    initial begin
        fail_count = 0;

        run_misaligned_case(
            "load",
            32'h00202283, // lw   x5,2(x0)
            32'h07700513, // addi x10,x0,0x77
            32'h00000077,
            MCAUSE_LOAD_ADDR_MISALIGNED,
            32'h00000002
        );

        run_misaligned_case(
            "store",
            32'h00002123, // sw   x0,2(x0)
            32'h07800513, // addi x10,x0,0x78
            32'h00000078,
            MCAUSE_STORE_ADDR_MISALIGNED,
            32'h00000002
        );

        run_misaligned_case(
            "instruction",
            32'h00200067, // jalr x0,2(x0), target 0x2 after bit-0 masking
            32'h07900513, // addi x10,x0,0x79
            32'h00000079,
            MCAUSE_INSTR_ADDR_MISALIGNED,
            32'h00000002
        );

        if (fail_count == 0) begin
            $display("==== tb_top_misaligned_smoke PASS ====");
        end else begin
            $display("==== tb_top_misaligned_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
