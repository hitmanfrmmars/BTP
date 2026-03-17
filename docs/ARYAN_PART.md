# Aryan's Part: Core Hardware Design (Modules 1-6)

## Overview

You designed and built the **core computation engine** of the GEMM accelerator -- the hardware modules that actually perform the matrix multiplication. This is everything inside the co-processor: from the individual multiply-accumulate units, up to the tiling engine that breaks any large matrix into small pieces the hardware can handle.

---

## Module 1: MAC Unit (`mac_unit_v2.v`)

**One-liner:** The smallest building block -- a single multiply-accumulate unit.

### What to say

- "Each MAC unit takes two numbers -- one from matrix A and one from matrix B -- multiplies them, and adds the product to a running total called an accumulator."
- "It is pipelined in 2 stages: Stage 1 does the multiplication and registers the result, Stage 2 adds that product to the accumulator and registers it. This means a new multiply can start every clock cycle even though each operation takes 2 cycles end-to-end."
- "It supports two data types:
  - **int8** -- 8-bit inputs, 16-bit product, 32-bit accumulator (for standard AI inference)
  - **int16** -- 16-bit inputs, 32-bit product, 48-bit accumulator (for higher precision)"
- "You switch between int8 and int16 with a single control signal called `mode`."
- "The accumulator is 48 bits wide. This matters because if you multiply 255 x 255 = 65,025 and accumulate hundreds of those, a 32-bit accumulator would overflow. 48 bits gives headroom for thousands of accumulations."
- "It has **saturation arithmetic** -- if the accumulated result gets too large, instead of wrapping around to a garbage number, it clamps to the maximum value. This prevents silent data corruption."

### Key internals

- `product_s1`: registered output of Stage 1 (multiply)
- `accumulator`: 48-bit running sum in Stage 2
- `clear_acc`: resets the accumulator when starting a new dot product
- `overflow`: flag raised if saturation is triggered

---

## Module 2: MAC Array (`mac_array_v2.v`)

**One-liner:** A 4x4 grid of 16 MAC units working in parallel.

### What to say

- "The MAC array is a 4x4 grid -- 16 MAC units that all compute simultaneously. Every single clock cycle, 16 multiplications and 16 additions happen at the same time."
- "It uses an **output-stationary dataflow**. Each MAC unit 'owns' one position in the 4x4 output tile. The MAC at position (row 2, column 3) always computes C[2][3]. It stays in place and accumulates its result over multiple K-steps."
- "Input data is **broadcast**: one row of A values is sent across all columns, and one column of B values is sent down all rows. So we feed 4 A values + 4 B values = 8 values per cycle to keep all 16 MACs busy. This is very efficient because it saves wiring and memory bandwidth."
- "For a 4x4 tile multiply, the array processes the K-dimension in just 4 cycles -- one K-step per cycle. After those 4 cycles, all 16 output values are ready."
- "The array is instantiated using Verilog `generate` loops -- the compiler unrolls the 4x4 grid automatically."

### Key internals

- `a_col[0:3]`: 4 values broadcast to MAC rows (A[0..3][k] for current K-step)
- `b_row[0:3]`: 4 values broadcast to MAC columns (B[k][0..3])
- `result_matrix[4][4]`: the 16 accumulated output values
- `overflow_flags[4][4]`: per-MAC overflow detection

---

## Module 3: Matmul Controller (`matmul_controller_v2.v`)

**One-liner:** The state machine that reads data from the scratchpad and feeds it to the MAC array in the correct order.

### What to say

- "The controller is a 10-state FSM (finite state machine) that orchestrates one tile of the matrix multiply."
- "It reads data from the scratchpad memory (the accelerator's private fast memory), unpacks it, feeds it to the MAC array step by step, collects results, packs them back, and writes them to the scratchpad."
- "For **int8 mode**: each 32-bit word from scratchpad holds 4 elements packed together. The controller uses a `extract_byte()` function to pull out individual bytes. One word per row = 4 elements."
- "For **int16 mode**: each 32-bit word holds 2 elements. The controller uses `extract_halfword()` to pull out 16-bit values. Two words per row = 4 elements."
- "The flow for one tile is: Load A words → Load B words → Compute (feed MAC for each K-step, loading new B each step) → Drain pipeline (wait 2 cycles for pipeline latency) → Write back results."
- "It supports **partial tiles** -- when the tiling engine says 'this tile only has 3 valid rows and 2 K-steps', the controller adjusts automatically using `eff_rows` and `eff_k` inputs. This is how non-aligned dimensions (like 7x5 matrices) work correctly."
- "After computation, it packs results back: 4 int8 values into one 32-bit word, or 2 int16 values into one word."

### Key internals

- States: `S_IDLE → S_INIT → S_LOAD_A → S_LOAD_B → S_COMPUTE → S_DRAIN → S_WRITE_BACK → S_DONE`
- `eff_rows` (1-4): how many valid rows this tile has
- `eff_k` (1-4): how many K-steps to process
- `accumulate` flag: when set, don't clear accumulators (used for multi-K-tile accumulation)

---

## Module 4: Double-Buffered Scratchpad (`scratchpad_double_buf.v` + `scratchpad_mem.v`)

**One-liner:** Two identical memory banks that swap roles -- one feeds computation while the other is being loaded.

### What to say

- "The scratchpad is the accelerator's **private fast memory**. It sits right next to the MAC array so data access is instant (single-cycle)."
- "There are **two identical banks** -- Bank 0 and Bank 1 -- working in a **ping-pong** pattern."
- "While the MAC array reads from one bank to compute the current tile, the DMA engine simultaneously writes the next tile into the other bank. When the tile is done, the banks swap roles with a single `swap_banks` pulse."
- "Without double-buffering, the accelerator would sit idle during every data load. With it, loading and computing overlap, which nearly doubles throughput."
- "Each bank is a **dual-port SRAM** -- 256 words of 32 bits each (1 KB per bank, 2 KB total). One port is used by the DMA side, the other by the compute side. Reads and writes happen simultaneously without conflict."
- "The `bank_sel` register tracks which bank is for DMA and which is for compute. The mux logic routes addresses and data to the correct bank based on `bank_sel`."

### Key internals

- `bank_sel`: 0 means DMA writes Bank 0 and compute reads Bank 1; 1 means the opposite
- `dma_addr/dma_wdata/dma_we`: DMA side interface
- `comp_addr/comp_rdata/comp_we`: Compute side interface
- Bank size: 256 words x 32 bits = 1 KB per bank

---

## Module 5: DMA Engine (`dma_engine.v`)

**One-liner:** The data mover that transfers matrix tiles between main memory and the scratchpad without using the CPU.

### What to say

- "DMA stands for Direct Memory Access. It moves data between the SoC's 128KB main memory and the scratchpad without any CPU involvement. The CPU just says 'move this block' and the DMA does it on its own."
- "It supports **burst transfers** -- instead of requesting one word at a time from memory, it requests up to 16 consecutive words in a single transaction (configurable via `burst_len`). This dramatically reduces per-word overhead."
- "It supports **2D strided access**. Matrices are stored row-by-row in memory. If you want a 4-row sub-block from a larger matrix, you read 4 words, skip ahead by the row stride, read 4 more, and so on. The DMA handles this automatically with:
  - `x_count`: words per row
  - `y_count`: number of rows
  - `src_stride` / `dst_stride`: byte distance between rows"
- "It supports both directions:
  - **LOAD** (memory → scratchpad): uses burst reads for speed
  - **STORE** (scratchpad → memory): reads from scratchpad one word at a time (respects 1-cycle read latency)"
- "An `irq` signal fires when the transfer completes, which the tiling engine uses to know when data is ready."

### Key internals

- States: `S_IDLE → S_LOAD_ADDR → S_LOAD_RECV → S_LOAD_NEXT` (for loads) or `S_STORE_READ → S_STORE_WAIT → S_STORE_WR` (for stores)
- `beat_cnt`: counts beats within a burst
- `row_src_base / row_dst_base`: base address for the current row (advances by stride per row)

---

## Module 6: Tiling Engine (`tiling_engine.v`)

**One-liner:** The orchestrator that decomposes any matrix multiplication into small 4x4 tiles and coordinates DMA + compute concurrently.

### What to say

- "This is the most complex and important module. It takes an arbitrary M x K times K x N matrix multiply and breaks it into a grid of small 4x4 tile operations."
- "For example, a 16x16 multiply becomes 4x4x4 = 64 tile operations. A 7x5 multiply becomes a mix of full 4x4 tiles and partial edge tiles."
- "It uses a **dual-FSM architecture** -- two state machines running at the same time:
  - **DMA FSM**: loads the next tile into the idle scratchpad bank
  - **Compute FSM**: runs the current tile through the MAC array
  - They work **concurrently** -- this is the overlapped load/compute feature that nearly doubles throughput."
- "The tile iteration order is **K → N → M**:
  1. Process all K-tiles for one output position first (accumulating partial sums across the K dimension)
  2. Then move to the next output column (N)
  3. Then the next output row (M)"
- "For **non-aligned dimensions** (matrix size not a multiple of 4), it calculates the effective number of valid rows/columns for each edge tile. For example, with M=7: the first tile has eff_m=4, the second has eff_m=3. These values are passed to the controller."
- "The **partial-N store fix** prevents output corruption: when storing results for edge tiles, it only writes the exact number of words containing valid columns (using `cur_store_words`), so adjacent memory isn't overwritten."
- "The main flow: M_IDLE → M_INIT → M_FIRST_LOAD (load first tile sequentially) → M_OVERLAP (concurrent load+compute) → M_STORE_C (store finished result) → repeat or M_DONE."

### Key internals

- Three FSMs: Main FSM (`m_state`), DMA FSM (`d_state`), Compute FSM (`c_state`)
- `cur_m/cur_n/cur_k`: current tile being computed
- `nxt_m/nxt_n/nxt_k`: next tile being prefetched
- `has_next_tile`: flag indicating whether there's another tile to prefetch
- `cur_eff_m/cur_eff_k/cur_eff_n`: effective dimensions of the current tile (4 for full tiles, 1-3 for edge tiles)
- `advance_nxt_tile`: task that increments the tile position in K → N → M order

---

## How Everything Connects

Here is the data flow when a matrix multiply runs:

1. **Tiling engine** calculates the first tile's addresses and tells the **DMA** to load tile A and tile B from main memory into **scratchpad Bank 0**.
2. Once loaded, it **swaps banks** and starts two things simultaneously:
   - The **matmul controller** reads from the compute bank, feeds the **MAC array**, collects results
   - The **DMA** prefetches the next tile into the load bank
3. When both computation and prefetch are done, it **swaps banks** again, **stores** the completed result back to main memory via DMA, and repeats.
4. This continues until all tiles in the M x N x K grid are processed.

---

## Key Numbers for Presentation

| Metric | Value |
|--------|-------|
| MACs per cycle | 16 (4x4 array) |
| Clock frequency | 100 MHz (on Artix-7) |
| LUT usage (accel only) | 1,921 (3% of xc7a100t) |
| DSP blocks | 22 |
| Block RAMs | 2 (for scratchpad) |
| Dynamic power (accel) | 43 mW |
| Max matrix dimensions | 65,535 x 65,535 (via tiling) |
| Data types | int8 and int16 |
| Pipeline stages | 2 (in each MAC unit) |
