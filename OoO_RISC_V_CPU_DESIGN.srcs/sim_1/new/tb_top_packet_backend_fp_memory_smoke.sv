`timescale 1ns / 1ps

// Simulation-only integration-level packet-backend testbench for top packet backend fp memory smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_top_packet_backend_fp_memory_smoke;

    import defines_pkg::*;
    import fp_defines_pkg::*;

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

    fp_preg_t f0_preg;
    fp_preg_t f1_preg;
    logic [31:0] f0_value;
    logic [31:0] f1_value;
    logic [31:0] stored_way0;
    logic [31:0] stored_way1;
    int errors;

    always #5 clk = ~clk;

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic check_ok(input logic condition, input string message);
    begin
        if (condition) begin
            $display("[PASS] %s", message);
        end else begin
            $display("[FAIL] %s", message);
            errors = errors + 1;
        end
    end
    endtask

    task automatic write_byte(input logic [31:0] address, input logic [7:0] value);
    begin
        load_en = 1'b1;
        load_addr = address;
        load_instr_byte = value;
        step_clk();
    end
    endtask

    task automatic write_word(input logic [31:0] address, input logic [31:0] value);
    begin
        write_byte(address + 0, value[7:0]);
        write_byte(address + 1, value[15:8]);
        write_byte(address + 2, value[23:16]);
        write_byte(address + 3, value[31:24]);
    end
    endtask

    top_packet_backend u_dut (
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
        .rob_head_rd(rob_head_rd)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        errors = 0;

        step_clk();
        rst_n = 1'b1;
        step_clk();

        u_dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] = 32'h3fc00000;
        u_dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[1] = '0;

        write_word(32'd0,  32'h00000093); // addi x1,x0,0
        write_word(32'd4,  32'h0000a087); // flw  f1,0(x1)
        write_word(32'd8,  32'h0010a227); // fsw  f1,4(x1)
        write_word(32'd12, 32'h0040a007); // flw  f0,4(x1)

        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (350) step_clk();

        f0_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[0];
        f1_preg = u_dut.u_rename_packet.u_fp_rename_map.u_fp_rat.rat[1];
        f0_value = u_dut.u_fp_prf_2w.regs[f0_preg];
        f1_value = u_dut.u_fp_prf_2w.regs[f1_preg];
        stored_way0 = u_dut.u_execution.u_lsu.u_data_cache.line_data[0][0][1];
        stored_way1 = u_dut.u_execution.u_lsu.u_data_cache.line_data[0][1][1];

        $display("[SUMMARY] f0_preg=%0d f0=0x%08h f1_preg=%0d f1=0x%08h store0=0x%08h store1=0x%08h rob_empty=%0b",
                 f0_preg, f0_value, f1_preg, f1_value,
                 stored_way0, stored_way1,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(u_dut.u_dispatch_packet.u_rob_2w.empty,
                 "packet backend ROB drains after FLW/FSW program");
        check_ok(f1_value == 32'h3fc00000,
                 "FLW writes the expected payload into f1");
        check_ok((stored_way0 == 32'h3fc00000) ||
                 (stored_way1 == 32'h3fc00000),
                 "FSW commits the f1 payload through the ordered LSU");
        check_ok(f0_value == 32'h3fc00000,
                 "FLW writes architectural f0 and observes the older FSW");
        check_ok(f0_preg != fp_preg_t'(0),
                 "architectural f0 is renamed rather than hard-wired");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_memory_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_memory_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
