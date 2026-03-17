#include "gemm_accel.h"

static gemm_result_t gemm_run_common(uint16_t M, uint16_t K, uint16_t N,
                                      uint32_t src_a, uint32_t src_b,
                                      uint32_t dst_c,
                                      uint16_t stride_a, uint16_t stride_b,
                                      uint16_t stride_c,
                                      uint32_t mode_bits)
{
    gemm_result_t res;

    /* Dimensions: DIM_MK = (M << 16) | K */
    gemm_cfg(((uint32_t)M << 16) | K, GEMM_REG_DIM_MK);
    gemm_cfg((uint32_t)N,              GEMM_REG_DIM_N);

    /* Source / destination addresses */
    gemm_cfg(src_a, GEMM_REG_SRC_A);
    gemm_cfg(src_b, GEMM_REG_SRC_B);
    gemm_cfg(dst_c, GEMM_REG_DST_C);

    /* Row strides (bytes) */
    gemm_cfg((uint32_t)stride_a, GEMM_REG_STRIDE_A);
    gemm_cfg((uint32_t)stride_b, GEMM_REG_STRIDE_B);
    gemm_cfg((uint32_t)stride_c, GEMM_REG_STRIDE_C);

    /* Start (writes CTRL register with mode + start bit internally via GEMM.START) */
    /* If int16 mode is needed, pre-write the mode bit before starting. */
    if (mode_bits)
        gemm_cfg(mode_bits, GEMM_REG_CTRL);

    res.status = gemm_start();
    res.cycles = gemm_wait();

    return res;
}

gemm_result_t gemm_run_int8(uint16_t M, uint16_t K, uint16_t N,
                             uint32_t src_a, uint32_t src_b, uint32_t dst_c,
                             uint16_t stride_a, uint16_t stride_b,
                             uint16_t stride_c)
{
    return gemm_run_common(M, K, N, src_a, src_b, dst_c,
                           stride_a, stride_b, stride_c, 0);
}

gemm_result_t gemm_run_int16(uint16_t M, uint16_t K, uint16_t N,
                              uint32_t src_a, uint32_t src_b, uint32_t dst_c,
                              uint16_t stride_a, uint16_t stride_b,
                              uint16_t stride_c)
{
    return gemm_run_common(M, K, N, src_a, src_b, dst_c,
                           stride_a, stride_b, stride_c, GEMM_MODE_INT16);
}
