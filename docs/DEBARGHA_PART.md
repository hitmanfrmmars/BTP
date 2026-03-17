# Debargha's Part: SoC Integration, FPGA Synthesis & Verification (Modules 7-9)

## Overview

You handled the **system-level integration** -- connecting the GEMM accelerator to a real RISC-V CPU, creating the complete System-on-Chip, running FPGA synthesis with Vivado to get real hardware metrics, and building the verification infrastructure that proves the entire system works correctly.

---

## Module 7: RISC-V CPU Integration & SoC Design

### 7a: PicoRV32 CPU (`rtl/riscv/picorv32.v`)

**What to say:**
- "We need a CPU to control the accelerator -- to set up matrix addresses, dimensions, and strides, tell the accelerator to start, and read back results. We chose **PicoRV32**, an open-source RISC-V CPU designed specifically for FPGAs."
- "PicoRV32 implements the **RV32I** instruction set -- the base 32-bit RISC-V. It's intentionally minimal (about 900 LUTs) and designed for low area, which is perfect for an edge device where the CPU is just the controller, not the main compute unit."
- "It has a feature called **PCPI** (Pico Co-Processor Interface) that lets us add custom instructions. When the CPU encounters an instruction it doesn't recognize, it forwards it to PCPI. That's how our accelerator receives commands."
- "It also has a built-in `rdcycle` instruction (via the `ENABLE_COUNTERS` parameter) that lets firmware measure clock cycles for benchmarking."

### 7b: PCPI Adapter (`rtl/gemm_pcpi_adapter.v`)

**What to say:**
- "The PCPI adapter is the **bridge** between the CPU and our accelerator. When the CPU executes one of our custom GEMM instructions, the adapter intercepts it and translates it into register reads/writes on the accelerator."
- "We defined **four custom instructions**, all encoded as R-type instructions with opcode `0x0B` (custom-0) and funct7 `0x08`:

  | Instruction | funct3 | What it does |
  |-------------|--------|-------------|
  | `GEMM.CFG` | 000 | Write a value to an accelerator register (like dimensions, addresses). Returns the old value. |
  | `GEMM.START` | 001 | Write start bit to the CTRL register, triggering computation. Returns status. |
  | `GEMM.WAIT` | 010 | **Stall the CPU** until the accelerator finishes. Returns the cycle count. |
  | `GEMM.STATUS` | 011 | Read the status register (busy/done/error/overflow) without side effects. |"

- "The adapter has a 4-state FSM: `S_IDLE → S_RESPOND` (for instant instructions) or `S_IDLE → S_WAITING → S_WDONE` (for GEMM.WAIT, which stalls the CPU pipeline)."
- "There's a `responded` flag to prevent re-triggering: after the adapter responds, PicoRV32 takes one cycle to deassert `pcpi_valid`. The flag blocks any re-decode during that gap."

### 7c: Register File (`rtl/gemm_regfile.v`)

**What to say:**
- "The register file holds **11 memory-mapped configuration registers** that the CPU programs before starting a GEMM operation:

  | Offset | Name | Purpose |
  |--------|------|---------|
  | 0x00 | CTRL | Start bit, mode (int8/int16), interrupt enable |
  | 0x04 | STATUS | Busy, done, error, overflow flags (read-only) |
  | 0x08 | DIM_MK | M dimension (upper 16 bits), K dimension (lower 16 bits) |
  | 0x0C | DIM_N | N dimension |
  | 0x10 | SRC_A | Memory address of matrix A |
  | 0x14 | SRC_B | Memory address of matrix B |
  | 0x18 | DST_C | Memory address of result matrix C |
  | 0x1C | STRIDE_A | Byte distance between rows of A |
  | 0x20 | STRIDE_B | Byte distance between rows of B |
  | 0x24 | STRIDE_C | Byte distance between rows of C |
  | 0x28 | CYCLES | Cycle counter (read-only, auto-cleared on start) |"

- "The start bit is **self-clearing** -- it generates a single-cycle pulse and then auto-resets to 0."
- "The cycle counter increments every clock cycle while `accel_busy` is high, giving an exact measure of how long the operation took."
- "The done flag is **latched** -- it stays set until the next start pulse, so software can poll it at any time."

### 7d: Full SoC Top-Level (`rtl/gemm_soc_top.v`)

**What to say:**
- "The SoC top-level wires everything together into a complete system: **PicoRV32 CPU + GEMM accelerator + 128KB unified memory**."
- "The memory is **dual-ported**: Port A is for the CPU (fetches instructions and reads/writes data), Port B is for the DMA engine (loads/stores matrix tiles). Since they use separate ports, they **never conflict** -- no bus arbitration needed."
- "There's an **address decoder** that routes CPU memory transactions based on the address:
  - `0x00000000 - 0x0001FFFF` → 128KB memory (firmware + matrix data)
  - `0x40000000 - 0x4000003F` → GEMM accelerator registers (MMIO)
  - `0x10000000` → Debug output port (testbench captures writes here)"
- "When the chip powers on, the CPU starts executing firmware from address `0x00000000`. The firmware initializes matrices, configures the accelerator registers, and triggers the computation."
- "For synthesis, there's a separate version (`gemm_soc_synth_top.v`) that uses a Vivado-friendly BRAM module (`dpram_bytewrite.v`) instead of the simulation memory model, because Vivado has strict requirements for inferring Block RAM correctly."

---

## Module 8: FPGA Synthesis & Implementation

### What to say

- "We synthesized the design using **Xilinx Vivado 2024.2**, targeting an **Artix-7 xc7a100t** FPGA. This is a real, commonly-used FPGA in edge computing research."
- "We ran the **full implementation flow**: synthesis → optimization → placement → routing. This gives us actual physical metrics from real EDA tools, not just estimates."
- "We synthesized **two separate targets** for comparison:
  1. **Accelerator only** (just the GEMM co-processor) -- to show its standalone cost
  2. **Full SoC** (CPU + accelerator + 128KB memory) -- to show the complete system cost"
- "We used **out-of-context synthesis** (`synth_design -mode out_of_context`) because we don't have a physical board with pin assignments. This gives accurate internal logic metrics without requiring I/O placement."

### Results -- Accelerator Only

| Resource | Count | % of Artix-7 |
|----------|-------|---------------|
| LUTs | 1,921 | 3.03% |
| Flip-Flops | 2,065 | 1.63% |
| Block RAMs | 2 | 1.48% |
| DSP Blocks | 22 | 9.17% |
| Dynamic Power | 43 mW | -- |

### Results -- Full SoC

| Resource | Count | % of Artix-7 |
|----------|-------|---------------|
| LUTs | 2,822 | 4.45% |
| Flip-Flops | 2,703 | 2.14% |
| Block RAMs | 34 | 25.19% |
| DSP Blocks | 22 | 9.17% |
| Dynamic Power | 64 mW | -- |
| Total Power | 149 mW | -- |

### What the numbers mean

- "The entire SoC uses less than **5% of the FPGA's logic**. It could easily be a small IP block inside a much larger system."
- "The CPU adds about 900 LUTs -- the accelerator is 2x the size of the CPU. Most of the accelerator area is the MAC array (503 LUTs) and tiling engine (404 LUTs)."
- "**34 Block RAMs** in the SoC: 32 are for the 128KB main memory, 2 are for the scratchpad. The BRAMs are the biggest resource consumer."
- "**149 mW total power** -- but 86 mW of that is static FPGA leakage (inherent to the chip). Our actual design only consumes 64 mW of dynamic power."
- "The design meets timing at **100 MHz** with positive slack of 0.179 ns, meaning there's room to push the clock higher."

### Key files

- `fpga/synth_accel.tcl` / `fpga/synth_soc.tcl` -- TCL synthesis scripts
- `fpga/constraints.xdc` -- timing constraint (100 MHz clock)
- `rtl/gemm_synth_wrapper.v` -- synthesis wrappers with registered I/O
- `rtl/gemm_soc_synth_top.v` -- synthesis-friendly SoC top-level
- `rtl/dpram_bytewrite.v` -- Vivado-compatible dual-port BRAM with byte-write enables
- `fpga/reports/` -- all utilization, timing, and power reports

---

## Module 9: Verification & Testing

### What to say

- "We have **24 testbenches** covering every level of the design -- from individual MAC units up to the full SoC running firmware."

**Unit tests (individual modules):**
- MAC unit: int8 mode, int16 mode, accumulation, overflow detection, saturation
- MAC array: full 4x4 broadcast, output-stationary verification
- DMA engine: burst transfers, 2D strided access, load and store directions
- Scratchpad: dual-port operation, simultaneous read/write, bank swapping
- Matmul controller: int8/int16 streaming, partial tiles, multi-K passes
- Tiling engine: tile iteration order, bank swapping, non-aligned dimensions

**Integration tests:**
- Full accelerator pipeline: data flows memory → DMA → scratchpad → controller → MAC array → scratchpad → DMA → memory
- Multi-tile matrices (8x8, 16x16), non-aligned matrices (7x5, 10x6)
- Overflow cases, interrupt handling, edge cases

**SoC-level tests:**
- `tb_gemm_soc.v`: boots the PicoRV32 CPU from firmware hex file, runs 4x4 GEMM through custom instructions, verifies every byte
- `tb_benchmark.v`: runs the benchmark firmware, parses debug output, reports SW vs HW cycle counts and speedup

**Python golden model** (`verification/golden_model.py`):
- Generates random test matrices of any size
- Computes expected results in Python
- Writes test vectors and expected outputs for testbenches
- Automates verification -- can generate hundreds of test cases

### Benchmark Results

| Matrix Size | Software Cycles | Hardware Cycles | Speedup |
|-------------|----------------|-----------------|---------|
| 4x4 | 15,367 | 99 | **155x** |
| 8x8 | 113,699 | 465 | **245x** |
| 16x16 | 894,291 | 3,105 | **288x** |

- "The speedup increases with matrix size because larger matrices amortize the DMA and control overhead better."
- "Software is especially slow because PicoRV32 is RV32I (no hardware multiply). Every `a * b` in C becomes a ~30-instruction software multiply routine. The accelerator does it in dedicated DSP hardware in one cycle."
- "All benchmarks produce **byte-identical results** -- hardware and software compute exactly the same output, proving correctness."

---

## How to Explain Your Part in the Presentation

"I handled the system integration and validation. I connected the GEMM accelerator to a PicoRV32 RISC-V CPU using four custom instructions (CFG, START, WAIT, STATUS), creating a complete System-on-Chip with a shared 128KB dual-port memory. I ran FPGA synthesis on a Xilinx Artix-7 using Vivado to get real area, timing, and power numbers -- the full SoC fits in under 5% of the FPGA at 149 milliwatts. And I built 24 testbenches plus a Python golden model that verify correctness from individual MAC units up to the full SoC running C firmware. The benchmarks show up to 288x speedup over pure software."
