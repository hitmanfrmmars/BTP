# Matrix Multiply Controller Specification

## Your Requirements:

1. ✅ Unpack data from scratchpad to feed into 1 MAC unit (e.g., MU[0][0])
2. ✅ Do 4 passes to compute C[0][0]
3. ✅ Then do this for rest 15 MUs

## Additional Functions Needed:

### 4. **Address Generation for Matrix Elements**
For each pass k (0 to 3), need to calculate:
- **For A matrix:** Which scratchpad address has A[i][k]?
- **For B matrix:** Which scratchpad address has B[k][j]?

Example for computing C[0][1]:
```
Pass 0: Need A[0][0] and B[0][1]
Pass 1: Need A[0][1] and B[1][1]
Pass 2: Need A[0][2] and B[2][1]
Pass 3: Need A[0][3] and B[3][1]
```

### 5. **Parallel vs Sequential Strategy**
Decision: Compute all 16 elements simultaneously (parallel) or one at a time (sequential)?

**Option A - Parallel (Better Performance):**
- Load A[row] and B[column] for all 16 positions simultaneously
- All 16 MACs compute in parallel
- 4 passes total
- Faster but more complex data routing

**Option B - Sequential (Simpler):**
- Compute C[0][0], then C[0][1], then C[0][2]... one by one
- Use only one MAC unit at a time
- 16 elements × 4 passes = 64 cycles
- Simpler but slower

### 6. **Control Signal Generation**
- `mac_enable` - Enable MAC computation
- `mac_accumulate` - 0 for first pass (k=0), 1 for subsequent passes
- `spad_read_enable` - Request data from scratchpad
- `spad_address` - Which address to read

### 7. **Data Unpacking Logic**
Scratchpad returns 32-bit words, need to extract 8-bit values:
```
spad_data = 0x04030201
  ↓
a[0] = data[7:0]   = 0x01 = 1
a[1] = data[15:8]  = 0x02 = 2
a[2] = data[23:16] = 0x03 = 3
a[3] = data[31:24] = 0x04 = 4
```

### 8. **Synchronization & Timing**
- Wait for scratchpad read to complete (1 cycle latency)
- Wait for MAC computation (1 cycle latency)
- Coordinate transitions between passes

### 9. **Result Collection & Write-Back**
- Read results from MAC array
- Pack 8-bit or 32-bit results into words
- Write back to scratchpad
- Signal completion

### 10. **State Management**
Track current state:
- Which pass (k = 0, 1, 2, 3)?
- Which element being computed (i, j)?
- Loading, computing, or writing?

---

## Complete Function List:

```
┌─────────────────────────────────────────────────────┐
│          MATRIX MULTIPLY CONTROLLER                 │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Initialize                                      │
│     - Reset state machine                           │
│     - Configure matrix dimensions & addresses       │
│                                                     │
│  2. Address Calculation                             │
│     - Calculate A matrix scratchpad address         │
│     - Calculate B matrix scratchpad address         │
│     - Generate read addresses for each pass         │
│                                                     │
│  3. Data Loading (Per Pass)                         │
│     - Read A matrix row from scratchpad             │
│     - Read B matrix column from scratchpad          │
│     - Unpack 32-bit → 8-bit values                  │
│     - Route to appropriate MAC inputs               │
│                                                     │
│  4. MAC Control                                     │
│     - Set mac_enable                                │
│     - Set mac_accumulate (0 first, 1 after)         │
│     - Trigger computation                           │
│     - Wait for completion                           │
│                                                     │
│  5. Pass Iteration (k = 0 to 3)                     │
│     Pass 0: A[i][0] × B[0][j] → result              │
│     Pass 1: A[i][1] × B[1][j] → add to result       │
│     Pass 2: A[i][2] × B[2][j] → add to result       │
│     Pass 3: A[i][3] × B[3][j] → final result        │
│                                                     │
│  6. Element Iteration (all 16 or sequential)        │
│     - For each C[i][j], execute 4 passes            │
│     - Can do parallel (all 16 at once)              │
│     - Or sequential (one at a time)                 │
│                                                     │
│  7. Result Collection                               │
│     - Read final values from MAC result registers   │
│     - Pack into 32-bit words if needed              │
│                                                     │
│  8. Write-Back                                      │
│     - Write results to scratchpad                   │
│     - Generate write addresses                      │
│     - Signal write enable                           │
│                                                     │
│  9. Status Reporting                                │
│     - Assert 'busy' during operation                │
│     - Assert 'done' when complete                   │
│     - Error flags if needed                         │
│                                                     │
│ 10. Timing & Synchronization                        │
│     - Coordinate scratchpad read timing             │
│     - Coordinate MAC computation timing             │
│     - Handle pipeline delays                        │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## Detailed Operation Flow

### Computing C[0][0] as Example:

```
C[0][0] = A[0][0]×B[0][0] + A[0][1]×B[1][0] + A[0][2]×B[2][0] + A[0][3]×B[3][0]
```

**Pass 0: k=0**
```
Step 1: Calculate addresses
  A[0][0] is in scratchpad[0x000][7:0]
  B[0][0] is in scratchpad[0x010][7:0]

Step 2: Read from scratchpad
  spad_addr = 0x000, read A row 0
  spad_addr = 0x010, read B row 0

Step 3: Unpack data
  a_value = spad_data_a[7:0]   (element [0])
  b_value = spad_data_b[7:0]   (element [0])

Step 4: Load to MAC
  mac[0][0].a = a_value
  mac[0][0].b = b_value

Step 5: Compute
  mac_enable = 1
  mac_accumulate = 0  (first pass, reset)
  → mac[0][0].result = a_value × b_value
```

**Pass 1: k=1**
```
Step 1: Calculate addresses
  A[0][1] is in scratchpad[0x000][15:8]
  B[1][0] is in scratchpad[0x014][7:0]

Step 2: Read & unpack
  a_value = spad_data_a[15:8]  (element [1])
  b_value = spad_data_b[7:0]   (element [0] of row 1)

Step 3: Compute with accumulation
  mac_enable = 1
  mac_accumulate = 1  (add to previous)
  → mac[0][0].result = previous + (a_value × b_value)
```

**Pass 2 and 3: Similar...**

After 4 passes: `mac[0][0].result = C[0][0]` ✓

---

## Memory Layout Assumptions

### Input Matrices in Scratchpad:

```
Address    | Content              | Description
-----------|---------------------|------------------
0x000      | A[0][0..3]          | A matrix row 0 (4 bytes)
0x004      | A[1][0..3]          | A matrix row 1
0x008      | A[2][0..3]          | A matrix row 2
0x00C      | A[3][0..3]          | A matrix row 3

0x010      | B[0][0..3]          | B matrix row 0
0x014      | B[1][0..3]          | B matrix row 1
0x018      | B[2][0..3]          | B matrix row 2
0x01C      | B[3][0..3]          | B matrix row 3

0x020      | (Reserved for C)    | C matrix results
```

### Address Calculation Formulas:

```verilog
// For A[i][k]:
a_word_addr = A_BASE + (i * 4);      // Which word (row)
a_byte_sel  = k;                      // Which byte in word (column)

// For B[k][j]:
b_word_addr = B_BASE + (k * 4);      // Which word (row)
b_byte_sel  = j;                      // Which byte in word (column)

// For C[i][j]:
c_word_addr = C_BASE + (i * 4);
c_byte_sel  = j;
```

---

## State Machine Design

### High-Level States:

```
IDLE
  ↓ (start signal)
INIT
  ↓
COMPUTE_PASS_0  (k=0, load & multiply)
  ↓
COMPUTE_PASS_1  (k=1, load & MAC)
  ↓
COMPUTE_PASS_2  (k=2, load & MAC)
  ↓
COMPUTE_PASS_3  (k=3, load & MAC)
  ↓
WRITE_RESULTS
  ↓
DONE
  ↓
IDLE
```

### Detailed States Per Pass:

```
COMPUTE_PASS_k:
  ↓
READ_A        (request A data from scratchpad)
  ↓
WAIT_A        (wait for scratchpad latency)
  ↓
READ_B        (request B data from scratchpad)
  ↓
WAIT_B        (wait for scratchpad latency)
  ↓
LOAD_MAC      (unpack and load MAC inputs)
  ↓
COMPUTE       (enable MAC, wait for result)
  ↓
NEXT_PASS or WRITE_RESULTS
```

---

## Design Choices

### Choice 1: Parallel vs Sequential

**Recommended: Parallel (use all 16 MACs simultaneously)**

Advantages:
- 16× speedup
- Better hardware utilization
- More impressive demo!

Complexity:
- Need to route 16 pairs of values per pass
- More complex address generation
- Larger datapath

### Choice 2: Scratchpad Access Pattern

**Option A: Dual-Port Simultaneous Read**
- Read A and B in same cycle
- Faster (1 cycle per pass)
- Uses both scratchpad ports

**Option B: Sequential Read**
- Read A, then B (2 cycles per pass)
- Simpler control
- Only uses one port

---

## Inputs & Outputs

### Controller Inputs:
```verilog
input wire clk;
input wire rst;
input wire start;                    // Start matrix multiply
input wire [9:0] a_base_addr;        // Scratchpad address for A
input wire [9:0] b_base_addr;        // Scratchpad address for B
input wire [9:0] c_base_addr;        // Scratchpad address for C
```

### Controller Outputs:
```verilog
output reg done;                     // Operation complete
output reg busy;                     // Operation in progress

// Scratchpad control (Port B)
output reg [9:0] spad_addr_b;
output reg spad_re_b;
input wire [31:0] spad_rdata_b;

// MAC array control
output reg [7:0] a_matrix [0:3][0:3];
output reg [7:0] b_matrix [0:3][0:3];
output reg mac_enable;
output reg mac_accumulate;
input wire [31:0] result_matrix [0:3][0:3];
```

---

## Timing Estimate

### Parallel Implementation (all 16 MACs):

```
Initialization:        1 cycle
Pass 0 (k=0):
  Read A row 0:        1 cycle
  Read B row 0:        1 cycle
  Load MACs:           1 cycle
  Compute:             1 cycle
                       ------
  Subtotal:            4 cycles

Pass 1 (k=1):          4 cycles
Pass 2 (k=2):          4 cycles
Pass 3 (k=3):          4 cycles

Write results:         4 cycles (4 words)
                       ------
TOTAL:                ~21 cycles

For 4×4 matrix multiply!
At 100MHz: 210 nanoseconds!
```

### Sequential Implementation (1 MAC):

```
16 elements × 4 passes × 4 cycles/pass = 256 cycles
Still much faster than software!
```

---

## Summary: Complete Function List

**Your Original Functions:**
1. ✅ Unpack data from scratchpad to MAC
2. ✅ Do 4 passes to compute C[0][0]
3. ✅ Repeat for all 16 MUs

**Additional Functions I Added:**
4. ✅ Address calculation for A[i][k] and B[k][j]
5. ✅ Parallel vs sequential strategy
6. ✅ Control signal generation (enable, accumulate)
7. ✅ Data unpacking (32-bit → 8-bit)
8. ✅ Synchronization & timing coordination
9. ✅ Result collection & write-back to scratchpad
10. ✅ State machine management

---

## Ready to Implement?

I can create:
- **Option A:** Simple sequential controller (easier to understand)
- **Option B:** Parallel controller (better performance, all 16 MACs)
- **Option C:** Hybrid (parallel loading, configurable)

Which would you like me to implement? 🚀


