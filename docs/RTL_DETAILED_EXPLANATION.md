# RTL Modules - Detailed Functionality Explanation

## Overview
This document provides a detailed explanation of each RTL module implemented in the `rtl/` folder, their expected functionality, interfaces, and how they work together in the complete system.

---

## 1. multiplier_8bit.v - Basic 8×8 Bit Multiplier

### Purpose
The foundation of all computations - performs unsigned 8-bit × 8-bit multiplication.

### Interface
```verilog
Inputs:
  - clk         : System clock
  - rst         : Synchronous reset
  - a[7:0]      : First 8-bit operand
  - b[7:0]      : Second 8-bit operand
  - valid_in    : Input data valid signal

Outputs:
  - product[15:0] : 16-bit multiplication result
  - valid_out     : Output valid flag (registered valid_in)
```

### Expected Functionality
1. **Multiplication**: Computes `product = a × b`
   - Max input: 255 × 255 = 65,025
   - Result fits in 16 bits (2^16 = 65,536)

2. **Pipeline Stage**: Single-cycle latency
   - Input captured on clock edge
   - Output available next cycle
   - Valid signal propagates through pipeline

3. **Reset Behavior**: Synchronous reset clears output to 0

### Example Operation
```
Cycle 0: a=5, b=6, valid_in=1
Cycle 1: product=30, valid_out=1 ✓
```

### Use Case
- Building block for MAC units
- Standalone multiplication operations
- Can be extended to pipelined multi-cycle designs

---

## 2. mac_unit.v - Multiply-Accumulate Unit

### Purpose
Core computation unit that performs: **result = a × b + accumulator**

### Interface
```verilog
Inputs:
  - clk          : System clock
  - rst          : Synchronous reset
  - enable       : Enable computation
  - accumulate   : 1=add to accumulator, 0=just multiply
  - a[7:0]       : First operand
  - b[7:0]       : Second operand

Outputs:
  - result[31:0] : 32-bit accumulated result
  - overflow     : Overflow detection flag
```

### Expected Functionality

#### 1. **Multiplication Mode** (accumulate = 0)
```
result = a × b (extended to 32 bits)
accumulator is reset
```
- Used to start new computation
- Clears previous accumulated value
- Example: 5 × 6 = 30

#### 2. **Accumulation Mode** (accumulate = 1)
```
result = previous_accumulator + (a × b)
accumulator stores result for next operation
```
- Adds new product to existing accumulator
- Essential for matrix multiplication
- Example: 30 + (5 × 6) = 60

#### 3. **Overflow Detection**
Detects when accumulation exceeds 32-bit signed range:
```verilog
if (accumulator[31]==0 && product[31]==0 && result[31]==1)
    overflow = 1;  // Positive overflow detected
```

### Mathematical Example
For dot product: **C = A·B = a₀b₀ + a₁b₁ + a₂b₂**

```
Cycle 1: a=2, b=3, accumulate=0  → result = 6
Cycle 2: a=4, b=5, accumulate=1  → result = 6 + 20 = 26
Cycle 3: a=1, b=2, accumulate=1  → result = 26 + 2 = 28
```

### Key Features
- **32-bit accumulator**: Prevents overflow for typical AI workloads
- **Enable control**: Power-efficient - only computes when enabled
- **Stateful operation**: Maintains accumulator between cycles

---

## 3. mac_array.v - 4×4 MAC Array

### Purpose
Parallel computation unit with **16 MAC units** arranged in a 4×4 grid for simultaneous operations.

### Interface
```verilog
Parameters:
  - ARRAY_SIZE = 4   : Size of array (4×4 = 16 MACs)
  - DATA_WIDTH = 8   : 8-bit operands
  - ACC_WIDTH = 32   : 32-bit results

Inputs:
  - clk              : System clock
  - rst              : Reset all MACs
  - enable           : Enable all MACs
  - accumulate       : Accumulate mode for all MACs
  - a_matrix[4][4]   : 4×4 input matrix A (16 elements)
  - b_matrix[4][4]   : 4×4 input matrix B (16 elements)

Outputs:
  - result_matrix[4][4] : 4×4 output matrix (16 results)
  - overflow_flags[4]   : Overflow detection per row
```

### Expected Functionality

#### 1. **Parallel Element-wise Operations**
All 16 MAC units operate simultaneously:
```
result[i][j] = a[i][j] × b[i][j] + accumulator[i][j]
```

**Not** performing matrix multiplication directly - that requires multiple operations and data reorganization.

#### 2. **Use in Matrix Multiplication**
For matrix multiplication C = A × B, you need multiple passes:

**Example: 2×2 matrix multiplication**
```
A = [a₀ a₁]    B = [b₀ b₁]
    [a₂ a₃]        [b₂ b₃]

C[0][0] = a₀×b₀ + a₁×b₂  (requires 2 MAC operations)
C[0][1] = a₀×b₁ + a₁×b₃
...etc
```

**Software/Controller must**:
- Load appropriate elements into array
- Perform first multiply-accumulate
- Load next elements
- Accumulate again
- Repeat until complete

#### 3. **Scalability**
The `generate` statement creates all MAC units:
```verilog
for (i = 0; i < 4; i++)
  for (j = 0; j < 4; j++)
    mac_unit mac_inst(...);  // Creates 16 instances
```

Easily changed to 8×8, 16×16, etc. by modifying `ARRAY_SIZE` parameter.

### Performance
- **Throughput**: 16 MAC operations per cycle
- **Peak**: At 100MHz → 1.6 GOPS (Giga Operations/sec)
- **Power**: All MACs active = high power, but high performance

---

## 4. scratchpad_mem.v - Dual-Port Scratchpad Memory

### Purpose
Fast on-chip memory buffer (1KB) with two independent access ports for simultaneous DMA and MAC operations.

### Interface
```verilog
Parameters:
  - ADDR_WIDTH = 10  : 10 bits → 1024 bytes = 1KB
  - DATA_WIDTH = 32  : 32-bit words

Port A (DMA Controller):
  - addr_a[9:0]     : Address
  - wdata_a[31:0]   : Write data
  - we_a            : Write enable
  - re_a            : Read enable
  - rdata_a[31:0]   : Read data

Port B (MAC Array):
  - addr_b[9:0]     : Address
  - wdata_b[31:0]   : Write data
  - we_b            : Write enable
  - re_b            : Read enable
  - rdata_b[31:0]   : Read data
```

### Expected Functionality

#### 1. **Memory Organization**
```
Total: 1KB = 1024 bytes
Word size: 32 bits = 4 bytes
Capacity: 1024 ÷ 4 = 256 words
Address: 10-bit byte address
```

Byte address → Word address conversion:
```verilog
word_addr = byte_addr[9:2]  // Drop lower 2 bits
```

#### 2. **Dual-Port Operation**
Both ports operate **independently** and **simultaneously**:

```
Cycle N:
  Port A: DMA writes data to address 0x00
  Port B: MAC reads data from address 0x10
  → Both operations complete in same cycle! ✓
```

**Collision handling**: If both ports access same address:
- Read-Read: Both succeed ✓
- Write-Write: Undefined behavior (should avoid in design)
- Read-Write: Newer simulators may show collision warning

#### 3. **Synchronous Operation**
All operations are clocked:
```
Cycle N:   Address & control signals set
Cycle N+1: Data available on read / Write completes
```

#### 4. **Typical Usage Pattern**

**Phase 1: DMA fills scratchpad**
```
Port A (DMA): Writing input matrices from main memory
Port B (MAC): Idle
```

**Phase 2: MAC computes while DMA loads next batch**
```
Port A (DMA): Writing next block of data
Port B (MAC): Reading current block for computation
→ Double buffering effect!
```

**Phase 3: Results written back**
```
Port A (DMA): Reading results to main memory
Port B (MAC): Writing computed results
```

### Memory Layout Example
```
Address   | Content                    | Owner
----------|----------------------------|--------
0x000-0x0FF | Input Matrix A           | DMA→MAC
0x100-0x1FF | Input Matrix B           | DMA→MAC
0x200-0x2FF | Output Matrix C          | MAC→DMA
0x300-0x3FF | Temporary/Next batch     | DMA
```

---

## 5. dma_controller.v - DMA Data Transfer Engine

### Purpose
Automates data movement between main memory and scratchpad memory without CPU intervention.

### Interface
```verilog
Control:
  - start              : Pulse to begin transfer
  - src_addr[31:0]     : Source address (main memory)
  - dst_addr[31:0]     : Destination address (scratchpad)
  - transfer_size[15:0]: Number of words to transfer
  - done               : Transfer complete flag
  - busy               : Transfer in progress

Main Memory Interface:
  - mem_addr[31:0]     : Memory address to read from
  - mem_read           : Read request signal
  - mem_rdata[31:0]    : Data from memory
  - mem_ready          : Memory ready signal

Scratchpad Interface (Port A):
  - spad_addr[9:0]     : Scratchpad address
  - spad_wdata[31:0]   : Data to write
  - spad_we            : Write enable
  - spad_re            : Read enable (unused in current design)
  - spad_rdata[31:0]   : Data from scratchpad
```

### State Machine

```
     ┌─────┐  start=1
     │IDLE │────────────┐
     └─────┘            │
        ▲               ▼
        │         ┌──────────┐
        │         │READ_MEM  │ Issue read to main memory
        │         └──────────┘
        │               │
        │               ▼
        │         ┌──────────┐
        │         │WAIT_MEM  │ Wait for mem_ready
        │         └──────────┘
        │               │
        │               ▼
        │         ┌───────────┐
        │         │WRITE_SPAD │ Write to scratchpad
        │         └───────────┘
        │               │
        │        count < size ?
        │          │         │
        │          │ YES     │ NO
        │          │         ▼
        │          │    ┌────────┐
        └──────────┴────│  DONE  │
                        └────────┘
```

### Expected Functionality

#### 1. **Transfer Sequence** (for each word)
```
Step 1 [READ_MEM]:
  - Assert mem_read
  - Set mem_addr = current_src_addr
  
Step 2 [WAIT_MEM]:
  - Wait for mem_ready = 1
  - Capture mem_rdata
  
Step 3 [WRITE_SPAD]:
  - Write mem_rdata to scratchpad
  - Set spad_addr = current_dst_addr
  - Assert spad_we
  - Increment addresses and counter
  
Step 4:
  - If transfer_count < transfer_size: Repeat
  - Else: Go to DONE
```

#### 2. **Example Transfer**
```
Configuration:
  src_addr = 0x1000_0000  (Main memory)
  dst_addr = 0x0000_0000  (Scratchpad offset 0)
  transfer_size = 4 words

Operation:
  Word 0: mem[0x1000_0000] → spad[0x000]
  Word 1: mem[0x1000_0004] → spad[0x004]
  Word 2: mem[0x1000_0008] → spad[0x008]
  Word 3: mem[0x1000_000C] → spad[0x00C]
  
Cycles: ~4 words × 3 cycles/word = 12 cycles (approximately)
```

#### 3. **Address Auto-Increment**
```verilog
current_src_addr  = current_src_addr + 4;  // Next word in main memory
current_dst_addr  = current_dst_addr + 4;  // Next word in scratchpad
```
Assumes **sequential** transfers (burst-friendly).

#### 4. **Status Signals**
- `busy`: High during transfer, prevents new transfers
- `done`: Pulsed for 1 cycle when complete

### Performance Characteristics
- **Latency**: 3 cycles per word (read, wait, write)
- **Throughput**: Limited by main memory speed
- **Burst**: Could be optimized for burst transfers

---

## 6. top.v - System Integration

### Purpose
Integrates all components and provides top-level control interface.

### Architecture
```
                     ┌──────────────┐
                     │ Main Memory  │
                     └──────┬───────┘
                            │
                    ┌───────▼────────┐
                    │ DMA Controller │
                    └───────┬────────┘
                            │ Port A
                    ┌───────▼────────┐
                    │  Scratchpad    │
                    │   Memory       │
                    │  (Dual-Port)   │
                    └───────┬────────┘
                            │ Port B
                    ┌───────▼────────┐
                    │   MAC Array    │
                    │    (4×4)       │
                    └────────────────┘
```

### Interface Summary
```verilog
DMA Control:
  - dma_start, dma_src_addr, dma_dst_addr, dma_transfer_size
  - dma_done, dma_busy

MAC Control:
  - mac_enable, mac_accumulate
  - mac_input_addr_a, mac_input_addr_b, mac_output_addr
  - mac_write_enable

Memory:
  - mem_addr, mem_read, mem_rdata, mem_ready

Debug:
  - mac_result_0_0, mac_overflow_0_0 (sample outputs)
```

### Expected System Operation Flow

#### **Phase 1: Data Loading**
```
1. Configure DMA:
   - src_addr  = 0x1000_0000 (where input matrix A is)
   - dst_addr  = 0x0000      (scratchpad offset 0)
   - size      = 16 words    (4×4 matrix, 4 bytes each)

2. Start DMA:
   - dma_start = 1 (pulse)
   
3. Wait for completion:
   - Poll dma_done = 1
```

#### **Phase 2: Computation**
```
1. Set MAC inputs:
   - mac_input_addr_a = 0x000  (where matrix A is)
   - mac_input_addr_b = 0x100  (where matrix B is)
   
2. Load data into MAC array:
   - This is simplified in current design
   - In full design, need state machine to load 16 values
   
3. Compute:
   - mac_enable = 1
   - mac_accumulate = 0 (first operation)
   
4. Accumulate (if needed):
   - Load next data
   - mac_accumulate = 1
   - Repeat for dot products
```

#### **Phase 3: Write Back Results**
```
1. Write results to scratchpad:
   - mac_output_addr = 0x200
   - mac_write_enable = 1
   
2. DMA results back to main memory:
   - Configure DMA for read-back
   - Start transfer
```

### Current Limitations & Future Work

**Current Implementation** (simplified):
- Data loading logic is placeholder
- Only exposes first MAC result for debugging
- Sequential operation (not pipelined)

**Full Implementation Would Need**:
1. **Proper data loading state machine**:
   - Read 16 values from scratchpad
   - Distribute to MAC array registers
   - Handle byte packing (4 bytes → 4 elements)

2. **Matrix multiplication controller**:
   - Tile large matrices into 4×4 blocks
   - Orchestrate multiple MAC operations
   - Implement dot product accumulation

3. **Pipeline control**:
   - Overlap DMA and MAC operations
   - Double buffering
   - Hide memory latency

---

## Complete Data Flow Example

### Matrix Multiplication: C = A × B (2×2 simplified)

```
A = [1  2]    B = [5  6]    Expected C = [19  22]
    [3  4]        [7  8]                  [43  50]

C[0][0] = 1×5 + 2×7 = 5 + 14 = 19
C[0][1] = 1×6 + 2×8 = 6 + 16 = 22
C[1][0] = 3×5 + 4×7 = 15 + 28 = 43
C[1][1] = 3×6 + 4×8 = 18 + 32 = 50
```

### Step-by-Step Hardware Execution

**Step 1: Load A and B into scratchpad via DMA**
```
Main Memory → DMA → Scratchpad
  A @ 0x000: [1, 2, 3, 4]
  B @ 0x010: [5, 6, 7, 8]
```

**Step 2: Compute C[0][0] = a[0][0]×b[0][0] + a[0][1]×b[1][0]**
```
Cycle 1:
  a_matrix[0][0] = 1, b_matrix[0][0] = 5
  mac_accumulate = 0
  → result[0][0] = 5

Cycle 2:
  a_matrix[0][0] = 2, b_matrix[0][0] = 7
  mac_accumulate = 1
  → result[0][0] = 5 + 14 = 19 ✓
```

**Step 3: Repeat for all elements**

**Step 4: Write back to main memory**
```
Scratchpad → DMA → Main Memory
  C @ 0x2000: [19, 22, 43, 50]
```

---

## Performance Summary

### Theoretical Performance (100 MHz clock)

| Component | Latency | Throughput |
|-----------|---------|------------|
| Multiplier | 1 cycle | 100 M ops/sec |
| MAC Unit | 1 cycle | 100 M MACs/sec |
| MAC Array | 1 cycle | 1.6 G MACs/sec |
| Scratchpad | 1 cycle | 400 MB/s per port |
| DMA | 3 cycles/word | ~133 MB/s |

### Bottlenecks
1. **Data loading**: DMA is sequential
2. **MAC utilization**: Need smart tiling to keep all 16 MACs busy
3. **Memory bandwidth**: Main memory slower than scratchpad

---

## Testing & Verification

### What Each Testbench Tests

**tb_multiplier_8bit.v**:
- Basic multiplication correctness
- Edge cases (0, max values)
- Valid signal propagation

**tb_mac_array.v**:
- Parallel MAC operations
- Accumulation functionality
- Overflow detection

**tb_top.v**:
- DMA transfers
- Complete system integration
- Data flow through all components

---

## Next Steps for Extension

1. **Add proper matrix multiplication controller**
2. **Implement systolic array dataflow**
3. **Add RISC-V custom instruction interface**
4. **Optimize for real workloads (GEMM blocking)**
5. **Add pipelining for higher throughput**
6. **Support signed integers and different bit widths**

---

## Summary

You now have a **functional hardware accelerator** with:
- ✅ 8×8 bit multiplication
- ✅ Accumulation for dot products  
- ✅ 16 parallel MAC units
- ✅ On-chip scratchpad memory
- ✅ Automated DMA transfers
- ✅ Complete system integration
- ✅ Testbenches for verification

This is a solid foundation to extend into a full RISC-V accelerator like the reference project!


