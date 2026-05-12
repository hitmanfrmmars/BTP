#include "gemm_accel.h"

/*
 * Benchmark firmware: compares software-only vs. hardware-accelerated GEMM.
 *
 * For each matrix size, we:
 *   1. Initialize A and B with a simple pattern (PAD4-aligned strides)
 *   2. Run software GEMM, report cycle count
 *   3. Run hardware GEMM, report cycle count
 *   4. Verify both produce the same result
 *
 * Debug output protocol (testbench reads these in order):
 *   word 0: 0xBEEF0000 | size   -- test header (size = M = K = N)
 *   word 1: SW cycle count
 *   word 2: HW cycle count
 *   word 3: 0x600D (pass) or 0xFA11 (fail)
 *   ... repeat for each size ...
 *   final:  0x0000DEAD            -- done marker
 */

#define ADDR_A     0x00010000u
#define ADDR_B     0x00012000u
#define ADDR_C_SW  0x00014000u
#define ADDR_C_HW  0x00016000u

#define MARKER_PASS  0x0000600Du
#define MARKER_FAIL  0x0000FA11u
#define MARKER_DONE  0x0000DEADu

static inline uint32_t rdcycle(void)
{
    uint32_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
}

static void sw_gemm_int8(uint16_t M, uint16_t K, uint16_t N,
                          volatile uint8_t *A,
                          volatile uint8_t *B,
                          volatile uint8_t *C,
                          uint16_t stride_a, uint16_t stride_b, uint16_t stride_c)
{
    for (uint16_t m = 0; m < M; m++) {
        for (uint16_t n = 0; n < N; n++) {
            uint32_t acc = 0;
            for (uint16_t k = 0; k < K; k++) {
                acc += (uint32_t)A[m * stride_a + k] * (uint32_t)B[k * stride_b + n];
            }
            C[m * stride_c + n] = (uint8_t)acc;
        }
    }
}

static void sw_gemm_int8_acc32(uint16_t M, uint16_t K, uint16_t N,
                                volatile uint8_t *A,
                                volatile uint8_t *B,
                                volatile uint32_t *C,
                                uint16_t stride_a, uint16_t stride_b,
                                uint16_t stride_c_words)
{
    for (uint16_t m = 0; m < M; m++) {
        for (uint16_t n = 0; n < N; n++) {
            uint32_t acc = 0;
            for (uint16_t k = 0; k < K; k++) {
                acc += (uint32_t)A[m * stride_a + k] * (uint32_t)B[k * stride_b + n];
            }
            C[m * stride_c_words + n] = acc;
        }
    }
}

static void init_matrix(volatile uint8_t *mat, uint16_t rows, uint16_t cols,
                         uint16_t stride)
{
    for (uint16_t r = 0; r < rows; r++) {
        for (uint16_t c = 0; c < cols; c++) {
            mat[r * stride + c] = (uint8_t)((r * 3 + c * 7 + 1) & 0x0F);
        }
    }
}

static int verify_match(volatile uint8_t *C_sw, volatile uint8_t *C_hw,
                         uint16_t M, uint16_t N,
                         uint16_t stride_sw, uint16_t stride_hw)
{
    int errors = 0;
    for (uint16_t m = 0; m < M; m++) {
        for (uint16_t n = 0; n < N; n++) {
            if (C_sw[m * stride_sw + n] != C_hw[m * stride_hw + n])
                errors++;
        }
    }
    return errors;
}

static int verify_match_32(volatile uint32_t *C_sw, volatile uint32_t *C_hw,
                            uint16_t M, uint16_t N,
                            uint16_t stride_words)
{
    int errors = 0;
    for (uint16_t m = 0; m < M; m++) {
        for (uint16_t n = 0; n < N; n++) {
            if (C_sw[m * stride_words + n] != C_hw[m * stride_words + n])
                errors++;
        }
    }
    return errors;
}

static void clear_matrix(volatile uint8_t *mat, uint16_t rows, uint16_t stride)
{
    for (uint16_t r = 0; r < rows; r++) {
        for (uint16_t c = 0; c < stride; c++) {
            mat[r * stride + c] = 0;
        }
    }
}

static void run_benchmark(uint16_t size)
{
    uint16_t M = size, K = size, N = size;
    uint16_t stride_a = PAD4(K);
    uint16_t stride_b = PAD4(N);
    uint16_t stride_c = PAD4(N);

    volatile uint8_t *A    = (volatile uint8_t *)ADDR_A;
    volatile uint8_t *B    = (volatile uint8_t *)ADDR_B;
    volatile uint8_t *C_sw = (volatile uint8_t *)ADDR_C_SW;
    volatile uint8_t *C_hw = (volatile uint8_t *)ADDR_C_HW;

    debug_putw(0xBEEF0000u | size);

    init_matrix(A, M, K, stride_a);
    init_matrix(B, K, N, stride_b);
    clear_matrix(C_sw, M, stride_c);
    clear_matrix(C_hw, M, stride_c);

    uint32_t t0 = rdcycle();
    sw_gemm_int8(M, K, N, A, B, C_sw, stride_a, stride_b, stride_c);
    uint32_t t1 = rdcycle();
    uint32_t sw_cycles = t1 - t0;

    debug_putw(sw_cycles);

    gemm_result_t res = gemm_run_int8(
        M, K, N,
        ADDR_A, ADDR_B, ADDR_C_HW,
        stride_a, stride_b, stride_c
    );

    debug_putw(res.cycles);

    int errors = verify_match(C_sw, C_hw, M, N, stride_c, stride_c);
    debug_putw(errors == 0 ? MARKER_PASS : MARKER_FAIL);
}

static void run_benchmark_acc32(uint16_t size)
{
    uint16_t M = size, K = size, N = size;
    uint16_t stride_a = PAD4(K);
    uint16_t stride_b = PAD4(N);
    uint16_t stride_c_bytes = GEMM_STRIDE_ACC32(N);
    uint16_t stride_c_words = stride_c_bytes / 4u;

    volatile uint8_t  *A    = (volatile uint8_t  *)ADDR_A;
    volatile uint8_t  *B    = (volatile uint8_t  *)ADDR_B;
    volatile uint32_t *C_sw = (volatile uint32_t *)ADDR_C_SW;
    volatile uint32_t *C_hw = (volatile uint32_t *)ADDR_C_HW;

    debug_putw(0xACC30000u | size);

    init_matrix(A, M, K, stride_a);
    init_matrix(B, K, N, stride_b);

    for (uint16_t r = 0; r < M; r++)
        for (uint16_t c = 0; c < stride_c_words; c++) {
            C_sw[r * stride_c_words + c] = 0;
            C_hw[r * stride_c_words + c] = 0;
        }

    uint32_t t0 = rdcycle();
    sw_gemm_int8_acc32(M, K, N, A, B, C_sw, stride_a, stride_b, stride_c_words);
    uint32_t t1 = rdcycle();
    debug_putw(t1 - t0);

    gemm_result_t res = gemm_run_int8_acc32(
        M, K, N,
        ADDR_A, ADDR_B, ADDR_C_HW,
        stride_a, stride_b, stride_c_bytes
    );
    debug_putw(res.cycles);

    int errors = verify_match_32(C_sw, C_hw, M, N, stride_c_words);
    debug_putw(errors == 0 ? MARKER_PASS : MARKER_FAIL);
}

int main(void)
{
    static const uint16_t sizes[] = { 4, 5, 7, 8, 10, 13, 16 };
    int n_tests = sizeof(sizes) / sizeof(sizes[0]);

    for (int i = 0; i < n_tests; i++) {
        run_benchmark(sizes[i]);
    }

    for (int i = 0; i < n_tests; i++) {
        run_benchmark_acc32(sizes[i]);
    }

    debug_putw(MARKER_DONE);
    return 0;
}
