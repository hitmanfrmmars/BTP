/*
 * GEMM Accelerator Stress Test for PicoRV32 SoC
 *
 * Comprehensive firmware to validate the 8x8 GEMM accelerator.
 * Compares hardware results against a simple software reference.
 *
 * Debug protocol (testbench reads):
 *   0xAAAA0000 | test_num  -> test start marker
 *   0x600D                 -> PASS
 *   0xFA11                 -> FAIL
 *   0xDEAD                 -> all done
 */

#include "gemm_accel.h"
#include <stdint.h>

/* Memory layout */
#define ADDR_A      0x00010000u
#define ADDR_B      0x00012000u
#define ADDR_C_HW   0x00014000u
#define ADDR_C_SW   0x00016000u

/* Debug protocol */
#define MARKER_START  0xAAAA0000u
#define MARKER_PASS   0x0000600Du
#define MARKER_FAIL   0x0000FA11u
#define MARKER_DONE   0x0000DEADu

/* Pattern types for run_test */
#define PATTERN_SEQ    0
#define PATTERN_ONES   1
#define PATTERN_IDENT  2
#define PATTERN_MAX    3

static uint32_t test_counter;

/* ---------------------------------------------------------------------------
 * Software GEMM reference (int8)
 * --------------------------------------------------------------------------- */
static void sw_gemm_int8(uint16_t M, uint16_t K, uint16_t N,
                         volatile uint8_t *A, volatile uint8_t *B, volatile uint8_t *C,
                         uint16_t stride_a, uint16_t stride_b, uint16_t stride_c)
{
    uint16_t i, j, k;
    uint32_t sum;
    for (i = 0; i < M; i++) {
        for (j = 0; j < N; j++) {
            sum = 0;
            for (k = 0; k < K; k++) {
                sum += (uint32_t)A[i * stride_a + k] * (uint32_t)B[k * stride_b + j];
            }
            C[i * stride_c + j] = (uint8_t)(sum & 0xFF);
        }
    }
}

static void sw_gemm_int8_acc32(uint16_t M, uint16_t K, uint16_t N,
                                volatile uint8_t *A, volatile uint8_t *B,
                                volatile uint32_t *C,
                                uint16_t stride_a, uint16_t stride_b,
                                uint16_t stride_c_words)
{
    uint16_t i, j, k;
    for (i = 0; i < M; i++) {
        for (j = 0; j < N; j++) {
            uint32_t sum = 0;
            for (k = 0; k < K; k++) {
                sum += (uint32_t)A[i * stride_a + k] * (uint32_t)B[k * stride_b + j];
            }
            C[i * stride_c_words + j] = sum;
        }
    }
}

static uint32_t verify_match_32(volatile uint32_t *C_sw, volatile uint32_t *C_hw,
                                 uint16_t M, uint16_t N, uint16_t stride_words)
{
    uint16_t i, j;
    uint32_t err = 0;
    for (i = 0; i < M; i++)
        for (j = 0; j < N; j++)
            if (C_sw[i * stride_words + j] != C_hw[i * stride_words + j])
                err++;
    return err;
}

/* ---------------------------------------------------------------------------
 * Matrix initialization
 * --------------------------------------------------------------------------- */
static void init_matrix_pattern(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                                uint16_t stride, uint8_t seed)
{
    uint16_t r, c;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++) {
            mat[r * stride + c] = (uint8_t)((seed + r * 3u + c * 7u) & 0xFFu);
        }
    }
}

static void init_matrix_const(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                             uint16_t stride, uint8_t val)
{
    uint16_t r, c;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++) {
            mat[r * stride + c] = val;
        }
    }
}

static void init_matrix_identity(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                                uint16_t stride)
{
    uint16_t r, c;
    uint16_t diag = rows < cols ? rows : cols;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++) {
            mat[r * stride + c] = (r == c && r < diag) ? 1u : 0u;
        }
    }
}

/* ---------------------------------------------------------------------------
 * Verification and utilities
 * --------------------------------------------------------------------------- */
static uint32_t verify_match(volatile uint8_t *C_sw, volatile uint8_t *C_hw,
                             uint16_t M, uint16_t N,
                             uint16_t stride_sw, uint16_t stride_hw)
{
    uint16_t i, j;
    uint32_t err = 0;
    for (i = 0; i < M; i++) {
        for (j = 0; j < N; j++) {
            if (C_sw[i * stride_sw + j] != C_hw[i * stride_hw + j])
                err++;
        }
    }
    return err;
}

static void clear_region(uint32_t addr, uint32_t bytes)
{
    volatile uint8_t *p = (volatile uint8_t *)addr;
    uint32_t i;
    for (i = 0; i < bytes; i++)
        p[i] = 0;
}

/* ---------------------------------------------------------------------------
 * Run a single test
 * --------------------------------------------------------------------------- */
static void run_test(uint16_t M, uint16_t K, uint16_t N,
                    uint8_t pattern_type, int run_twice)
{
    volatile uint8_t *A = (volatile uint8_t *)ADDR_A;
    volatile uint8_t *B = (volatile uint8_t *)ADDR_B;
    volatile uint8_t *C_hw = (volatile uint8_t *)ADDR_C_HW;
    volatile uint8_t *C_sw = (volatile uint8_t *)ADDR_C_SW;

    uint16_t stride_a = PAD4(K);
    uint16_t stride_b = PAD4(N);
    uint16_t stride_c = PAD4(N);

    uint32_t run;
    uint32_t runs = run_twice ? 2u : 1u;

    test_counter++;
    debug_putw(MARKER_START | (test_counter & 0xFFFFu));

    for (run = 0; run < runs; run++) {
        /* Initialize A and B */
        switch (pattern_type) {
        case PATTERN_SEQ:
            init_matrix_pattern(A, M, K, stride_a, (uint8_t)(run * 17u));
            init_matrix_pattern(B, K, N, stride_b, (uint8_t)(run * 31u));
            break;
        case PATTERN_ONES:
            init_matrix_const(A, M, K, stride_a, 1);
            init_matrix_const(B, K, N, stride_b, 1);
            break;
        case PATTERN_IDENT:
            init_matrix_identity(A, M, K, stride_a);
            init_matrix_pattern(B, K, N, stride_b, (uint8_t)(run * 7u));
            break;
        case PATTERN_MAX:
            init_matrix_const(A, M, K, stride_a, 0xFF);
            init_matrix_const(B, K, N, stride_b, 0xFF);
            break;
        default:
            init_matrix_pattern(A, M, K, stride_a, 0);
            init_matrix_pattern(B, K, N, stride_b, 0);
            break;
        }

        /* Clear output regions */
        clear_region(ADDR_C_SW, (uint32_t)M * stride_c);
        clear_region(ADDR_C_HW, (uint32_t)M * stride_c);

        /* Software reference */
        sw_gemm_int8(M, K, N, A, B, C_sw, stride_a, stride_b, stride_c);

        /* Hardware accelerator */
        gemm_result_t res = gemm_run_int8(M, K, N, ADDR_A, ADDR_B, ADDR_C_HW,
                                          stride_a, stride_b, stride_c);

        (void)res; /* cycles/status unused for pass/fail */

        /* Verify */
        if (verify_match(C_sw, C_hw, M, N, stride_c, stride_c) != 0) {
            debug_putw(MARKER_FAIL);
            return;
        }
    }

    debug_putw(MARKER_PASS);
}

/* ---------------------------------------------------------------------------
 * Run a single test in acc32 mode
 * --------------------------------------------------------------------------- */
static void run_test_acc32(uint16_t M, uint16_t K, uint16_t N,
                           uint8_t pattern_type)
{
    volatile uint8_t  *A    = (volatile uint8_t  *)ADDR_A;
    volatile uint8_t  *B    = (volatile uint8_t  *)ADDR_B;
    volatile uint32_t *C_hw = (volatile uint32_t *)ADDR_C_HW;
    volatile uint32_t *C_sw = (volatile uint32_t *)ADDR_C_SW;

    uint16_t stride_a = PAD4(K);
    uint16_t stride_b = PAD4(N);
    uint16_t stride_c_bytes = GEMM_STRIDE_ACC32(N);
    uint16_t stride_c_words = stride_c_bytes / 4u;

    test_counter++;
    debug_putw(MARKER_START | (test_counter & 0xFFFFu));

    switch (pattern_type) {
    case PATTERN_SEQ:
        init_matrix_pattern(A, M, K, stride_a, 0);
        init_matrix_pattern(B, K, N, stride_b, 0);
        break;
    case PATTERN_ONES:
        init_matrix_const(A, M, K, stride_a, 1);
        init_matrix_const(B, K, N, stride_b, 1);
        break;
    case PATTERN_MAX:
        init_matrix_const(A, M, K, stride_a, 0xFF);
        init_matrix_const(B, K, N, stride_b, 0xFF);
        break;
    default:
        init_matrix_pattern(A, M, K, stride_a, 0);
        init_matrix_pattern(B, K, N, stride_b, 0);
        break;
    }

    uint16_t r, c;
    for (r = 0; r < M; r++)
        for (c = 0; c < stride_c_words; c++) {
            C_sw[r * stride_c_words + c] = 0;
            C_hw[r * stride_c_words + c] = 0;
        }

    sw_gemm_int8_acc32(M, K, N, A, B, C_sw, stride_a, stride_b, stride_c_words);

    gemm_run_int8_acc32(M, K, N, ADDR_A, ADDR_B, ADDR_C_HW,
                        stride_a, stride_b, stride_c_bytes);

    if (verify_match_32(C_sw, C_hw, M, N, stride_c_words) != 0) {
        debug_putw(MARKER_FAIL);
        return;
    }

    debug_putw(MARKER_PASS);
}

/* ---------------------------------------------------------------------------
 * Main
 * --------------------------------------------------------------------------- */
int main(void)
{
    test_counter = 0;

    run_test(1, 1, 1, PATTERN_SEQ, 0);      /* 1. 1x1x1 trivial */
    run_test(2, 2, 2, PATTERN_SEQ, 0);      /* 2. 2x2x2 tiny */
    run_test(3, 3, 3, PATTERN_SEQ, 0);      /* 3. 3x3x3 small odd */
    run_test(4, 4, 4, PATTERN_SEQ, 0);      /* 4. 4x4x4 sub-tile */
    run_test(5, 5, 5, PATTERN_SEQ, 0);      /* 5. 5x5x5 non-aligned */
    run_test(7, 7, 7, PATTERN_SEQ, 0);      /* 6. 7x7x7 near boundary */
    run_test(8, 8, 8, PATTERN_SEQ, 0);      /* 7. 8x8x8 exact tile */
    run_test(9, 9, 9, PATTERN_SEQ, 0);      /* 8. 9x9x9 just over one tile */
    run_test(15, 15, 15, PATTERN_SEQ, 0);   /* 9. 15x15x15 non-aligned multi-tile */
    run_test(16, 16, 16, PATTERN_SEQ, 0);   /* 10. 16x16x16 exact multi-tile */
    run_test(1, 8, 1, PATTERN_SEQ, 0);      /* 11. 1x8x1 single row/col */
    run_test(8, 1, 8, PATTERN_SEQ, 0);      /* 12. 8x1x8 single K */
    run_test(3, 5, 7, PATTERN_SEQ, 0);      /* 13. 3x5x7 non-square */
    run_test(7, 9, 3, PATTERN_SEQ, 0);      /* 14. 7x9x3 non-square multi-K */
    run_test(1, 16, 1, PATTERN_SEQ, 0);     /* 15. 1x16x1 long K accumulation */
    run_test(8, 8, 8, PATTERN_ONES, 0);     /* 16. 8x8x8 all-ones */
    run_test(8, 8, 8, PATTERN_IDENT, 0);    /* 17. 8x8x8 identity A */
    run_test(4, 4, 4, PATTERN_MAX, 0);      /* 18. 4x4x4 max values (overflow) */
    run_test(8, 8, 8, PATTERN_SEQ, 1);      /* 19. 8x8x8 back-to-back */
    run_test(16, 8, 16, PATTERN_SEQ, 0);    /* 20. 16x8x16 wide multi-tile */
    run_test(8, 16, 8, PATTERN_SEQ, 0);     /* 21. 8x16x8 tall K multi-tile */

    /* --- acc32 mode tests --- */
    run_test_acc32(1, 1, 1, PATTERN_SEQ);      /* 22. acc32 1x1x1 */
    run_test_acc32(4, 4, 4, PATTERN_SEQ);      /* 23. acc32 4x4x4 */
    run_test_acc32(5, 5, 5, PATTERN_SEQ);      /* 24. acc32 5x5x5 non-aligned */
    run_test_acc32(8, 8, 8, PATTERN_SEQ);      /* 25. acc32 8x8x8 exact tile */
    run_test_acc32(8, 8, 8, PATTERN_ONES);     /* 26. acc32 8x8x8 ones */
    run_test_acc32(8, 8, 8, PATTERN_MAX);      /* 27. acc32 8x8x8 max values */
    run_test_acc32(3, 5, 7, PATTERN_SEQ);      /* 28. acc32 3x5x7 non-square */
    run_test_acc32(9, 9, 9, PATTERN_SEQ);      /* 29. acc32 9x9x9 multi-tile */
    run_test_acc32(16, 16, 16, PATTERN_SEQ);   /* 30. acc32 16x16x16 multi-tile */
    run_test_acc32(7, 9, 3, PATTERN_SEQ);      /* 31. acc32 7x9x3 non-square multi-K */

    debug_putw(MARKER_DONE);
    return 0;
}
