`timescale 1ns / 1ps

package fp_defines_pkg;

    parameter int FP_AREG_NUM = 32;
    parameter int FP_AREG_W   = $clog2(FP_AREG_NUM);
    parameter int FP_PREG_NUM = 128;
    parameter int FP_PREG_W   = $clog2(FP_PREG_NUM);

    parameter logic [11:0] CSR_FFLAGS = 12'h001;
    parameter logic [11:0] CSR_FRM    = 12'h002;
    parameter logic [11:0] CSR_FCSR   = 12'h003;

    parameter logic [4:0] FP_OP_NONE      = 5'd0;
    parameter logic [4:0] FP_OP_LOAD      = 5'd1;
    parameter logic [4:0] FP_OP_STORE     = 5'd2;
    parameter logic [4:0] FP_OP_ADD       = 5'd3;
    parameter logic [4:0] FP_OP_SUB       = 5'd4;
    parameter logic [4:0] FP_OP_MUL       = 5'd5;
    parameter logic [4:0] FP_OP_DIV       = 5'd6;
    parameter logic [4:0] FP_OP_SQRT      = 5'd7;
    parameter logic [4:0] FP_OP_SGNJ      = 5'd8;
    parameter logic [4:0] FP_OP_SGNJN     = 5'd9;
    parameter logic [4:0] FP_OP_SGNJX     = 5'd10;
    parameter logic [4:0] FP_OP_MIN       = 5'd11;
    parameter logic [4:0] FP_OP_MAX       = 5'd12;
    parameter logic [4:0] FP_OP_CVT_W_S   = 5'd13;
    parameter logic [4:0] FP_OP_CVT_WU_S  = 5'd14;
    parameter logic [4:0] FP_OP_MV_X_W    = 5'd15;
    parameter logic [4:0] FP_OP_CLASS     = 5'd16;
    parameter logic [4:0] FP_OP_EQ        = 5'd17;
    parameter logic [4:0] FP_OP_LT        = 5'd18;
    parameter logic [4:0] FP_OP_LE        = 5'd19;
    parameter logic [4:0] FP_OP_CVT_S_W   = 5'd20;
    parameter logic [4:0] FP_OP_CVT_S_WU  = 5'd21;
    parameter logic [4:0] FP_OP_MV_W_X    = 5'd22;
    parameter logic [4:0] FP_OP_MADD      = 5'd23;
    parameter logic [4:0] FP_OP_MSUB      = 5'd24;
    parameter logic [4:0] FP_OP_NMSUB     = 5'd25;
    parameter logic [4:0] FP_OP_NMADD     = 5'd26;

    typedef logic [FP_AREG_W-1:0] fp_areg_t;
    typedef logic [FP_PREG_W-1:0] fp_preg_t;

    typedef struct packed {
        logic       valid;
        logic       illegal;
        logic [4:0] operation;
        logic       uses_rounding_mode;
        logic [2:0] rounding_mode;
        logic       mem_read;
        logic       mem_write;

        logic       int_rs1_valid;
        logic [4:0] int_rs1;
        logic       int_rd_valid;
        logic [4:0] int_rd;

        logic       fp_rs1_valid;
        logic [4:0] fp_rs1;
        logic       fp_rs2_valid;
        logic [4:0] fp_rs2;
        logic       fp_rs3_valid;
        logic [4:0] fp_rs3;
        logic       fp_rd_valid;
        logic [4:0] fp_rd;
    } fp_decode_t;

endpackage
