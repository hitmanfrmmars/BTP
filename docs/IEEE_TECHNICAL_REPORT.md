# Design and Implementation of a Matrix Multiplication Accelerator for RISC-V Architecture

**IEEE Standard Technical Report**

**Version:** 1.0  
**Date:** 2024  
**Author:** Hardware Design Team  
**Project:** RISC-V Matrix Multiplication Accelerator

---

## Abstract

This document presents the complete design, implementation, and verification of a hardware accelerator for matrix multiplication operations, designed as a simplified version of a RISC-V accelerator architecture. The system implements a 4×4 MAC (Multiply-Accumulate) array with 8-bit data precision, featuring a dual-port scratchpad memory, DMA controller, and dedicated matrix multiplication controller. The accelerator achieves parallel computation of 16 MAC operations simultaneously, completing a 4×4 matrix multiplication in approximately 72 clock cycles. The design follows an incremental development methodology with comprehensive test coverage at each stage. All components have been verified through simulation, and the complete end-to-end system demonstrates correct functionality with zero errors.

**Keywords:** Matrix Multiplication, Hardware Accelerator, MAC Array, RISC-V, FPGA, Parallel Computing, DMA Controller

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [System Architecture](#2-system-architecture)
3. [Design Methodology](#3-design-methodology)
4. [Implementation Details](#4-implementation-details)
5. [Testing and Verification](#5-testing-and-verification)
6. [Results](#6-results)
7. [Codebase Navigation](#7-codebase-navigation)
8. [Conclusion](#8-conclusion)
9. [References](#9-references)
10. [Appendices](#10-appendices)

---

## 1. Introduction

### 1.1 Background

Matrix multiplication is a fundamental operation in numerous applications including machine learning, signal processing, computer graphics, and scientific computing. Traditional CPU-based implementations suffer from performance bottlenecks due to sequential execution and memory bandwidth limitations. Hardware accelerators dedicated to matrix operations can achieve significant speedup through parallel processing and optimized data movement.

### 1.2 Objectives

The primary objectives of this project are:

1. Design and implement a complete matrix multiplication accelerator system
2. Achieve parallel computation through a 4×4 MAC array
3. Implement efficient data movement using DMA and scratchpad memory
4. Develop a controller to orchestrate the complete computation flow
5. Verify functionality through comprehensive testing at each development stage
6. Document the complete system for future extension and integration

### 1.3 Scope

This project implements:
- 8-bit × 8-bit multiplication with 32-bit accumulation
- 4×4 MAC array (16 parallel units)
- Dual-port scratchpad memory (1KB)
- DMA controller for data transfer
- Matrix multiplication controller with state machine
- Complete end-to-end integration

### 1.4 Document Organization

This report is organized as follows: Section 2 describes the system architecture, Section 3 outlines the design methodology, Section 4 provides detailed implementation information, Section 5 covers testing and verification, Section 6 presents results, Section 7 provides codebase navigation, and Section 8 concludes the document.

---

## 2. System Architecture

### 2.1 High-Level Architecture

The accelerator system follows a hierarchical architecture with the following data flow:

```
Main Memory → DMA Controller → Scratchpad Memory → Matrix Controller → MAC Array → Scratchpad Memory
```

**Figure 1: System Data Flow**

```
┌─────────────┐         ┌──────────────┐         ┌─────────────────┐
│ Main Memory │ ◄─────► │ DMA Controller│ ◄─────► │ Scratchpad Mem  │
│            │         │              │         │  (Dual-Port)    │
└─────────────┘         └──────────────┘         └────────┬────────┘
                                                              │
                                                              │ Port B
                                                              ▼
                                                    ┌─────────────────┐
                                                    │ Matrix Controller│
                                                    └────────┬────────┘
                                                              │
                                                              ▼
                                                    ┌─────────────────┐
                                                    │   MAC Array     │
                                                    │   (4×4 = 16)    │
                                                    └─────────────────┘
```

### 2.2 Component Overview

#### 2.2.1 Multiplier (8-bit × 8-bit)

**File:** `rtl/multiplier_8bit.v`

The fundamental building block performs unsigned 8-bit multiplication, producing a 16-bit product. This module serves as the computational core for the MAC units.

**Key Features:**
- Input: Two 8-bit operands (a, b)
- Output: 16-bit product
- Registered output with valid signal
- Single-cycle latency

#### 2.2.2 MAC Unit

**File:** `rtl/mac_unit.v`

The Multiply-Accumulate unit performs the operation: `result = a × b + accumulator`. This is the core computational element for matrix multiplication.

**Key Features:**
- 8-bit inputs (a, b)
- 32-bit accumulator
- Configurable accumulation mode
- Overflow detection
- Single-cycle multiply, one-cycle accumulation

**Operation Modes:**
- `accumulate = 0`: Simple multiplication (result = a × b)
- `accumulate = 1`: Accumulation (result = accumulator + a × b)

#### 2.2.3 MAC Array

**File:** `rtl/mac_array.v`

A 4×4 array of MAC units, enabling parallel computation of 16 multiply-accumulate operations simultaneously.

**Key Features:**
- 16 parallel MAC units
- Parameterized array size (default: 4×4)
- Configurable data width (default: 8-bit)
- Configurable accumulator width (default: 32-bit)
- SystemVerilog 2D array interface

**Architecture:**
```
MAC[0][0]  MAC[0][1]  MAC[0][2]  MAC[0][3]
MAC[1][0]  MAC[1][1]  MAC[1][2]  MAC[1][3]
MAC[2][0]  MAC[2][1]  MAC[2][2]  MAC[2][3]
MAC[3][0]  MAC[3][1]  MAC[3][2]  MAC[3][3]
```

#### 2.2.4 Scratchpad Memory

**File:** `rtl/scratchpad_mem.v`

A dual-port SRAM providing fast on-chip memory for data buffering. Port A is dedicated to DMA operations, while Port B serves the matrix multiplication controller.

**Key Features:**
- 1KB memory (256 × 32-bit words)
- Dual independent ports
- Byte-addressable interface (word-aligned internally)
- Synchronous read/write operations
- Zero-cycle read latency (registered output)

**Memory Organization:**
- Address width: 10 bits (byte address)
- Data width: 32 bits (word)
- Depth: 256 words
- Address mapping: `word_addr = byte_addr[9:2]`

#### 2.2.5 DMA Controller

**File:** `rtl/dma_controller.v`

A Direct Memory Access controller that efficiently transfers data between main memory and scratchpad memory, offloading the CPU from data movement tasks.

**Key Features:**
- State machine-based control
- Configurable transfer size
- Source and destination address support
- Main memory interface with ready/valid handshaking
- Scratchpad interface (Port A)

**State Machine:**
1. **IDLE**: Waiting for start signal
2. **READ_MEM**: Initiating main memory read
3. **WAIT_MEM**: Waiting for memory response
4. **WRITE_SPAD**: Writing to scratchpad
5. **DONE_STATE**: Transfer complete

#### 2.2.6 Matrix Multiplication Controller

**File:** `rtl/matmul_controller.v`

The orchestrator for the complete matrix multiplication operation. This controller manages data loading, MAC array control, and result write-back.

**Key Features:**
- 7-state finite state machine
- Address calculation for matrix elements
- Data unpacking from 32-bit words to 8-bit elements
- Parallel data distribution to 16 MAC units
- Four-pass dot product computation
- Result write-back to scratchpad

**State Machine:**
1. **IDLE**: Waiting for start
2. **INIT**: Initialize counters and registers
3. **LOAD_DATA**: Load A and B matrix data from scratchpad
4. **COMPUTE**: Enable MAC array for one cycle
5. **WAIT_MAC**: Wait for MAC completion, prepare next pass
6. **WRITE_BACK**: Write results to scratchpad
7. **DONE_STATE**: Operation complete

**Computation Algorithm:**
For 4×4 matrix multiplication C = A × B:
- Each element C[i][j] = Σ(k=0 to 3) A[i][k] × B[k][j]
- Four passes (k = 0, 1, 2, 3)
- Each pass: Load A column k and B row k, distribute to all MACs
- Accumulate results over four passes

#### 2.2.7 Top-Level Integration

**File:** `rtl/top.v`

The top-level module integrates all components into a complete system.

**Interfaces:**
- DMA control interface
- Matrix multiplication control interface
- Main memory interface
- Debug outputs

**Component Instantiation:**
- DMA Controller (Port A of scratchpad)
- Scratchpad Memory (dual-port)
- Matrix Multiplication Controller (Port B of scratchpad)
- MAC Array

### 2.3 Data Flow

#### 2.3.1 Matrix Multiplication Flow

1. **DMA Load Phase:**
   - DMA transfers matrix A from main memory to scratchpad (base address: 0x000)
   - DMA transfers matrix B from main memory to scratchpad (base address: 0x010)

2. **Computation Phase:**
   - Controller reads A and B matrices from scratchpad
   - For each pass k (0 to 3):
     - Load A column k (A[0..3][k]) into all MAC rows
     - Load B row k (B[k][0..3]) into all MAC columns
     - Enable MAC array for one cycle
     - Accumulate results
   - After 4 passes, all 16 C[i][j] elements are computed

3. **Write-Back Phase:**
   - Controller writes results to scratchpad (base address: 0x020)
   - Results packed as 4×8-bit values per 32-bit word

### 2.4 Memory Map

**Scratchpad Memory Layout:**

| Address Range | Purpose | Size |
|--------------|---------|------|
| 0x000 - 0x00F | Matrix A | 4 words (16 bytes) |
| 0x010 - 0x01F | Matrix B | 4 words (16 bytes) |
| 0x020 - 0x02F | Matrix C (Results) | 4 words (16 bytes) |
| 0x030 - 0x3FF | Reserved | 1008 bytes |

**Word Layout (32-bit):**
```
[31:24] [23:16] [15:8]  [7:0]
  C[3]    C[2]    C[1]    C[0]
```

---

## 3. Design Methodology

### 3.1 Incremental Development Approach

The project followed an incremental development methodology, building and testing components in stages:

**Stage 1: Basic Components**
- 8-bit multiplier
- MAC unit
- MAC array

**Stage 2: Memory and Data Movement**
- Scratchpad memory
- DMA controller

**Stage 3: Control Logic**
- Matrix multiplication controller (8 incremental steps)

**Stage 4: Integration**
- Top-level integration
- End-to-end testing

### 3.2 Controller Development Steps

The matrix multiplication controller was developed in 8 incremental steps:

1. **Step 1: State Machine Skeleton**
   - Basic state machine with IDLE, INIT, LOAD_DATA, COMPUTE, WAIT_MAC, WRITE_BACK, DONE_STATE
   - Control signals (start, done, busy)

2. **Step 2: Address Calculation**
   - Functions for calculating scratchpad addresses
   - Byte extraction functions
   - Address calculation verification

3. **Step 3: Single Data Load**
   - Load single 32-bit word from scratchpad
   - Extract 8-bit values
   - Timing verification

4. **Step 4: Single MAC Operation**
   - Feed data to single MAC unit
   - Enable MAC for computation
   - Result verification

5. **Step 5: Four-Pass Dot Product**
   - Implement pass counter (k = 0 to 3)
   - Accumulation control
   - Dot product verification

6. **Step 6: Parallel MAC Array**
   - Extend to all 16 MAC units
   - Parallel data loading and distribution
   - Full 4×4 matrix multiplication

7. **Step 7: Write-Back**
   - Result capture
   - Write results to scratchpad
   - Memory readback verification

8. **Step 8: Full Integration**
   - Integrate with top-level module
   - End-to-end flow verification

### 3.3 Design Principles

1. **Modularity**: Each component is a separate module with well-defined interfaces
2. **Parameterization**: Key parameters (array size, data width) are configurable
3. **Testability**: Each component has dedicated testbench
4. **Incremental Verification**: Testing at each development stage
5. **Documentation**: Comprehensive inline comments and documentation

---

## 4. Implementation Details

### 4.1 Technology and Tools

- **HDL**: Verilog/SystemVerilog (IEEE 1364-2005, IEEE 1800-2009)
- **Simulator**: Icarus Verilog (iverilog)
- **Waveform Viewer**: GTKWave
- **Target**: FPGA-ready (synthesizable RTL)

### 4.2 Module Specifications

#### 4.2.1 Multiplier Module

```verilog
module multiplier_8bit (
    input wire clk,
    input wire rst,
    input wire [7:0] a,
    input wire [7:0] b,
    input wire valid_in,
    output reg [15:0] product,
    output reg valid_out
);
```

**Timing:**
- Latency: 1 clock cycle
- Throughput: 1 multiplication per cycle

#### 4.2.2 MAC Unit Module

```verilog
module mac_unit (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire accumulate,
    input wire [7:0] a,
    input wire [7:0] b,
    output reg [31:0] result,
    output reg overflow
);
```

**Timing:**
- Multiplication: 1 cycle
- Accumulation: 1 cycle (when enabled)
- Result available: 1 cycle after enable

#### 4.2.3 MAC Array Module

```verilog
module mac_array #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire enable,
    input wire accumulate,
    input wire [DATA_WIDTH-1:0] a_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    input wire [DATA_WIDTH-1:0] b_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    output wire [ACC_WIDTH-1:0] result_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1],
    output wire [ARRAY_SIZE-1:0] overflow_flags [0:ARRAY_SIZE-1]
);
```

**Performance:**
- Parallel operations: 16 MACs simultaneously
- Total MAC operations per cycle: 16

#### 4.2.4 Scratchpad Memory Module

```verilog
module scratchpad_mem #(
    parameter ADDR_WIDTH = 10,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    // Port A
    input wire [ADDR_WIDTH-1:0] addr_a,
    input wire [DATA_WIDTH-1:0] wdata_a,
    input wire we_a,
    input wire re_a,
    output reg [DATA_WIDTH-1:0] rdata_a,
    // Port B
    input wire [ADDR_WIDTH-1:0] addr_b,
    input wire [DATA_WIDTH-1:0] wdata_b,
    input wire we_b,
    input wire re_b,
    output reg [DATA_WIDTH-1:0] rdata_b
);
```

**Timing:**
- Read latency: 1 cycle (registered output)
- Write latency: 1 cycle
- Port independence: Simultaneous access to different addresses

#### 4.2.5 DMA Controller Module

```verilog
module dma_controller #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [ADDR_WIDTH-1:0] src_addr,
    input wire [ADDR_WIDTH-1:0] dst_addr,
    input wire [15:0] transfer_size,
    output reg done,
    output reg busy,
    // Main memory interface
    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg mem_read,
    input wire [DATA_WIDTH-1:0] mem_rdata,
    input wire mem_ready,
    // Scratchpad interface
    output reg [9:0] spad_addr,
    output reg [DATA_WIDTH-1:0] spad_wdata,
    output reg spad_we,
    output reg spad_re,
    input wire [DATA_WIDTH-1:0] spad_rdata
);
```

**Performance:**
- Transfer rate: 1 word per 3-4 cycles (depending on memory latency)
- Overhead: Minimal (state machine overhead)

#### 4.2.6 Matrix Multiplication Controller Module

```verilog
module matmul_controller (
    input wire clk,
    input wire rst,
    input wire start,
    input wire [9:0] a_base_addr,
    input wire [9:0] b_base_addr,
    input wire [9:0] c_base_addr,
    output reg done,
    output reg busy,
    // Scratchpad interface
    output reg [9:0] spad_addr,
    output reg spad_re,
    input wire [31:0] spad_rdata,
    output reg spad_we,
    output reg [31:0] spad_wdata,
    // MAC Array interface
    output reg [7:0] a_matrix [0:3][0:3],
    output reg [7:0] b_matrix [0:3][0:3],
    output reg mac_enable,
    output reg mac_accumulate,
    input wire [31:0] result_matrix [0:3][0:3]
);
```

**Performance:**
- Load phase: 16 cycles (4 A rows + 1 B row, 3 cycles each)
- Compute phase: 1 cycle per pass
- Wait phase: 1 cycle per pass
- Write-back phase: 4 cycles (1 per row)
- Total cycles: ~72 cycles for 4×4 matrix multiplication

### 4.3 Key Algorithms

#### 4.3.1 Matrix Multiplication Algorithm

For matrices A (4×4) and B (4×4), compute C = A × B:

```
For i = 0 to 3:
    For j = 0 to 3:
        C[i][j] = 0
        For k = 0 to 3:
            C[i][j] += A[i][k] × B[k][j]
```

**Hardware Implementation:**
- Parallel computation: All 16 C[i][j] computed simultaneously
- Four passes: k = 0, 1, 2, 3
- Each pass: Load A column k and B row k, distribute to MACs

#### 4.3.2 Data Distribution Strategy

**Pass k:**
1. Load A[0..3][k] → Distribute to MAC[0..3][*] (same value across row)
2. Load B[k][0..3] → Distribute to MAC[*][0..3] (same value down column)
3. Each MAC[i][j] computes: A[i][k] × B[k][j]
4. Accumulate result in MAC[i][j]

**Example (Pass 0):**
- MAC[0][0] gets A[0][0] and B[0][0] → computes A[0][0] × B[0][0]
- MAC[0][1] gets A[0][0] and B[0][1] → computes A[0][0] × B[0][1]
- MAC[1][0] gets A[1][0] and B[0][0] → computes A[1][0] × B[0][0]
- etc.

### 4.4 Address Calculation

#### 4.4.1 Matrix A Address

```verilog
function [9:0] calc_a_word_addr;
    input [1:0] row;
    begin
        calc_a_word_addr = a_base_addr + {6'd0, row, 2'b00}; // row * 4
    end
endfunction
```

**Example:**
- A[0][*] → address = a_base_addr + 0 = 0x000
- A[1][*] → address = a_base_addr + 4 = 0x004
- A[2][*] → address = a_base_addr + 8 = 0x008
- A[3][*] → address = a_base_addr + 12 = 0x00C

#### 4.4.2 Matrix B Address

```verilog
function [9:0] calc_b_word_addr;
    input [1:0] row;
    begin
        calc_b_word_addr = b_base_addr + {6'd0, row, 2'b00}; // row * 4
    end
endfunction
```

**Example:**
- B[0][*] → address = b_base_addr + 0 = 0x010
- B[1][*] → address = b_base_addr + 4 = 0x014
- B[2][*] → address = b_base_addr + 8 = 0x018
- B[3][*] → address = b_base_addr + 12 = 0x01C

#### 4.4.3 Matrix C Address

```verilog
function [9:0] calc_c_word_addr;
    input [1:0] row;
    begin
        calc_c_word_addr = c_base_addr + {6'd0, row, 2'b00}; // row * 4
    end
endfunction
```

**Example:**
- C[0][*] → address = c_base_addr + 0 = 0x020
- C[1][*] → address = c_base_addr + 4 = 0x024
- C[2][*] → address = c_base_addr + 8 = 0x028
- C[3][*] → address = c_base_addr + 12 = 0x02C

### 4.5 Data Packing/Unpacking

#### 4.5.1 Byte Extraction

```verilog
function [7:0] extract_byte;
    input [31:0] word;
    input [1:0] byte_sel;
    begin
        case (byte_sel)
            2'd0: extract_byte = word[7:0];
            2'd1: extract_byte = word[15:8];
            2'd2: extract_byte = word[23:16];
            2'd3: extract_byte = word[31:24];
        endcase
    end
endfunction
```

#### 4.5.2 Result Packing

```verilog
function [31:0] pack_results;
    input [31:0] r0, r1, r2, r3;
    begin
        pack_results = {r3[7:0], r2[7:0], r1[7:0], r0[7:0]};
    end
endfunction
```

**Layout:**
```
[31:24] [23:16] [15:8]  [7:0]
  C[3]    C[2]    C[1]    C[0]
```

---

## 5. Testing and Verification

### 5.1 Test Strategy

The testing strategy follows a bottom-up approach:

1. **Unit Testing**: Individual component verification
2. **Integration Testing**: Component interaction verification
3. **System Testing**: End-to-end functionality verification

### 5.2 Testbenches

#### 5.2.1 Component Testbenches

| Component | Testbench File | Test Cases |
|-----------|---------------|------------|
| Multiplier | `testbench/tb_multiplier_8bit.v` | Basic multiplication, edge cases (0, 255) |
| MAC Unit | `testbench/tb_mac_unit.v` | Single multiply, accumulation, dot product |
| MAC Array | `testbench/tb_mac_array.v` | Parallel operation, all 16 MACs |
| Scratchpad | `testbench/tb_dma_controller.v` | Dual-port access, read/write |
| DMA | `testbench/tb_dma_controller.v` | Transfer verification |

#### 5.2.2 Controller Testbenches (Incremental)

| Step | Testbench File | Verification |
|------|---------------|--------------|
| Step 1 | `testbench/tb_matmul_step1.v` | State machine transitions |
| Step 2 | `testbench/tb_matmul_step2.v` | Address calculation |
| Step 3 | `testbench/tb_matmul_step3.v` | Single data load |
| Step 4 | `testbench/tb_matmul_step4.v` | Single MAC operation |
| Step 5 | `testbench/tb_matmul_step5.v` | Four-pass dot product |
| Step 6 | `testbench/tb_matmul_step6.v` | Parallel MAC array |
| Step 7 | `testbench/tb_matmul_step7.v` | Write-back functionality |
| Step 8 | `testbench/tb_top_complete.v` | End-to-end integration |

### 5.3 Test Execution

#### 5.3.1 Running Individual Tests

Each test has a dedicated batch script:

```batch
test_multiplier.bat    # Test 8-bit multiplier
test_mac_unit.bat      # Test MAC unit
test_mac_array.bat     # Test MAC array
test_dma.bat           # Test DMA controller
test_step1.bat         # Test controller step 1
test_step2.bat         # Test controller step 2
...
test_step8.bat         # Test end-to-end system
```

#### 5.3.2 Compilation Command

```bash
iverilog -g2009 -o sim.vvp rtl/*.v testbench/tb_*.v
vvp sim.vvp
```

### 5.4 Test Results Summary

#### 5.4.1 Component Tests

| Component | Status | Notes |
|-----------|--------|-------|
| Multiplier | ✅ PASS | All test cases passed |
| MAC Unit | ✅ PASS | Single and accumulation modes verified |
| MAC Array | ✅ PASS | All 16 MACs working in parallel |
| Scratchpad | ✅ PASS | Dual-port access verified |
| DMA | ✅ PASS | Transfer functionality verified |

#### 5.4.2 Controller Tests

| Step | Status | Verification |
|------|--------|--------------|
| Step 1 | ✅ PASS | State machine working |
| Step 2 | ✅ PASS | Address calculation correct |
| Step 3 | ✅ PASS | Data loading working |
| Step 4 | ✅ PASS | Single MAC operation correct |
| Step 5 | ✅ PASS | Four-pass dot product correct |
| Step 6 | ✅ PASS | All 16 MACs parallel operation |
| Step 7 | ✅ PASS | Write-back verified |
| Step 8 | ✅ PASS | End-to-end system working |

#### 5.4.3 End-to-End Test Results

**Test Case 1: 2×2 Matrix Multiply**
- Input: A = [[1,2],[3,4]], B = [[5,6],[7,8]]
- Expected: C = [[19,22],[43,50]]
- Result: ✅ PASS (All 4 elements correct)

**Test Case 2: 4×4 Identity Matrix**
- Input: A = [[1,2,3,4],[5,6,7,8],[1,2,3,4],[5,6,7,8]], B = Identity
- Expected: C = A (since B is identity)
- Result: ✅ PASS (All 16 elements correct)

**Overall Result: ✅ ALL TESTS PASSING (0 ERRORS)**

---

## 6. Results

### 6.1 Performance Metrics

#### 6.1.1 Computation Performance

- **Matrix Size**: 4×4
- **Data Precision**: 8-bit inputs, 32-bit accumulation
- **Computation Time**: ~72 clock cycles
- **Parallelism**: 16 MAC units operating simultaneously
- **Throughput**: 64 MAC operations per 4×4 matrix multiply

#### 6.1.2 Resource Utilization (Estimated)

| Resource | Count | Notes |
|----------|-------|-------|
| MAC Units | 16 | 4×4 array |
| Multipliers | 16 | One per MAC unit |
| Adders | 16 | Accumulation in MAC units |
| Memory (Scratchpad) | 1KB | 256 × 32-bit words |
| State Machines | 2 | DMA controller, Matrix controller |

#### 6.1.3 Timing Analysis

| Operation | Cycles | Notes |
|-----------|--------|-------|
| DMA Load (A) | ~20 | 4 words × ~5 cycles/word |
| DMA Load (B) | ~20 | 4 words × ~5 cycles/word |
| Matrix Multiply | 72 | 4 passes × 18 cycles/pass |
| Write-Back | 4 | 1 cycle per row |
| **Total** | **~116** | End-to-end operation |

### 6.2 Functional Verification

All functional requirements have been verified:

✅ **Requirement 1**: 8-bit × 8-bit multiplication - **VERIFIED**  
✅ **Requirement 2**: 4×4 MAC array - **VERIFIED**  
✅ **Requirement 3**: Parallel computation - **VERIFIED**  
✅ **Requirement 4**: DMA data transfer - **VERIFIED**  
✅ **Requirement 5**: Scratchpad memory - **VERIFIED**  
✅ **Requirement 6**: Matrix multiplication controller - **VERIFIED**  
✅ **Requirement 7**: Result write-back - **VERIFIED**  
✅ **Requirement 8**: End-to-end integration - **VERIFIED**  

### 6.3 Correctness Verification

**Test Matrix 1: Identity Property**
- A × I = A ✅ Verified

**Test Matrix 2: 2×2 Sub-matrix**
- Manual calculation matches hardware result ✅ Verified

**Test Matrix 3: Full 4×4**
- All 16 elements computed correctly ✅ Verified

---

## 7. Codebase Navigation

### 7.1 Directory Structure

```
project_sim/
├── rtl/                          # RTL Implementation
│   ├── multiplier_8bit.v        # 8-bit multiplier
│   ├── mac_unit.v                # MAC unit
│   ├── mac_array.v               # 4×4 MAC array
│   ├── scratchpad_mem.v          # Dual-port scratchpad
│   ├── dma_controller.v          # DMA controller
│   ├── matmul_controller.v       # Matrix multiplication controller
│   └── top.v                     # Top-level integration
│
├── testbench/                    # Testbenches
│   ├── tb_multiplier_8bit.v     # Multiplier testbench
│   ├── tb_mac_unit.v             # MAC unit testbench
│   ├── tb_mac_array.v            # MAC array testbench
│   ├── tb_dma_controller.v       # DMA testbench
│   ├── tb_matmul_step1.v          # Controller step 1 test
│   ├── tb_matmul_step2.v          # Controller step 2 test
│   ├── tb_matmul_step3.v          # Controller step 3 test
│   ├── tb_matmul_step4.v          # Controller step 4 test
│   ├── tb_matmul_step5.v          # Controller step 5 test
│   ├── tb_matmul_step6.v          # Controller step 6 test
│   ├── tb_matmul_step7.v          # Controller step 7 test
│   └── tb_top_complete.v          # End-to-end testbench
│
├── docs/                          # Documentation
│   ├── architecture.md           # Architecture documentation
│   ├── RTL_DETAILED_EXPLANATION.md # Detailed RTL explanation
│   ├── COMPLETE_FLOW_EXPLAINED.md  # Data flow explanation
│   ├── CONTROLLER_SPECIFICATION.md # Controller specification
│   ├── CONTROLLER_BUILD_PLAN.md    # Controller development plan
│   └── IEEE_TECHNICAL_REPORT.md    # This document
│
├── test_*.bat                     # Test execution scripts
├── run_sim.bat                     # General simulation script
├── README.md                       # Project overview
└── TESTING_GUIDE.md                # Testing instructions
```

### 7.2 File Navigation Guide

#### 7.2.1 Starting Point

**For Understanding the System:**
1. Start with `README.md` - Project overview
2. Read `docs/architecture.md` - System architecture
3. Review `rtl/top.v` - Top-level integration

**For Understanding Components:**
1. `rtl/multiplier_8bit.v` - Basic building block
2. `rtl/mac_unit.v` - Core computation unit
3. `rtl/mac_array.v` - Parallel computation
4. `rtl/scratchpad_mem.v` - Memory subsystem
5. `rtl/dma_controller.v` - Data movement
6. `rtl/matmul_controller.v` - Control logic

**For Testing:**
1. Run individual component tests: `test_multiplier.bat`, etc.
2. Run controller step tests: `test_step1.bat` through `test_step8.bat`
3. Run end-to-end test: `test_step8.bat`

#### 7.2.2 Key Files by Function

**Computation:**
- `rtl/multiplier_8bit.v` - Basic multiplication
- `rtl/mac_unit.v` - Multiply-accumulate
- `rtl/mac_array.v` - Parallel MAC array

**Memory:**
- `rtl/scratchpad_mem.v` - Dual-port SRAM

**Control:**
- `rtl/dma_controller.v` - DMA state machine
- `rtl/matmul_controller.v` - Matrix multiplication state machine

**Integration:**
- `rtl/top.v` - System integration

**Testing:**
- `testbench/tb_*.v` - Component testbenches
- `testbench/tb_top_complete.v` - System testbench

#### 7.2.3 Code Flow Navigation

**Data Flow Path:**
1. `rtl/top.v` (line 67-90) → DMA Controller instantiation
2. `rtl/dma_controller.v` → Data transfer logic
3. `rtl/top.v` (line 95-113) → Scratchpad memory
4. `rtl/top.v` (line 118-140) → Matrix controller
5. `rtl/matmul_controller.v` → Control logic
6. `rtl/top.v` (line 145-158) → MAC array
7. `rtl/mac_array.v` → Parallel computation
8. `rtl/matmul_controller.v` (WRITE_BACK state) → Result write-back

**Control Flow Path:**
1. `rtl/matmul_controller.v` (line 115-175) → State machine
2. `rtl/matmul_controller.v` (line 216-320) → LOAD_DATA state
3. `rtl/matmul_controller.v` (line 322-330) → COMPUTE state
4. `rtl/matmul_controller.v` (line 332-348) → WAIT_MAC state
5. `rtl/matmul_controller.v` (line 384-410) → WRITE_BACK state

### 7.3 Module Dependencies

```
top.v
├── dma_controller.v
│   └── (no dependencies)
├── scratchpad_mem.v
│   └── (no dependencies)
├── matmul_controller.v
│   └── scratchpad_mem.v (interface)
└── mac_array.v
    └── mac_unit.v
        └── multiplier_8bit.v (conceptually)
```

### 7.4 Key Code Sections

#### 7.4.1 State Machine Definitions

**Location:** `rtl/matmul_controller.v` (lines 32-39)

```verilog
localparam IDLE        = 3'd0;
localparam INIT        = 3'd1;
localparam LOAD_DATA   = 3'd2;
localparam COMPUTE     = 3'd3;
localparam WAIT_MAC    = 3'd4;
localparam WRITE_BACK  = 3'd5;
localparam DONE_STATE  = 3'd6;
```

#### 7.4.2 MAC Array Generation

**Location:** `rtl/mac_array.v` (lines 26-41)

```verilog
generate
    for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : row
        for (j = 0; j < ARRAY_SIZE; j = j + 1) begin : col
            mac_unit mac_inst (
                .clk(clk),
                .rst(rst),
                .enable(enable),
                .accumulate(accumulate),
                .a(a_matrix[i][j]),
                .b(b_matrix[i][j]),
                .result(result_matrix[i][j]),
                .overflow(overflow_flags[i][j])
            );
        end
    end
endgenerate
```

#### 7.4.3 Data Distribution Logic

**Location:** `rtl/matmul_controller.v` (lines 309-325)

```verilog
5'd15: begin
    // Distribute data to all 16 MACs
    for (i = 0; i < 4; i = i + 1) begin
        // Column 0
        a_matrix[i][0] <= extract_byte(a_row_data[i], pass_k[1:0]);
        b_matrix[i][0] <= b_row_data[7:0];
        // ... columns 1, 2, 3
    end
end
```

### 7.5 Testing Navigation

#### 7.5.1 Running Tests

**Individual Component Tests:**
```bash
.\test_multiplier.bat
.\test_mac_unit.bat
.\test_mac_array.bat
.\test_dma.bat
```

**Controller Development Tests:**
```bash
.\test_step1.bat  # State machine
.\test_step2.bat  # Address calculation
.\test_step3.bat  # Data loading
.\test_step4.bat  # Single MAC
.\test_step5.bat  # Dot product
.\test_step6.bat  # Parallel array
.\test_step7.bat  # Write-back
.\test_step8.bat  # End-to-end
```

#### 7.5.2 Viewing Waveforms

After running tests, view waveforms with:
```bash
gtkwave tb_*.vcd
```

**Key Signals to Monitor:**
- `clk`, `rst` - Clock and reset
- `state` - Controller state machine
- `spad_addr`, `spad_rdata`, `spad_wdata` - Scratchpad interface
- `mac_enable`, `mac_accumulate` - MAC control
- `result_matrix` - MAC array outputs

---

## 8. Conclusion

### 8.1 Summary

This project successfully designed and implemented a complete matrix multiplication accelerator system. The system features:

- **16 parallel MAC units** operating simultaneously
- **Dual-port scratchpad memory** for efficient data buffering
- **DMA controller** for optimized data movement
- **Dedicated matrix multiplication controller** orchestrating the complete flow
- **End-to-end integration** with verified functionality

### 8.2 Achievements

1. ✅ **Complete System Implementation**: All components designed and verified
2. ✅ **Parallel Computation**: 16 MACs operating in parallel
3. ✅ **Efficient Data Movement**: DMA and scratchpad memory working correctly
4. ✅ **Comprehensive Testing**: All 8 development steps verified
5. ✅ **Zero Errors**: Complete system passing all tests

### 8.3 Performance

- **Computation Time**: ~72 cycles for 4×4 matrix multiplication
- **Parallelism**: 16 MAC operations per cycle
- **Throughput**: 64 MAC operations per matrix multiply
- **Efficiency**: Optimal 4-pass algorithm for 4×4 matrices

### 8.4 Future Work

Potential extensions and improvements:

1. **Scaling**: Extend to 8×8 or 16×16 MAC arrays
2. **Data Types**: Support for int16, int32, or floating-point
3. **Pipelining**: Add pipeline stages for higher throughput
4. **RISC-V Integration**: Connect to RISC-V core with custom instructions
5. **FPGA Implementation**: Synthesize and test on real hardware
6. **Optimization**: Further optimize timing and resource utilization

### 8.5 Lessons Learned

1. **Incremental Development**: Step-by-step approach enabled easier debugging
2. **Comprehensive Testing**: Testing at each stage caught issues early
3. **Modular Design**: Well-defined interfaces simplified integration
4. **Documentation**: Good documentation facilitated understanding and maintenance

---

## 9. References

### 9.1 Standards

1. IEEE Std 1364-2005, "IEEE Standard for Verilog Hardware Description Language"
2. IEEE Std 1800-2009, "IEEE Standard for SystemVerilog—Unified Hardware Design, Specification, and Verification Language"

### 9.2 Tools

1. Icarus Verilog - Open-source Verilog simulation tool
2. GTKWave - Waveform viewer for VCD files

### 9.3 Related Work

1. RISC-V Instruction Set Manual
2. Matrix Multiplication Accelerator Architectures
3. Hardware Accelerator Design Principles

---

## 10. Appendices

### Appendix A: Complete File Listing

**RTL Files:**
- `rtl/multiplier_8bit.v` (25 lines)
- `rtl/mac_unit.v` (44 lines)
- `rtl/mac_array.v` (44 lines)
- `rtl/scratchpad_mem.v` (68 lines)
- `rtl/dma_controller.v` (152 lines)
- `rtl/matmul_controller.v` (459 lines)
- `rtl/top.v` (167 lines)

**Testbench Files:**
- `testbench/tb_multiplier_8bit.v`
- `testbench/tb_mac_unit.v`
- `testbench/tb_mac_array.v`
- `testbench/tb_dma_controller.v`
- `testbench/tb_matmul_step1.v` through `tb_matmul_step7.v`
- `testbench/tb_top_complete.v`

**Total Lines of Code:** ~3000+ lines (RTL + Testbenches)

### Appendix B: State Machine Diagrams

**DMA Controller State Machine:**
```
IDLE → READ_MEM → WAIT_MEM → WRITE_SPAD → (loop or DONE_STATE)
```

**Matrix Multiplication Controller State Machine:**
```
IDLE → INIT → LOAD_DATA → COMPUTE → WAIT_MAC → (loop or WRITE_BACK) → DONE_STATE
```

### Appendix C: Memory Map Details

**Scratchpad Memory Map:**
```
0x000-0x00F: Matrix A (4 words, 16 bytes)
0x010-0x01F: Matrix B (4 words, 16 bytes)
0x020-0x02F: Matrix C (4 words, 16 bytes)
0x030-0x3FF: Reserved (1008 bytes)
```

### Appendix D: Test Results Log

**All Tests: PASSED**

- Component Tests: 5/5 PASSED
- Controller Step Tests: 8/8 PASSED
- End-to-End Test: 1/1 PASSED
- **Total: 14/14 PASSED (100%)**

### Appendix E: Performance Metrics

**Computation Performance:**
- Matrix Size: 4×4
- Data Width: 8-bit inputs, 32-bit accumulation
- Cycles per Multiply: ~72 cycles
- MAC Operations: 64 per matrix multiply
- Parallelism: 16 MACs

**Resource Estimates (FPGA):**
- LUTs: ~2000-3000 (estimated)
- Registers: ~1500-2000 (estimated)
- Memory: 1KB (256 × 32-bit)
- DSP Slices: 16 (if using hard multipliers)

---

**End of Document**

---

**Document Information:**
- **Version**: 1.0
- **Last Updated**: 2024
- **Status**: Final
- **Classification**: Technical Report

