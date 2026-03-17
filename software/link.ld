/*
 * Linker script for PicoRV32 GEMM SoC
 *
 * Memory map:
 *   0x0000_0000 - 0x0001_FFFF  128KB unified memory (code + data)
 *   0x1000_0000               Debug output port (write-only)
 *   0x4000_0000 - 0x4000_003F  GEMM accelerator MMIO registers
 *
 * Stack grows down from 0x0002_0000.
 * Matrices and working data should be placed in the upper portion
 * of memory (e.g., 0x0001_0000+) to avoid overlapping with firmware.
 */

MEMORY
{
    MEM (rwx) : ORIGIN = 0x00000000, LENGTH = 128K
}

ENTRY(_start)

SECTIONS
{
    /* Reset + IRQ vectors -- must be at address 0 */
    .vectors 0x00000000 : {
        KEEP(*(.vectors))
    } > MEM

    /* Code */
    .text : {
        *(.text .text.*)
    } > MEM

    /* Read-only data */
    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
    } > MEM

    /* Initialized data */
    .data : ALIGN(4) {
        _data_start = .;
        *(.data .data.*)
        _data_end = .;
    } > MEM

    /* Uninitialized data (cleared by crt0) */
    .bss : ALIGN(4) {
        _bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        _bss_end = .;
    } > MEM

    _end = .;

    /* Firmware must not exceed 64KB to leave room for matrix data */
    ASSERT(. <= 0x00010000, "Firmware too large -- overlaps matrix data area")

    /* Stack top (used by crt0.S) */
    _stack_top = 0x00020000;
}
