# Arihant's Part: Software Stack

## Overview

You built the **entire software layer** that makes the hardware usable -- from the very first assembly instruction the CPU executes at boot, to the C driver library that lets a programmer run a matrix multiply with one function call, to the benchmark firmware that measures real performance. Without the software stack, the hardware is just a collection of wires and gates that can't do anything useful.

---

## Component 1: Startup Code (`software/src/crt0.S`)

**What it is:** The very first code that runs when the chip powers on. Written in RISC-V assembly.

### What to say

- "When the chip starts, the CPU begins executing from memory address `0x00000000`. But you can't jump straight into C code -- the machine isn't ready yet. `crt0.S` sets up the environment."
- "It does three critical things:
  1. **Sets up the stack pointer** -- C functions need a stack to store local variables and return addresses. We point the stack at the top of our 128KB memory (address `0x20000`) and it grows downward.
  2. **Clears the BSS section** -- in C, any global variable you don't explicitly initialize is guaranteed to be zero. The BSS section is where these live. crt0 loops through it and writes zeros.
  3. **Calls `main()`** -- once the environment is ready, it jumps to the C main function."
- "There's also a minimal **interrupt handler** at address `0x10`. PicoRV32 requires one even if we don't use interrupts. Ours just immediately returns using a `retirq` instruction."
- "If `main()` ever returns, the code enters an infinite loop (`j .L_halt`) so the CPU doesn't execute random memory."
- "This file is only about 30 lines of assembly, but without it, nothing else can run."

---

## Component 2: Linker Script (`software/link.ld`)

**What it is:** A configuration file that tells the compiler exactly where to place every piece of the program in the 128KB memory.

### What to say

- "Our SoC has 128KB of memory starting at address `0x00000000`. This single memory holds everything: program code, constant data, global variables, the stack, and the matrix data. The linker script divides this space."
- "The memory layout is:

  | Address Range | Content |
  |---------------|---------|
  | `0x00000000` | Reset vector + IRQ handler (must be exactly here -- hardcoded in CPU) |
  | After vectors | Program code (`.text` section) |
  | After code | Read-only data (`.rodata` -- constants, lookup tables) |
  | After rodata | Initialized globals (`.data`) |
  | After data | Uninitialized globals (`.bss` -- cleared to zero by crt0) |
  | `0x00010000`+ | Matrix data area (where A, B, C matrices are stored at runtime) |
  | `0x0001FFFC` | Stack top (grows downward) |"

- "There's a **safety check**: `ASSERT(. <= 0x00010000)` -- if the firmware code exceeds 64KB, the linker throws an error so it doesn't accidentally overlap with the matrix data area."
- "The `ENTRY(_start)` directive tells the linker that execution begins at the `_start` label in `crt0.S`."

---

## Component 3: Accelerator Driver (`software/include/gemm_accel.h` + `software/src/gemm_accel.c`)

**What it is:** The C library that lets programmers talk to the GEMM hardware. This is the most important part of the software stack.

### The Header File (`gemm_accel.h`)

**What to say:**
- "This file defines all the low-level building blocks for talking to the accelerator."
- "**Register offset constants** -- every hardware register has a name and byte address:
  - `GEMM_REG_CTRL` (0x00) -- start bit, mode selection
  - `GEMM_REG_DIM_MK` (0x08) -- M and K dimensions packed into one 32-bit word
  - `GEMM_REG_SRC_A` (0x10) -- memory address where matrix A is stored
  - ... and so on for all 11 registers"
- "**Four inline assembly intrinsics** -- these are C functions that emit custom RISC-V instructions:
  - `gemm_cfg(value, offset)` -- writes a value to an accelerator register. Under the hood, this generates the machine instruction `.insn r 0x0B, 0, 8, rd, rs1, rs2` which the CPU sends to the PCPI adapter.
  - `gemm_start()` -- triggers the accelerator to begin computation. Returns a status word.
  - `gemm_wait()` -- **stalls the entire CPU pipeline** until the accelerator finishes, then returns the cycle count. The CPU literally freezes and does nothing. This is the simplest possible synchronization -- no polling loops, no interrupts.
  - `gemm_status()` -- reads the accelerator's status without side effects (non-blocking)."
- "**Byte-packing helpers** -- since int8 matrices store 4 elements per 32-bit word:
  - `pack4_u8(1, 3, 2, 0)` creates the word `0x00020301`
  - `unpack_u8(word, 2)` extracts the third byte
  - Similar functions for int16: `pack2_i16()` and `unpack_i16()`"
- "**`rdcycle()`** -- reads the CPU's hardware cycle counter for precise performance measurement."

### The Driver Implementation (`gemm_accel.c`)

**What to say:**
- "This wraps the low-level intrinsics into two easy-to-use functions that hide all the register programming."
- "**`gemm_run_int8(M, K, N, src_a, src_b, dst_c, stride_a, stride_b, stride_c)`**:
  1. Programs dimensions: `gemm_cfg((M << 16) | K, GEMM_REG_DIM_MK)` and `gemm_cfg(N, GEMM_REG_DIM_N)`
  2. Programs addresses: `gemm_cfg(src_a, GEMM_REG_SRC_A)`, same for B and C
  3. Programs strides: `gemm_cfg(stride_a, GEMM_REG_STRIDE_A)`, same for B and C
  4. Triggers computation: `gemm_start()`
  5. Blocks until done: `gemm_wait()` -- returns cycle count
  6. Returns a `gemm_result_t` struct with status and cycle count"
- "**`gemm_run_int16(...)`** -- same thing but sets the mode bit to int16 before starting."
- "From the programmer's point of view, doing a full matrix multiply is one line:
  ```c
  gemm_result_t res = gemm_run_int8(16, 16, 16, addr_A, addr_B, addr_C, 16, 16, 16);
  ```
  That's it. The hardware handles tiling, DMA, double-buffering, everything."

---

## Component 4: Demo Firmware (`software/src/main.c`)

**What it is:** A simple test program that demonstrates the accelerator working end-to-end.

### What to say

- "This is a complete working program that proves the entire hardware/software stack works."
- "It does:
  1. Writes two known 4x4 test matrices (A and B) into memory using `pack4_u8()`
  2. Calls `gemm_run_int8(4, 4, 4, ...)` to multiply them using the hardware accelerator
  3. Reads back the result matrix C from memory
  4. Compares every single byte against the pre-computed expected answer
  5. Writes PASS (`0x600D`) or FAIL (`0xFA11`) and cycle count to the debug port"
- "The test matrices are chosen to have small values (0-2) so results are easy to verify:
  ```
  A = [[1,2,0,0], [0,1,2,0], [0,0,1,2], [1,0,0,1]]
  B = [[1,1,0,0], [0,1,1,0], [0,0,1,1], [1,0,0,1]]
  Expected C = [[1,3,2,0], [0,1,3,2], [2,0,1,3], [2,1,0,1]]
  ```"
- "When you run this on the SoC testbench, you see: firmware boots → configures the accelerator → accelerator runs in ~99 cycles → result verified → PASS."

---

## Component 5: Benchmark Firmware (`software/src/benchmark.c`)

**What it is:** A performance testing program that compares software-only GEMM vs. hardware-accelerated GEMM.

### What to say

- "This firmware runs the same matrix multiplication **twice** -- once in pure software (a triple-nested C loop on the CPU) and once through the hardware accelerator -- then measures cycle counts for both."
- "It tests three sizes: **4x4, 8x8, and 16x16**."
- "The **software GEMM** is a straightforward implementation:
  ```
  for each row m:
    for each column n:
      for each element k:
        C[m][n] += A[m][k] * B[k][n]
  ```
  This is the baseline that any programmer would write."
- "For each size, it:
  1. Initializes A and B with a deterministic pattern: `(row * 3 + col * 7 + 1) & 0x0F`
  2. Runs software GEMM, measures cycles with `rdcycle()`
  3. Runs hardware GEMM via `gemm_run_int8()`, gets cycle count from the accelerator
  4. **Verifies both produce byte-identical results** -- proving the hardware is correct, not just fast
  5. Reports results through the debug port"
- "The results are dramatic:

  | Size | Software | Hardware | Speedup |
  |------|----------|----------|---------|
  | 4x4 | 15,367 cycles | 99 cycles | **155x** |
  | 8x8 | 113,699 | 465 | **245x** |
  | 16x16 | 894,291 | 3,105 | **288x** |"

- "The speedup **increases with matrix size** because larger matrices amortize DMA and control overhead."
- "Software is especially slow because PicoRV32 is **RV32I -- no hardware multiply instruction**. Every `a * b` in the C loop becomes a ~30-instruction software multiply routine called `__mulsi3` from `libgcc`. The accelerator does the same multiply in one cycle using dedicated DSP hardware."

---

## Component 6: Build System (`software/Makefile` + `software/bin2hex.py`)

**What it is:** The toolchain setup that converts C source code into a hex file the FPGA simulation can load.

### What to say

- "The build pipeline is: **C source → compile → link → flat binary → hex file**."
- "We use the **xPack RISC-V GCC toolchain** -- a standard C compiler that targets RISC-V processors."
- "Key compiler flags:
  - `-march=rv32i` -- target the base RISC-V integer instruction set (no multiply, no floating point)
  - `-mabi=ilp32` -- 32-bit integers and pointers
  - `-Os` -- optimize for small code size (important when firmware must fit in 64KB)
  - `-ffreestanding` -- tells the compiler there's no operating system
  - `-nostdlib` -- don't link the standard C library (we have no OS to provide it)"
- "The **linker** combines `crt0.o + gemm_accel.o + main.o` using our `link.ld` script, producing `firmware.elf`."
- "**`objcopy`** strips the ELF metadata (debug symbols, section headers) to produce a flat binary (`firmware.bin`) -- just raw machine code bytes."
- "**`bin2hex.py`** converts the binary to a text file with one 32-bit hex word per line (`firmware.hex`). This is the format Verilog's `$readmemh` function uses to initialize the FPGA's memory at simulation start."
- "The output `firmware.hex` is 32,768 lines (one per word of the 128KB memory). The first ~300 lines are actual program code; the rest are zeros."
- "**`make sim`** copies the hex file to the testbench directory so the SoC simulation picks it up automatically."

### Build commands

```
make           # Builds firmware.hex
make sim       # Copies hex to testbench directory
make disasm    # Shows human-readable disassembly
make size      # Shows section sizes (text, data, bss)
make clean     # Removes build artifacts
```

---

## How to Explain Your Part in the Presentation

"I built the complete software stack that turns the raw hardware into a programmable system. Starting from the boot-level RISC-V assembly (`crt0.S`) that initializes the CPU environment, through a linker script that maps the 128KB memory, to a C driver library with custom RISC-V instruction intrinsics. The driver abstracts the entire accelerator into a single function call -- `gemm_run_int8()` -- that configures all registers, triggers computation, waits for completion, and returns the cycle count. I also wrote the benchmark firmware that proved the hardware accelerator is up to 288 times faster than a pure software implementation running on the same CPU, with byte-identical results. The build system uses the xPack RISC-V GCC toolchain to compile C into a hex file that the FPGA simulation loads directly."
