/*
 * GEMM Accelerator Fast Stress Test (Golden Model Verification)
 *
 * Runs 21 test patterns WITHOUT a software GEMM reference.
 * Instead, it computes a checksum of the HW output and compares
 * against values precomputed by the Python golden_model.py.
 *
 * This eliminates the O(M*N*K) software multiply bottleneck,
 * making the entire stress test run in minutes on Icarus Verilog
 * instead of hours.
 *
 * Debug protocol (same as original):
 *   0xAAAA0000 | test_num  -> test start marker
 *   0x600D                 -> PASS
 *   0xFA11                 -> FAIL
 *   0x0BAD                 -> checksum mismatch (new)
 *   0xDEAD                 -> all done
 */

#include "gemm_accel.h"
#include <stdint.h>

#define ADDR_A      0x00010000u
#define ADDR_B      0x00012000u
#define ADDR_C_HW   0x00014000u

#define MARKER_START  0xAAAA0000u
#define MARKER_PASS   0x0000600Du
#define MARKER_FAIL   0x0000FA11u
#define MARKER_BAD    0x00000BADu
#define MARKER_DONE   0x0000DEADu

#define PAT_SEQ    0
#define PAT_ONES   1
#define PAT_IDENT  2
#define PAT_MAX    3

#define PAD4(x)  (((x) + 3u) & ~3u)

static uint32_t test_counter;

/* ------------------------------------------------------------------ */
/* Matrix initialization (no multiply -- uses pointer arithmetic)     */
/* ------------------------------------------------------------------ */

static void init_pattern(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                         uint16_t stride, uint8_t seed)
{
    uint16_t r, c;
    volatile uint8_t *row = mat;
    for (r = 0; r < rows; r++) {
        uint8_t rv = (uint8_t)(seed + r * 3u);
        for (c = 0; c < cols; c++) {
            row[c] = (uint8_t)((rv + c * 7u) & 0xFFu);
        }
        for (c = cols; c < stride; c++)
            row[c] = 0;
        row += stride;
    }
}

static void init_const(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                       uint16_t stride, uint8_t val)
{
    uint16_t r, c;
    volatile uint8_t *row = mat;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++)
            row[c] = val;
        for (c = cols; c < stride; c++)
            row[c] = 0;
        row += stride;
    }
}

static void init_identity(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                          uint16_t stride)
{
    uint16_t r, c;
    uint16_t diag = (rows < cols) ? rows : cols;
    volatile uint8_t *row = mat;
    for (r = 0; r < rows; r++) {
        for (c = 0; c < cols; c++)
            row[c] = (r == c && r < diag) ? 1u : 0u;
        for (c = cols; c < stride; c++)
            row[c] = 0;
        row += stride;
    }
}

static void clear_region(volatile uint8_t *p, uint32_t bytes)
{
    uint32_t i;
    for (i = 0; i < bytes; i++)
        p[i] = 0;
}

/* ------------------------------------------------------------------ */
/* Checksum: sum all M*N output bytes (addition only, no multiply)    */
/* ------------------------------------------------------------------ */

static uint32_t compute_checksum(volatile uint8_t *C, uint16_t M, uint16_t N,
                                 uint16_t stride_c)
{
    uint32_t sum = 0;
    uint16_t i, j;
    volatile uint8_t *row = C;
    for (i = 0; i < M; i++) {
        for (j = 0; j < N; j++)
            sum += row[j];
        row += stride_c;
    }
    return sum;
}

/* ------------------------------------------------------------------ */
/* Single test: init -> HW GEMM -> checksum -> compare golden         */
/* ------------------------------------------------------------------ */

static void run_golden(uint16_t M, uint16_t K, uint16_t N,
                       uint8_t pattern,
                       uint32_t exp_checksum, uint8_t exp_c00,
                       int run_twice)
{
    volatile uint8_t *A    = (volatile uint8_t *)ADDR_A;
    volatile uint8_t *B    = (volatile uint8_t *)ADDR_B;
    volatile uint8_t *C_hw = (volatile uint8_t *)ADDR_C_HW;

    uint16_t sa = (uint16_t)PAD4(K);
    uint16_t sb = (uint16_t)PAD4(N);
    uint16_t sc = (uint16_t)PAD4(N);

    uint32_t runs = run_twice ? 2u : 1u;
    uint32_t run;

    test_counter++;
    debug_putw(MARKER_START | (test_counter & 0xFFFFu));

    for (run = 0; run < runs; run++) {
        switch (pattern) {
        case PAT_SEQ:
            init_pattern(A, M, K, sa, 0);
            init_pattern(B, K, N, sb, 0);
            break;
        case PAT_ONES:
            init_const(A, M, K, sa, 1);
            init_const(B, K, N, sb, 1);
            break;
        case PAT_IDENT:
            init_identity(A, M, K, sa);
            init_pattern(B, K, N, sb, 0);
            break;
        case PAT_MAX:
            init_const(A, M, K, sa, 0xFF);
            init_const(B, K, N, sb, 0xFF);
            break;
        default:
            init_pattern(A, M, K, sa, 0);
            init_pattern(B, K, N, sb, 0);
            break;
        }

        clear_region(C_hw, (uint32_t)M * sc);

        gemm_run_int8(M, K, N, ADDR_A, ADDR_B, ADDR_C_HW, sa, sb, sc);

        uint32_t chk = compute_checksum(C_hw, M, N, sc);
        uint8_t  c00 = C_hw[0];

        if (chk != exp_checksum || c00 != exp_c00) {
            debug_putw(chk);
            debug_putw((uint32_t)c00);
            debug_putw(exp_checksum);
            debug_putw(MARKER_FAIL);
            return;
        }
    }

    debug_putw(MARKER_PASS);
}

/* ------------------------------------------------------------------ */
/* Main -- 21 tests with golden expected values from golden_model.py  */
/* ------------------------------------------------------------------ */

int main(void)
{
    test_counter = 0;

    /*       M   K   N   pattern      checksum  c00  b2b */
    run_golden( 1,  1,  1, PAT_SEQ,   0x00000000, 0x00, 0); /*  1 */
    run_golden( 2,  2,  2, PAT_SEQ,   0x000000F2, 0x15, 0); /*  2 */
    run_golden( 3,  3,  3, PAT_SEQ,   0x00000506, 0x69, 0); /*  3 */
    run_golden( 4,  4,  4, PAT_SEQ,   0x000007D0, 0x26, 0); /*  4 */
    run_golden( 5,  5,  5, PAT_SEQ,   0x00000BD2, 0x76, 0); /*  5 */
    run_golden( 7,  7,  7, PAT_SEQ,   0x00001968, 0x77, 0); /*  6 */
    run_golden( 8,  8,  8, PAT_SEQ,   0x00001C80, 0x7C, 0); /*  7 */
    run_golden( 9,  9,  9, PAT_SEQ,   0x000028EC, 0xBC, 0); /*  8 */
    run_golden(15, 15, 15, PAT_SEQ,   0x00006C94, 0x43, 0); /*  9 */
    run_golden(16, 16, 16, PAT_SEQ,   0x00007F00, 0xB8, 0); /* 10 */
    run_golden( 1,  8,  1, PAT_SEQ,   0x0000007C, 0x7C, 0); /* 11 */
    run_golden( 8,  1,  8, PAT_SEQ,   0x00001950, 0x00, 0); /* 12 */
    run_golden( 3,  5,  7, PAT_SEQ,   0x0000097D, 0x76, 0); /* 13 */
    run_golden( 7,  9,  3, PAT_SEQ,   0x00000A5F, 0xBC, 0); /* 14 */
    run_golden( 1, 16,  1, PAT_SEQ,   0x000000B8, 0xB8, 0); /* 15 */
    run_golden( 8,  8,  8, PAT_ONES,  0x00000200, 0x08, 0); /* 16 */
    run_golden( 8,  8,  8, PAT_IDENT, 0x000008C0, 0x00, 0); /* 17 */
    run_golden( 4,  4,  4, PAT_MAX,   0x00000040, 0x04, 0); /* 18 */
    run_golden( 8,  8,  8, PAT_SEQ,   0x00001C80, 0x7C, 1); /* 19 back-to-back */
    run_golden(16,  8, 16, PAT_SEQ,   0x00007A00, 0x7C, 0); /* 20 */
    run_golden( 8, 16,  8, PAT_SEQ,   0x00002000, 0xB8, 0); /* 21 */

    debug_putw(MARKER_DONE);
    return 0;
}
