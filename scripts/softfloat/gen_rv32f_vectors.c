#include <inttypes.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "softfloat.h"

enum {
    FP_OP_ADD = 3,
    FP_OP_SUB = 4,
    FP_OP_MUL = 5,
    FP_OP_DIV = 6,
    FP_OP_SQRT = 7,
    FP_OP_CVT_W_S = 13,
    FP_OP_CVT_WU_S = 14,
    FP_OP_EQ = 17,
    FP_OP_LT = 18,
    FP_OP_LE = 19,
    FP_OP_CVT_S_W = 20,
    FP_OP_CVT_S_WU = 21,
    FP_OP_MADD = 23,
    FP_OP_MSUB = 24,
    FP_OP_NMSUB = 25,
    FP_OP_NMADD = 26
};

static const uint32_t interesting[] = {
    0x00000000, 0x80000000, 0x00000001, 0x80000001,
    0x007FFFFF, 0x807FFFFF, 0x00800000, 0x80800000,
    0x3EAAAAAB, 0xBEAAAAAB, 0x3F000000, 0xBF000000,
    0x3F7FFFFF, 0x3F800000, 0x3F800001, 0xBF800000,
    0x40000000, 0xC0000000, 0x4EFFFFFF, 0x4F000000,
    0xCF000000, 0x7F7FFFFF, 0xFF7FFFFF, 0x7F800000,
    0xFF800000, 0x7FC00000, 0x7FC12345, 0xFFC00000,
    0x7F800001, 0x7FA00001, 0xFF800001, 0xFFFFFFFF
};

static uint32_t rng_state;

static uint32_t next_random(void)
{
    uint32_t value = rng_state;

    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    rng_state = value;
    return value;
}

static uint32_t random_operand(void)
{
    uint32_t selector = next_random();
    uint32_t base;

    switch (selector & 7U) {
    case 0:
        return interesting[next_random() %
                           (sizeof(interesting) / sizeof(interesting[0]))];
    case 1:
        base = interesting[next_random() %
                           (sizeof(interesting) / sizeof(interesting[0]))];
        return base ^ (next_random() & 0x0000FFFFU);
    case 2:
        base = interesting[next_random() %
                           (sizeof(interesting) / sizeof(interesting[0]))];
        return base ^ (next_random() & 0x007FFFFFU);
    default:
        return next_random();
    }
}

static float32_t as_f32(uint32_t bits)
{
    float32_t value;

    value.v = bits;
    return value;
}

static uint32_t run_reference(
    unsigned operation,
    unsigned rounding_mode,
    uint32_t operand_a,
    uint32_t operand_b,
    uint32_t operand_c
)
{
    float32_t a = as_f32(operand_a);
    float32_t b = as_f32(operand_b);
    float32_t c = as_f32(operand_c);
    float32_t fp_result;
    uint32_t int_result;

    softfloat_roundingMode = (uint_fast8_t)rounding_mode;
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    softfloat_exceptionFlags = 0;

    switch (operation) {
    case FP_OP_ADD:
        fp_result = f32_add(a, b);
        return fp_result.v;
    case FP_OP_SUB:
        fp_result = f32_sub(a, b);
        return fp_result.v;
    case FP_OP_MUL:
        fp_result = f32_mul(a, b);
        return fp_result.v;
    case FP_OP_DIV:
        fp_result = f32_div(a, b);
        return fp_result.v;
    case FP_OP_SQRT:
        fp_result = f32_sqrt(a);
        return fp_result.v;
    case FP_OP_MADD:
        fp_result = f32_mulAdd(a, b, c);
        return fp_result.v;
    case FP_OP_MSUB:
        c.v ^= UINT32_C(0x80000000);
        fp_result = f32_mulAdd(a, b, c);
        return fp_result.v;
    case FP_OP_NMSUB:
        a.v ^= UINT32_C(0x80000000);
        fp_result = f32_mulAdd(a, b, c);
        return fp_result.v;
    case FP_OP_NMADD:
        a.v ^= UINT32_C(0x80000000);
        c.v ^= UINT32_C(0x80000000);
        fp_result = f32_mulAdd(a, b, c);
        return fp_result.v;
    case FP_OP_CVT_W_S:
        int_result = (uint32_t)f32_to_i32(
            a, (uint_fast8_t)rounding_mode, true
        );
        return int_result;
    case FP_OP_CVT_WU_S:
        return (uint32_t)f32_to_ui32(
            a, (uint_fast8_t)rounding_mode, true
        );
    case FP_OP_CVT_S_W:
        fp_result = i32_to_f32((int32_t)operand_a);
        return fp_result.v;
    case FP_OP_CVT_S_WU:
        fp_result = ui32_to_f32(operand_a);
        return fp_result.v;
    case FP_OP_EQ:
        return f32_eq(a, b) ? 1U : 0U;
    case FP_OP_LT:
        return f32_lt(a, b) ? 1U : 0U;
    case FP_OP_LE:
        return f32_le(a, b) ? 1U : 0U;
    default:
        fprintf(stderr, "Unsupported operation %u\n", operation);
        exit(EXIT_FAILURE);
    }
}

static void emit_vector(
    FILE *output,
    unsigned operation,
    unsigned rounding_mode,
    uint32_t operand_a,
    uint32_t operand_b,
    uint32_t operand_c,
    uint64_t *vector_count
)
{
    uint32_t result = run_reference(
        operation, rounding_mode, operand_a, operand_b, operand_c
    );

    fprintf(
        output,
        "%02x %x %08" PRIx32 " %08" PRIx32 " %08" PRIx32
        " %08" PRIx32 " %02x\n",
        operation,
        rounding_mode,
        operand_a,
        operand_b,
        operand_c,
        result,
        (unsigned)softfloat_exceptionFlags
    );
    ++*vector_count;
}

static void emit_operation(
    FILE *output,
    unsigned operation,
    unsigned rounding_mode,
    unsigned random_count,
    uint64_t *vector_count
)
{
    size_t index;
    unsigned random_index;
    size_t interesting_count = sizeof(interesting) / sizeof(interesting[0]);

    for (index = 0; index < interesting_count; ++index) {
        emit_vector(
            output,
            operation,
            rounding_mode,
            interesting[index],
            interesting[(index * 5U + 3U) % interesting_count],
            interesting[(index * 11U + 7U) % interesting_count],
            vector_count
        );
    }

    for (random_index = 0; random_index < random_count; ++random_index) {
        emit_vector(
            output,
            operation,
            rounding_mode,
            random_operand(),
            random_operand(),
            random_operand(),
            vector_count
        );
    }
}

int main(int argc, char **argv)
{
    static const unsigned rounded_operations[] = {
        FP_OP_ADD, FP_OP_SUB, FP_OP_MUL, FP_OP_DIV, FP_OP_SQRT,
        FP_OP_MADD, FP_OP_MSUB, FP_OP_NMSUB, FP_OP_NMADD,
        FP_OP_CVT_W_S, FP_OP_CVT_WU_S, FP_OP_CVT_S_W, FP_OP_CVT_S_WU
    };
    static const unsigned comparison_operations[] = {
        FP_OP_EQ, FP_OP_LT, FP_OP_LE
    };
    const char *output_path;
    unsigned random_count = 128;
    uint64_t vector_count = 0;
    size_t operation_index;
    unsigned rounding_mode;
    FILE *output;

    if (argc < 2 || argc > 4) {
        fprintf(
            stderr,
            "Usage: %s OUTPUT [RANDOM_VECTORS_PER_CASE] [SEED]\n",
            argv[0]
        );
        return EXIT_FAILURE;
    }

    output_path = argv[1];
    if (argc >= 3) {
        random_count = (unsigned)strtoul(argv[2], NULL, 0);
    }
    rng_state = (argc >= 4)
                    ? (uint32_t)strtoul(argv[3], NULL, 0)
                    : UINT32_C(0x18932F5A);
    if (rng_state == 0) {
        rng_state = UINT32_C(1);
    }

    output = fopen(output_path, "w");
    if (!output) {
        perror(output_path);
        return EXIT_FAILURE;
    }

    for (operation_index = 0;
         operation_index <
             sizeof(rounded_operations) / sizeof(rounded_operations[0]);
         ++operation_index) {
        for (rounding_mode = 0; rounding_mode <= 4; ++rounding_mode) {
            emit_operation(
                output,
                rounded_operations[operation_index],
                rounding_mode,
                random_count,
                &vector_count
            );
        }
    }

    for (operation_index = 0;
         operation_index <
             sizeof(comparison_operations) /
                 sizeof(comparison_operations[0]);
         ++operation_index) {
        emit_operation(
            output,
            comparison_operations[operation_index],
            0,
            random_count,
            &vector_count
        );
    }

    if (fclose(output) != 0) {
        perror(output_path);
        return EXIT_FAILURE;
    }

    printf(
        "Generated %" PRIu64 " RV32F vectors in %s\n",
        vector_count,
        output_path
    );
    return EXIT_SUCCESS;
}
