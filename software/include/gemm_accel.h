#ifndef GEMM_ACCEL_H
#define GEMM_ACCEL_H

#include <stdint.h>

/*
 * GEMM Accelerator Driver for PicoRV32 SoC
 *
 * Provides inline-asm intrinsics for the four GEMM custom instructions
 * and a high-level API that hides register programming.
 *
 * Custom instruction encoding (R-type, custom-0 opcode 0x0B):
 *   funct7=0x08  funct3=000  GEMM.CFG    rd, rs1, rs2
 *   funct7=0x08  funct3=001  GEMM.START  rd
 *   funct7=0x08  funct3=010  GEMM.WAIT   rd
 *   funct7=0x08  funct3=011  GEMM.STATUS rd
 */

/* ================================================================
 * Register offsets (byte addresses within MMIO / PCPI rs2 values)
 * ================================================================ */
#define GEMM_REG_CTRL       0x00   /* [0]=start, [1]=mode(0=int8,1=int16), [2]=irq_en */
#define GEMM_REG_STATUS     0x04   /* [0]=busy, [1]=done, [2]=error, [3]=overflow */
#define GEMM_REG_DIM_MK     0x08   /* [31:16]=M, [15:0]=K */
#define GEMM_REG_DIM_N      0x0C   /* [15:0]=N */
#define GEMM_REG_SRC_A      0x10   /* byte address of matrix A in memory */
#define GEMM_REG_SRC_B      0x14   /* byte address of matrix B in memory */
#define GEMM_REG_DST_C      0x18   /* byte address of result matrix C in memory */
#define GEMM_REG_STRIDE_A   0x1C   /* byte stride between rows of A */
#define GEMM_REG_STRIDE_B   0x20   /* byte stride between rows of B */
#define GEMM_REG_STRIDE_C   0x24   /* byte stride between rows of C */
#define GEMM_REG_CYCLES     0x28   /* cycle counter (read-only) */

/* Status bits */
#define GEMM_STATUS_BUSY     (1u << 0)
#define GEMM_STATUS_DONE     (1u << 1)
#define GEMM_STATUS_ERROR    (1u << 2)
#define GEMM_STATUS_OVERFLOW (1u << 3)

/* Mode flags for CTRL register */
#define GEMM_MODE_INT8       0
#define GEMM_MODE_INT16      (1u << 1)
#define GEMM_IRQ_ENABLE      (1u << 2)

/* Debug output address */
#define DEBUG_ADDR  ((volatile uint32_t *)0x10000000)

/* ================================================================
 * Low-level intrinsics (inline assembly)
 * ================================================================ */

/* GEMM.CFG: write `value` to accelerator register at `offset`.
 * Returns the register's previous value. */
static inline uint32_t gemm_cfg(uint32_t value, uint32_t offset)
{
    uint32_t old;
    __asm__ volatile (".insn r 0x0B, 0, 8, %0, %1, %2"
                      : "=r"(old) : "r"(value), "r"(offset));
    return old;
}

/* GEMM.START: trigger computation. Returns status word. */
static inline uint32_t gemm_start(void)
{
    uint32_t status;
    __asm__ volatile (".insn r 0x0B, 1, 8, %0, zero, zero"
                      : "=r"(status));
    return status;
}

/* GEMM.WAIT: stall the CPU until the accelerator finishes.
 * Returns the cycle count of the completed operation. */
static inline uint32_t gemm_wait(void)
{
    uint32_t cycles;
    __asm__ volatile (".insn r 0x0B, 2, 8, %0, zero, zero"
                      : "=r"(cycles));
    return cycles;
}

/* GEMM.STATUS: read accelerator status without side-effects. */
static inline uint32_t gemm_status(void)
{
    uint32_t st;
    __asm__ volatile (".insn r 0x0B, 3, 8, %0, zero, zero"
                      : "=r"(st));
    return st;
}

/* ================================================================
 * Byte-packing helpers (int8 matrices are stored 4 per 32-bit word)
 * ================================================================ */

static inline uint32_t pack4_u8(uint8_t a, uint8_t b, uint8_t c, uint8_t d)
{
    return (uint32_t)a | ((uint32_t)b << 8) |
           ((uint32_t)c << 16) | ((uint32_t)d << 24);
}

static inline uint8_t unpack_u8(uint32_t word, int idx)
{
    return (uint8_t)(word >> (idx * 8));
}

static inline uint32_t pack2_i16(int16_t a, int16_t b)
{
    return ((uint32_t)(uint16_t)a) | ((uint32_t)(uint16_t)b << 16);
}

static inline int16_t unpack_i16(uint32_t word, int idx)
{
    return (int16_t)(word >> (idx * 16));
}

/* ================================================================
 * High-level driver API
 * ================================================================ */

typedef struct {
    uint32_t status;
    uint32_t cycles;
} gemm_result_t;

/*
 * gemm_run_int8 -- Run an MxK * KxN int8 GEMM.
 *
 * A, B, C are byte addresses in SoC memory.
 * stride_a/b = bytes between consecutive rows (typically K or N).
 * stride_c   = bytes between consecutive output rows (typically N,
 *              since output is packed int8).
 *
 * Blocks until the operation completes.
 */
gemm_result_t gemm_run_int8(uint16_t M, uint16_t K, uint16_t N,
                             uint32_t src_a, uint32_t src_b, uint32_t dst_c,
                             uint16_t stride_a, uint16_t stride_b,
                             uint16_t stride_c);

/*
 * gemm_run_int16 -- Run an MxK * KxN int16 GEMM.
 *
 * Same interface as int8, but input elements are 16-bit.
 * stride_a/b = bytes between rows (typically K*2 or N*2).
 * stride_c   = bytes between output rows (typically N*2).
 */
gemm_result_t gemm_run_int16(uint16_t M, uint16_t K, uint16_t N,
                              uint32_t src_a, uint32_t src_b, uint32_t dst_c,
                              uint16_t stride_a, uint16_t stride_b,
                              uint16_t stride_c);

/* Write a value to the debug output port (visible in testbench). */
static inline void debug_putw(uint32_t val)
{
    *DEBUG_ADDR = val;
}

#endif /* GEMM_ACCEL_H */
