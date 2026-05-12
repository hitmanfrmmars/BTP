/*
 * Neural Network Layer Demo for PicoRV32 GEMM SoC
 *
 * Demonstrates Fully-Connected (FC) and Conv2D layers using the
 * GEMM accelerator, comparing HW results against SW reference.
 *
 * Debug protocol:
 *   0xBBBB0001  -> FC layer test start
 *   0xBBBB0002  -> Conv2D layer test start
 *   HW cycle count
 *   SW cycle count
 *   0x600D      -> PASS
 *   0xFA11      -> FAIL
 *   0xDEAD      -> all done
 */

#include "gemm_accel.h"
#include <stdint.h>

/* Memory layout: keep matrices in upper 64KB (0x10000-0x1FFFF) */
#define ADDR_WEIGHTS  0x00010000u
#define ADDR_INPUT    0x00012000u
#define ADDR_BIAS     0x00013000u
#define ADDR_IM2COL   0x00013800u
#define ADDR_OUT_HW   0x00015000u
#define ADDR_OUT_SW   0x00016000u

#define MARKER_FC     0xBBBB0001u
#define MARKER_CONV   0xBBBB0002u
#define MARKER_PASS   0x0000600Du
#define MARKER_FAIL   0x0000FA11u
#define MARKER_DONE   0x0000DEADu

static inline uint32_t rdcycle(void)
{
    uint32_t c;
    __asm__ volatile ("rdcycle %0" : "=r"(c));
    return c;
}

/* ================================================================
 * Software reference GEMM (int8, truncated to uint8)
 * ================================================================ */
static void sw_gemm_int8(uint16_t M, uint16_t K, uint16_t N,
                          volatile uint8_t *A, volatile uint8_t *B,
                          volatile uint8_t *C,
                          uint16_t sa, uint16_t sb, uint16_t sc)
{
    for (uint16_t i = 0; i < M; i++) {
        for (uint16_t j = 0; j < N; j++) {
            uint32_t acc = 0;
            for (uint16_t k = 0; k < K; k++)
                acc += (uint32_t)A[i * sa + k] * (uint32_t)B[k * sb + j];
            C[i * sc + j] = (uint8_t)(acc & 0xFF);
        }
    }
}

static void clear_region(volatile uint8_t *p, uint32_t bytes)
{
    for (uint32_t i = 0; i < bytes; i++) p[i] = 0;
}

static uint32_t verify(volatile uint8_t *a, volatile uint8_t *b,
                       uint16_t M, uint16_t N, uint16_t sa, uint16_t sb)
{
    uint32_t err = 0;
    for (uint16_t i = 0; i < M; i++)
        for (uint16_t j = 0; j < N; j++)
            if (a[i * sa + j] != b[i * sb + j]) err++;
    return err;
}

/* ================================================================
 * Fully-Connected Layer
 *
 * y[1 x N_out] = x[1 x N_in] * W[N_in x N_out] + b[N_out]
 *
 * We express the FC as a GEMM: C = A * B where
 *   A = x  (1 x N_in)
 *   B = W  (N_in x N_out)
 *   C = y  (1 x N_out), then add bias elementwise
 *
 * Using small sizes to keep simulation time reasonable:
 *   N_in = 16, N_out = 8
 * ================================================================ */
#define FC_N_IN   16
#define FC_N_OUT   8

static void test_fc_layer(void)
{
    volatile uint8_t *weights = (volatile uint8_t *)ADDR_WEIGHTS;
    volatile uint8_t *input   = (volatile uint8_t *)ADDR_INPUT;
    volatile uint8_t *bias    = (volatile uint8_t *)ADDR_BIAS;
    volatile uint8_t *out_hw  = (volatile uint8_t *)ADDR_OUT_HW;
    volatile uint8_t *out_sw  = (volatile uint8_t *)ADDR_OUT_SW;

    debug_putw(MARKER_FC);

    /* Initialize weights: W[i][j] = ((i*5 + j*3 + 1) & 0x0F) */
    for (uint16_t i = 0; i < FC_N_IN; i++)
        for (uint16_t j = 0; j < FC_N_OUT; j++)
            weights[i * FC_N_OUT + j] = (uint8_t)((i * 5 + j * 3 + 1) & 0x0F);

    /* Initialize input: x[j] = ((j * 7 + 3) & 0x0F) */
    for (uint16_t j = 0; j < FC_N_IN; j++)
        input[j] = (uint8_t)((j * 7 + 3) & 0x0F);

    /* Bias: b[j] = j & 0x03 */
    for (uint16_t j = 0; j < FC_N_OUT; j++)
        bias[j] = (uint8_t)(j & 0x03);

    clear_region(out_hw, FC_N_OUT);
    clear_region(out_sw, FC_N_OUT);

    /* --- Software FC --- */
    uint32_t t0 = rdcycle();
    sw_gemm_int8(1, FC_N_IN, FC_N_OUT,
                 input, weights, out_sw,
                 FC_N_IN, FC_N_OUT, FC_N_OUT);
    for (uint16_t j = 0; j < FC_N_OUT; j++)
        out_sw[j] = (uint8_t)((out_sw[j] + bias[j]) & 0xFF);
    uint32_t t1 = rdcycle();
    uint32_t sw_cycles = t1 - t0;

    /* --- Hardware FC --- */
    uint32_t th0 = rdcycle();
    gemm_result_t res = gemm_run_int8(
        1, FC_N_IN, FC_N_OUT,
        ADDR_INPUT, ADDR_WEIGHTS, ADDR_OUT_HW,
        FC_N_IN, FC_N_OUT, FC_N_OUT
    );
    (void)res;
    for (uint16_t j = 0; j < FC_N_OUT; j++)
        out_hw[j] = (uint8_t)((out_hw[j] + bias[j]) & 0xFF);
    uint32_t th1 = rdcycle();
    uint32_t hw_cycles = th1 - th0;

    debug_putw(hw_cycles);
    debug_putw(sw_cycles);

    if (verify(out_sw, out_hw, 1, FC_N_OUT, FC_N_OUT, FC_N_OUT) == 0)
        debug_putw(MARKER_PASS);
    else
        debug_putw(MARKER_FAIL);
}

/* ================================================================
 * Conv2D Layer via im2col
 *
 * Input:  H_in x W_in x C_in  (e.g., 6x6x1)
 * Kernel: K_h x K_w x C_in x C_out  (e.g., 3x3x1x2)
 * Output: H_out x W_out x C_out (e.g., 4x4x2)
 *
 * im2col transforms each output position's receptive field into a
 * row of a matrix. The reshaped input has dimensions:
 *   A_im2col[H_out*W_out, K_h*K_w*C_in]  (16 x 9)
 *   B_kernel[K_h*K_w*C_in, C_out]         (9 x 2)
 *   C_output[H_out*W_out, C_out]          (16 x 2)
 *
 * Then C = A_im2col * B_kernel gives the convolution output.
 * ================================================================ */
#define CONV_H_IN    6
#define CONV_W_IN    6
#define CONV_C_IN    1
#define CONV_K_H     3
#define CONV_K_W     3
#define CONV_C_OUT   4
#define CONV_STRIDE  1
#define CONV_H_OUT   ((CONV_H_IN - CONV_K_H) / CONV_STRIDE + 1)  /* 4 */
#define CONV_W_OUT   ((CONV_W_IN - CONV_K_W) / CONV_STRIDE + 1)  /* 4 */
#define IM2COL_ROWS  (CONV_H_OUT * CONV_W_OUT)                    /* 16 */
#define IM2COL_COLS  (CONV_K_H * CONV_K_W * CONV_C_IN)            /* 9 */
#define IM2COL_STRIDE ((IM2COL_COLS + 3) & ~3)                    /* 12 -- word-aligned for DMA */

static void im2col(volatile uint8_t *input, volatile uint8_t *col_buf,
                   uint16_t w_in,
                   uint16_t kh, uint16_t kw, uint16_t c_in,
                   uint16_t stride, uint16_t h_out, uint16_t w_out,
                   uint16_t out_stride)
{
    for (uint16_t oh = 0; oh < h_out; oh++) {
        for (uint16_t ow = 0; ow < w_out; ow++) {
            uint16_t row = oh * w_out + ow;
            uint16_t col = 0;
            for (uint16_t fh = 0; fh < kh; fh++) {
                for (uint16_t fw = 0; fw < kw; fw++) {
                    for (uint16_t fc = 0; fc < c_in; fc++) {
                        uint16_t ih = oh * stride + fh;
                        uint16_t iw = ow * stride + fw;
                        col_buf[row * out_stride + col] =
                            input[(ih * w_in + iw) * c_in + fc];
                        col++;
                    }
                }
            }
        }
    }
}

static void test_conv2d_layer(void)
{
    volatile uint8_t *input    = (volatile uint8_t *)ADDR_INPUT;
    volatile uint8_t *kernel   = (volatile uint8_t *)ADDR_WEIGHTS;
    volatile uint8_t *col_buf  = (volatile uint8_t *)ADDR_IM2COL;
    volatile uint8_t *out_hw   = (volatile uint8_t *)ADDR_OUT_HW;
    volatile uint8_t *out_sw   = (volatile uint8_t *)ADDR_OUT_SW;

    debug_putw(MARKER_CONV);

    /* Initialize input image (6x6x1): pixel = (r + c) & 0x0F */
    for (uint16_t r = 0; r < CONV_H_IN; r++)
        for (uint16_t c = 0; c < CONV_W_IN; c++)
            input[r * CONV_W_IN * CONV_C_IN + c] = (uint8_t)((r + c) & 0x0F);

    /* Initialize kernel (3x3x1x2): two 3x3 filters */
    /* 4 filters: cross, box, horizontal edge, vertical edge */
    /* Laid out as kernel[k_idx * C_OUT + c_out] */
    static const uint8_t filters[9 * 4] = {
        0,1,0,1,  1,1,1,0,  0,1,0,0,
        1,1,0,1,  2,1,0,0,  1,1,0,1,
        0,1,0,1,  1,1,1,0,  0,1,0,0
    };

    for (uint16_t i = 0; i < IM2COL_COLS * CONV_C_OUT; i++)
        kernel[i] = filters[i];

    /* im2col: transform input patches to matrix rows (word-aligned stride) */
    clear_region(col_buf, IM2COL_ROWS * IM2COL_STRIDE);
    im2col(input, col_buf,
           CONV_W_IN,
           CONV_K_H, CONV_K_W, CONV_C_IN,
           CONV_STRIDE, CONV_H_OUT, CONV_W_OUT,
           IM2COL_STRIDE);

    clear_region(out_hw, IM2COL_ROWS * CONV_C_OUT);
    clear_region(out_sw, IM2COL_ROWS * CONV_C_OUT);

    /* --- Software Conv2D via GEMM --- */
    uint32_t t0 = rdcycle();
    sw_gemm_int8(IM2COL_ROWS, IM2COL_COLS, CONV_C_OUT,
                 col_buf, kernel, out_sw,
                 IM2COL_STRIDE, CONV_C_OUT, CONV_C_OUT);
    uint32_t t1 = rdcycle();
    uint32_t sw_cycles = t1 - t0;

    /* --- Hardware Conv2D via GEMM --- */
    uint32_t th0 = rdcycle();
    gemm_result_t res = gemm_run_int8(
        IM2COL_ROWS, IM2COL_COLS, CONV_C_OUT,
        ADDR_IM2COL, ADDR_WEIGHTS, ADDR_OUT_HW,
        IM2COL_STRIDE, CONV_C_OUT, CONV_C_OUT
    );
    (void)res;
    uint32_t th1 = rdcycle();
    uint32_t hw_cycles = th1 - th0;

    debug_putw(hw_cycles);
    debug_putw(sw_cycles);

    if (verify(out_sw, out_hw, IM2COL_ROWS, CONV_C_OUT,
               CONV_C_OUT, CONV_C_OUT) == 0)
        debug_putw(MARKER_PASS);
    else
        debug_putw(MARKER_FAIL);
}

/* ================================================================
 * Main
 * ================================================================ */
int main(void)
{
    test_fc_layer();
    test_conv2d_layer();

    debug_putw(MARKER_DONE);
    return 0;
}
