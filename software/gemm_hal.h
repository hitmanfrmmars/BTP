/**
 * GEMM Accelerator Hardware Abstraction Layer
 *
 * Register-level driver for the RISC-V GEMM accelerator.
 * Provides configuration, control, and status polling functions.
 */

#ifndef GEMM_HAL_H
#define GEMM_HAL_H

#include <stdint.h>

/* Base address of the accelerator in the memory map (platform-specific) */
#ifndef GEMM_BASE_ADDR
#define GEMM_BASE_ADDR  0x40000000UL
#endif

/* Register offsets */
#define GEMM_REG_CTRL       0x00
#define GEMM_REG_STATUS     0x04
#define GEMM_REG_DIM_MK     0x08
#define GEMM_REG_DIM_N      0x0C
#define GEMM_REG_SRC_A      0x10
#define GEMM_REG_SRC_B      0x14
#define GEMM_REG_DST_C      0x18
#define GEMM_REG_STRIDE_A   0x1C
#define GEMM_REG_STRIDE_B   0x20
#define GEMM_REG_STRIDE_C   0x24
#define GEMM_REG_CYCLES     0x28

/* CTRL register bits */
#define GEMM_CTRL_START     (1U << 0)
#define GEMM_CTRL_MODE_INT16 (1U << 1)
#define GEMM_CTRL_IRQ_EN   (1U << 2)

/* STATUS register bits */
#define GEMM_STATUS_BUSY    (1U << 0)
#define GEMM_STATUS_DONE    (1U << 1)
#define GEMM_STATUS_ERROR   (1U << 2)
#define GEMM_STATUS_OVF     (1U << 3)

/* Precision modes */
typedef enum {
    GEMM_MODE_INT8  = 0,
    GEMM_MODE_INT16 = 1
} gemm_mode_t;

/* Configuration structure */
typedef struct {
    uint16_t    m;              /* M dimension */
    uint16_t    k;              /* K dimension */
    uint16_t    n;              /* N dimension */
    uint32_t    src_a;          /* Source address for matrix A */
    uint32_t    src_b;          /* Source address for matrix B */
    uint32_t    dst_c;          /* Destination address for matrix C */
    uint16_t    stride_a;       /* Row stride for A (bytes) */
    uint16_t    stride_b;       /* Row stride for B (bytes) */
    uint16_t    stride_c;       /* Row stride for C (bytes) */
    gemm_mode_t mode;           /* Precision mode */
    int         irq_enable;     /* Enable completion interrupt */
} gemm_config_t;

/* ---- Low-level register access ---- */

static inline void gemm_write_reg(uint32_t offset, uint32_t value) {
    *(volatile uint32_t *)(GEMM_BASE_ADDR + offset) = value;
}

static inline uint32_t gemm_read_reg(uint32_t offset) {
    return *(volatile uint32_t *)(GEMM_BASE_ADDR + offset);
}

/* ---- High-level API ---- */

/**
 * Configure the GEMM accelerator with the given parameters.
 * Does NOT start computation.
 */
void gemm_configure(const gemm_config_t *cfg);

/**
 * Start the GEMM computation. Call gemm_configure() first.
 */
void gemm_start(void);

/**
 * Blocking wait until accelerator completes.
 * Returns the number of cycles elapsed.
 */
uint32_t gemm_wait(void);

/**
 * Non-blocking status check.
 * Returns 1 if accelerator is done, 0 if still busy.
 */
int gemm_is_done(void);

/**
 * Read the current status register.
 */
uint32_t gemm_status(void);

/**
 * Read the cycle counter.
 */
uint32_t gemm_cycles(void);

/**
 * Convenience function: configure, start, and wait.
 * Returns cycle count.
 */
uint32_t gemm_run(const gemm_config_t *cfg);

/**
 * Install an interrupt handler for accelerator completion.
 * Platform-specific; weak default does nothing.
 */
void gemm_install_irq_handler(void (*handler)(void));

#endif /* GEMM_HAL_H */
