# Detailed Explanation: How Multiplication Works in the MAC Array

## Table of Contents
1. [Overview](#1-overview)
2. [Single MAC Unit Multiplication](#2-single-mac-unit-multiplication)
3. [MAC Array Architecture](#3-mac-array-architecture)
4. [Data Flow and Distribution](#4-data-flow-and-distribution)
5. [Matrix Multiplication Algorithm](#5-matrix-multiplication-algorithm)
6. [Step-by-Step Example](#6-step-by-step-example)
7. [Timing and Parallelism](#7-timing-and-parallelism)
8. [Hardware Implementation](#8-hardware-implementation)

---

## 1. Overview

The MAC array performs **parallel matrix multiplication** using 16 independent MAC (Multiply-Accumulate) units arranged in a 4×4 grid. Each MAC unit performs 8-bit × 8-bit multiplication and accumulation.

**Key Concept:** All 16 MACs operate **simultaneously** in parallel, not sequentially!

---

## 2. Single MAC Unit Multiplication

### 2.1 Basic Operation

Each MAC unit (`mac_unit.v`) performs:

```
result = a × b + accumulator
```

**Inputs:**
- `a[7:0]`: 8-bit multiplicand (0 to 255)
- `b[7:0]`: 8-bit multiplier (0 to 255)
- `accumulate`: Control signal (0 = multiply only, 1 = multiply + accumulate)

**Outputs:**
- `result[31:0]`: 32-bit result
- `overflow`: Overflow flag

### 2.2 Hardware Implementation

```verilog
// From mac_unit.v

// Step 1: Multiply (combinational)
assign product = a * b;                    // 8×8 = 16-bit result

// Step 2: Extend to 32 bits
assign extended_product = {16'd0, product}; // Zero-extend to 32 bits

// Step 3: Add to accumulator (if enabled)
assign next_result = accumulate ? (accumulator + extended_product) 
                                 : extended_product;

// Step 4: Register on clock edge
always @(posedge clk) begin
    if (enable) begin
        accumulator <= next_result;  // Store for next accumulation
        result <= next_result;       // Output current result
    end
end
```

### 2.3 Example: Single MAC Operation

**Cycle 1: Simple Multiply (accumulate = 0)**
```
Input:  a = 5, b = 6
        product = 5 × 6 = 30
        extended_product = 0x0000001E (30 in hex)
        next_result = 30 (no accumulation)
        
Result: result = 30, accumulator = 30
```

**Cycle 2: Accumulate (accumulate = 1)**
```
Input:  a = 3, b = 4
        product = 3 × 4 = 12
        extended_product = 0x0000000C
        next_result = accumulator + extended_product = 30 + 12 = 42
        
Result: result = 42, accumulator = 42
```

**Cycle 3: Another Accumulation**
```
Input:  a = 2, b = 5
        product = 2 × 5 = 10
        next_result = 42 + 10 = 52
        
Result: result = 52, accumulator = 52
```

**This is how a dot product is computed:**
```
dot_product = 5×6 + 3×4 + 2×5 = 30 + 12 + 10 = 52
```

---

## 3. MAC Array Architecture

### 3.1 Physical Layout

The MAC array is a **4×4 grid** of independent MAC units:

```
        Column 0    Column 1    Column 2    Column 3
Row 0:  MAC[0][0]   MAC[0][1]   MAC[0][2]   MAC[0][3]
Row 1:  MAC[1][0]   MAC[1][1]   MAC[1][2]   MAC[1][3]
Row 2:  MAC[2][0]   MAC[2][1]   MAC[2][2]   MAC[2][3]
Row 3:  MAC[3][0]   MAC[3][1]   MAC[3][2]   MAC[3][3]
```

**Total: 16 MAC units**

### 3.2 Code Structure

```verilog
// From mac_array.v

generate
    for (i = 0; i < 4; i = i + 1) begin : row
        for (j = 0; j < 4; j = j + 1) begin : col
            mac_unit mac_inst (
                .clk(clk),
                .rst(rst),
                .enable(enable),           // All MACs enabled together
                .accumulate(accumulate),   // All MACs accumulate together
                .a(a_matrix[i][j]),       // Input A for this MAC
                .b(b_matrix[i][j]),       // Input B for this MAC
                .result(result_matrix[i][j]), // Output from this MAC
                .overflow(overflow_flags[i][j])
            );
        end
    end
endgenerate
```

**Key Point:** All 16 MACs receive the same `enable` and `accumulate` signals, but each gets different `a` and `b` inputs!

---

## 4. Data Flow and Distribution

### 4.1 Input Data Structure

The controller provides two 4×4 matrices:

```verilog
// From matmul_controller.v

output reg [7:0] a_matrix [0:3][0:3];  // 16 values (4×4)
output reg [7:0] b_matrix [0:3][0:3];  // 16 values (4×4)
```

**Each MAC gets one pair:**
- `MAC[i][j]` receives: `a_matrix[i][j]` and `b_matrix[i][j]`

### 4.2 Data Distribution Example

**Input:**
```
a_matrix = [[1, 2, 3, 4],
           [5, 6, 7, 8],
           [9, 10, 11, 12],
           [13, 14, 15, 16]]

b_matrix = [[10, 20, 30, 40],
           [50, 60, 70, 80],
           [90, 100, 110, 120],
           [130, 140, 150, 160]]
```

**Distribution:**
```
MAC[0][0]: a=1,  b=10  → 1×10  = 10
MAC[0][1]: a=2,  b=20  → 2×20  = 40
MAC[0][2]: a=3,  b=30  → 3×30  = 90
MAC[0][3]: a=4,  b=40  → 4×40  = 160

MAC[1][0]: a=5,  b=50  → 5×50  = 250
MAC[1][1]: a=6,  b=60  → 6×60  = 360
MAC[1][2]: a=7,  b=70  → 7×70  = 490
MAC[1][3]: a=8,  b=80  → 8×80  = 640

MAC[2][0]: a=9,  b=90  → 9×90  = 810
MAC[2][1]: a=10, b=100 → 10×100 = 1000
MAC[2][2]: a=11, b=110 → 11×110 = 1210
MAC[2][3]: a=12, b=120 → 12×120 = 1440

MAC[3][0]: a=13, b=130 → 13×130 = 1690
MAC[3][1]: a=14, b=140 → 14×140 = 1960
MAC[3][2]: a=15, b=150 → 15×150 = 2250
MAC[3][3]: a=16, b=160 → 16×160 = 2560
```

**ALL 16 MULTIPLICATIONS HAPPEN IN THE SAME CLOCK CYCLE!**

---

## 5. Matrix Multiplication Algorithm

### 5.1 Mathematical Formula

For matrices C = A × B (4×4):

```
C[i][j] = Σ(k=0 to 3) A[i][k] × B[k][j]
```

**Example:**
```
C[0][0] = A[0][0]×B[0][0] + A[0][1]×B[1][0] + A[0][2]×B[2][0] + A[0][3]×B[3][0]
```

### 5.2 Hardware Algorithm: Four-Pass Approach

The controller uses a **4-pass algorithm** where each pass computes one term of the dot product:

**Pass 0 (k=0):**
- Load: A column 0 (A[0..3][0]) and B row 0 (B[0][0..3])
- Compute: All MACs compute A[i][0] × B[0][j]
- Result: Partial C[i][j] = A[i][0] × B[0][j]

**Pass 1 (k=1):**
- Load: A column 1 (A[0..3][1]) and B row 1 (B[1][0..3])
- Compute: All MACs compute A[i][1] × B[1][j]
- Accumulate: C[i][j] += A[i][1] × B[1][j]

**Pass 2 (k=2):**
- Load: A column 2 (A[0..3][2]) and B row 2 (B[2][0..3])
- Compute: All MACs compute A[i][2] × B[2][j]
- Accumulate: C[i][j] += A[i][2] × B[2][j]

**Pass 3 (k=3):**
- Load: A column 3 (A[0..3][3]) and B row 3 (B[3][0..3])
- Compute: All MACs compute A[i][3] × B[3][j]
- Accumulate: C[i][j] += A[i][3] × B[3][j] (FINAL RESULT)

### 5.3 Data Distribution Strategy

**Key Insight:** For each pass k, we need to distribute:
- A[i][k] to all MACs in row i (same value across columns)
- B[k][j] to all MACs in column j (same value down rows)

**Code from matmul_controller.v (lines 314-330):**

```verilog
for (i = 0; i < 4; i = i + 1) begin
    // Column 0
    a_matrix[i][0] <= extract_byte(a_row_data[i], pass_k[1:0]);  // A[i][k]
    b_matrix[i][0] <= b_row_data[7:0];                          // B[k][0]
    
    // Column 1
    a_matrix[i][1] <= extract_byte(a_row_data[i], pass_k[1:0]);  // A[i][k] (same!)
    b_matrix[i][1] <= b_row_data[15:8];                          // B[k][1]
    
    // Column 2
    a_matrix[i][2] <= extract_byte(a_row_data[i], pass_k[1:0]);  // A[i][k] (same!)
    b_matrix[i][2] <= b_row_data[23:16];                         // B[k][2]
    
    // Column 3
    a_matrix[i][3] <= extract_byte(a_row_data[i], pass_k[1:0]);   // A[i][k] (same!)
    b_matrix[i][3] <= b_row_data[31:24];                         // B[k][3]
end
```

**Visual Representation (Pass 0, k=0):**

```
A column 0:        B row 0:
A[0][0] = 1        B[0][0]=5  B[0][1]=6  B[0][2]=7  B[0][3]=8
A[1][0] = 2
A[2][0] = 3
A[3][0] = 4

Distribution:
Row 0: MAC[0][0] gets A[0][0]=1, B[0][0]=5 → 1×5 = 5
       MAC[0][1] gets A[0][0]=1, B[0][1]=6 → 1×6 = 6
       MAC[0][2] gets A[0][0]=1, B[0][2]=7 → 1×7 = 7
       MAC[0][3] gets A[0][0]=1, B[0][3]=8 → 1×8 = 8

Row 1: MAC[1][0] gets A[1][0]=2, B[0][0]=5 → 2×5 = 10
       MAC[1][1] gets A[1][0]=2, B[0][1]=6 → 2×6 = 12
       MAC[1][2] gets A[1][0]=2, B[0][2]=7 → 2×7 = 14
       MAC[1][3] gets A[1][0]=2, B[0][3]=8 → 2×8 = 16

Row 2: MAC[2][0] gets A[2][0]=3, B[0][0]=5 → 3×5 = 15
       MAC[2][1] gets A[2][0]=3, B[0][1]=6 → 3×6 = 18
       MAC[2][2] gets A[2][0]=3, B[0][2]=7 → 3×7 = 21
       MAC[2][3] gets A[2][0]=3, B[0][3]=8 → 3×8 = 24

Row 3: MAC[3][0] gets A[3][0]=4, B[0][0]=5 → 4×5 = 20
       MAC[3][1] gets A[3][0]=4, B[0][1]=6 → 4×6 = 24
       MAC[3][2] gets A[3][0]=4, B[0][2]=7 → 4×7 = 28
       MAC[3][3] gets A[3][0]=4, B[0][3]=8 → 4×8 = 32
```

**Notice:** Each row gets the same A value, each column gets the same B value!

---

## 6. Step-by-Step Example

Let's compute C = A × B where:

```
A = [1  2  3  4]    B = [5   6   7   8]
    [5  6  7  8]        [9  10  11  12]
    [1  2  3  4]        [13 14  15  16]
    [5  6  7  8]        [17 18  19  20]
```

### Pass 0 (k=0): First Term

**Data Loaded:**
- A column 0: [1, 5, 1, 5]
- B row 0: [5, 6, 7, 8]

**MAC Operations (all simultaneous):**
```
MAC[0][0]: 1×5 = 5    MAC[0][1]: 1×6 = 6    MAC[0][2]: 1×7 = 7    MAC[0][3]: 1×8 = 8
MAC[1][0]: 5×5 = 25   MAC[1][1]: 5×6 = 30   MAC[1][2]: 5×7 = 35   MAC[1][3]: 5×8 = 40
MAC[2][0]: 1×5 = 5    MAC[2][1]: 1×6 = 6    MAC[2][2]: 1×7 = 7    MAC[2][3]: 1×8 = 8
MAC[3][0]: 5×5 = 25   MAC[3][1]: 5×6 = 30   MAC[3][2]: 5×7 = 35   MAC[3][3]: 5×8 = 40
```

**Result after Pass 0 (accumulate=0, so this is the initial value):**
```
C[0][0] = 5    C[0][1] = 6    C[0][2] = 7    C[0][3] = 8
C[1][0] = 25   C[1][1] = 30   C[1][2] = 35   C[1][3] = 40
C[2][0] = 5    C[2][1] = 6    C[2][2] = 7    C[2][3] = 8
C[3][0] = 25   C[3][1] = 30   C[3][2] = 35   C[3][3] = 40
```

### Pass 1 (k=1): Second Term

**Data Loaded:**
- A column 1: [2, 6, 2, 6]
- B row 1: [9, 10, 11, 12]

**MAC Operations (accumulate=1, so add to previous result):**
```
MAC[0][0]: 5 + (2×9)  = 5 + 18  = 23
MAC[0][1]: 6 + (2×10) = 6 + 20  = 26
MAC[0][2]: 7 + (2×11) = 7 + 22  = 29
MAC[0][3]: 8 + (2×12) = 8 + 24  = 32

MAC[1][0]: 25 + (6×9)  = 25 + 54  = 79
MAC[1][1]: 30 + (6×10) = 30 + 60  = 90
MAC[1][2]: 35 + (6×11) = 35 + 66  = 101
MAC[1][3]: 40 + (6×12) = 40 + 72  = 112

MAC[2][0]: 5 + (2×9)   = 5 + 18   = 23
MAC[2][1]: 6 + (2×10)  = 6 + 20   = 26
MAC[2][2]: 7 + (2×11)  = 7 + 22   = 29
MAC[2][3]: 8 + (2×12)  = 8 + 24   = 32

MAC[3][0]: 25 + (6×9)  = 25 + 54  = 79
MAC[3][1]: 30 + (6×10) = 30 + 60  = 90
MAC[3][2]: 35 + (6×11) = 35 + 66  = 101
MAC[3][3]: 40 + (6×12) = 40 + 72  = 112
```

**Result after Pass 1:**
```
C[0][0] = 23   C[0][1] = 26   C[0][2] = 29   C[0][3] = 32
C[1][0] = 79   C[1][1] = 90   C[1][2] = 101  C[1][3] = 112
C[2][0] = 23   C[2][1] = 26   C[2][2] = 29   C[2][3] = 32
C[3][0] = 79   C[3][1] = 90   C[3][2] = 101  C[3][3] = 112
```

### Pass 2 (k=2): Third Term

**Data Loaded:**
- A column 2: [3, 7, 3, 7]
- B row 2: [13, 14, 15, 16]

**MAC Operations (accumulate=1):**
```
MAC[0][0]: 23 + (3×13) = 23 + 39 = 62
MAC[0][1]: 26 + (3×14) = 26 + 42 = 68
MAC[0][2]: 29 + (3×15) = 29 + 45 = 74
MAC[0][3]: 32 + (3×16) = 32 + 48 = 80

MAC[1][0]: 79 + (7×13) = 79 + 91  = 170
MAC[1][1]: 90 + (7×14) = 90 + 98  = 188
MAC[1][2]: 101 + (7×15) = 101 + 105 = 206
MAC[1][3]: 112 + (7×16) = 112 + 112 = 224

MAC[2][0]: 23 + (3×13) = 23 + 39 = 62
MAC[2][1]: 26 + (3×14) = 26 + 42 = 68
MAC[2][2]: 29 + (3×15) = 29 + 45 = 74
MAC[2][3]: 32 + (3×16) = 32 + 48 = 80

MAC[3][0]: 79 + (7×13) = 79 + 91  = 170
MAC[3][1]: 90 + (7×14) = 90 + 98  = 188
MAC[3][2]: 101 + (7×15) = 101 + 105 = 206
MAC[3][3]: 112 + (7×16) = 112 + 112 = 224
```

### Pass 3 (k=3): Final Term

**Data Loaded:**
- A column 3: [4, 8, 4, 8]
- B row 3: [17, 18, 19, 20]

**MAC Operations (accumulate=1, FINAL):**
```
MAC[0][0]: 62 + (4×17) = 62 + 68 = 130
MAC[0][1]: 68 + (4×18) = 68 + 72 = 140
MAC[0][2]: 74 + (4×19) = 74 + 76 = 150
MAC[0][3]: 80 + (4×20) = 80 + 80 = 160

MAC[1][0]: 170 + (8×17) = 170 + 136 = 306
MAC[1][1]: 188 + (8×18) = 188 + 144 = 332
MAC[1][2]: 206 + (8×19) = 206 + 152 = 358
MAC[1][3]: 224 + (8×20) = 224 + 160 = 384

MAC[2][0]: 62 + (4×17) = 62 + 68 = 130
MAC[2][1]: 68 + (4×18) = 68 + 72 = 140
MAC[2][2]: 74 + (4×19) = 74 + 76 = 150
MAC[2][3]: 80 + (4×20) = 80 + 80 = 160

MAC[3][0]: 170 + (8×17) = 170 + 136 = 306
MAC[3][1]: 188 + (8×18) = 188 + 144 = 332
MAC[3][2]: 206 + (8×19) = 206 + 152 = 358
MAC[3][3]: 224 + (8×20) = 224 + 160 = 384
```

**FINAL RESULT:**
```
C = [130  140  150  160]
    [306  332  358  384]
    [130  140  150  160]
    [306  332  358  384]
```

**Verification:**
```
C[0][0] = 1×5 + 2×9 + 3×13 + 4×17 = 5 + 18 + 39 + 68 = 130 ✓
C[0][1] = 1×6 + 2×10 + 3×14 + 4×18 = 6 + 20 + 42 + 72 = 140 ✓
```

---

## 7. Timing and Parallelism

### 7.1 Clock Cycle Breakdown

**Per Pass:**
- **Load Data**: 16 cycles (read 4 A rows + 1 B row, 3 cycles each)
- **Distribute**: 1 cycle (cycle 15)
- **Compute**: 1 cycle (enable MAC)
- **Wait**: 1 cycle (disable MAC, prepare next pass)
- **Total per pass**: ~18 cycles

**Complete 4×4 Multiply:**
- 4 passes × 18 cycles = **72 cycles**

### 7.2 Parallelism Analysis

**At Each Compute Cycle:**
- **16 MACs** operating simultaneously
- **16 multiplications** in parallel
- **16 accumulations** in parallel (if accumulate=1)

**Total Operations:**
- 4 passes × 16 MACs = **64 MAC operations**
- All completed in **72 clock cycles**

**Throughput Breakdown:**

**Peak Throughput (During Compute Cycles):**
- **16 operations per cycle** (when MACs are enabled)
- This is the **actual parallelism** - all 16 MACs working simultaneously!

**Average Throughput (Including Overhead):**
- 64 operations / 72 cycles = **0.89 operations per cycle**
- This includes load time, wait time, etc.

**Why the Difference?**

The 0.89 number is **misleading**! Here's what's really happening:

```
Cycle Breakdown (per pass):
- Load Data:  16 cycles  (0 MAC operations - just loading)
- Distribute:  1 cycle   (0 MAC operations - just routing)
- Compute:     1 cycle   (16 MAC operations - PEAK PARALLELISM!)
- Wait:        1 cycle   (0 MAC operations - just waiting)
- Total:      18 cycles  (16 operations in 18 cycles)

Efficiency = 16 ops / 18 cycles = 0.89 ops/cycle (average)
BUT during the compute cycle: 16 ops/cycle (peak)!
```

**Key Insight:**
- **Peak Throughput**: 16 operations/cycle (during compute cycles)
- **Average Throughput**: 0.89 operations/cycle (including all overhead)
- **Efficiency**: 88.9% of cycles are overhead (loading/waiting), only 11.1% are actual computation

**This is normal for matrix multiplication!** The overhead comes from:
- Loading data from memory (16 cycles per pass)
- Data routing and distribution (1 cycle)
- State machine overhead (1 cycle wait)

**In a pipelined design**, you could overlap loading and computation to improve efficiency!

### 7.3 Timing Diagram

```
Cycle:  0    1    2    3  ...  15   16   17   18   19  ...  35   36   37
        |----LOAD_DATA----|    |COMP|WAIT|----LOAD_DATA----|    |COMP|WAIT|
        
Pass 0: [Load A[0..3][0] and B[0][0..3]] → [Compute] → [Wait]
Pass 1: [Load A[0..3][1] and B[1][0..3]] → [Compute] → [Wait]
Pass 2: [Load A[0..3][2] and B[2][0..3]] → [Compute] → [Wait]
Pass 3: [Load A[0..3][3] and B[3][0..3]] → [Compute] → [Wait] → [Write-Back]
```

---

## 8. Hardware Implementation

### 8.1 Multiplication Circuit

**8-bit × 8-bit Multiplier:**
- Typically implemented as:
  - **Combinational logic**: Array multiplier or Wallace tree
  - **DSP Slice** (in FPGAs): Hard multiplier (1 cycle)
  - **Booth Multiplier**: For signed numbers

**In our design:**
```verilog
assign product = a * b;  // Synthesizer chooses best implementation
```

### 8.2 Accumulator Circuit

**32-bit Adder:**
```verilog
assign next_result = accumulator + extended_product;
```

- **Combinational addition**: 32-bit ripple-carry or carry-lookahead adder
- **Registered output**: Stored in accumulator register

### 8.3 Control Signals

**Synchronous Control:**
```verilog
always @(posedge clk) begin
    if (enable) begin
        accumulator <= next_result;
        result <= next_result;
    end
end
```

**Key Points:**
- All operations are **synchronous** (clocked)
- `enable` controls when computation happens
- `accumulate` controls whether to add or replace

### 8.4 Resource Usage

**Per MAC Unit:**
- 1 × 8-bit multiplier
- 1 × 32-bit adder
- 1 × 32-bit accumulator register
- Control logic

**For 16 MAC Units:**
- 16 × multipliers
- 16 × adders
- 16 × 32-bit registers (512 bits total)
- Control logic

**Estimated FPGA Resources:**
- LUTs: ~2000-3000
- Registers: ~1500-2000
- DSP Slices: 16 (if using hard multipliers)

---

## Summary

**How Multiplication Works:**

1. **Single MAC Unit:**
   - Multiplies two 8-bit numbers → 16-bit product
   - Extends to 32 bits
   - Adds to accumulator (if enabled)
   - Stores result in register

2. **MAC Array:**
   - 16 MAC units in parallel
   - Each gets different input pair
   - All compute simultaneously
   - All accumulate simultaneously

3. **Matrix Multiplication:**
   - 4 passes (k = 0, 1, 2, 3)
   - Each pass: Load A column k and B row k
   - Distribute to all 16 MACs
   - Compute and accumulate
   - After 4 passes: Complete result

4. **Key Insight:**
   - **Parallelism**: 16 operations per cycle
   - **Efficiency**: 4-pass algorithm optimal for 4×4
   - **Speed**: ~72 cycles for complete 4×4 multiply

**The magic is in the parallelism - 16 MACs working together!** 🚀

