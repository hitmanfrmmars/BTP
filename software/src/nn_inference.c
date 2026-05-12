/*
 * Complete Neural Network Inference on the GEMM Accelerator
 *   WITH PROPER CPU-SIDE REQUANTIZATION (no offline precompute)
 *
 * Architecture:
 *   Input 8x8x1 -> Conv2D(3x3,1->4) -> Requantize -> ReLU
 *                -> Conv2D(3x3,4->8) -> Requantize -> ReLU
 *                -> Flatten(128) -> FC(128->4) -> Requantize -> Argmax
 *
 * Pipeline per layer:
 *   1. im2col on CPU (rearranges input for GEMM)
 *   2. GEMM on accelerator in acc32 mode (outputs full 32-bit accumulators)
 *   3. CPU reads 32-bit accumulators and applies:
 *        output_u8 = clamp((acc32 * multiplier) >> shift, 0, 255)
 *      using the RV32IM hardware multiplier -- NO offline precomputation.
 *
 * The requantization parameters (multiplier, shift) are TFLite-style
 * fixed-point scale factors computed from the quantization ranges.
 */

#include "gemm_accel.h"
#include <stdint.h>

/* ================================================================
 * DMA alignment helper -- THE critical constraint for im2col
 * ================================================================ */
#define PAD4(x)  (((x) + 3u) & ~3u)

/* ================================================================
 * Network dimensions
 * ================================================================ */
#define INPUT_H     8
#define INPUT_W     8
#define INPUT_C     1

#define CONV1_KH    3
#define CONV1_KW    3
#define CONV1_CIN   1
#define CONV1_COUT  4
#define CONV1_STR   1
#define CONV1_HOUT  ((INPUT_H - CONV1_KH) / CONV1_STR + 1)    /* 6 */
#define CONV1_WOUT  ((INPUT_W - CONV1_KW) / CONV1_STR + 1)    /* 6 */

#define CONV2_KH    3
#define CONV2_KW    3
#define CONV2_CIN   4
#define CONV2_COUT  8
#define CONV2_STR   1
#define CONV2_HOUT  ((CONV1_HOUT - CONV2_KH) / CONV2_STR + 1) /* 4 */
#define CONV2_WOUT  ((CONV1_WOUT - CONV2_KW) / CONV2_STR + 1) /* 4 */

#define FC_IN       (CONV2_HOUT * CONV2_WOUT * CONV2_COUT)     /* 128 */
#define FC_OUT      4

/* im2col dimensions (GEMM M, K, N for each conv layer) */
#define IM2COL1_ROWS  (CONV1_HOUT * CONV1_WOUT)               /* 36 */
#define IM2COL1_COLS  (CONV1_KH * CONV1_KW * CONV1_CIN)       /*  9 */
#define IM2COL1_STRIDE PAD4(IM2COL1_COLS)                      /* 12 */

#define IM2COL2_ROWS  (CONV2_HOUT * CONV2_WOUT)               /* 16 */
#define IM2COL2_COLS  (CONV2_KH * CONV2_KW * CONV2_CIN)       /* 36 */
#define IM2COL2_STRIDE PAD4(IM2COL2_COLS)                      /* 36 */

/* ================================================================
 * Memory map (all in upper 64KB data region)
 * ================================================================ */
#define ADDR_INPUT      0x00010000u
#define ADDR_CONV1_W    0x00010100u   /* 9 x 4 = 36 bytes */
#define ADDR_IM2COL1    0x00010200u   /* 36 x 12 = 432 bytes */
#define ADDR_CONV1_OUT  0x00010400u   /* 36 x 4 = 144 bytes */
#define ADDR_CONV2_W    0x00010500u   /* 36 x 8 = 288 bytes */
#define ADDR_IM2COL2    0x00010700u   /* 16 x 36 = 576 bytes */
#define ADDR_CONV2_OUT  0x00010A00u   /* 16 x 8 = 128 bytes */
#define ADDR_FC_W       0x00010B00u   /* 128 x 4 = 512 bytes */
#define ADDR_FC_OUT     0x00010D00u   /* 1 x 4 = 4 bytes */
#define ADDR_TMP32      0x00010E00u   /* temp 32-bit acc output (max 576 bytes) */

/* ================================================================
 * Requantization parameters (from golden_nn.py --header)
 *   output_u8 = clamp((acc32 * MULT) >> SHIFT, 0, 255)
 * ================================================================ */
#define CONV1_REQUANT_MULT   417792u
#define CONV1_REQUANT_SHIFT  18u
#define CONV2_REQUANT_MULT   792u
#define CONV2_REQUANT_SHIFT  16u
#define FC_REQUANT_MULT      77u
#define FC_REQUANT_SHIFT     16u

/* ================================================================
 * Golden values (from golden_nn.py with requantization)
 * ================================================================ */
#define GOLDEN_CONV1_CHECKSUM  0x000049E8u
#define GOLDEN_CONV1_C00       0x82u
#define GOLDEN_CONV2_CHECKSUM  0x000067A4u
#define GOLDEN_CONV2_C00       0xB2u
#define GOLDEN_FC_CHECKSUM     0x000003A5u
#define GOLDEN_FC_CLASS        3u

/* Debug markers */
#define MARKER_CONV1  0xCCCC0001u
#define MARKER_CONV2  0xCCCC0002u
#define MARKER_FC     0xCCCC0003u
#define MARKER_CLASS  0xCCCC0004u
#define MARKER_PASS   0x0000600Du
#define MARKER_FAIL   0x0000FA11u
#define MARKER_DONE   0x0000DEADu

/* ================================================================
 * Utility functions
 * ================================================================ */

static void clear_region(volatile uint8_t *p, uint32_t bytes)
{
    for (uint32_t i = 0; i < bytes; i++) p[i] = 0;
}

static uint32_t compute_checksum(volatile uint8_t *data, uint16_t rows,
                                 uint16_t cols, uint16_t stride)
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
 * CPU-side requantization using RV32IM hardware multiply.
 * Reads full 32-bit accumulators from the accelerator output,
 * applies fixed-point scaling, and clamps to uint8.
 */
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

static void relu_inplace(volatile uint8_t *data, uint16_t rows,
                         uint16_t cols, uint16_t stride)
{
    /*
     * For uint8 output, all values are already >= 0.
     * In a signed-quantized scheme with zero-point, we'd clamp here.
     * Included for architectural completeness -- this is where
     * activation would go in a production pipeline.
     */
    (void)data; (void)rows; (void)cols; (void)stride;
}

/* ================================================================
 * im2col -- transforms convolution into GEMM
 *
 * Converts each receptive field patch of the input feature map
 * into a row of the column buffer matrix.
 *
 * CRITICAL: out_stride MUST be word-aligned (multiple of 4) for
 * the DMA engine to correctly read this buffer during GEMM.
 * ================================================================ */
static void im2col(volatile uint8_t *input, volatile uint8_t *col_buf,
                   uint16_t w_in, uint16_t c_in,
                   uint16_t kh, uint16_t kw,
                   uint16_t stride, uint16_t h_out, uint16_t w_out,
                   uint16_t out_stride)
{
    for (uint16_t oh = 0; oh < h_out; oh++) {
        for (uint16_t ow = 0; ow < w_out; ow++) {
            uint16_t row_offset = (oh * w_out + ow) * out_stride;
            uint16_t col = 0;
            for (uint16_t fh = 0; fh < kh; fh++) {
                for (uint16_t fw = 0; fw < kw; fw++) {
                    uint16_t ih = oh * stride + fh;
                    uint16_t iw = ow * stride + fw;
                    uint16_t base = (ih * w_in + iw) * c_in;
                    for (uint16_t fc = 0; fc < c_in; fc++) {
                        col_buf[row_offset + col] = input[base + fc];
                        col++;
                    }
                }
            }
            /* Zero-pad remaining columns to stride boundary */
            while (col < out_stride) {
                col_buf[row_offset + col] = 0;
                col++;
            }
        }
    }
}

/* ================================================================
 * Weight initialization (must match golden_nn.py exactly)
 * ================================================================ */

static void init_input(volatile uint8_t *img)
{
    for (uint16_t r = 0; r < INPUT_H; r++)
        for (uint16_t c = 0; c < INPUT_W; c++)
            img[r * INPUT_W + c] = (uint8_t)((r * 17u + c * 13u + 5u) & 0x1Fu);
}

static void init_conv1_weights(volatile uint8_t *W)
{
    /* 4 filters: cross, box, top-edge, diagonal */
    static const uint8_t p0[9] = {0,1,0, 1,2,1, 0,1,0};
    static const uint8_t p1[9] = {1,1,1, 1,0,1, 1,1,1};
    static const uint8_t p2[9] = {1,2,1, 0,0,0, 0,0,0};
    static const uint8_t p3[9] = {0,0,1, 0,1,0, 1,0,0};

    for (uint16_t k = 0; k < 9; k++) {
        W[k * CONV1_COUT + 0] = p0[k];
        W[k * CONV1_COUT + 1] = p1[k];
        W[k * CONV1_COUT + 2] = p2[k];
        W[k * CONV1_COUT + 3] = p3[k];
    }
}

static void init_conv2_weights(volatile uint8_t *W)
{
    for (uint16_t k = 0; k < IM2COL2_COLS; k++)
        for (uint16_t f = 0; f < CONV2_COUT; f++)
            W[k * CONV2_COUT + f] = (uint8_t)((k * 3u + f * 7u + 1u) & 0x07u);
}

static void init_fc_weights(volatile uint8_t *W)
{
    for (uint16_t i = 0; i < FC_IN; i++)
        for (uint16_t j = 0; j < FC_OUT; j++)
            W[i * FC_OUT + j] = (uint8_t)((i * (j + 3u) + j * j * 7u + 2u) & 0x0Fu);
}

/* ================================================================
 * Argmax
 * ================================================================ */
static uint8_t argmax(volatile uint8_t *data, uint16_t len)
{
    uint8_t best_idx = 0;
    uint8_t best_val = data[0];
    for (uint16_t i = 1; i < len; i++) {
        if (data[i] > best_val) {
            best_val = data[i];
            best_idx = (uint8_t)i;
        }
    }
    return best_idx;
}

/* ================================================================
 * Main inference pipeline
 * ================================================================ */
int main(void)
{
    volatile uint8_t *input     = (volatile uint8_t *)ADDR_INPUT;
    volatile uint8_t *conv1_w   = (volatile uint8_t *)ADDR_CONV1_W;
    volatile uint8_t *im2col1   = (volatile uint8_t *)ADDR_IM2COL1;
    volatile uint8_t *conv1_out = (volatile uint8_t *)ADDR_CONV1_OUT;
    volatile uint8_t *conv2_w   = (volatile uint8_t *)ADDR_CONV2_W;
    volatile uint8_t *im2col2   = (volatile uint8_t *)ADDR_IM2COL2;
    volatile uint8_t *conv2_out = (volatile uint8_t *)ADDR_CONV2_OUT;
    volatile uint8_t *fc_w      = (volatile uint8_t *)ADDR_FC_W;
    volatile uint8_t *fc_out    = (volatile uint8_t *)ADDR_FC_OUT;

    uint32_t chk;

    /* ---- Initialize all weights and input ---- */
    init_input(input);
    init_conv1_weights(conv1_w);
    init_conv2_weights(conv2_w);
    init_fc_weights(fc_w);

    /* ============================================================
     * LAYER 1: Conv2D  (8x8x1) -> (6x6x4)
     *
     * im2col:  36 x 9 (padded to stride 12)
     * GEMM:    36 x 9 * 9 x 4 = 36 x 4
     *
     * DMA strides: stride_a=12(padded), stride_b=4, stride_c=4
     * ============================================================ */
    debug_putw(MARKER_CONV1);

    clear_region(im2col1, IM2COL1_ROWS * IM2COL1_STRIDE);
    im2col(input, im2col1,
           INPUT_W, INPUT_C,
           CONV1_KH, CONV1_KW,
           CONV1_STR, CONV1_HOUT, CONV1_WOUT,
           IM2COL1_STRIDE);

    clear_region(conv1_out, IM2COL1_ROWS * CONV1_COUT);
    clear_region((volatile uint8_t *)ADDR_TMP32, IM2COL1_ROWS * GEMM_STRIDE_ACC32(CONV1_COUT));

    gemm_run_int8_acc32(
        IM2COL1_ROWS, IM2COL1_COLS, CONV1_COUT,
        ADDR_IM2COL1, ADDR_CONV1_W, ADDR_TMP32,
        IM2COL1_STRIDE,                        /* stride_a = 12 (word-aligned) */
        CONV1_COUT,                            /* stride_b = 4 */
        GEMM_STRIDE_ACC32(CONV1_COUT)          /* stride_c = 16 (4 elements * 4 bytes) */
    );

    requantize_acc32((volatile uint32_t *)ADDR_TMP32, CONV1_COUT,
                      conv1_out, CONV1_COUT,
                      IM2COL1_ROWS, CONV1_COUT,
                      CONV1_REQUANT_MULT, CONV1_REQUANT_SHIFT);

    relu_inplace(conv1_out, IM2COL1_ROWS, CONV1_COUT, CONV1_COUT);

    chk = compute_checksum(conv1_out, IM2COL1_ROWS, CONV1_COUT, CONV1_COUT);
    debug_putw(chk);

    if (chk != GOLDEN_CONV1_CHECKSUM || conv1_out[0] != GOLDEN_CONV1_C00) {
        debug_putw(MARKER_FAIL);
        debug_putw(MARKER_DONE);
        return 1;
    }
    debug_putw(MARKER_PASS);

    /* ============================================================
     * LAYER 2: Conv2D  (6x6x4) -> (4x4x8)
     *
     * The Conv1 output is in (H*W) x C format with stride=C_OUT=4.
     * im2col gathers 3x3x4=36 values per output position.
     *
     * im2col:  16 x 36 (stride 36, already word-aligned)
     * GEMM:    16 x 36 * 36 x 8 = 16 x 8
     *
     * DMA strides: stride_a=36, stride_b=8, stride_c=8
     * ============================================================ */
    debug_putw(MARKER_CONV2);

    clear_region(im2col2, IM2COL2_ROWS * IM2COL2_STRIDE);
    im2col(conv1_out, im2col2,
           CONV1_WOUT, CONV1_COUT,
           CONV2_KH, CONV2_KW,
           CONV2_STR, CONV2_HOUT, CONV2_WOUT,
           IM2COL2_STRIDE);

    clear_region(conv2_out, IM2COL2_ROWS * CONV2_COUT);
    clear_region((volatile uint8_t *)ADDR_TMP32, IM2COL2_ROWS * GEMM_STRIDE_ACC32(CONV2_COUT));

    gemm_run_int8_acc32(
        IM2COL2_ROWS, IM2COL2_COLS, CONV2_COUT,
        ADDR_IM2COL2, ADDR_CONV2_W, ADDR_TMP32,
        IM2COL2_STRIDE,                        /* stride_a = 36 (word-aligned) */
        CONV2_COUT,                            /* stride_b = 8 */
        GEMM_STRIDE_ACC32(CONV2_COUT)          /* stride_c = 32 (8 elements * 4 bytes) */
    );

    requantize_acc32((volatile uint32_t *)ADDR_TMP32, CONV2_COUT,
                      conv2_out, CONV2_COUT,
                      IM2COL2_ROWS, CONV2_COUT,
                      CONV2_REQUANT_MULT, CONV2_REQUANT_SHIFT);

    relu_inplace(conv2_out, IM2COL2_ROWS, CONV2_COUT, CONV2_COUT);

    chk = compute_checksum(conv2_out, IM2COL2_ROWS, CONV2_COUT, CONV2_COUT);
    debug_putw(chk);

    if (chk != GOLDEN_CONV2_CHECKSUM || conv2_out[0] != GOLDEN_CONV2_C00) {
        debug_putw(MARKER_FAIL);
        debug_putw(MARKER_DONE);
        return 1;
    }
    debug_putw(MARKER_PASS);

    /* ============================================================
     * LAYER 3: Fully Connected  (128) -> (4)
     *
     * The Conv2 output (16 x 8, stride=8) is treated as a flat
     * 1 x 128 vector.  Since stride=8 and there are 16 rows,
     * the 128 bytes are contiguous in memory.
     *
     * GEMM:    1 x 128 * 128 x 4 = 1 x 4
     *
     * DMA strides: stride_a=128, stride_b=4, stride_c=4
     * ============================================================ */
    debug_putw(MARKER_FC);

    clear_region(fc_out, FC_OUT);
    clear_region((volatile uint8_t *)ADDR_TMP32, GEMM_STRIDE_ACC32(FC_OUT));

    gemm_run_int8_acc32(
        1, FC_IN, FC_OUT,
        ADDR_CONV2_OUT, ADDR_FC_W, ADDR_TMP32,
        (uint16_t)PAD4(FC_IN),                 /* stride_a = 128 (word-aligned) */
        FC_OUT,                                 /* stride_b = 4 */
        GEMM_STRIDE_ACC32(FC_OUT)              /* stride_c = 16 (4 elements * 4 bytes) */
    );

    requantize_acc32((volatile uint32_t *)ADDR_TMP32, FC_OUT,
                      fc_out, FC_OUT,
                      1, FC_OUT,
                      FC_REQUANT_MULT, FC_REQUANT_SHIFT);

    chk = compute_checksum(fc_out, 1, FC_OUT, FC_OUT);
    debug_putw(chk);

    if (chk != GOLDEN_FC_CHECKSUM) {
        debug_putw(MARKER_FAIL);
        debug_putw(MARKER_DONE);
        return 1;
    }
    debug_putw(MARKER_PASS);

    /* ============================================================
     * CLASSIFICATION: Argmax
     * ============================================================ */
    debug_putw(MARKER_CLASS);

    uint8_t predicted = argmax(fc_out, FC_OUT);
    debug_putw((uint32_t)predicted);

    /* Report per-class scores for visibility */
    debug_putw((uint32_t)fc_out[0]);
    debug_putw((uint32_t)fc_out[1]);
    debug_putw((uint32_t)fc_out[2]);
    debug_putw((uint32_t)fc_out[3]);

    if (predicted == GOLDEN_FC_CLASS)
        debug_putw(MARKER_PASS);
    else
        debug_putw(MARKER_FAIL);

    debug_putw(MARKER_DONE);
    return 0;
}
