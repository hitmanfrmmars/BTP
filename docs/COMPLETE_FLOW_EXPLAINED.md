# Complete Flow: How Matrix Multiplication SHOULD Work

## Current Situation (Testbench - Hardcoded)

### What the Testbench Does:

```verilog
// Testbench can magically set all values at once:
a_matrix[0][0] = 2;
a_matrix[0][1] = 3;
a_matrix[0][2] = 4;
... (manually set all 16 values for A)
... (manually set all 16 values for B)

// Then tell MAC array: "GO!"
mac_enable = 1;

// MAC array computes immediately
// result_matrix[i][j] available next cycle
```

**This is like having a magic hand that can place 32 chess pieces on a board instantly!**

---

## Real Hardware Flow (What's Missing)

In real hardware, you can't "magically" set 32 values at once. You need to:
1. Store data in memory
2. Read it sequentially (a few bytes at a time)
3. Arrange it into the MAC array
4. Then compute

---

## Complete Flow: Step-by-Step Detailed Example

Let's multiply two 4×4 matrices:

```
Matrix A:              Matrix B:              Result C:
[1  2  3  4]          [9  10 11 12]          [To be computed]
[5  6  7  8]          [13 14 15 16]
[1  2  3  4]          [17 18 19 20]
[5  6  7  8]          [21 22 23 24]
```

---

### Phase 1: Data in Main Memory

```
Main Memory (starting at address 0x1000):
Address    | Data (4 bytes)           | Contains
-----------|--------------------------|------------------
0x1000     | 0x04030201               | A[0][0..3] = 1,2,3,4
0x1004     | 0x08070605               | A[1][0..3] = 5,6,7,8
0x1008     | 0x04030201               | A[2][0..3] = 1,2,3,4
0x100C     | 0x08070605               | A[3][0..3] = 5,6,7,8
0x1010     | 0x0C0B0A09               | B[0][0..3] = 9,10,11,12
0x1014     | 0x100F0E0D               | B[1][0..3] = 13,14,15,16
0x1018     | 0x14131211               | B[2][0..3] = 17,18,19,20
0x101C     | 0x18171615               | B[3][0..3] = 21,22,23,24

Total: 8 words (32 bytes) of data
```

---

### Phase 2: DMA Transfer to Scratchpad

**DMA Controller Configuration:**
```
src_addr  = 0x1000      (main memory start)
dst_addr  = 0x0000      (scratchpad start)
size      = 8 words     (32 bytes)
```

**DMA Operation (simplified, actually takes ~24 cycles):**

```
Cycle 1-3:   Read 0x1000 from main memory → Write to scratchpad[0x000]
Cycle 4-6:   Read 0x1004 from main memory → Write to scratchpad[0x004]
Cycle 7-9:   Read 0x1008 from main memory → Write to scratchpad[0x008]
Cycle 10-12: Read 0x100C from main memory → Write to scratchpad[0x00C]
Cycle 13-15: Read 0x1010 from main memory → Write to scratchpad[0x010]
Cycle 16-18: Read 0x1014 from main memory → Write to scratchpad[0x014]
Cycle 19-21: Read 0x1018 from main memory → Write to scratchpad[0x018]
Cycle 22-24: Read 0x101C from main memory → Write to scratchpad[0x01C]

Status: dma_done = 1
```

**Scratchpad Memory Now Contains:**
```
Scratchpad Address | Data
-------------------|------------------------
0x000              | 0x04030201  (A row 0)
0x004              | 0x08070605  (A row 1)
0x008              | 0x04030201  (A row 2)
0x00C              | 0x08070605  (A row 3)
0x010              | 0x0C0B0A09  (B row 0)
0x014              | 0x100F0E0D  (B row 1)
0x018              | 0x14131211  (B row 2)
0x01C              | 0x18171615  (B row 3)
```

---

### Phase 3: Data Loading Controller (MISSING!)

**This is what we DON'T have yet!**

The controller needs to:
1. Read from scratchpad (32-bit words)
2. Unpack into bytes (8-bit values)
3. Route to correct MAC unit positions
4. Do this for all 32 values

#### State Machine for Data Loader:

```
┌──────────┐
│   IDLE   │
└─────┬────┘
      │ start_load = 1
      ▼
┌──────────────┐
│  LOAD_A_ROW0 │ Read spad[0x000], unpack to a_matrix[0][0..3]
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  LOAD_A_ROW1 │ Read spad[0x004], unpack to a_matrix[1][0..3]
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  LOAD_A_ROW2 │ Read spad[0x008], unpack to a_matrix[2][0..3]
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  LOAD_A_ROW3 │ Read spad[0x00C], unpack to a_matrix[3][0..3]
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  LOAD_B_ROW0 │ Read spad[0x010], unpack to b_matrix[0][0..3]
└──────┬───────┘
       │
       ▼
     ... (4 more states for B rows)
       │
       ▼
┌──────────────┐
│  LOAD_DONE   │ Signal: data_ready = 1
└──────────────┘
```

**Detailed Operation of One State (LOAD_A_ROW0):**

```
State: LOAD_A_ROW0

Step 1: Set scratchpad read address
  spad_addr_b = 0x000
  spad_re_b = 1

Step 2: Wait 1 cycle for scratchpad read
  
Step 3: Scratchpad returns data
  spad_rdata_b = 0x04030201

Step 4: Unpack bytes and route to MAC array
  a_matrix[0][0] <= spad_rdata_b[7:0]    = 0x01 = 1
  a_matrix[0][1] <= spad_rdata_b[15:8]   = 0x02 = 2
  a_matrix[0][2] <= spad_rdata_b[23:16]  = 0x03 = 3
  a_matrix[0][3] <= spad_rdata_b[31:24]  = 0x04 = 4

Step 5: Move to next state (LOAD_A_ROW1)
```

**Total Loading Time:** ~8 cycles (one per scratchpad read)

---

### Phase 4: Matrix Multiplication

Now comes the tricky part - **actual matrix multiplication**!

#### Understanding Matrix Multiply:

```
C[i][j] = Σ(k=0 to 3) A[i][k] × B[k][j]

Example: C[0][0] = A[0][0]*B[0][0] + A[0][1]*B[1][0] + A[0][2]*B[2][0] + A[0][3]*B[3][0]
                 = 1*9 + 2*13 + 3*17 + 4*21
                 = 9 + 26 + 51 + 84
                 = 170
```

#### Problem: MAC Array Does Element-wise, Not Matrix Multiply!

**Current MAC Array:**
```verilog
// Does this:
result[i][j] = a_matrix[i][j] × b_matrix[i][j]  ← Element-wise!

// NOT this:
result[i][j] = Σ(k) a_matrix[i][k] × b_matrix[k][j]  ← Matrix multiply!
```

#### Solution: Multiple Passes with Data Reorganization

**For C[0][0], need 4 MAC operations:**

```
Pass 1: Load appropriate values
  a_matrix[0][0] = A[0][0] = 1
  b_matrix[0][0] = B[0][0] = 9
  
  mac_enable = 1
  mac_accumulate = 0  (start fresh)
  
  → result[0][0] = 1 × 9 = 9

Pass 2: Load next values
  a_matrix[0][0] = A[0][1] = 2
  b_matrix[0][0] = B[1][0] = 13
  
  mac_enable = 1
  mac_accumulate = 1  (add to previous)
  
  → result[0][0] = 9 + (2 × 13) = 35

Pass 3: Load next values
  a_matrix[0][0] = A[0][2] = 3
  b_matrix[0][0] = B[2][0] = 17
  
  mac_enable = 1
  mac_accumulate = 1
  
  → result[0][0] = 35 + (3 × 17) = 86

Pass 4: Load next values
  a_matrix[0][0] = A[0][3] = 4
  b_matrix[0][0] = B[3][0] = 21
  
  mac_enable = 1
  mac_accumulate = 1
  
  → result[0][0] = 86 + (4 × 21) = 170 ✓
```

**This is just for ONE element! Need to do this for all 16 elements!**

#### Matrix Multiply Controller State Machine:

```
For each output element C[i][j]:
  1. Reset accumulator
  2. For k = 0 to 3:
       - Load A[i][k] and B[k][j] into appropriate MAC
       - Enable MAC with accumulate flag
  3. Read result from MAC
  4. Write result to scratchpad

Total: 16 elements × 4 operations each = 64 MAC operations
With parallelism: Can compute 16 elements simultaneously!
Cycles needed: ~4 passes
```

---

### Phase 5: Write Results Back

**After computation, results are in MAC array:**

```
result_matrix[0][0] = 170
result_matrix[0][1] = 180
... (16 total results)
```

**Controller writes to scratchpad:**

```
State: WRITE_RESULTS

For i = 0 to 3:
  For j = 0 to 3:
    Pack results into 32-bit word
    Write to scratchpad

Example (writing row 0):
  Pack: result[0][0], result[0][1], result[0][2], result[0][3]
  Into: 32-bit word
  Write: to scratchpad[0x020]
```

**Scratchpad now has:**
```
Address | Data                  | Contains
--------|----------------------|------------------
0x020   | Packed C[0][0..3]   | Result row 0
0x024   | Packed C[1][0..3]   | Result row 1
0x028   | Packed C[2][0..3]   | Result row 2
0x02C   | Packed C[3][0..3]   | Result row 3
```

---

### Phase 6: DMA Results Back to Main Memory

**DMA Configuration:**
```
src_addr  = 0x0020      (scratchpad results)
dst_addr  = 0x2000      (main memory destination)
size      = 4 words     (16 bytes)
```

**DMA copies results back:**
```
Scratchpad → Main Memory

Main Memory 0x2000 now contains computed matrix C
```

---

## Complete Flow Timeline

```
Cycle Range | Phase                          | Who's Working
------------|--------------------------------|---------------
0-24        | DMA: Main → Scratchpad         | DMA Controller
25-32       | Load data into MAC array       | Data Loader ❌ MISSING
33-36       | MAC computation (4 passes)     | MAC Array + Controller ❌ MISSING
37-44       | Write results to scratchpad    | Data Loader ❌ MISSING
45-57       | DMA: Scratchpad → Main         | DMA Controller

Total: ~57 cycles for 4×4 matrix multiply

Without hardware: ~1000+ cycles in software!
Speedup: ~20× faster!
```

---

## What's Missing: The Controllers

### 1. Data Loading Controller
**Job:** Move data from scratchpad memory into MAC array registers

**Pseudocode:**
```
module mac_data_loader (
    input  start_load,
    input  [9:0] spad_base_addr,
    output reg [7:0] a_matrix[0:3][0:3],
    output reg [7:0] b_matrix[0:3][0:3],
    output reg done
);

state machine:
    IDLE → LOAD_A_ROW0 → LOAD_A_ROW1 → LOAD_A_ROW2 → LOAD_A_ROW3
         → LOAD_B_ROW0 → LOAD_B_ROW1 → LOAD_B_ROW2 → LOAD_B_ROW3
         → DONE

each state:
    - Read 32-bit word from scratchpad
    - Unpack 4 bytes
    - Route to appropriate matrix positions
```

### 2. Matrix Multiplication Controller
**Job:** Orchestrate multiple MAC operations to perform actual matrix multiply

**Pseudocode:**
```
module matrix_multiply_controller (
    input  start,
    output reg mac_enable,
    output reg mac_accumulate,
    control data loading for each pass,
    output reg done
);

For computing C = A × B:
    for each output row i (0 to 3):
        for each output col j (0 to 3):
            reset MAC[i][j]
            for k (0 to 3):  // dot product
                load A[i][k] into MAC[i][j].a
                load B[k][j] into MAC[i][j].b
                enable MAC with accumulate
            read result from MAC[i][j]
            store result
```

### 3. Top-Level Sequencer
**Job:** Coordinate all phases

**Pseudocode:**
```
State machine:
    IDLE
    → DMA_LOAD (wait for DMA)
    → LOAD_DATA (wait for data loader)
    → COMPUTE (wait for matrix controller)
    → WRITE_BACK (write results)
    → DMA_STORE (wait for DMA)
    → DONE
```

---

## Comparison: Testbench vs Real Hardware

| Aspect | Testbench (Now) | Real Hardware (Needed) |
|--------|----------------|------------------------|
| Data Source | Hardcoded in Verilog | From main memory |
| Data Transfer | Instant (magic) | DMA + controllers |
| Data Loading | All 32 at once | 8 reads, unpacking |
| MAC Control | Manual enable | Automated controller |
| Timing | Immediate | ~50+ cycles total |
| Realistic | No | Yes |

---

## Summary

### What We Tested (Hardcoded):
```
Testbench: 
  ↓ (magic assignment)
MAC Array
  ↓ (immediate computation)
Results
```

### What Real Hardware Needs:
```
Main Memory
  ↓ (DMA)
Scratchpad
  ↓ (Data Loader Controller) ❌ MISSING
MAC Array
  ↓ (Matrix Multiply Controller) ❌ MISSING
Results in MAC Array
  ↓ (Write Back Controller) ❌ MISSING
Scratchpad
  ↓ (DMA)
Main Memory
```

---

## Next Steps to Build Complete Flow

**Option 1: Build Simple Data Loader**
- Just load data from scratchpad to MAC array
- Don't worry about matrix multiply yet
- Test that data routing works

**Option 2: Build Matrix Multiply Controller**
- Assume data is already in MAC array
- Orchestrate multiple passes for dot products
- Compute one 4×4 matrix multiply

**Option 3: Build Complete System**
- All controllers
- End-to-end flow
- Full integration

**Which would you like to tackle first?** 🤔

The good news: **Your MAC hardware works!** Now we just need the "traffic cop" to direct data flow! 🚦


