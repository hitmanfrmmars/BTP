# Matrix Multiply Controller - Complete Build Plan

## Project Goal
Build a controller that orchestrates 16 MAC units to perform 4×4 matrix multiplication using data from scratchpad memory.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                MATRIX MULTIPLY CONTROLLER                    │
│                                                              │
│  ┌────────────┐    ┌──────────────┐    ┌────────────┐     │
│  │   State    │───▶│   Address    │───▶│   Data     │     │
│  │  Machine   │    │  Calculator  │    │   Loader   │     │
│  └────────────┘    └──────────────┘    └────────────┘     │
│         │                  │                   │            │
│         ▼                  ▼                   ▼            │
│  ┌────────────┐    ┌──────────────┐    ┌────────────┐     │
│  │Pass Counter│───▶│     MAC      │───▶│  Result    │     │
│  │  (k=0..3)  │    │   Control    │    │ Write-Back │     │
│  └────────────┘    └──────────────┘    └────────────┘     │
└─────────────────────────────────────────────────────────────┘
         ▲                                          │
         │                                          ▼
    ┌─────────┐                            ┌──────────────┐
    │ Control │                            │  Scratchpad  │
    │ Inputs  │                            │    Memory    │
    └─────────┘                            └──────────────┘
                                                   │
                                                   ▼
                                           ┌──────────────┐
                                           │  MAC Array   │
                                           │   (4×4)      │
                                           └──────────────┘
```

---

## Step-by-Step Build Plan

### **STEP 1: State Machine Skeleton** (Foundation)
**Goal:** Create basic state machine framework

**What We'll Build:**
```verilog
module matmul_controller (
    input wire clk,
    input wire rst,
    input wire start,
    output reg done,
    output reg busy
);

States:
    IDLE          - Waiting for start
    INIT          - Initialize counters
    LOAD_DATA     - Read from scratchpad
    COMPUTE       - Enable MACs
    WRITE_BACK    - Write results
    DONE_STATE    - Signal completion
```

**What We'll Test:**
- Reset puts us in IDLE
- `start` signal triggers INIT
- States transition: IDLE → INIT → LOAD_DATA → COMPUTE → WRITE_BACK → DONE → IDLE
- `busy` goes high during operation
- `done` pulses when complete

**Test Method:**
- Simple testbench that asserts start
- Monitor state transitions
- Verify timing

**Expected Result:**
```
Cycle 0-10:  State = IDLE, busy=0, done=0
Cycle 11:    start=1
Cycle 12:    State = INIT, busy=1
Cycle 13:    State = LOAD_DATA
Cycle 14:    State = COMPUTE
Cycle 15:    State = WRITE_BACK
Cycle 16:    State = DONE_STATE, done=1
Cycle 17:    State = IDLE, busy=0
```

**Files Created:**
- `rtl/matmul_controller.v` (basic skeleton)
- `testbench/tb_matmul_step1.v`

**Time Estimate:** 10 minutes

---

### **STEP 2: Address Calculation** (Brain)
**Goal:** Add logic to calculate scratchpad addresses for A[i][k] and B[k][j]

**What We'll Build:**
```verilog
// Inputs
input wire [9:0] a_base_addr;   // Where A matrix starts (e.g., 0x000)
input wire [9:0] b_base_addr;   // Where B matrix starts (e.g., 0x010)

// Functions
function [9:0] calc_a_addr;
    input [1:0] row;    // i
    input [1:0] col;    // k
    begin
        // A[i][k] is in word (A_BASE + i*4), byte k
        calc_a_addr = a_base_addr + (row << 2);
    end
endfunction

function [1:0] calc_a_byte;
    input [1:0] col;    // k
    begin
        calc_a_byte = col;  // Which byte in the word
    end
endfunction

// Similar for B matrix
```

**Address Mapping:**
```
For 4×4 matrix stored row-wise:

A Matrix (base = 0x000):
  A[0][0..3] at 0x000, bytes [0][1][2][3]
  A[1][0..3] at 0x004, bytes [0][1][2][3]
  A[2][0..3] at 0x008, bytes [0][1][2][3]
  A[3][0..3] at 0x00C, bytes [0][1][2][3]

B Matrix (base = 0x010):
  B[0][0..3] at 0x010, bytes [0][1][2][3]
  B[1][0..3] at 0x014, bytes [0][1][2][3]
  B[2][0..3] at 0x018, bytes [0][1][2][3]
  B[3][0..3] at 0x01C, bytes [0][1][2][3]
```

**What We'll Test:**
```
Test calc_a_addr(0, 0) = 0x000  ✓ (A[0][0])
Test calc_a_addr(0, 1) = 0x000, byte 1  ✓ (A[0][1])
Test calc_a_addr(1, 2) = 0x004, byte 2  ✓ (A[1][2])
Test calc_b_addr(2, 3) = 0x018, byte 3  ✓ (B[2][3])
```

**Test Method:**
- Testbench calls address functions with various i,j,k
- Compares against expected addresses
- Prints table of all addresses

**Expected Result:**
```
Address Calculation Test:
  A[0][0]: addr=0x000, byte=0 ✓
  A[0][1]: addr=0x000, byte=1 ✓
  A[1][0]: addr=0x004, byte=0 ✓
  B[2][3]: addr=0x018, byte=3 ✓
  All 32 addresses correct!
```

**Files Modified:**
- `rtl/matmul_controller.v` (add address functions)
- `testbench/tb_matmul_step2.v` (test addresses)

**Time Estimate:** 15 minutes

---

### **STEP 3: Single Data Load (One Element)** (First Real Work)
**Goal:** Read one element from scratchpad and unpack it

**What We'll Build:**
```verilog
// Scratchpad interface
output reg [9:0] spad_addr;
output reg spad_re;
input wire [31:0] spad_rdata;

// Internal
reg [7:0] loaded_value;

// In LOAD_DATA state:
case (load_step)
    0: begin
        spad_addr <= calc_a_addr(0, 0);  // Request A[0][0]
        spad_re <= 1'b1;
        load_step <= 1;
    end
    1: begin
        // Wait for scratchpad (1 cycle latency)
        spad_re <= 1'b0;
        load_step <= 2;
    end
    2: begin
        // Unpack the byte we need
        loaded_value <= spad_rdata[7:0];  // Byte 0
        load_step <= 0;
        state <= COMPUTE;
    end
endcase
```

**What We'll Test:**
- Load A[0][0] from scratchpad
- Verify correct address is generated
- Verify correct byte is extracted
- Test with known scratchpad data

**Test Setup:**
```verilog
// Pre-load scratchpad with test data
scratchpad.memory[0] = 32'h04030201;  // A[0]=[1,2,3,4]
scratchpad.memory[1] = 32'h08070605;  // A[1]=[5,6,7,8]

// Test loading A[0][0]
Expected: loaded_value = 8'd1  ✓

// Test loading A[0][1]
Expected: loaded_value = 8'd2  ✓
```

**Expected Result:**
```
Loading A[0][0]:
  Cycle 1: Request addr=0x000
  Cycle 2: Wait for scratchpad
  Cycle 3: Receive 0x04030201
  Cycle 4: Extract byte[0] = 0x01 = 1 ✓
```

**Files Modified:**
- `rtl/matmul_controller.v` (add scratchpad read logic)
- `testbench/tb_matmul_step3.v`

**Time Estimate:** 20 minutes

---

### **STEP 4: Single MAC Operation** (First Computation)
**Goal:** Load two values and compute one multiply

**What We'll Build:**
```verilog
// MAC interface (simplified - one MAC for now)
output reg [7:0] mac_a;
output reg [7:0] mac_b;
output reg mac_enable;
output reg mac_accumulate;
input wire [31:0] mac_result;

// Load A[0][0] and B[0][0], compute product
State COMPUTE:
    mac_a <= loaded_a_value;
    mac_b <= loaded_b_value;
    mac_enable <= 1'b1;
    mac_accumulate <= 1'b0;  // First operation
    state <= WAIT_MAC;

State WAIT_MAC:
    mac_enable <= 1'b0;
    // Result ready next cycle
    state <= DONE_STATE;
```

**What We'll Test:**
```
Load A[0][0] = 2
Load B[0][0] = 3
Compute: 2 × 3 = 6
Verify: mac_result = 6  ✓
```

**Test Method:**
- Pre-load scratchpad with known values
- Trigger controller
- Monitor MAC inputs (a, b)
- Monitor MAC output (result)
- Verify computation

**Expected Result:**
```
Single MAC Test:
  Loaded A[0][0] = 2 ✓
  Loaded B[0][0] = 3 ✓
  MAC computed: 2 × 3 = 6 ✓
  Result correct!
```

**Files Modified:**
- `rtl/matmul_controller.v` (add MAC control)
- `testbench/tb_matmul_step4.v`

**Time Estimate:** 15 minutes

---

### **STEP 5: Four-Pass Dot Product** (Core Algorithm)
**Goal:** Compute C[0][0] = A[0][0]×B[0][0] + A[0][1]×B[1][0] + A[0][2]×B[2][0] + A[0][3]×B[3][0]

**What We'll Build:**
```verilog
reg [1:0] pass_counter;  // 0, 1, 2, 3

// For each pass k:
Pass 0: Load A[0][0], B[0][0], multiply (accumulate=0)
Pass 1: Load A[0][1], B[1][0], MAC (accumulate=1)
Pass 2: Load A[0][2], B[2][0], MAC (accumulate=1)
Pass 3: Load A[0][3], B[3][0], MAC (accumulate=1)

State machine:
    INIT: pass_counter = 0
    LOAD_PASS: Load A[0][k] and B[k][0]
    COMPUTE_PASS: MAC with accumulate=(k>0)
    if (pass_counter < 3)
        pass_counter++
        goto LOAD_PASS
    else
        goto DONE_STATE
```

**What We'll Test:**
```
Example: Compute C[0][0]
A[0] = [1, 2, 3, 4]
B column 0 = [5, 6, 7, 8]

Pass 0: 1×5 = 5       result = 5
Pass 1: 5 + 2×6 = 17  result = 17
Pass 2: 17 + 3×7 = 38 result = 38
Pass 3: 38 + 4×8 = 70 result = 70 ✓

Expected: C[0][0] = 70
```

**Test Method:**
- Pre-load scratchpad with test matrices
- Trigger controller
- Monitor pass counter
- Monitor accumulation after each pass
- Verify final result

**Expected Result:**
```
Four-Pass Dot Product Test:
  Pass 0: A[0][0]=1, B[0][0]=5 → result=5 ✓
  Pass 1: A[0][1]=2, B[1][0]=6 → result=17 ✓
  Pass 2: A[0][2]=3, B[2][0]=7 → result=38 ✓
  Pass 3: A[0][3]=4, B[3][0]=8 → result=70 ✓
  Final C[0][0] = 70 ✓
```

**Files Modified:**
- `rtl/matmul_controller.v` (add pass loop)
- `testbench/tb_matmul_step5.v`

**Time Estimate:** 20 minutes

---

### **STEP 6: Parallel Loading (All 16 MACs)** (Scale Up)
**Goal:** Extend to compute all 16 elements simultaneously

**What We'll Build:**
```verilog
// Full MAC array interface
output reg [7:0] a_matrix [0:3][0:3];
output reg [7:0] b_matrix [0:3][0:3];
input wire [31:0] result_matrix [0:3][0:3];

// For each pass k, load all 16 pairs:
Pass k:
    Load entire A (all 4 rows)
    Load entire B (row k only, but broadcast to columns)
    
    For all i,j:
        a_matrix[i][j] = A[i][k]
        b_matrix[i][j] = B[k][j]
```

**Data Distribution Pattern:**
```
Pass 0 (k=0):
  All MACs need B[0][j], so load B row 0
  
  MAC[0][0]: a=A[0][0], b=B[0][0]
  MAC[0][1]: a=A[0][0], b=B[0][1]
  MAC[0][2]: a=A[0][0], b=B[0][2]
  MAC[0][3]: a=A[0][0], b=B[0][3]
  
  MAC[1][0]: a=A[1][0], b=B[0][0]
  ... etc for all 16

Pass 1 (k=1):
  Load B row 1
  Each MAC gets A[i][1] and B[1][j]
```

**Loading Strategy:**
```verilog
// Load A column k into all MAC rows
for i = 0 to 3:
    Read A[i][k]
    
    // Distribute A[i][k] across row i
    a_matrix[i][0] = A[i][k]
    a_matrix[i][1] = A[i][k]  // Same value!
    a_matrix[i][2] = A[i][k]
    a_matrix[i][3] = A[i][k]

// Load B row k into all MAC columns
Read B[k][0..3]

// Distribute B[k][j] down column j
for j = 0 to 3:
    b_matrix[0][j] = B[k][j]
    b_matrix[1][j] = B[k][j]  // Same value!
    b_matrix[2][j] = B[k][j]
    b_matrix[3][j] = B[k][j]
```

**What We'll Test:**
```
Small test matrix:
A = [1 2]    B = [5 6]
    [3 4]        [7 8]

Expected:
C = [19 22]
    [43 50]

Verify all 4 elements computed correctly
```

**Expected Result:**
```
Parallel MAC Test:
  Pass 0 complete: partial results
  Pass 1 complete: final results
  
  C[0][0] = 19 ✓
  C[0][1] = 22 ✓
  C[1][0] = 43 ✓
  C[1][1] = 50 ✓
  
  All 16 MACs working in parallel!
```

**Files Modified:**
- `rtl/matmul_controller.v` (extend to 4×4)
- `testbench/tb_matmul_step6.v`

**Time Estimate:** 30 minutes

---

### **STEP 7: Result Write-Back** (Close the Loop)
**Goal:** Write computed results back to scratchpad

**What We'll Build:**
```verilog
output reg [9:0] spad_waddr;
output reg [31:0] spad_wdata;
output reg spad_we;

State WRITE_BACK:
    for row = 0 to 3:
        // Pack 4 results into one word
        spad_wdata = {result[row][3], result[row][2], 
                      result[row][1], result[row][0]};
        spad_waddr = c_base_addr + (row << 2);
        spad_we = 1'b1;
        wait 1 cycle
```

**What We'll Test:**
- Compute a simple matrix multiply
- Verify results written to correct addresses
- Read back from scratchpad
- Compare with expected

**Test Setup:**
```
C_BASE = 0x020

After computation:
  Scratchpad[0x020] should contain C[0][0..3]
  Scratchpad[0x024] should contain C[1][0..3]
  Scratchpad[0x028] should contain C[2][0..3]
  Scratchpad[0x02C] should contain C[3][0..3]
```

**Expected Result:**
```
Write-Back Test:
  Writing C[0] to 0x020: [19,22,43,50] ✓
  Memory[0x020] = 0x32165013 ✓
  All results written correctly!
```

**Files Modified:**
- `rtl/matmul_controller.v` (add write-back)
- `testbench/tb_matmul_step7.v`

**Time Estimate:** 20 minutes

---

### **STEP 8: Full Integration** (Put It All Together)
**Goal:** Complete end-to-end 4×4 matrix multiplication

**What We'll Build:**
- Integrate controller with existing top.v
- Connect to DMA, scratchpad, MAC array
- Complete data flow

**Integration Points:**
```verilog
module top (
    // DMA brings data from main memory → scratchpad
    dma_controller dma_inst (...);
    
    // Scratchpad holds data
    scratchpad_mem spad_inst (...);
    
    // NEW: Controller orchestrates computation
    matmul_controller ctrl_inst (
        .a_base_addr(10'h000),
        .b_base_addr(10'h010),
        .c_base_addr(10'h020),
        ...
    );
    
    // MAC array does computation
    mac_array mac_inst (...);
);
```

**What We'll Test:**
```
Complete Flow:
1. DMA loads matrices A and B into scratchpad
2. Controller reads A and B
3. Controller orchestrates 4 passes
4. MAC array computes all 16 elements
5. Controller writes results to scratchpad
6. DMA writes results back to main memory

End-to-end verification!
```

**Test Matrices:**
```
A = [1  2  3  4]
    [5  6  7  8]
    [1  2  3  4]
    [5  6  7  8]

B = [9  10 11 12]
    [13 14 15 16]
    [17 18 19 20]
    [21 22 23 24]

Expected C (compute manually to verify)
```

**Expected Result:**
```
End-to-End Test:
  ✓ DMA loaded A and B
  ✓ Controller computed for 4 passes
  ✓ All 16 elements correct
  ✓ Results written back
  ✓ Complete matrix multiply in ~50 cycles
  
  SUCCESS: Hardware accelerator working!
```

**Files Modified:**
- `rtl/top.v` (integrate controller)
- `testbench/tb_top_complete.v`

**Time Estimate:** 30 minutes

---

## Summary Timeline

| Step | Task | Time | Cumulative |
|------|------|------|------------|
| 1 | State machine skeleton | 10 min | 10 min |
| 2 | Address calculation | 15 min | 25 min |
| 3 | Single data load | 20 min | 45 min |
| 4 | Single MAC operation | 15 min | 60 min |
| 5 | Four-pass dot product | 20 min | 80 min |
| 6 | Parallel (16 MACs) | 30 min | 110 min |
| 7 | Result write-back | 20 min | 130 min |
| 8 | Full integration | 30 min | 160 min |

**Total Estimated Time: ~2.5-3 hours** (with testing at each step)

---

## Testing Strategy

### After Each Step:
1. ✅ **Compile** - No syntax errors
2. ✅ **Simulate** - Run step-specific testbench
3. ✅ **Verify** - Check expected behavior
4. ✅ **Debug** - Fix any issues before proceeding
5. ✅ **Document** - Note what works

### Incremental Verification:
- Step 1: States transition correctly
- Step 2: Addresses are correct
- Step 3: Data loads correctly
- Step 4: One MAC works
- Step 5: Dot product works
- Step 6: All 16 MACs work
- Step 7: Write-back works
- Step 8: Everything together works

---

## Key Design Decisions

### 1. **Parallel Processing**
- All 16 MACs compute simultaneously
- 4 passes for 4×4 matrices
- Maximum hardware utilization

### 2. **Memory Layout**
- A matrix at base + 0x000
- B matrix at base + 0x010
- C matrix at base + 0x020
- Row-major storage (contiguous rows)

### 3. **Data Distribution**
- Each pass loads full A column and B row
- Broadcast A[i][k] across MAC row i
- Broadcast B[k][j] down MAC column j

### 4. **Timing**
- 1 cycle scratchpad read latency
- 1 cycle MAC computation latency
- ~4 cycles per pass
- ~21 cycles total for 4×4 multiply

---

## Files We'll Create/Modify

### New Files:
```
rtl/matmul_controller.v          Main controller
testbench/tb_matmul_step1.v       Step 1 test
testbench/tb_matmul_step2.v       Step 2 test
testbench/tb_matmul_step3.v       Step 3 test
testbench/tb_matmul_step4.v       Step 4 test
testbench/tb_matmul_step5.v       Step 5 test
testbench/tb_matmul_step6.v       Step 6 test
testbench/tb_matmul_step7.v       Step 7 test
testbench/tb_top_complete.v       Final integration test
test_step1.bat ... test_step8.bat Test scripts
```

### Modified Files:
```
rtl/top.v                         Integrate controller
```

---

## Success Criteria

### By End of Each Step:
- ✅ Code compiles without errors
- ✅ Testbench runs to completion
- ✅ All tests pass
- ✅ Ready for next step

### Final Success:
- ✅ Complete 4×4 matrix multiplication
- ✅ All 16 elements correct
- ✅ ~20-25 cycles execution time
- ✅ Verified with multiple test matrices
- ✅ Integrated with DMA and scratchpad

---

## Ready to Begin?

**Next Action:** Implement Step 1 - State Machine Skeleton

Shall we start? 🚀


