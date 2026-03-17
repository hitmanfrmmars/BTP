/*
 * crt0.S -- Startup code for PicoRV32 GEMM SoC
 *
 * Memory layout:
 *   0x00000000  Reset vector (this file)
 *   0x00000010  IRQ handler  (PicoRV32 PROGADDR_IRQ)
 *   0x00000020+ Application code
 *   0x0001FFFC  Stack top (grows downward)
 *
 * PicoRV32 initializes SP via STACKADDR parameter, but we set it
 * explicitly here for portability.
 */

    .section .vectors, "ax"
    .global _start

/* ---- 0x0000: Reset vector ---- */
_start:
    j       _crt0_main          /* jump past IRQ handler */
    nop
    nop
    nop

/* ---- 0x0010: IRQ handler ---- */
    .org 0x10
    .global _irq_handler
_irq_handler:
    /* Minimal handler: acknowledge and return immediately.
     * PicoRV32 saves return PC to x3 (gp) with ENABLE_IRQ_QREGS=0.
     * retirq restores PC from x3 and unmasks interrupts.
     * Encoding: funct7=0, rs2=2, rs1=0, funct3=0, rd=0, opcode=0x0B */
    .word 0x0020000B            /* picorv32_retirq_insn */
    nop
    nop
    nop

/* ---- 0x0020: Startup code ---- */
    .section .text
    .global _crt0_main
_crt0_main:
    /* Initialize stack pointer */
    lui     sp, %hi(0x00020000)
    addi    sp, sp, %lo(0x00020000)

    /* Clear .bss section */
    la      t0, _bss_start
    la      t1, _bss_end
.L_bss_loop:
    bge     t0, t1, .L_bss_done
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       .L_bss_loop
.L_bss_done:

    /* Call main() */
    call    main

    /* If main() returns, spin forever */
.L_halt:
    j       .L_halt
