`timescale 1ns / 1ps

// Integration test for the architectural mstatus.FS=Off gate. It verifies
// that representative FP ALU, load, store, and FP-CSR instructions become
// precise illegal-instruction traps without touching FP or memory state.
module tb_top_packet_backend_fp_fs_smoke;

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

    int errors;
    int trap_count;
    int disabled_fire_count;
    int forbidden_side_effect_count;
    logic [31:0] x10_value;
    logic [31:0] x11_value;
    logic [31:0] x12_value;
    logic [31:0] x20_value;
    preg_t x10_preg;
    preg_t x11_preg;
    preg_t x12_preg;
    preg_t x20_preg;

    localparam logic [31:0] FP_ALU_INSTR =
        {7'b1111000, 5'd0, 5'd0, 3'b000, 5'd1, 7'b1010011};
    localparam logic [31:0] FLW_INSTR =
        {12'd0, 5'd0, 3'b010, 5'd2, 7'b0000111};
    localparam logic [31:0] FSW_INSTR =
        {7'd0, 5'd2, 5'd0, 3'b010, 5'd4, 7'b0100111};
    localparam logic [31:0] FFLAGS_READ_INSTR =
        {12'h001, 5'd0, 3'b010, 5'd5, 7'b1110011};

    always #5 clk = ~clk;

    function automatic logic [31:0] csr_instr(
        input logic [11:0] csr,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
    begin
        csr_instr = {csr, rs1, funct3, rd, 7'b1110011};
    end
    endfunction

    task automatic step_clk;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    task automatic write_byte(
        input logic [31:0] address,
        input logic [7:0] value
    );
    begin
        load_en = 1'b1;
        load_addr = address;
        load_instr_byte = value;
        step_clk();
    end
    endtask

    task automatic write_word(
        input logic [31:0] address,
        input logic [31:0] value
    );
    begin
        write_byte(address + 0, value[7:0]);
        write_byte(address + 1, value[15:8]);
        write_byte(address + 2, value[23:16]);
        write_byte(address + 3, value[31:24]);
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

    always @(posedge clk) begin
        if (rst_n) begin
            if (u_dut.trap_commit &&
                (u_dut.rob_head.datapath.pc >= 32'd12) &&
                (u_dut.rob_head.datapath.pc <= 32'd24)) begin
                trap_count <= trap_count + 1;
                if ((u_dut.rob_head.datapath.exception_cause !=
                     MCAUSE_ILLEGAL) ||
                    (u_dut.rob_head.datapath.exception_tval !=
                     u_dut.rob_head.datapath.instr)) begin
                    forbidden_side_effect_count <=
                        forbidden_side_effect_count + 1;
                end
            end

            if (u_dut.u_execution.issue0_fp_disabled_fire ||
                u_dut.u_execution.issue1_fp_disabled_fire) begin
                disabled_fire_count <= disabled_fire_count + 1;
            end

            if ((u_dut.u_execution.lsu_req_valid &&
                 ((u_dut.u_execution.selected_mem_datapath.pc == 32'd16) ||
                  (u_dut.u_execution.selected_mem_datapath.pc == 32'd20))) ||
                u_dut.u_execution.fp0_out_valid ||
                u_dut.u_execution.fp1_out_valid ||
                u_dut.u_execution.fp_long_out_valid ||
                u_dut.fp_csr_write_en) begin
                forbidden_side_effect_count <=
                    forbidden_side_effect_count + 1;
            end
        end
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        load_en = 1'b1;
        load_addr = '0;
        load_instr_byte = '0;
        errors = 0;
        trap_count = 0;
        disabled_fire_count = 0;
        forbidden_side_effect_count = 0;

        repeat (2) step_clk();
        rst_n = 1'b1;
        step_clk();

        // Main program: configure mtvec, explicitly keep FS Off, and execute
        // one representative instruction from each FP-state access class.
        write_word(32'd0,  32'h10000093); // addi x1,x0,0x100
        write_word(32'd4,  csr_instr(CSR_MTVEC, 5'd1, 3'b001, 5'd0));
        write_word(32'd8,  csr_instr(CSR_MSTATUS, 5'd0, 3'b001, 5'd0));
        write_word(32'd12, FP_ALU_INSTR);
        write_word(32'd16, FLW_INSTR);
        write_word(32'd20, FSW_INSTR);
        write_word(32'd24, FFLAGS_READ_INSTR);
        write_word(32'd28, 32'h05500513); // addi x10,x0,0x55
        write_word(32'd32, 32'h0000006f); // jal x0,0

        // Trap handler records the latest fault, counts traps, advances mepc,
        // and returns so all four prohibited classes are exercised.
        write_word(32'h100, csr_instr(CSR_MCAUSE, 5'd0, 3'b010, 5'd11));
        write_word(32'h104, csr_instr(CSR_MTVAL, 5'd0, 3'b010, 5'd12));
        write_word(32'h108, 32'h001a0a13); // addi x20,x20,1
        write_word(32'h10c, csr_instr(CSR_MEPC, 5'd0, 3'b010, 5'd13));
        write_word(32'h110, 32'h00468693); // addi x13,x13,4
        write_word(32'h114, csr_instr(CSR_MEPC, 5'd13, 3'b001, 5'd0));
        write_word(32'h118, 32'h30200073); // mret

        u_dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] =
            32'h11223344;
        load_en = 1'b0;
        load_addr = '0;
        load_instr_byte = '0;

        repeat (900) step_clk();

        x10_preg = u_dut.u_rename_packet.u_rat_2w.rat[10];
        x11_preg = u_dut.u_rename_packet.u_rat_2w.rat[11];
        x12_preg = u_dut.u_rename_packet.u_rat_2w.rat[12];
        x20_preg = u_dut.u_rename_packet.u_rat_2w.rat[20];
        x10_value = u_dut.u_prf_2w.regs[x10_preg];
        x11_value = u_dut.u_prf_2w.regs[x11_preg];
        x12_value = u_dut.u_prf_2w.regs[x12_preg];
        x20_value = u_dut.u_prf_2w.regs[x20_preg];

        $display("[SUMMARY] traps=%0d disabled_fires=%0d bad_effects=%0d a0=0x%08h mcause=0x%08h mtval=0x%08h count=%0d mstatus=0x%08h rob_empty=%0b",
                 trap_count, disabled_fire_count,
                 forbidden_side_effect_count, x10_value, x11_value,
                 x12_value, x20_value, u_dut.csr_mstatus_value,
                 u_dut.u_dispatch_packet.u_rob_2w.empty);

        check_ok(trap_count == 4,
                 "FP ALU, FLW, FSW, and FP CSR each trap exactly once");
        check_ok(disabled_fire_count >= 4,
                 "both-slot FS gate catches every prohibited issue attempt");
        check_ok(forbidden_side_effect_count == 0,
                 "FS=Off instructions never enter FPU, LSU, or FP CSR");
        check_ok(x10_value == 32'h00000055,
                 "execution resumes after the final illegal instruction");
        check_ok(x11_value == MCAUSE_ILLEGAL,
                 "handler observes illegal-instruction mcause");
        check_ok(x12_value == FFLAGS_READ_INSTR,
                 "handler observes the prohibited instruction in mtval");
        check_ok(x20_value == 32'd4,
                 "handler executed once for every prohibited FP access");
        check_ok(u_dut.csr_mstatus_value[14:13] == 2'b00,
                 "mstatus.FS remains Off");
        check_ok(u_dut.fp_fflags == 5'b0,
                 "prohibited FP operations do not update fflags");
        check_ok(u_dut.u_execution.u_lsu.u_data_cache.u_data_memory.mem[0] ==
                 32'h11223344,
                 "prohibited FSW has no backing-memory side effect");

        if (errors == 0) begin
            $display("==== tb_top_packet_backend_fp_fs_smoke PASS ====");
        end else begin
            $display("==== tb_top_packet_backend_fp_fs_smoke FAIL (%0d errors) ====",
                     errors);
        end
        $finish;
    end

endmodule
