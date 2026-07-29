`timescale 1ns / 1ps

// Simulation-only floating-point datapath/control testbench for fp infrastructure smoke.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_fp_infrastructure_smoke;

    import fp_defines_pkg::*;

    logic clk;
    logic rst_n;
    logic [31:0] instr;
    fp_decode_t decoded;

    logic wb0_en;
    fp_preg_t wb0_addr;
    logic [31:0] wb0_data;
    logic wb1_en;
    fp_preg_t wb1_addr;
    logic [31:0] wb1_data;
    fp_preg_t lane0_raddr0;
    fp_preg_t lane0_raddr1;
    fp_preg_t lane1_raddr0;
    fp_preg_t lane1_raddr1;
    logic [31:0] lane0_rdata0;
    logic [31:0] lane0_rdata1;
    logic [31:0] lane1_rdata0;
    logic [31:0] lane1_rdata1;
    logic [1:0] rename_en;
    fp_preg_t lane0_src1_addr;
    fp_preg_t lane0_src2_addr;
    fp_preg_t lane0_new_preg;
    fp_preg_t lane1_src1_addr;
    fp_preg_t lane1_src2_addr;
    fp_preg_t lane1_new_preg;
    logic lane0_src1_ready;
    logic lane0_src2_ready;
    logic lane1_src1_ready;
    logic lane1_src2_ready;

    logic csr_we;
    logic [11:0] csr_addr;
    logic [31:0] csr_wdata;
    logic flags_valid;
    logic [4:0] flags;
    logic [31:0] csr_rdata;
    logic [4:0] fflags;
    logic [2:0] frm;
    logic [7:0] fcsr;

    int errors;

    always #5 clk = ~clk;

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

    task automatic apply_clock;
    begin
        @(posedge clk);
        #1;
    end
    endtask

    fp_decode u_fp_decode (
        .instr   (instr),
        .decoded (decoded)
    );

    fp_reg_file_2w u_fp_reg_file (
        .clk              (clk),
        .rst_n            (rst_n),
        .wb0_en           (wb0_en),
        .wb0_addr         (wb0_addr),
        .wb0_data         (wb0_data),
        .wb1_en           (wb1_en),
        .wb1_addr         (wb1_addr),
        .wb1_data         (wb1_data),
        .lane0_raddr0     (lane0_raddr0),
        .lane0_rdata0     (lane0_rdata0),
        .lane0_raddr1     (lane0_raddr1),
        .lane0_rdata1     (lane0_rdata1),
        .lane1_raddr0     (lane1_raddr0),
        .lane1_rdata0     (lane1_rdata0),
        .lane1_raddr1     (lane1_raddr1),
        .lane1_rdata1     (lane1_rdata1),
        .rename_en        (rename_en),
        .lane0_src1_addr  (lane0_src1_addr),
        .lane0_src2_addr  (lane0_src2_addr),
        .lane0_new_preg   (lane0_new_preg),
        .lane1_src1_addr  (lane1_src1_addr),
        .lane1_src2_addr  (lane1_src2_addr),
        .lane1_new_preg   (lane1_new_preg),
        .lane0_src1_ready (lane0_src1_ready),
        .lane0_src2_ready (lane0_src2_ready),
        .lane1_src1_ready (lane1_src1_ready),
        .lane1_src2_ready (lane1_src2_ready)
    );

    fp_csr u_fp_csr (
        .clk         (clk),
        .rst_n       (rst_n),
        .csr_we      (csr_we),
        .csr_addr    (csr_addr),
        .csr_wdata   (csr_wdata),
        .flags_valid (flags_valid),
        .flags       (flags),
        .csr_rdata   (csr_rdata),
        .fflags      (fflags),
        .frm         (frm),
        .fcsr        (fcsr)
    );

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        instr = '0;
        wb0_en = 1'b0;
        wb0_addr = '0;
        wb0_data = '0;
        wb1_en = 1'b0;
        wb1_addr = '0;
        wb1_data = '0;
        lane0_raddr0 = '0;
        lane0_raddr1 = '0;
        lane1_raddr0 = '0;
        lane1_raddr1 = '0;
        rename_en = '0;
        lane0_src1_addr = '0;
        lane0_src2_addr = '0;
        lane0_new_preg = '0;
        lane1_src1_addr = '0;
        lane1_src2_addr = '0;
        lane1_new_preg = '0;
        csr_we = 1'b0;
        csr_addr = '0;
        csr_wdata = '0;
        flags_valid = 1'b0;
        flags = '0;
        errors = 0;

        repeat (2) apply_clock();
        rst_n = 1'b1;
        apply_clock();

        instr = {12'd8, 5'd2, 3'b010, 5'd1, 7'b0000111};
        #1;
        check_ok(decoded.valid && !decoded.illegal &&
                 decoded.operation == FP_OP_LOAD,
                 "FLW is recognized");
        check_ok(decoded.int_rs1_valid && decoded.int_rs1 == 5'd2 &&
                 decoded.fp_rd_valid && decoded.fp_rd == 5'd1,
                 "FLW crosses integer address to FP destination");

        instr = {7'd0, 5'd3, 5'd4, 3'b010, 5'd12, 7'b0100111};
        #1;
        check_ok(decoded.valid && !decoded.illegal &&
                 decoded.operation == FP_OP_STORE,
                 "FSW is recognized");
        check_ok(decoded.int_rs1_valid && decoded.int_rs1 == 5'd4 &&
                 decoded.fp_rs2_valid && decoded.fp_rs2 == 5'd3,
                 "FSW uses integer base and FP store data");

        instr = {7'b0000000, 5'd7, 5'd6, 3'b000, 5'd5, 7'b1010011};
        #1;
        check_ok(decoded.operation == FP_OP_ADD && !decoded.illegal &&
                 decoded.fp_rs1_valid && decoded.fp_rs2_valid &&
                 decoded.fp_rd_valid,
                 "FADD.S decodes two FP sources and one FP destination");

        instr = {5'd8, 2'b00, 5'd7, 5'd6, 3'b111, 5'd5, 7'b1000011};
        #1;
        check_ok(decoded.operation == FP_OP_MADD && !decoded.illegal &&
                 decoded.fp_rs3_valid && decoded.uses_rounding_mode,
                 "FMADD.S decodes the third FP source and dynamic rounding");

        instr = {7'b1100000, 5'd0, 5'd9, 3'b001, 5'd10, 7'b1010011};
        #1;
        check_ok(decoded.operation == FP_OP_CVT_W_S && !decoded.illegal &&
                 decoded.fp_rs1_valid && decoded.int_rd_valid,
                 "FCVT.W.S crosses from FP source to integer destination");

        instr = {7'b1101000, 5'd0, 5'd11, 3'b010, 5'd12, 7'b1010011};
        #1;
        check_ok(decoded.operation == FP_OP_CVT_S_W && !decoded.illegal &&
                 decoded.int_rs1_valid && decoded.fp_rd_valid,
                 "FCVT.S.W crosses from integer source to FP destination");

        instr = {7'b1010000, 5'd2, 5'd1, 3'b010, 5'd3, 7'b1010011};
        #1;
        check_ok(decoded.operation == FP_OP_EQ && !decoded.illegal &&
                 decoded.fp_rs1_valid && decoded.fp_rs2_valid &&
                 decoded.int_rd_valid,
                 "FEQ.S writes an integer destination");

        instr = {7'b0000000, 5'd7, 5'd6, 3'b101, 5'd5, 7'b1010011};
        #1;
        check_ok(decoded.valid && decoded.illegal &&
                 decoded.operation == FP_OP_NONE,
                 "reserved rounding mode is rejected");

        instr = 32'h00100093;
        #1;
        check_ok(!decoded.valid && !decoded.illegal,
                 "integer instruction is ignored by FP decoder");

        lane0_src1_addr = fp_preg_t'(7'd40);
        lane1_src1_addr = fp_preg_t'(7'd40);
        lane1_src2_addr = fp_preg_t'(7'd41);
        lane0_new_preg = fp_preg_t'(7'd40);
        lane1_new_preg = fp_preg_t'(7'd41);
        rename_en = 2'b11;
        #1;
        check_ok(!lane0_src1_ready && !lane1_src1_ready &&
                 !lane1_src2_ready,
                 "FP PRF exposes same-packet rename dependencies");
        apply_clock();
        rename_en = '0;
        check_ok(!lane0_src1_ready && !lane1_src2_ready,
                 "FP rename clears both destination ready bits");

        wb0_en = 1'b1;
        wb0_addr = fp_preg_t'(7'd40);
        wb0_data = 32'h3f800000;
        wb1_en = 1'b1;
        wb1_addr = fp_preg_t'(7'd41);
        wb1_data = 32'h40000000;
        lane0_raddr0 = fp_preg_t'(7'd40);
        lane1_raddr1 = fp_preg_t'(7'd41);
        #1;
        check_ok(lane0_src1_ready && lane1_src2_ready,
                 "dual FP writeback forwards readiness");
        check_ok(lane0_rdata0 == 32'h3f800000 &&
                 lane1_rdata1 == 32'h40000000,
                 "dual FP writeback forwards data");
        apply_clock();
        wb0_en = 1'b0;
        wb1_en = 1'b0;
        check_ok(lane0_rdata0 == 32'h3f800000 &&
                 lane1_rdata1 == 32'h40000000,
                 "FP PRF stores both writeback values");

        wb0_en = 1'b1;
        wb0_addr = fp_preg_t'(7'd0);
        wb0_data = 32'h40400000;
        lane0_raddr1 = fp_preg_t'(7'd0);
        apply_clock();
        wb0_en = 1'b0;
        check_ok(lane0_rdata1 == 32'h40400000,
                 "floating-point register zero remains writable");

        csr_we = 1'b1;
        csr_addr = CSR_FRM;
        csr_wdata = 32'd3;
        apply_clock();
        csr_we = 1'b0;
        check_ok(frm == 3'd3 && fcsr[7:5] == 3'd3,
                 "FRM write updates the FCSR rounding field");

        flags_valid = 1'b1;
        flags = 5'b00101;
        apply_clock();
        flags = 5'b10000;
        apply_clock();
        flags_valid = 1'b0;
        check_ok(fflags == 5'b10101,
                 "floating-point exception flags accumulate");

        csr_we = 1'b1;
        csr_addr = CSR_FCSR;
        csr_wdata = 32'h00000042;
        flags_valid = 1'b1;
        flags = 5'b01000;
        apply_clock();
        csr_we = 1'b0;
        flags_valid = 1'b0;
        csr_addr = CSR_FCSR;
        #1;
        check_ok(frm == 3'b010 && fflags == 5'b01010 &&
                 csr_rdata[7:0] == 8'h4a,
                 "FCSR aliases FRM and sticky FFLAGS");

        if (errors == 0) begin
            $display("==== tb_fp_infrastructure_smoke PASS ====");
        end else begin
            $display("==== tb_fp_infrastructure_smoke FAIL (%0d errors) ====", errors);
        end
        $finish;
    end

endmodule
