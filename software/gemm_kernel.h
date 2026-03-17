/**
 * GEMM Kernel Library
 *
 * Tiled matrix multiplication for arbitrary dimensions using the HW accelerator.
 * Handles non-aligned sizes with padding, quantized GEMM with requantization,
 * and memory layout transformations.
 */

#ifndef GEMM_KERNEL_H
#define GEMM_KERNEL_H

#include <stdint.h>

#define GEMM_TILE_SIZE  4   /* Matches hardware MAC array dimension */

/* Minimum GEMM size to use HW accelerator (below this, use software) */
#define GEMM_HW_THRESHOLD  64

/**
 * General int8 matrix multiply: C = A * B
 * Automatically tiles and dispatches to HW accelerator for large matrices.
 *
 * @param a     Row-major int8 matrix A [m x k]
 * @param b     Row-major int8 matrix B [k x n]
 * @param c     Row-major int32 output  [m x n] (accumulated in 32-bit)
 * @param m     Number of rows in A
 * @param k     Shared inner dimension
 * @param n     Number of columns in B
 * @param lda   Leading dimension (row stride in elements) of A
 * @param ldb   Leading dimension of B
 * @param ldc   Leading dimension of C
 */
void gemm_int8(const uint8_t *a, const uint8_t *b, int32_t *c,
               int m, int k, int n,
               int lda, int ldb, int ldc);

/**
 * General int16 matrix multiply: C = A * B
 *
 * @param a     Row-major int16 matrix A [m x k]
 * @param b     Row-major int16 matrix B [k x n]
 * @param c     Row-major int64 output  [m x n]
 */
void gemm_int16(const uint16_t *a, const uint16_t *b, int64_t *c,
                int m, int k, int n,
                int lda, int ldb, int ldc);

/**
 * Quantized GEMM: C_q = requantize(A_q * B_q + bias)
 * int8 inputs, int32 accumulation, requantized back to int8.
 *
 * @param a         int8 activations [m x k]
 * @param b         int8 weights [k x n]
 * @param bias      int32 bias vector [n] (NULL for no bias)
 * @param c         int8 output [m x n]
 * @param m, k, n   Dimensions
 * @param scale     Fixed-point scale (Q16.16 format)
 * @param zero_pt   Output zero point
 */
void gemm_quantized_int8(const uint8_t *a, const uint8_t *b,
                         const int32_t *bias, uint8_t *c,
                         int m, int k, int n,
                         int lda, int ldb, int ldc,
                         int32_t scale, uint8_t zero_pt);

/**
 * Software-only reference GEMM (no hardware acceleration).
 * Used for small matrices and verification.
 */
void gemm_int8_sw(const uint8_t *a, const uint8_t *b, int32_t *c,
                  int m, int k, int n,
                  int lda, int ldb, int ldc);

#endif /* GEMM_KERNEL_H */
