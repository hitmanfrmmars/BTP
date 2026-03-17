/**
 * GEMM Accelerator HAL Implementation
 */

#include "gemm_hal.h"

void gemm_configure(const gemm_config_t *cfg) {
    /* Dimensions: M in upper 16 bits, K in lower 16 bits */
    gemm_write_reg(GEMM_REG_DIM_MK, ((uint32_t)cfg->m << 16) | cfg->k);
    gemm_write_reg(GEMM_REG_DIM_N,  (uint32_t)cfg->n);

    /* Source and destination addresses */
    gemm_write_reg(GEMM_REG_SRC_A, cfg->src_a);
    gemm_write_reg(GEMM_REG_SRC_B, cfg->src_b);
    gemm_write_reg(GEMM_REG_DST_C, cfg->dst_c);

    /* Row strides */
    gemm_write_reg(GEMM_REG_STRIDE_A, (uint32_t)cfg->stride_a);
    gemm_write_reg(GEMM_REG_STRIDE_B, (uint32_t)cfg->stride_b);
    gemm_write_reg(GEMM_REG_STRIDE_C, (uint32_t)cfg->stride_c);
}

void gemm_start(void) {
    uint32_t ctrl = GEMM_CTRL_START;
    uint32_t current = gemm_read_reg(GEMM_REG_CTRL);

    /* Preserve mode and IRQ enable bits, set start */
    ctrl |= (current & (GEMM_CTRL_MODE_INT16 | GEMM_CTRL_IRQ_EN));
    gemm_write_reg(GEMM_REG_CTRL, ctrl);
}

uint32_t gemm_wait(void) {
    while (!(gemm_read_reg(GEMM_REG_STATUS) & GEMM_STATUS_DONE)) {
        /* Spin -- in a real system, could use WFI here */
    }
    return gemm_read_reg(GEMM_REG_CYCLES);
}

int gemm_is_done(void) {
    return (gemm_read_reg(GEMM_REG_STATUS) & GEMM_STATUS_DONE) ? 1 : 0;
}

uint32_t gemm_status(void) {
    return gemm_read_reg(GEMM_REG_STATUS);
}

uint32_t gemm_cycles(void) {
    return gemm_read_reg(GEMM_REG_CYCLES);
}

uint32_t gemm_run(const gemm_config_t *cfg) {
    gemm_configure(cfg);

    /* Set mode in CTRL before starting */
    uint32_t ctrl = 0;
    if (cfg->mode == GEMM_MODE_INT16)
        ctrl |= GEMM_CTRL_MODE_INT16;
    if (cfg->irq_enable)
        ctrl |= GEMM_CTRL_IRQ_EN;
    gemm_write_reg(GEMM_REG_CTRL, ctrl);

    gemm_start();
    return gemm_wait();
}

/* Weak default -- platform must override */
__attribute__((weak))
void gemm_install_irq_handler(void (*handler)(void)) {
    (void)handler;
}
