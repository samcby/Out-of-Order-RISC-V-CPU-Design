`timescale 1ns/1ps

// Simulation-only top-level integration testbench for top csr smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_csr_smoke;

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
    preg_t a0_preg;
    preg_t a1_preg;
    logic [31:0] a0_value;
    logic [31:0] a1_value;
    logic [31:0] mtvec_value;
    logic [31:0] mie_value;
    int drain_cycles;

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

        // Minimal machine-CSR smoke program:
        // - CSRRW writes mtvec and returns the old zero value.
        // - CSRRS/CSRRC and their immediate forms read old values and update CSR state.
        // - Final architectural results expose CSR readback through integer registers.
        write_word(32'd0,  32'h10000093); // addi   x1,x0,0x100
        write_word(32'd4,  32'h30509573); // csrrw  x10,mtvec,x1
        write_word(32'd8,  32'h305025f3); // csrrs  x11,mtvec,x0
        write_word(32'd12, 32'h3050e673); // csrrsi x12,mtvec,1
        write_word(32'd16, 32'h3050b6f3); // csrrc  x13,mtvec,x1
        write_word(32'd20, 32'h3050f773); // csrrci x14,mtvec,1
        write_word(32'd24, 32'h304457f3); // csrrwi x15,mie,8
        write_word(32'd28, 32'h30402873); // csrrs  x16,mie,x0
        write_word(32'd32, 32'h00080513); // addi   x10,x16,0
        write_word(32'd36, 32'h00070593); // addi   x11,x14,0

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (220) step_clk;

        // CSR serialization can leave the final completed entries retiring a
        // few cycles after the architectural result is already visible.
        for (drain_cycles = 0;
             drain_cycles < 500 && dut.u_dispatch.u_rob.empty !== 1'b1;
             drain_cycles = drain_cycles + 1) begin
            step_clk;
        end

        a0_preg     = dut.u_rename.u_rat.rat[10];
        a1_preg     = dut.u_rename.u_rat.rat[11];
        a0_value    = dut.u_prf.regs[a0_preg];
        a1_value    = dut.u_prf.regs[a1_preg];
        mtvec_value = dut.u_execution.u_csr_file.mtvec_q;
        mie_value   = dut.u_execution.u_csr_file.mie_q;

        $display("[SUMMARY] a0_preg=%0d a0=%0d (0x%08h) a1_preg=%0d a1=%0d (0x%08h) mtvec=0x%08h mie=0x%08h rob_empty=%0b drain_cycles=%0d",
                 a0_preg, $signed(a0_value), a0_value,
                 a1_preg, $signed(a1_value), a1_value,
                 mtvec_value,
                 mie_value,
                 dut.u_dispatch.u_rob.empty,
                 drain_cycles);

        check_ok(dut.u_dispatch.u_rob.empty == 1'b1, "ROB drained after CSR smoke program");
        check_ok(a0_value == 32'h00000008, "CSR smoke a0(x10) reads final mie value 8");
        check_ok(a1_value == 32'h00000001, "CSR smoke a1(x11) reads old mtvec before final clear");
        check_ok(mtvec_value == 32'h00000000, "CSR smoke mtvec cleared by csrrci");
        check_ok(mie_value == 32'h00000008, "CSR smoke mie written by csrrwi");

        if (fail_count == 0) begin
            $display("==== tb_top_csr_smoke PASS ====");
        end else begin
            $display("==== tb_top_csr_smoke FAIL (%0d errors) ====", fail_count);
        end

        $finish;
    end

endmodule
