`timescale 1ns/1ps

// Simulation-only top-level integration testbench for top interrupt sources smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_interrupt_sources_smoke;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic software_irq;
    logic timer_irq;
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
    preg_t a0_preg;
    preg_t a1_preg;
    preg_t a2_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] a2_value;
    logic [31:0] mtvec_value;
    logic [31:0] mstatus_value;
    logic [31:0] mie_value;
    logic [31:0] mcause_value;

    top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .software_irq     (software_irq),
        .timer_irq        (timer_irq),
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

    task automatic load_program;
        input logic [31:0] mie_enable_value;
    begin
        write_word(32'd0,  32'h7f000093); // addi  x1,x0,0x7f0
        write_word(32'd4,  32'h30509073); // csrrw x0,mtvec,x1
        write_word(32'd8,  32'h00800113); // addi  x2,x0,8
        write_word(32'd12, 32'h30011073); // csrrw x0,mstatus,x2
        if (mie_enable_value == 32'h00000888) begin
            write_word(32'd16, 32'h000011b7); // lui  x3,0x1
            write_word(32'd20, 32'h88818193); // addi x3,x3,-0x778
        end else if (mie_enable_value == 32'h00000088) begin
            write_word(32'd16, 32'h08800193); // addi x3,x0,0x88
            write_word(32'd20, 32'h00000013); // nop
        end else if (mie_enable_value == 32'h00000080) begin
            write_word(32'd16, 32'h08000193); // addi x3,x0,0x80
            write_word(32'd20, 32'h00000013); // nop
        end else begin
            write_word(32'd16, 32'h00800193); // addi x3,x0,0x08
            write_word(32'd20, 32'h00000013); // nop
        end
        write_word(32'd24, 32'h30419073); // csrrw x0,mie,x3
        write_word(32'd28, 32'h03300513); // addi  x10,x0,0x33

        // Shared handler at 0x7f0: capture mstatus and mcause, then return.
        write_word(32'd2032, 32'h30002673); // csrrs x12,mstatus,x0
        write_word(32'd2036, 32'h342025f3); // csrrs x11,mcause,x0
        write_word(32'd2040, 32'h30200073); // mret
    end
    endtask

    task automatic reset_and_load;
        input logic [31:0] mie_enable_value;
    begin
        rst_n = 1'b0;
        software_irq = 1'b0;
        timer_irq = 1'b0;
        external_irq = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;

        step_clk;
        rst_n = 1'b1;
        step_clk;

        load_program(mie_enable_value);

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;
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
        mstatus_value = dut.u_execution.u_csr_file.mstatus_q;
        mie_value     = dut.u_execution.u_csr_file.mie_q;
        mcause_value  = dut.u_execution.u_csr_file.mcause_q;
    end
    endtask

    task automatic run_irq_case;
        input string case_name;
        input int    irq_kind;
        input logic [31:0] mie_enable_value;
        input logic [31:0] expected_mcause;
    begin
        reset_and_load(mie_enable_value);

        if (irq_kind == 0) begin
            software_irq = 1'b1;
        end else begin
            timer_irq = 1'b1;
        end
        step_clk;
        software_irq = 1'b0;
        timer_irq = 1'b0;

        repeat (220) step_clk;
        drain_rob();
        sample_state();

        $display("[SUMMARY:%s] a0=0x%08h a1=0x%08h a2=0x%08h mtvec=0x%08h mstatus=0x%08h mie=0x%08h mcause=0x%08h rob_empty=%0b drain_cycles=%0d",
                 case_name,
                 a0_value,
                 a1_value,
                 a2_value,
                 mtvec_value,
                 mstatus_value,
                 mie_value,
                 mcause_value,
                 dut.u_dispatch.u_rob.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, $sformatf("%s ROB drained", case_name));
        check_ok(a0_value == 32'h00000033, $sformatf("%s main program completed before interrupt", case_name));
        check_ok(a1_value == expected_mcause, $sformatf("%s handler captured expected mcause", case_name));
        check_ok(a2_value == 32'h00001880, $sformatf("%s trap entry mstatus captured MIE->MPIE and MPP=M", case_name));
        check_ok(mtvec_value == 32'h000007f0, $sformatf("%s mtvec retains handler address", case_name));
        check_ok(mstatus_value == 32'h00000088, $sformatf("%s mret restored MIE and cleared MPP", case_name));
        check_ok(mie_value == mie_enable_value, $sformatf("%s mie retains selected interrupt enable", case_name));
        check_ok(mcause_value == expected_mcause, $sformatf("%s mcause CSR records expected interrupt", case_name));
    end
    endtask

    task automatic run_priority_case;
        input string case_name;
        input logic  sw_pending;
        input logic  timer_pending;
        input logic  ext_pending;
        input logic [31:0] mie_enable_value;
        input logic [31:0] expected_mcause;
    begin
        reset_and_load(mie_enable_value);

        software_irq = sw_pending;
        timer_irq    = timer_pending;
        external_irq = ext_pending;
        step_clk;

        $display("[PRIORITY:%s] interrupt_take=%0b interrupt_mcause=0x%08h mie=0x%08h sw=%0b timer=%0b ext=%0b",
                 case_name,
                 dut.interrupt_take,
                 dut.interrupt_mcause,
                 dut.u_execution.u_csr_file.mie_q,
                 sw_pending,
                 timer_pending,
                 ext_pending);

        check_ok(dut.interrupt_take == 1'b1, $sformatf("%s selected a pending interrupt", case_name));
        check_ok(dut.interrupt_mcause == expected_mcause, $sformatf("%s selected expected interrupt priority", case_name));

        software_irq = 1'b0;
        timer_irq    = 1'b0;
        external_irq = 1'b0;
    end
    endtask

    initial begin
        fail_count = 0;
        run_irq_case("software", 0, 32'h00000008, 32'h80000003);
        run_irq_case("timer",    1, 32'h00000080, 32'h80000007);
        run_priority_case("software_over_timer", 1'b1, 1'b1, 1'b0, 32'h00000088, 32'h80000003);
        run_priority_case("external_over_software", 1'b1, 1'b0, 1'b1, 32'h00000888, 32'h8000000b);

        if (fail_count == 0) begin
            $display("==== tb_top_interrupt_sources_smoke PASS ====");
        end else begin
            $display("==== tb_top_interrupt_sources_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
