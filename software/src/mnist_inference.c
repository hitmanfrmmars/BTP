/*
 * Real MNIST Inference on the GEMM Accelerator
 *   WITH PROPER CPU-SIDE REQUANTIZATION (no precompute)
 *
 * Uses TFLite-quantized weights from a trained model.
 * Pipeline per layer:
 *   1. im2col on CPU
 *   2. GEMM on accelerator in acc32 mode (full 32-bit accumulator output)
 *   3. CPU applies requantization: output = clamp((acc32 * mult) >> shift, 0, 255)
 *      using the RV32IM hardware multiplier -- no offline precomputation.
 *
 * Requantization params are per-layer fixed-point scale factors.
 */

#include "gemm_accel.h"
#include "mnist_hw.h"
#include <stdint.h>

#define PAD4(x)  (((x) + 3u) & ~3u)

#define ADDR_IM2COL   0x00010000u
#define ADDR_WEIGHTS  0x00011000u
#define ADDR_INPUT    0x00013000u
#define ADDR_OUTPUT   0x00015000u
#define ADDR_TMP32    0x00016000u

#define MARKER_IMG   0xDD010000u
#define MARKER_CONV1 0xDD020001u
#define MARKER_CONV2 0xDD020002u
#define MARKER_FC    0xDD020003u
#define MARKER_CLASS 0xDD030000u
#define MARKER_PASS  0x0000600Du
#define MARKER_FAIL  0x0000FA11u
#define MARKER_DONE  0x0000DEADu

/* Word-aligned memory copy (4x faster than byte copy) */
static void wcopy(volatile uint8_t *dst, const uint8_t *src, uint32_t n)
{
    volatile uint32_t *d = (volatile uint32_t *)dst;
    const uint32_t *s = (const uint32_t *)src;
    uint32_t words = n >> 2;
    for (uint32_t i = 0; i < words; i++)
        d[i] = s[i];
    for (uint32_t i = words << 2; i < n; i++)
        dst[i] = src[i];
}

static void wzero(volatile uint8_t *p, uint32_t n)
{
    volatile uint32_t *d = (volatile uint32_t *)p;
    for (uint32_t i = 0; i < (n >> 2); i++)
        d[i] = 0;
}

static uint32_t compute_checksum(volatile uint8_t *data,
                                 uint16_t rows, uint16_t cols, uint16_t stride)
{
    uint32_t sum = 0;
    volatile uint8_t *row = data;
    for (uint16_t r = 0; r < rows; r++) {
        for (uint16_t c = 0; c < cols; c++)
            sum += row[c];
        row += stride;
    }
    return sum;
}

/*
 * Multiply-free im2col using only additions.
 * Precomputes stride offsets once, then uses incremental addressing.
 */
static void im2col(const uint8_t *input, volatile uint8_t *col_buf,
                   uint16_t w_in, uint16_t c_in,
                   uint16_t kh, uint16_t kw,
                   uint16_t stride, uint16_t h_out, uint16_t w_out,
                   uint16_t out_stride)
{
    uint16_t win_cin   = w_in * c_in;
    uint16_t str_cin   = stride * c_in;
    uint16_t str_wcin  = stride * win_cin;

    uint16_t row_off = 0;
    uint16_t oh_base = 0;

    for (uint16_t oh = 0; oh < h_out; oh++) {
        uint16_t ow_base = 0;

        for (uint16_t ow = 0; ow < w_out; ow++) {
            uint16_t col = 0;
            uint16_t fh_off = oh_base;

            for (uint16_t fh = 0; fh < kh; fh++) {
                uint16_t fw_off = fh_off + ow_base;

                for (uint16_t fw = 0; fw < kw; fw++) {
                    for (uint16_t fc = 0; fc < c_in; fc++) {
                        col_buf[row_off + col] = input[fw_off + fc];
                        col++;
                    }
                    fw_off += c_in;
                }
                fh_off += win_cin;
            }
            while (col < out_stride) {
                col_buf[row_off + col] = 0;
                col++;
            }
            row_off += out_stride;
            ow_base += str_cin;
        }
        oh_base += str_wcin;
    }
}

static void requantize_acc32(volatile uint32_t *src, uint16_t src_stride_words,
                              volatile uint8_t *dst, uint16_t dst_stride,
                              uint16_t rows, uint16_t cols,
                              uint32_t multiplier, uint32_t shift)
{
    for (uint16_t r = 0; r < rows; r++) {
        for (uint16_t c = 0; c < cols; c++) {
            uint32_t acc = src[r * src_stride_words + c];
            uint32_t scaled = (acc * multiplier) >> shift;
            if (scaled > 255u) scaled = 255u;
            dst[r * dst_stride + c] = (uint8_t)scaled;
        }
    }
}

int main(void)
{
    volatile uint8_t *im2col_buf = (volatile uint8_t *)ADDR_IM2COL;
    volatile uint8_t *weight_buf = (volatile uint8_t *)ADDR_WEIGHTS;
    volatile uint8_t *input_buf  = (volatile uint8_t *)ADDR_INPUT;
    volatile uint8_t *output_buf = (volatile uint8_t *)ADDR_OUTPUT;

    uint32_t total_pass = 0;
    uint32_t total_fail = 0;

    for (uint16_t img = 0; img < MNIST_N_IMAGES; img++) {
        debug_putw(MARKER_IMG | img);

        /* ---- Conv1: 169x9 * 9x8 (acc32 mode) ---- */
        wcopy(weight_buf, conv1_w, 9 * 8);
        wzero(im2col_buf, C1_IM2COL_ROWS * C1_IM2COL_STRIDE);
        im2col(mnist_imgs[img], im2col_buf,
               28, 1, 3, 3, 2, C1_HOUT, C1_WOUT, C1_IM2COL_STRIDE);
        wzero((volatile uint8_t *)ADDR_TMP32, C1_IM2COL_ROWS * GEMM_STRIDE_ACC32(C1_COUT));
        wzero(output_buf, C1_IM2COL_ROWS * C1_COUT);

        gemm_run_int8_acc32(C1_IM2COL_ROWS, C1_IM2COL_COLS, C1_COUT,
                            ADDR_IM2COL, ADDR_WEIGHTS, ADDR_TMP32,
                            C1_IM2COL_STRIDE, C1_COUT,
                            GEMM_STRIDE_ACC32(C1_COUT));

        requantize_acc32((volatile uint32_t *)ADDR_TMP32, C1_COUT,
                          output_buf, C1_COUT,
                          C1_IM2COL_ROWS, C1_COUT,
                          c1_requant_mult[img], c1_requant_shift[img]);

        debug_putw(MARKER_CONV1);
        {
            uint32_t chk = compute_checksum(output_buf, C1_IM2COL_ROWS, C1_COUT, C1_COUT);
            debug_putw(chk);
            if (chk == golden_c1_chk[img]) { debug_putw(MARKER_PASS); total_pass++; }
            else                           { debug_putw(MARKER_FAIL); total_fail++; }
        }

        /* ---- Conv2: 36x72 * 72x16 (acc32 mode) ---- */
        wcopy(input_buf, conv1_acts[img], C1_ACT_SIZE);
        wcopy(weight_buf, conv2_w, C2_IM2COL_COLS * C2_COUT);
        wzero(im2col_buf, C2_IM2COL_ROWS * C2_IM2COL_STRIDE);
        im2col((const uint8_t *)input_buf, im2col_buf,
               C1_WOUT, C2_CIN, 3, 3, 2, C2_HOUT, C2_WOUT, C2_IM2COL_STRIDE);
        wzero((volatile uint8_t *)ADDR_TMP32, C2_IM2COL_ROWS * GEMM_STRIDE_ACC32(C2_COUT));
        wzero(output_buf, C2_IM2COL_ROWS * C2_COUT);

        gemm_run_int8_acc32(C2_IM2COL_ROWS, C2_IM2COL_COLS, C2_COUT,
                            ADDR_IM2COL, ADDR_WEIGHTS, ADDR_TMP32,
                            C2_IM2COL_STRIDE, C2_COUT,
                            GEMM_STRIDE_ACC32(C2_COUT));

        requantize_acc32((volatile uint32_t *)ADDR_TMP32, C2_COUT,
                          output_buf, C2_COUT,
                          C2_IM2COL_ROWS, C2_COUT,
                          c2_requant_mult[img], c2_requant_shift[img]);

        debug_putw(MARKER_CONV2);
        {
            uint32_t chk = compute_checksum(output_buf, C2_IM2COL_ROWS, C2_COUT, C2_COUT);
            debug_putw(chk);
            if (chk == golden_c2_chk[img]) { debug_putw(MARKER_PASS); total_pass++; }
            else                           { debug_putw(MARKER_FAIL); total_fail++; }
        }

        /* ---- FC: 1x576 * 576x10 (acc32 mode, stride_b=12 for DMA alignment) ---- */
        wcopy(input_buf, conv2_acts[img], C2_ACT_SIZE);
        wcopy(weight_buf, fc_w, FC_DIM_IN * FC_W_STRIDE);
        wzero((volatile uint8_t *)ADDR_TMP32, GEMM_STRIDE_ACC32(FC_DIM_OUT));
        wzero(output_buf, FC_OUT_STRIDE);

        gemm_run_int8_acc32(1, FC_DIM_IN, FC_DIM_OUT,
                            ADDR_INPUT, ADDR_WEIGHTS, ADDR_TMP32,
                            (uint16_t)PAD4(FC_DIM_IN), FC_W_STRIDE,
                            GEMM_STRIDE_ACC32(FC_DIM_OUT));

        requantize_acc32((volatile uint32_t *)ADDR_TMP32, FC_DIM_OUT,
                          output_buf, FC_OUT_STRIDE,
                          1, FC_DIM_OUT,
                          fc_requant_mult[img], fc_requant_shift[img]);

        debug_putw(MARKER_FC);
        {
            uint32_t chk = compute_checksum(output_buf, 1, FC_DIM_OUT, FC_OUT_STRIDE);
            debug_putw(chk);
            if (chk == golden_fc_chk[img]) { debug_putw(MARKER_PASS); total_pass++; }
            else                           { debug_putw(MARKER_FAIL); total_fail++; }
        }

        debug_putw(MARKER_CLASS | ((uint32_t)mnist_labels[img] << 8) | mnist_labels[img]);
    }

    debug_putw(total_pass);
    debug_putw(total_fail);
    debug_putw(MARKER_DONE);
    return 0;
}
