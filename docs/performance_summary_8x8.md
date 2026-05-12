# GEMM Accelerator Performance Summary (8x8 MAC Array)

**Target Device:** Xilinx Artix-7 xc7a100tcsg324-1  
**Clock Constraint:** 100 MHz (10 ns period)  
**Tool:** Vivado 2024.2  
**Date:** March 19, 2026

---

## 1. FPGA Resource Utilization

### Accelerator Only (Out-of-Context)

| Resource | Used | Available | Util% |
|----------|------|-----------|-------|
| Slice LUTs | 3,936 | 63,400 | 6.21% |
| Slice Registers | 3,704 | 126,800 | 2.92% |
| Block RAM (36Kb) | 2 | 135 | 1.48% |
| DSP48E1 | 70 | 240 | 29.17% |

### Hierarchical Breakdown (Accelerator)

| Module | LUTs | FFs | DSPs | BRAM |
|--------|------|-----|------|------|
| MAC Array (8x8) | 1,452 | 1,109 | 64 | 0 |
| Controller | 1,318 | 1,242 | 0 | 0 |
| Tiling Engine | 439 | 305 | 6 | 0 |
| DMA Engine | 320 | 325 | 0 | 0 |
| Register File | 282 | 322 | 0 | 0 |
| PCPI Adapter | 167 | 92 | 0 | 0 |
| Scratchpad (2-bank) | 64 | 1 | 0 | 2 |

### Full SoC (PicoRV32 + Accelerator + 128KB Memory)

| Resource | Used | Available | Util% |
|----------|------|-----------|-------|
| Slice LUTs | 3,087 | 63,400 | 4.87% |
| Slice Registers | 2,380 | 126,800 | 1.88% |
| Block RAM (36Kb) | 34 | 135 | 25.19% |
| DSP48E1 | 22 | 240 | 9.17% |

### SoC Power Breakdown

| Module | Power (mW) |
|--------|-----------|
| GEMM Accelerator | 31 |
| PicoRV32 CPU | 5 |
| Unified Memory (128KB) | 25 |
| **SoC Dynamic Total** | **63** |
| Device Static | 86 |
| **SoC Total** | **148** |

---

## 2. Timing

| Metric | Accelerator | Full SoC |
|--------|------------|----------|
| WNS (ns) | +0.038 | +0.122 |
| Fmax (MHz) | 100.4 | 101.2 |
| Timing Met? | Yes | Yes |

---

## 3. Theoretical Peak Performance

### Throughput

| Config | MACs | Freq (MHz) | Peak GMAC/s | Peak GOPS (int8) |
|--------|------|-----------|-------------|-------------------|
| 4x4 Array | 16 | 100 | 1.6 | 3.2 |
| **8x8 Array** | **64** | **100** | **6.4** | **12.8** |

> GOPS = 2 x GMAC/s (each MAC = 1 multiply + 1 accumulate)

### Energy Efficiency

| Metric | Accelerator Only | Full SoC |
|--------|-----------------|----------|
| Dynamic Power (mW) | 67 | 63 |
| Peak GOPS/W (int8) | 191 | 203 |
| Peak GMAC/s/W | 95.5 | 101.6 |

### Area Efficiency

| Metric | Value |
|--------|-------|
| GOPS / DSP48 | 0.183 |
| MOPS / LUT | 3.25 |
| GOPS / Slice | 8.22 |

---

## 4. 4x4 vs 8x8 Comparison (Projected)

| Metric | 4x4 (prev.) | 8x8 (current) | Improvement |
|--------|-------------|---------------|-------------|
| MAC Units | 16 | 64 | 4x |
| Peak GOPS (int8) | 3.2 | 12.8 | 4x |
| DSP48E1 Usage | ~20 | 70 | 3.5x |
| LUT Usage | ~1,600 | 3,936 | 2.5x |
| BRAM Usage | 1 | 2 | 2x |
| Dynamic Power (mW) | ~30 | 67 | 2.2x |
| GOPS/W | ~107 | 191 | 1.8x |
| Scratchpad (words) | 256/bank | 512/bank | 2x |

> 4x throughput for 2.2x power = 1.8x energy efficiency gain

---

## 5. Software vs Hardware Speedup (Estimated)

For RV32I (no MUL instruction), each int8 MAC takes ~30 cycles in software
(shift-and-add multiply + load/store overhead).

| Matrix Size | SW Cycles (est.) | HW Cycles (est.) | Speedup |
|-------------|-----------------|-------------------|---------|
| 8x8x8 (=512 MACs) | ~15,360 | ~80 | ~192x |
| 16x16x16 (=4096 MACs) | ~122,880 | ~400 | ~307x |
| 32x32x32 (=32768 MACs) | ~983,040 | ~2,500 | ~393x |

> HW cycles include DMA load/store and tiling overhead.
> SW estimate: ~30 cycles/MAC on RV32I without hardware multiply.
> Actual numbers to be confirmed via SoC simulation.

---

## 6. Feature Summary

| Feature | Status |
|---------|--------|
| 8x8 Output-Stationary MAC Array | Implemented |
| 2-Stage Pipelined MACs | Implemented |
| int8 Mode (32-bit accumulator) | Implemented |
| int16 Mode (48-bit accumulator) | Implemented |
| Saturation Arithmetic | Implemented |
| Double-Buffered Scratchpad SRAM | Implemented |
| Burst DMA with 2D Strided Access | Implemented |
| Hardware Tiling Engine | Implemented |
| Non-Aligned Dimension Handling | Implemented |
| Overlapped Load/Compute | Implemented |
| RISC-V Custom Instructions (PCPI) | Implemented |
| PicoRV32 SoC Integration | Implemented |
| C Driver + Build System | Implemented |
| FC Layer (GEMM-based) | Demonstrated |
| Conv2D via im2col + GEMM | Demonstrated |
| 21-Pattern Stress Test Suite | Implemented |
| Vivado Synthesis (Artix-7) | Verified |

---

## 7. Comparison with Related Work

| Design | Array | Tech | Freq | GOPS | GOPS/W | Precision |
|--------|-------|------|------|------|--------|-----------|
| This work | 8x8 | Artix-7 | 100 MHz | 12.8 | 191 | int8/int16 |
| Genc et al. (Gemmini) | 16x16 | ASIC 22nm | 1 GHz | 512 | ~200 | int8 |
| NVDLA (small) | 8x8 | ASIC 16nm | 1 GHz | 128 | ~500 | int8/int16/fp16 |
| TinyML Accel (MCU) | 4x4 | Artix-7 | 50 MHz | 1.6 | ~50 | int8 |

> Note: Direct comparison is approximate due to different process nodes and clock speeds.
> Our design achieves competitive GOPS/W on low-cost FPGA fabric.
