`timescale 1ns/1ps

// Simulation-only directed unit-level testbench for issue packet arbiter.
//
// Generates a clock/reset and directed stimulus, then observes DUT outputs,
// assertions, or explicit checks to validate the behavior named by this file.
// Delays, initial blocks, tasks, $display, and $fatal are intentional testbench
// constructs and must not be included in synthesizable hardware source lists.
module tb_issue_packet_arbiter;

    import defines_pkg::*;

    logic clk;
    logic rst_n;
    logic [1:0] issue0_fu_sel;
    logic [1:0] issue1_fu_sel;

    pip_if #(alu_rs_t)    alu_if    (.clk(clk), .rst_n(rst_n));
    pip_if #(alu_rs_t)    alu1_if   (.clk(clk), .rst_n(rst_n));
    pip_if #(lsu_rs_t)    lsu_if    (.clk(clk), .rst_n(rst_n));
    pip_if #(branch_rs_t) branch_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue0_if (.clk(clk), .rst_n(rst_n));
    pip_if #(issue_exe_t) issue1_if (.clk(clk), .rst_n(rst_n));

    issue_packet_arbiter dut (
        .alu_if(alu_if.consumer),
        .alu1_if(alu1_if.consumer),
        .lsu_if(lsu_if.consumer),
        .branch_if(branch_if.consumer),
        .issue0_if(issue0_if.producer),
        .issue1_if(issue1_if.producer),
        .rob_head_valid(1'bx),
        .rob_head_tag('x),
        .issue0_fu_sel(issue0_fu_sel),
        .issue1_fu_sel(issue1_fu_sel)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_ok(input logic cond, input string msg);
    begin
        if (!cond) begin
            $display("[FAIL] %s", msg);
            $fatal;
        end else begin
            $display("[PASS] %s", msg);
        end
    end
    endtask

    task automatic clear_inputs;
    begin
        alu_if.valid = 1'b0;
        alu_if.data = '0;
        alu1_if.valid = 1'b0;
        alu1_if.data = '0;
        lsu_if.valid = 1'b0;
        lsu_if.data = '0;
        branch_if.valid = 1'b0;
        branch_if.data = '0;
        issue0_if.ready = 1'b1;
        issue1_if.ready = 1'b1;
        #1;
    end
    endtask

    task automatic set_alu1(
        input rob_tag_t tag,
        input logic csr_en,
        input logic sys_en
    );
    begin
        alu1_if.valid = 1'b1;
        alu1_if.data = '0;
        alu1_if.data.datapath.rob_tag = tag;
        alu1_if.data.datapath.pc = 32'h00001100 + {24'b0, tag};
        alu1_if.data.control_signal.reg_write = 1'b1;
        alu1_if.data.control_signal.csr_en = csr_en;
        alu1_if.data.control_signal.sys_en = sys_en;
        #1;
    end
    endtask

    task automatic set_alu(
        input rob_tag_t tag,
        input logic csr_en,
        input logic sys_en
    );
    begin
        alu_if.valid = 1'b1;
        alu_if.data = '0;
        alu_if.data.datapath.rob_tag = tag;
        alu_if.data.datapath.pc = 32'h00001000 + {24'b0, tag};
        alu_if.data.control_signal.reg_write = 1'b1;
        alu_if.data.control_signal.csr_en = csr_en;
        alu_if.data.control_signal.sys_en = sys_en;
        #1;
    end
    endtask

    task automatic set_lsu(input rob_tag_t tag);
    begin
        lsu_if.valid = 1'b1;
        lsu_if.data = '0;
        lsu_if.data.datapath.rob_tag = tag;
        lsu_if.data.datapath.pc = 32'h00002000 + {24'b0, tag};
        lsu_if.data.control_signal.mem_read = 1'b1;
        #1;
    end
    endtask

    task automatic set_branch(input rob_tag_t tag);
    begin
        branch_if.valid = 1'b1;
        branch_if.data = '0;
        branch_if.data.datapath.rob_tag = tag;
        branch_if.data.datapath.pc = 32'h00003000 + {24'b0, tag};
        branch_if.data.control_signal.branch = 1'b1;
        #1;
    end
    endtask

    initial begin
        rst_n = 1'b0;
        clear_inputs();
        rst_n = 1'b1;

        clear_inputs();
        check_ok(!issue0_if.valid && !issue1_if.valid, "no ready inputs produces no issue");

        clear_inputs();
        set_alu(8'd1, 1'b0, 1'b0);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_ALU, "ALU-only issues on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd1, "ALU-only preserves tag");
        check_ok(!issue1_if.valid, "ALU-only leaves lane1 idle");
        check_ok(alu_if.ready && !alu1_if.ready && !lsu_if.ready && !branch_if.ready, "ALU-only ready routes to ALU");

        clear_inputs();
        set_lsu(8'd2);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_MEM, "MEM-only issues on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd2, "MEM-only preserves tag");
        check_ok(lsu_if.ready && !alu_if.ready && !alu1_if.ready && !branch_if.ready, "MEM-only ready routes to LSU");

        clear_inputs();
        set_branch(8'd3);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_BRANCH, "BR-only issues on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd3, "BR-only preserves tag");
        check_ok(branch_if.ready && !alu_if.ready && !alu1_if.ready && !lsu_if.ready, "BR-only ready routes to branch");

        clear_inputs();
        set_alu(8'd20, 1'b0, 1'b0);
        set_alu1(8'd21, 1'b0, 1'b0);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_ALU, "ALU+ALU puts first ALU on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd20, "ALU+ALU lane0 preserves first ALU tag");
        check_ok(issue1_if.valid && issue1_if.data.fu_sel == FU_ALU, "ALU+ALU puts second ALU on lane1");
        check_ok(issue1_if.data.datapath.rob_tag == 8'd21, "ALU+ALU lane1 preserves second ALU tag");
        check_ok(alu_if.ready && alu1_if.ready && !lsu_if.ready && !branch_if.ready, "ALU+ALU consumes both ALU inputs");

        clear_inputs();
        set_alu(8'd4, 1'b0, 1'b0);
        set_lsu(8'd5);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_ALU, "ALU+MEM puts ALU on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd4, "ALU+MEM lane0 preserves ALU tag");
        check_ok(issue1_if.valid && issue1_if.data.fu_sel == FU_MEM, "ALU+MEM puts MEM on lane1");
        check_ok(issue1_if.data.datapath.rob_tag == 8'd5, "ALU+MEM lane1 preserves MEM tag");
        check_ok(alu_if.ready && !alu1_if.ready && lsu_if.ready && !branch_if.ready, "ALU+MEM consumes both selected inputs");

        clear_inputs();
        set_alu(8'd6, 1'b0, 1'b0);
        set_branch(8'd7);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_BRANCH, "BR+ALU prioritizes branch on lane0");
        check_ok(issue1_if.valid && issue1_if.data.fu_sel == FU_ALU, "BR+ALU pairs ALU on lane1");
        check_ok(branch_if.ready && alu_if.ready && !alu1_if.ready && !lsu_if.ready, "BR+ALU consumes branch and ALU");

        clear_inputs();
        set_lsu(8'd8);
        set_branch(8'd9);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_BRANCH, "BR+MEM prioritizes branch on lane0");
        check_ok(issue0_if.data.datapath.rob_tag == 8'd9, "BR+MEM lane0 preserves branch tag");
        check_ok(issue1_if.valid && issue1_if.data.fu_sel == FU_MEM, "BR+MEM places MEM on lane1");
        check_ok(issue1_if.data.datapath.rob_tag == 8'd8, "BR+MEM lane1 preserves MEM tag");
        check_ok(branch_if.ready && lsu_if.ready && !alu_if.ready && !alu1_if.ready, "BR+MEM consumes branch and LSU");

        clear_inputs();
        set_alu(8'd10, 1'b0, 1'b0);
        set_lsu(8'd11);
        set_branch(8'd12);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_BRANCH, "all-valid keeps branch on lane0");
        check_ok(issue1_if.valid && issue1_if.data.fu_sel == FU_ALU, "all-valid chooses ALU for lane1");
        check_ok(branch_if.ready && alu_if.ready && !alu1_if.ready && !lsu_if.ready, "all-valid leaves LSU for a later cycle");

        clear_inputs();
        set_alu(8'd13, 1'b1, 1'b0);
        set_lsu(8'd14);
        set_branch(8'd15);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_ALU, "CSR ALU issues alone on lane0");
        check_ok(!issue1_if.valid, "CSR ALU suppresses lane1 pairing");
        check_ok(alu_if.ready && !alu1_if.ready && !lsu_if.ready && !branch_if.ready, "CSR ALU blocks other FU consumption");

        clear_inputs();
        set_alu(8'd16, 1'b0, 1'b1);
        set_lsu(8'd17);
        check_ok(issue0_if.valid && issue0_if.data.fu_sel == FU_ALU, "system ALU issues alone on lane0");
        check_ok(!issue1_if.valid, "system ALU suppresses lane1 pairing");
        check_ok(alu_if.ready && !alu1_if.ready && !lsu_if.ready, "system ALU blocks MEM consumption");

        clear_inputs();
        set_alu(8'd18, 1'b0, 1'b0);
        set_lsu(8'd19);
        issue0_if.ready = 1'b0;
        issue1_if.ready = 1'b1;
        #1;
        check_ok(issue0_if.valid && !lsu_if.ready, "lane0 backpressure stalls lane0 input");
        check_ok(!issue1_if.valid && !alu_if.ready, "lane0 backpressure holds lane1 to preserve packet order");

        issue0_if.ready = 1'b1;
        issue1_if.ready = 1'b0;
        #1;
        check_ok(alu_if.ready, "lane0 ALU can proceed when lane1 MEM is backpressured");
        check_ok(issue1_if.valid && !lsu_if.ready, "lane1 backpressure stalls only the MEM input");

        $display("==== tb_issue_packet_arbiter PASS ====");
        $finish;
    end

endmodule
