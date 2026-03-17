/**
 * TensorFlow Lite Micro Custom Delegate for GEMM Accelerator
 *
 * Routes FullyConnected and Conv2D (via im2col) GEMM operations
 * to the hardware accelerator when beneficial.
 */

#ifndef TFLITE_DELEGATE_H
#define TFLITE_DELEGATE_H

#include <stdint.h>

/* Kernel types supported by the accelerator */
typedef enum {
    GEMM_KERNEL_FULLY_CONNECTED,
    GEMM_KERNEL_CONV2D_IM2COL,
    GEMM_KERNEL_DEPTHWISE_CONV,
    GEMM_KERNEL_SOFTWARE_FALLBACK
} gemm_kernel_type_t;

/**
 * Determine which kernel to use for a given GEMM operation.
 * Returns SOFTWARE_FALLBACK if HW accelerator is not beneficial.
 */
gemm_kernel_type_t gemm_select_kernel(int m, int k, int n);

/**
 * Execute a FullyConnected layer using the accelerator.
 *
 * @param input     Quantized int8 input  [batch x input_dim]
 * @param weights   Quantized int8 weights [output_dim x input_dim]
 * @param bias      int32 bias vector [output_dim], or NULL
 * @param output    Quantized int8 output [batch x output_dim]
 * @param batch     Batch size
 * @param input_dim Input feature dimension
 * @param output_dim Output feature dimension
 * @param scale     Output requantization scale (Q16.16)
 * @param zero_pt   Output zero point
 */
void gemm_fully_connected(const uint8_t *input, const uint8_t *weights,
                          const int32_t *bias, uint8_t *output,
                          int batch, int input_dim, int output_dim,
                          int32_t scale, uint8_t zero_pt);

/**
 * Execute a Conv2D layer by converting to GEMM (im2col approach).
 *
 * @param input     Input feature map [1 x H x W x C_in]  (NHWC)
 * @param kernel    Convolution kernel [C_out x kH x kW x C_in]
 * @param bias      int32 bias [C_out], or NULL
 * @param output    Output feature map [1 x H_out x W_out x C_out]
 * @param h, w      Input spatial dimensions
 * @param c_in      Input channels
 * @param c_out     Output channels
 * @param kh, kw    Kernel spatial dimensions
 * @param stride    Convolution stride
 * @param padding   0=valid, 1=same
 * @param scale     Output requantization scale
 * @param zero_pt   Output zero point
 */
void gemm_conv2d_im2col(const uint8_t *input, const uint8_t *kernel,
                        const int32_t *bias, uint8_t *output,
                        int h, int w, int c_in, int c_out,
                        int kh, int kw, int stride, int padding,
                        int32_t scale, uint8_t zero_pt);

/**
 * Register the GEMM accelerator delegate with TFLite Micro.
 * After calling this, supported ops will be routed to HW.
 */
void gemm_delegate_init(void);

#endif /* TFLITE_DELEGATE_H */
