package defines_pkg;

    parameter int WIDTH = 32;

    parameter int AREG_NUM = 32;
    parameter int AREG_W   = $clog2(AREG_NUM);

    parameter int PREG_NUM = 128;
    parameter int PREG_W   = $clog2(PREG_NUM);

    parameter int ICACHE_BYTES = 4096;
    parameter int ICACHE_WORDS = ICACHE_BYTES / 4;

    parameter int ROB_DEPTH = 16;
    // ROB depth and ROB completion tag width serve different purposes:
    // depth sizes the queue, while the tag must stay unique long enough to
    // avoid aliasing against older in-flight entries. A wider tag keeps
    // completion routing stable across longer traces with loops.
    parameter int ROB_TAG_W = 8;

    parameter int RS_DEPTH = 8;
    parameter int CHECKPOINT_NUM = 4;
    parameter int CHECKPOINT_W   = $clog2(CHECKPOINT_NUM);

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

    parameter logic [11:0] CSR_MSTATUS = 12'h300;
    parameter logic [11:0] CSR_MIE     = 12'h304;
    parameter logic [11:0] CSR_MTVEC   = 12'h305;
    parameter logic [11:0] CSR_MEPC    = 12'h341;
    parameter logic [11:0] CSR_MCAUSE  = 12'h342;
    parameter logic [11:0] CSR_MTVAL   = 12'h343;
    parameter logic [11:0] CSR_MIP     = 12'h344;

    parameter logic [2:0] SYS_ECALL   = 3'd1;
    parameter logic [2:0] SYS_EBREAK  = 3'd2;
    parameter logic [2:0] SYS_MRET    = 3'd3;
    parameter logic [2:0] SYS_ILLEGAL = 3'd4;

    parameter logic [WIDTH-1:0] MCAUSE_INSTR_ADDR_MISALIGNED = 32'd0;
    parameter logic [WIDTH-1:0] MCAUSE_ILLEGAL               = 32'd2;
    parameter logic [WIDTH-1:0] MCAUSE_EBREAK                = 32'd3;
    parameter logic [WIDTH-1:0] MCAUSE_LOAD_ADDR_MISALIGNED  = 32'd4;
    parameter logic [WIDTH-1:0] MCAUSE_STORE_ADDR_MISALIGNED = 32'd6;
    parameter logic [WIDTH-1:0] MCAUSE_ECALL_M               = 32'd11;

    parameter logic [1:0] FU_NOP    = 2'd0;
    parameter logic [1:0] FU_ALU    = 2'd1;
    parameter logic [1:0] FU_MEM    = 2'd2;
    parameter logic [1:0] FU_BRANCH = 2'd3;

    typedef logic [AREG_W-1:0]    areg_t;
    typedef logic [PREG_W-1:0]    preg_t;
    typedef logic [ROB_TAG_W-1:0] rob_tag_t;
    typedef logic [CHECKPOINT_W-1:0] cp_id_t;
    typedef logic [CHECKPOINT_NUM-1:0] cp_mask_t;

    typedef struct packed {
        logic [WIDTH-1:0] pc;
        logic [WIDTH-1:0] instr;
        logic             pred_taken;
        logic [WIDTH-1:0] pred_target;
    } fetch_decode_t;

    typedef struct packed {
        logic reg_write;
        logic alu_src;
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
    } rob_control_t;

    typedef struct packed {
        rs_control_t  rs_control_signal;
        rob_control_t rob_control_signal;
    } control_t;

    typedef struct packed {
        logic [WIDTH-1:0] pc;
        areg_t            rs1;
        areg_t            rs2;
        areg_t            rd;
        logic [WIDTH-1:0] imm;
        logic [WIDTH-1:0] instr;
        logic             pred_taken;
        logic [WIDTH-1:0] pred_target;
    } decode_datapath_t;

    typedef struct packed {
        decode_datapath_t datapath;
        control_t         control_signal;
    } decode_rat_t;

    typedef struct packed {
        preg_t     src_reg_1p;
        preg_t     src_reg_2p;
        preg_t     new_des_preg;
        cp_id_t    checkpoint_id;
        cp_mask_t  speculation_mask;
        logic [WIDTH-1:0] src1_value;
        logic [WIDTH-1:0] src2_value;
        rob_tag_t  rob_tag;
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
    } alu_rs_t;

    typedef struct packed {
        lsu_control_t control_signal;
        rs_datapath_t datapath;
        logic         src1_ready;
        logic         src2_ready;
    } lsu_rs_t;

    typedef struct packed {
        branch_control_t control_signal;
        rs_datapath_t    datapath;
        logic            src1_ready;
        logic            src2_ready;
    } branch_rs_t;

    typedef struct packed {
        rs_control_t  control_signal;
        rs_datapath_t datapath;
        logic         src1_ready;
        logic         src2_ready;
    } rs_t;

    typedef struct packed {
        rob_tag_t rob_tag;
        preg_t    new_des_preg;
        preg_t    old_des_preg;
        cp_id_t   checkpoint_id;
        cp_mask_t speculation_mask;
        areg_t    rd;
        logic     complete;
        logic [WIDTH-1:0] result;
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
        alu_control_t    alu;
        lsu_control_t    lsu;
        branch_control_t branch;
    } issue_ctrl_t;

    typedef struct packed {
        issue_ctrl_t control_signal;
        rs_datapath_t datapath;
        logic [1:0] fu_sel;
    } issue_exe_t;

endpackage
