# Energy-Efficient RISC-V Matrix Multiplication Accelerator

## Project Overview

A RISC-V-based GEMM (General Matrix Multiply) accelerator optimized for edge AI inference. Features a pipelined 4x4 int8/int16 MAC array with output-stationary dataflow, double-buffered scratchpad SRAM, burst DMA engine with 2D strided access, hardware tiling engine for large matrices, and a RISC-V custom instruction interface.

## Architecture

```
RISC-V Core ──► Custom Insn Decoder ──► Register File (MMIO)
                                              │
                                        Tiling Engine
                                         ┌────┴────┐
                                    Burst DMA    Matmul Controller v2
                                         │              │
                                  ┌──────┴──────┐       │
                                Bank 0       Bank 1     │
                              (Double-Buffered SRAM)    │
                                         └──────┬──────┘
                                         MAC Array v2 (4x4)
                                        16x Pipelined MACs
                                         int8 / int16
```

## Key Features

| Feature | Description |
|---------|-------------|
| MAC Array | 4x4 output-stationary with broadcast dataflow, 2-stage pipeline |
| Precision | Configurable int8 (32-bit acc) and int16 (48-bit acc) |
| Scratchpad | Double-buffered ping-pong banks (2x 2KB), dual-port |
| DMA | Burst mode (~1 word/cycle), 2D strided, bidirectional |
| Tiling | Hardware tiling engine for matrices larger than 4x4 |
| RISC-V | Custom-0 instructions (GEMM.CFG, GEMM.START, GEMM.WAIT) |
| Software | C HAL driver, GEMM kernel library, TFLite Micro delegate |
| FPGA | Xilinx Artix-7 targeting 100 MHz |

## Project Structure

```
project_sim/
├── rtl/                            # RTL Implementation
│   ├── multiplier_8bit.v          # Standalone 8x8 multiplier (legacy)
│   ├── mac_unit.v                 # Original MAC unit (legacy)
│   ├── mac_unit_v2.v             # Pipelined MAC, int8/int16, saturation
│   ├── mac_array.v                # Original 4x4 array (legacy)
│   ├── mac_array_v2.v            # Output-stationary broadcast array
│   ├── scratchpad_mem.v           # Dual-port SRAM (1KB/bank)
│   ├── scratchpad_double_buf.v    # Ping-pong double buffer wrapper
│   ├── dma_controller.v           # Original sequential DMA (legacy)
│   ├── dma_engine.v              # Burst DMA, 2D strided, bidirectional
│   ├── matmul_controller.v        # Original 72-cycle controller (legacy)
│   ├── matmul_controller_v2.v    # Streaming controller (~16 cycles)
│   ├── tiling_engine.v           # Hardware tiling for large matrices
│   ├── gemm_regfile.v            # Memory-mapped register file
│   ├── gemm_custom_insn.v        # RISC-V custom instruction decoder
│   ├── gemm_accelerator_top.v    # Full system integration
│   └── top.v                      # Legacy top module
│
├── testbench/                      # Verification
│   ├── tb_scratchpad_mem.v        # Scratchpad dual-port tests
│   ├── tb_mac_unit_v2.v          # Pipelined MAC, int8/int16 tests
│   ├── tb_mac_array_v2.v         # Broadcast dataflow, GEMM tests
│   ├── tb_dma_engine.v           # Burst, 2D stride, store tests
│   ├── tb_matmul_controller_v2.v # Streaming controller + scratchpad
│   ├── tb_tiling_engine.v        # 4x4, 8x8, non-aligned tiling
│   ├── tb_gemm_accelerator.v     # Full system end-to-end via MMIO
│   └── (legacy testbenches)       # tb_multiplier_8bit.v, etc.
│
├── verification/                   # Golden model + test vectors
│   ├── golden_model.py            # NumPy reference, generates .hex files
│   └── test*_*.hex                # Generated test vectors
│
├── software/                       # C software stack
│   ├── gemm_hal.h / .c           # Hardware abstraction layer
│   ├── gemm_kernel.h / .c        # Tiled GEMM kernel library
│   └── tflite_delegate.h / .c    # TFLite Micro integration
│
├── fpga/                           # FPGA implementation
│   ├── constraints.xdc            # Xilinx Artix-7 pin/timing constraints
│   ├── synth.tcl                  # Vivado synthesis + P&R script
│   ├── program.tcl                # FPGA programming script
│   └── benchmark.tcl              # Performance analysis script
│
├── docs/                           # Documentation
├── run_all_v2_tests.bat           # Run all v2 tests (Windows)
├── run_all_v2_tests.sh            # Run all v2 tests (Linux/Mac)
└── (legacy run scripts)
```

## Quick Start

### Run All Tests (Icarus Verilog)

```bash
# Windows
run_all_v2_tests.bat

# Linux/Mac
chmod +x run_all_v2_tests.sh
./run_all_v2_tests.sh
```

### Run Individual Tests

```bash
# Scratchpad memory
iverilog -o sim.vvp rtl/scratchpad_mem.v testbench/tb_scratchpad_mem.v && vvp sim.vvp

# MAC unit v2 (pipelined, int8/int16)
iverilog -o sim.vvp rtl/mac_unit_v2.v testbench/tb_mac_unit_v2.v && vvp sim.vvp

# MAC array v2 (broadcast dataflow)
iverilog -o sim.vvp rtl/mac_unit_v2.v rtl/mac_array_v2.v testbench/tb_mac_array_v2.v && vvp sim.vvp

# Full system
iverilog -o sim.vvp rtl/scratchpad_mem.v rtl/scratchpad_double_buf.v rtl/mac_unit_v2.v rtl/mac_array_v2.v rtl/dma_engine.v rtl/matmul_controller_v2.v rtl/tiling_engine.v rtl/gemm_regfile.v rtl/gemm_custom_insn.v rtl/gemm_accelerator_top.v testbench/tb_gemm_accelerator.v && vvp sim.vvp
```

### Generate Test Vectors

```bash
cd verification
python golden_model.py
```

### FPGA Synthesis (Vivado)

```bash
cd fpga
vivado -mode batch -source synth.tcl
```

## Performance

| Metric | v1 (Original) | v2 (Optimized) | Improvement |
|--------|---------------|----------------|-------------|
| 4x4 GEMM cycles | 72 | ~16 | 4.5x |
| Compute utilization | 5.6% | ~25% | 4.5x |
| DMA bandwidth | 1 word/3 cyc | 1 word/cyc | 3x |
| Precision | int8 only | int8 + int16 | -- |
| Large matrix support | No | Yes (HW tiling) | -- |
| Double buffering | No | Yes (ping-pong) | ~2x for tiled |

## Register Map

| Offset | Register | Description |
|--------|----------|-------------|
| 0x00 | CTRL | [0] start, [1] mode, [2] irq_en |
| 0x04 | STATUS | [0] busy, [1] done, [2] error, [3] overflow |
| 0x08 | DIM_MK | [31:16] M, [15:0] K |
| 0x0C | DIM_N | [15:0] N |
| 0x10 | SRC_A | Matrix A base address |
| 0x14 | SRC_B | Matrix B base address |
| 0x18 | DST_C | Matrix C base address |
| 0x1C | STRIDE_A | Row stride for A (bytes) |
| 0x20 | STRIDE_B | Row stride for B (bytes) |
| 0x24 | STRIDE_C | Row stride for C (bytes) |
| 0x28 | CYCLES | Cycle counter (read-only) |
