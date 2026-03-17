/**
 * GEMM Kernel Library Implementation
 *
 * Tiled GEMM using HW accelerator for large matrices,
 * falls back to software for small ones.
 */

#include "gemm_kernel.h"
#include "gemm_hal.h"
#include <string.h>

/* ---- Helpers ---- */

static inline uint8_t saturate_uint8(int32_t val) {
    if (val < 0)   return 0;
    if (val > 255) return 255;
    return (uint8_t)val;
}

static inline int min_int(int a, int b) {
    return (a < b) ? a : b;
}

/* ---- Software reference ---- */

void gemm_int8_sw(const uint8_t *a, const uint8_t *b, int32_t *c,
                  int m, int k, int n,
                  int lda, int ldb, int ldc) {
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            int32_t acc = 0;
            for (int kk = 0; kk < k; kk++) {
                acc += (int32_t)a[i * lda + kk] * (int32_t)b[kk * ldb + j];
            }
            c[i * ldc + j] = acc;
        }
    }
}

/* ---- Hardware-accelerated GEMM ---- */

/**
 * Copy a tile from source matrix into a contiguous tile buffer.
 * Pads with zeros if the tile extends beyond matrix boundaries.
 */
static void extract_tile_uint8(const uint8_t *src, uint8_t *tile,
                               int row_start, int col_start,
                               int total_rows, int total_cols,
                               int ld, int tile_size) {
    for (int i = 0; i < tile_size; i++) {
        for (int j = 0; j < tile_size; j++) {
            int r = row_start + i;
            int c = col_start + j;
            if (r < total_rows && c < total_cols)
                tile[i * tile_size + j] = src[r * ld + c];
            else
                tile[i * tile_size + j] = 0;
        }
    }
}

/**
 * Accumulate a tile of int32 results back into the output matrix.
 */
static void store_tile_int32(int32_t *dst, const int32_t *tile,
                             int row_start, int col_start,
                             int total_rows, int total_cols,
                             int ld, int tile_size, int accumulate) {
    for (int i = 0; i < tile_size; i++) {
        for (int j = 0; j < tile_size; j++) {
            int r = row_start + i;
            int c = col_start + j;
            if (r < total_rows && c < total_cols) {
                if (accumulate)
                    dst[r * ld + c] += tile[i * tile_size + j];
                else
                    dst[r * ld + c] = tile[i * tile_size + j];
            }
        }
    }
}

void gemm_int8(const uint8_t *a, const uint8_t *b, int32_t *c,
               int m, int k, int n,
               int lda, int ldb, int ldc) {

    /* Fall back to software for small matrices */
    if ((int64_t)m * k * n < GEMM_HW_THRESHOLD) {
        gemm_int8_sw(a, b, c, m, k, n, lda, ldb, ldc);
        return;
    }

    const int T = GEMM_TILE_SIZE;

    /*
     * For HW-accelerated path: configure the accelerator tile by tile.
     * The tiling engine in hardware handles this, but the software must
     * set up the correct addresses and dimensions.
     */
    gemm_config_t cfg;
    cfg.mode       = GEMM_MODE_INT8;
    cfg.irq_enable = 0;
    cfg.m          = (uint16_t)m;
    cfg.k          = (uint16_t)k;
    cfg.n          = (uint16_t)n;
    cfg.src_a      = (uint32_t)(uintptr_t)a;
    cfg.src_b      = (uint32_t)(uintptr_t)b;
    cfg.dst_c      = (uint32_t)(uintptr_t)c;
    cfg.stride_a   = (uint16_t)(lda * sizeof(uint8_t));
    cfg.stride_b   = (uint16_t)(ldb * sizeof(uint8_t));
    cfg.stride_c   = (uint16_t)(ldc * sizeof(int32_t));

    gemm_run(&cfg);
}

void gemm_int16(const uint16_t *a, const uint16_t *b, int64_t *c,
                int m, int k, int n,
                int lda, int ldb, int ldc) {
    /* Software fallback for int16 (HW path similar) */
    for (int i = 0; i < m; i++) {
        for (int j = 0; j < n; j++) {
            int64_t acc = 0;
            for (int kk = 0; kk < k; kk++) {
                acc += (int64_t)a[i * lda + kk] * (int64_t)b[kk * ldb + j];
            }
            c[i * ldc + j] = acc;
        }
    }
}

void gemm_quantized_int8(const uint8_t *a, const uint8_t *b,
                         const int32_t *bias, uint8_t *c,
                         int m, int k, int n,
                         int lda, int ldb, int ldc,
                         int32_t scale, uint8_t zero_pt) {
    /* Temporary int32 accumulation buffer */
    int32_t acc_buf[GEMM_TILE_SIZE * GEMM_TILE_SIZE];
    const int T = GEMM_TILE_SIZE;

    /* Tiled GEMM with requantization */
    for (int tm = 0; tm < m; tm += T) {
        for (int tn = 0; tn < n; tn += T) {
            /* Clear accumulation buffer */
            memset(acc_buf, 0, sizeof(acc_buf));

            for (int tk = 0; tk < k; tk += T) {
                int tile_m = min_int(T, m - tm);
                int tile_k = min_int(T, k - tk);
                int tile_n = min_int(T, n - tn);

                /* Software accumulation for this K-tile */
                for (int i = 0; i < tile_m; i++) {
                    for (int j = 0; j < tile_n; j++) {
                        int32_t partial = 0;
                        for (int kk = 0; kk < tile_k; kk++) {
                            partial += (int32_t)a[(tm+i)*lda + (tk+kk)]
                                     * (int32_t)b[(tk+kk)*ldb + (tn+j)];
                        }
                        acc_buf[i * T + j] += partial;
                    }
                }
            }

            /* Requantize and store */
            for (int i = 0; i < min_int(T, m - tm); i++) {
                for (int j = 0; j < min_int(T, n - tn); j++) {
                    int32_t val = acc_buf[i * T + j];

                    /* Add bias if present */
                    if (bias)
                        val += bias[tn + j];

                    /* Fixed-point multiply: val * scale >> 16 */
                    int64_t scaled = ((int64_t)val * scale) >> 16;

                    /* Add zero point and saturate */
                    c[(tm+i)*ldc + (tn+j)] = saturate_uint8((int32_t)scaled + zero_pt);
                }
            }
        }
    }
}
