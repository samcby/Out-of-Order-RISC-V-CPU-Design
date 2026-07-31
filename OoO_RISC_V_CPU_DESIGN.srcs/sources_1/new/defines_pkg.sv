`timescale 1ns / 1ps


// The package in systemverilog 是全工程共享的命名空间，其他模块只需要“import defines_pkg::*;”就可以使用里面的参数和类型定义了。

// Central type and constant package for the complete processor.
//
// Keep architectural widths, operation encodings, and inter-stage payloads in
// this package so that all pipeline stages agree on the exact bit layout. The
// packed structures declared here are transported through pip_if interfaces,
// stored in queues/ROB entries, and copied into recovery checkpoints. Adding a
// field therefore changes a hardware interface even when no module port list
// changes explicitly.
//
// Naming convention used by the packet backend:
//   *_control_t  - decoded operation controls; no dynamic operand values.
//   *_datapath_t - PC, instruction, tags, physical-register IDs, and values.
//   *_packet_t   - two ordered lanes; lane 0 is always older than lane 1.
package defines_pkg;

    parameter int WIDTH = 32;   // RV32 的数据宽度、地址宽度

    parameter int AREG_NUM = 32;    // 架构整数寄存器数量：x0–x31
    parameter int AREG_W   = $clog2(AREG_NUM);

    parameter int PREG_NUM = 128;   // 用于重命名的物理寄存器数量
    parameter int PREG_W   = $clog2(PREG_NUM);

    parameter int ICACHE_BYTES = 4096;
    parameter int ICACHE_WORDS = ICACHE_BYTES / 4;

    parameter int ROB_DEPTH = 16;     // 最多允许 16 条指令在 ROB 中等待提交
    // ROB depth and ROB completion tag width serve different purposes:
    // depth sizes the queue, while the tag must stay unique long enough to
    // avoid aliasing against older in-flight entries. A wider tag keeps
    // completion routing stable across longer traces with loops.
    parameter int ROB_TAG_W = 8;
    parameter int MEM_SEQ_W = 16;

    parameter int RS_DEPTH = 8;     // 单个保留站的默认容量
    parameter int CHECKPOINT_NUM = 4;   // 同时跟踪4个未解决的分支
    parameter int CHECKPOINT_W   = $clog2(CHECKPOINT_NUM);
    parameter int ISSUE_WIDTH = 2;      // 每个时钟周期最多发射两条指令

    parameter logic [3:0] ALU_ADD  = 4'd0;
    parameter logic [3:0] ALU_SUB  = 4'd1;
    parameter logic [3:0] ALU_AND  = 4'd2;
    parameter logic [3:0] ALU_OR   = 4'd3;
    parameter logic [3:0] ALU_SLTU = 4'd4;
    parameter logic [3:0] ALU_SRA  = 4'd5;
    parameter logic [3:0] ALU_LUI  = 4'd6;
    parameter logic [3:0] ALU_XOR  = 4'd7;
    parameter logic [3:0] ALU_SLL  = 4'd8;
    parameter logic [3:0] ALU_SRL  = 4'd9;
    parameter logic [3:0] ALU_SLT  = 4'd10;
    parameter logic [3:0] ALU_AUIPC = 4'd11;
    parameter logic [3:0] ALU_NOP  = 4'd15;

    parameter logic [1:0] CSR_RW = 2'd1;
    parameter logic [1:0] CSR_RS = 2'd2;
    parameter logic [1:0] CSR_RC = 2'd3;

    parameter logic [1:0] PRV_U = 2'b00;
    parameter logic [1:0] PRV_M = 2'b11;

    parameter logic [11:0] CSR_MSTATUS = 12'h300;
    parameter logic [11:0] CSR_MIE     = 12'h304;
    parameter logic [11:0] CSR_MTVEC   = 12'h305;
    parameter logic [11:0] CSR_MEPC    = 12'h341;
    parameter logic [11:0] CSR_MCAUSE  = 12'h342;
    parameter logic [11:0] CSR_MTVAL   = 12'h343;
    parameter logic [11:0] CSR_MIP     = 12'h344;
    parameter logic [11:0] CSR_PMPCFG0  = 12'h3a0;
    parameter logic [11:0] CSR_PMPCFG1  = 12'h3a1;
    parameter logic [11:0] CSR_PMPCFG2  = 12'h3a2;
    parameter logic [11:0] CSR_PMPCFG3  = 12'h3a3;
    parameter logic [11:0] CSR_PMPADDR0 = 12'h3b0;
    parameter logic [11:0] CSR_PMPADDR1 = 12'h3b1;
    parameter logic [11:0] CSR_PMPADDR2 = 12'h3b2;
    parameter logic [11:0] CSR_PMPADDR3 = 12'h3b3;
    parameter logic [11:0] CSR_PMPADDR4 = 12'h3b4;
    parameter logic [11:0] CSR_PMPADDR5 = 12'h3b5;
    parameter logic [11:0] CSR_PMPADDR6 = 12'h3b6;
    parameter logic [11:0] CSR_PMPADDR7 = 12'h3b7;
    parameter logic [11:0] CSR_PMPADDR8 = 12'h3b8;
    parameter logic [11:0] CSR_PMPADDR9 = 12'h3b9;
    parameter logic [11:0] CSR_PMPADDR10 = 12'h3ba;
    parameter logic [11:0] CSR_PMPADDR11 = 12'h3bb;
    parameter logic [11:0] CSR_PMPADDR12 = 12'h3bc;
    parameter logic [11:0] CSR_PMPADDR13 = 12'h3bd;
    parameter logic [11:0] CSR_PMPADDR14 = 12'h3be;
    parameter logic [11:0] CSR_PMPADDR15 = 12'h3bf;
    parameter logic [11:0] CSR_MHARTID = 12'hf14;

    parameter int PMP_ENTRY_COUNT = 16;
    parameter int PMP_CFG_WORD_COUNT = PMP_ENTRY_COUNT / 4;
    parameter logic [1:0] PMP_A_OFF   = 2'b00;
    parameter logic [1:0] PMP_A_TOR   = 2'b01;
    parameter logic [1:0] PMP_A_NA4   = 2'b10;
    parameter logic [1:0] PMP_A_NAPOT = 2'b11;

    parameter logic [2:0] SYS_ECALL   = 3'd1;
    parameter logic [2:0] SYS_EBREAK  = 3'd2;
    parameter logic [2:0] SYS_MRET    = 3'd3;
    parameter logic [2:0] SYS_ILLEGAL = 3'd4;
    parameter logic [2:0] SYS_FENCE   = 3'd5;
    parameter logic [2:0] SYS_WFI     = 3'd6;

    parameter logic [WIDTH-1:0] MCAUSE_INSTR_ADDR_MISALIGNED = 32'd0;
    parameter logic [WIDTH-1:0] MCAUSE_INSTR_ACCESS_FAULT     = 32'd1;
    parameter logic [WIDTH-1:0] MCAUSE_ILLEGAL               = 32'd2;
    parameter logic [WIDTH-1:0] MCAUSE_EBREAK                = 32'd3;
    parameter logic [WIDTH-1:0] MCAUSE_LOAD_ADDR_MISALIGNED  = 32'd4;
    parameter logic [WIDTH-1:0] MCAUSE_LOAD_ACCESS_FAULT      = 32'd5;
    parameter logic [WIDTH-1:0] MCAUSE_STORE_ADDR_MISALIGNED = 32'd6;
    parameter logic [WIDTH-1:0] MCAUSE_STORE_ACCESS_FAULT     = 32'd7;
    parameter logic [WIDTH-1:0] MCAUSE_ECALL_U               = 32'd8;
    parameter logic [WIDTH-1:0] MCAUSE_ECALL_M               = 32'd11;

    // True for every RV32F instruction and for CSR accesses to the three
    // floating-point state CSRs. mstatus.FS=Off makes all of these illegal.
    function automatic logic instruction_uses_fp_state(
        input logic [WIDTH-1:0] instr
    );
        logic [6:0] opcode;
        logic [11:0] csr_addr;
    begin
        opcode = instr[6:0];
        csr_addr = instr[31:20];
        unique case (opcode)
            7'b0000111, // FLW
            7'b0100111, // FSW
            7'b1000011, // FMADD.S
            7'b1000111, // FMSUB.S
            7'b1001011, // FNMSUB.S
            7'b1001111, // FNMADD.S
            7'b1010011: // OP-FP
                instruction_uses_fp_state = 1'b1;
            7'b1110011:
                instruction_uses_fp_state =
                    (instr[14:12] != 3'b000) &&
                    ((csr_addr == 12'h001) ||
                     (csr_addr == 12'h002) ||
                     (csr_addr == 12'h003));
            default:
                instruction_uses_fp_state = 1'b0;
        endcase
    end
    endfunction

    // RV32 PMP checker for sixteen statically prioritized entries. The first
    // entry matching any accessed byte wins; partial coverage therefore fails
    // instead of falling through to a lower-priority entry.
    function automatic logic pmp_access_allowed(
        input logic [1:0] privilege,
        input logic [PMP_ENTRY_COUNT*8-1:0] pmpcfg,
        input logic [PMP_ENTRY_COUNT*WIDTH-1:0] pmpaddr,
        input logic [WIDTH-1:0] access_addr,
        input logic [2:0] access_size_minus1,
        input logic access_read,
        input logic access_write,
        input logic access_execute
    );
        logic [WIDTH+3:0] region_first;
        logic [WIDTH+3:0] region_end;
        logic [WIDTH+3:0] region_size;
        logic [WIDTH+3:0] access_first;
        logic [WIDTH+3:0] access_last;
        logic [WIDTH-1:0] entry_addr;
        logic [WIDTH-1:0] previous_addr;
        logic [7:0]       entry_cfg;
        logic             entry_active;
        logic             entry_overlap;
        logic             entry_covers;
        logic             permission_ok;
        logic             matched;
        logic             count_trailing_ones;
        integer           trailing_ones;
        integer           entry_index;
        integer           bit_index;
    begin
        access_first = {{4{1'b0}}, access_addr};
        access_last  = access_first + access_size_minus1;
        matched = 1'b0;
        pmp_access_allowed = (privilege == PRV_M);

        for (entry_index = 0;
             entry_index < PMP_ENTRY_COUNT;
             entry_index = entry_index + 1) begin
            entry_cfg = pmpcfg[entry_index*8 +: 8];
            entry_addr = pmpaddr[entry_index*WIDTH +: WIDTH];
            previous_addr = (entry_index == 0) ? '0 :
                pmpaddr[(entry_index-1)*WIDTH +: WIDTH];
            region_first = '0;
            region_end = '0;
            region_size = '0;
            entry_active = 1'b1;

            unique case (entry_cfg[4:3])
                PMP_A_TOR: begin
                    region_first = {{4{1'b0}}, previous_addr} << 2;
                    region_end = {{4{1'b0}}, entry_addr} << 2;
                    if (region_first >= region_end) begin
                        entry_active = 1'b0;
                    end
                end
                PMP_A_NA4: begin
                    region_first = {{4{1'b0}}, entry_addr} << 2;
                    region_end = region_first + 4;
                end
                PMP_A_NAPOT: begin
                    trailing_ones = 0;
                    count_trailing_ones = 1'b1;
                    for (bit_index = 0;
                         bit_index < WIDTH;
                         bit_index = bit_index + 1) begin
                        if (count_trailing_ones && entry_addr[bit_index]) begin
                            trailing_ones = trailing_ones + 1;
                        end else begin
                            count_trailing_ones = 1'b0;
                        end
                    end
                    region_size = {{(WIDTH+3){1'b0}}, 1'b1} <<
                                  (trailing_ones + 3);
                    region_first =
                        ({{4{1'b0}}, entry_addr} << 2) &
                        ~(region_size - 1'b1);
                    region_end = region_first + region_size;
                end
                default: begin
                    entry_active = 1'b0;
                end
            endcase

            entry_overlap =
                entry_active &&
                (access_first < region_end) &&
                (access_last >= region_first);
            entry_covers =
                (access_first >= region_first) &&
                (access_last < region_end);
            permission_ok =
                (!access_read    || entry_cfg[0]) &&
                (!access_write   || entry_cfg[1]) &&
                (!access_execute || entry_cfg[2]);

            if (!matched && entry_overlap) begin
                matched = 1'b1;
                if (!entry_covers) begin
                    pmp_access_allowed = 1'b0;
                end else if ((privilege == PRV_M) && !entry_cfg[7]) begin
                    pmp_access_allowed = 1'b1;
                end else begin
                    pmp_access_allowed = permission_ok;
                end
            end
        end
    end
    endfunction

    parameter logic [1:0] FU_NOP    = 2'd0;
    parameter logic [1:0] FU_ALU    = 2'd1;
    parameter logic [1:0] FU_MEM    = 2'd2;
    parameter logic [1:0] FU_BRANCH = 2'd3;

    typedef logic [AREG_W-1:0]    areg_t;
    typedef logic [PREG_W-1:0]    preg_t;
    typedef logic [ROB_TAG_W-1:0] rob_tag_t;
    typedef logic [MEM_SEQ_W-1:0] mem_seq_t;
    typedef logic [CHECKPOINT_W-1:0] cp_id_t;
    typedef logic [CHECKPOINT_NUM-1:0] cp_mask_t;

    typedef struct packed {
        logic [WIDTH-1:0] pc;
        logic [WIDTH-1:0] instr;
        logic             pred_taken;
        logic [WIDTH-1:0] pred_target;
        logic             exception_valid;
        logic [WIDTH-1:0] exception_cause;
        logic [WIDTH-1:0] exception_tval;
    } fetch_decode_t;

    typedef struct packed {
        logic reg_write;
        logic alu_src;
        logic fp_en;
        logic [4:0] fp_op;
        logic [2:0] fp_rm;
        logic csr_en;
        logic csr_use_imm;
        logic [1:0] csr_op;
        logic [4:0] csr_zimm;
        logic [11:0] csr_addr;
        logic sys_en;
        logic [2:0] sys_op;
        logic [3:0] alu_op;
    } alu_control_t;

    typedef struct packed {
        logic reg_write;
        logic mem_read;
        logic mem_write;
        logic [2:0] funct3;
    } lsu_control_t;

    typedef struct packed {
        logic branch;
        logic jump;
        logic jump_reg;
        logic [2:0] funct3;
    } branch_control_t;

    typedef struct packed {
        logic [1:0] fu_type;
        logic       rename;
        alu_control_t    alu_control_signal;
        lsu_control_t    lsu_control_signal;
        branch_control_t branch_control_signal;
    } rs_control_t;

    typedef struct packed {
        logic branch;
        logic store;
    } rob_control_t;

    typedef struct packed {
        rs_control_t  rs_control_signal;
        rob_control_t rob_control_signal;
    } control_t;

    typedef struct packed {
        logic [WIDTH-1:0] pc;
        areg_t            rs1;
        areg_t            rs2;
        areg_t            rs3;
        areg_t            rd;
        logic             src1_is_fp;
        logic             src2_is_fp;
        logic             src3_is_fp;
        logic             dest_is_fp;
        logic [WIDTH-1:0] imm;
        logic [WIDTH-1:0] instr;
        logic             pred_taken;
        logic [WIDTH-1:0] pred_target;
        logic             exception_valid;
        logic [WIDTH-1:0] exception_cause;
        logic [WIDTH-1:0] exception_tval;
    } decode_datapath_t;

    typedef struct packed {
        decode_datapath_t datapath;
        control_t         control_signal;
    } decode_rat_t;

    typedef struct packed {
        preg_t     src_reg_1p;
        preg_t     src_reg_2p;
        preg_t     src_reg_3p;
        preg_t     new_des_preg;
        logic      src1_is_fp;
        logic      src2_is_fp;
        logic      src3_is_fp;
        logic      dest_is_fp;
        cp_id_t    checkpoint_id;
        cp_mask_t  speculation_mask;
        logic [WIDTH-1:0] src1_value;
        logic [WIDTH-1:0] src2_value;
        logic [WIDTH-1:0] src3_value;
        rob_tag_t  rob_tag;
        mem_seq_t  mem_seq;
        logic [WIDTH-1:0] imm;
        logic [WIDTH-1:0] instr;
        logic [WIDTH-1:0] pc;
        logic             pred_taken;
        logic [WIDTH-1:0] pred_target;
    } rs_datapath_t;

    typedef struct packed {
        alu_control_t control_signal;
        rs_datapath_t datapath;
        logic         src1_ready;
        logic         src2_ready;
        logic         src3_ready;
    } alu_rs_t;

    typedef struct packed {
        lsu_control_t control_signal;
        rs_datapath_t datapath;
        logic         src1_ready;
        logic         src2_ready;
        logic         src3_ready;
    } lsu_rs_t;

    typedef struct packed {
        branch_control_t control_signal;
        rs_datapath_t    datapath;
        logic            src1_ready;
        logic            src2_ready;
        logic            src3_ready;
    } branch_rs_t;

    typedef struct packed {
        rs_control_t  control_signal;
        rs_datapath_t datapath;
        logic         src1_ready;
        logic         src2_ready;
        logic         src3_ready;
    } rs_t;

    typedef struct packed {
        rob_tag_t rob_tag;
        preg_t    new_des_preg;
        preg_t    old_des_preg;
        logic     dest_is_fp;
        cp_id_t   checkpoint_id;
        cp_mask_t speculation_mask;
        areg_t    rd;
        logic     complete;
        logic [WIDTH-1:0] result;
        logic [4:0] fp_flags;
        logic             exception_valid;
        logic [WIDTH-1:0] exception_cause;
        logic [WIDTH-1:0] exception_tval;
        logic [WIDTH-1:0] pc;
        logic [WIDTH-1:0] instr;
    } rob_datapath_t;

    typedef struct packed {
        rob_datapath_t datapath;
        rob_control_t  control_signal;
    } rob_t;

    typedef struct packed {
        rs_t  rs_entry;
        rob_t rob_entry;
    } rat_dis_t;

    typedef struct packed {
        logic          valid;
        fetch_decode_t data;
    } fetch_decode_lane_t;

    typedef struct packed {
        fetch_decode_lane_t lane0;
        fetch_decode_lane_t lane1;
    } fetch_decode_packet_t;

    typedef struct packed {
        logic        valid;
        decode_rat_t data;
    } decode_rat_lane_t;

    typedef struct packed {
        decode_rat_lane_t lane0;
        decode_rat_lane_t lane1;
    } decode_rat_packet_t;

    typedef struct packed {
        logic     valid;
        rat_dis_t data;
    } rat_dis_lane_t;

    typedef struct packed {
        rat_dis_lane_t lane0;
        rat_dis_lane_t lane1;
    } rat_dis_packet_t;

    typedef struct packed {
        alu_control_t    alu;
        lsu_control_t    lsu;
        branch_control_t branch;
    } issue_ctrl_t;

    typedef struct packed {
        logic             valid;
        logic [63:0]      order;
        logic [WIDTH-1:0] pc;
        logic [WIDTH-1:0] instr;
        logic             rd_wen;
        logic             rd_is_fp;
        areg_t            rd;
        logic [WIDTH-1:0] rd_wdata;
        logic [4:0]       fp_flags;
        logic             is_store;
        logic             is_branch;
        rob_tag_t         rob_tag;
    } retire_trace_t;

    typedef struct packed {
        issue_ctrl_t control_signal;
        rs_datapath_t datapath;
        logic [1:0] fu_sel;
    } issue_exe_t;

endpackage
