# MAC Array Explained - What's the Difference?

## Summary Table

| Module | What It Is | Inputs | Outputs | Operations/Cycle |
|--------|-----------|---------|---------|------------------|
| **multiplier_8bit.v** | Single 8×8 multiplier | 2 values (a, b) | 1 product | 1 multiply |
| **mac_unit.v** | Single MAC | 2 values (a, b) | 1 result | 1 MAC |
| **mac_array.v** | 4×4 grid of MACs | 32 values (16 pairs) | 16 results | **16 MACs!** |

---

## 1. Single Multiplier (multiplier_8bit.v)

### What it does:
Multiplies **ONE** pair of 8-bit numbers

### Example:
```
Input:  a = 5, b = 6
Output: product = 30

Operations: 1 multiplication
```

### Code:
```verilog
multiplier_8bit mult (
    .a(8'd5),           // Single 8-bit value
    .b(8'd6),           // Single 8-bit value
    .product(result)    // Single 16-bit output = 30
);
```

---

## 2. MAC Unit (mac_unit.v)

### What it does:
Multiplies **ONE** pair and accumulates

### Example:
```
Cycle 1: a=2, b=3, accumulate=0 → result = 6
Cycle 2: a=4, b=5, accumulate=1 → result = 6 + 20 = 26
Cycle 3: a=1, b=2, accumulate=1 → result = 26 + 2 = 28

Operations: 1 MAC per cycle
```

### Use case:
Perfect for computing dot products:
```
dot_product = a[0]×b[0] + a[1]×b[1] + a[2]×b[2] + ...
```

---

## 3. MAC Array (mac_array.v) - 4×4 = 16 MAC Units

### What it is:
A **grid of 16 independent MAC units** working in parallel!

### Structure:
```
        a[0][0],b[0][0]  a[0][1],b[0][1]  a[0][2],b[0][2]  a[0][3],b[0][3]
           ↓                 ↓                 ↓                 ↓
Row 0:  [MAC 0,0]  →    [MAC 0,1]  →    [MAC 0,2]  →    [MAC 0,3]
           ↓                 ↓                 ↓                 ↓
        result[0][0]     result[0][1]     result[0][2]     result[0][3]

Row 1:  [MAC 1,0]       [MAC 1,1]       [MAC 1,2]       [MAC 1,3]
Row 2:  [MAC 2,0]       [MAC 2,1]       [MAC 2,2]       [MAC 2,3]
Row 3:  [MAC 3,0]       [MAC 3,1]       [MAC 3,2]       [MAC 3,3]
```

### Example:
```
Input (16 pairs of values):
  a_matrix[0][0] = 2,  b_matrix[0][0] = 3  → result[0][0] = 6
  a_matrix[0][1] = 5,  b_matrix[0][1] = 4  → result[0][1] = 20
  a_matrix[0][2] = 1,  b_matrix[0][2] = 7  → result[0][2] = 7
  ... (13 more pairs)

ALL 16 MULTIPLICATIONS HAPPEN SIMULTANEOUSLY!

Operations: 16 MACs in ONE cycle!
```

---

## Key Differences

### Throughput:

| Module | Operations/Cycle | At 100MHz |
|--------|------------------|-----------|
| Single Multiplier | 1 multiply | 100 M ops/sec |
| Single MAC | 1 MAC | 100 M MACs/sec |
| **MAC Array** | **16 MACs** | **1.6 GIGA MACs/sec** 🚀 |

### Inputs Required:

```
Single Multiplier:
  a[7:0]              ← 1 value
  b[7:0]              ← 1 value
  Total: 2 values (16 bits)

MAC Array:
  a_matrix[0][0..3]   ← 4 values
  a_matrix[1][0..3]   ← 4 values
  a_matrix[2][0..3]   ← 4 values
  a_matrix[3][0..3]   ← 4 values
  b_matrix[0..3][0..3] ← 16 values
  Total: 32 values (256 bits!)
```

---

## What Does "8-bit × 8-bit" Mean?

**Each individual MAC unit** does 8-bit × 8-bit multiplication:
- Input: Two 8-bit numbers (0 to 255)
- Multiply result: 16-bit (0 to 65,025)
- Accumulate result: 32-bit (up to 4,294,967,295)

So when we say "MAC Array with 8-bit multipliers", we mean:
- ✅ Each of the 16 MAC units uses 8-bit × 8-bit multiplication
- ❌ NOT a single 8×8 = 64 multiplier array

---

## Analogy

Think of it like workers in a factory:

### Single Multiplier:
```
1 worker → processes 1 item at a time
```

### MAC Array:
```
16 workers → process 16 items simultaneously!
Same quality (8-bit precision)
16× throughput!
```

---

## When Would You Use Each?

### Use Single Multiplier (`multiplier_8bit.v`):
- Simple calculations
- Learning/testing
- Building block for larger designs
- Area-constrained designs

### Use MAC Unit (`mac_unit.v`):
- Dot products
- Convolutions
- FIR filters
- Any accumulation needed

### Use MAC Array (`mac_array.v`):
- **Matrix multiplication** (with proper controller)
- **Neural network inference** (many MACs needed)
- **High-performance computing**
- **When you need speed over area**

---

## Current Implementation

### What You Have Now:

```verilog
mac_array.v:
  - ARRAY_SIZE = 4     → 4×4 grid
  - DATA_WIDTH = 8     → Each MAC uses 8-bit inputs
  - ACC_WIDTH = 32     → Results are 32-bit
  
  Total: 16 MAC units, each doing 8×8 bit operations
```

### Scalability:

Want more performance? Just change the parameter:

```verilog
// 8×8 array = 64 MAC units!
mac_array #(.ARRAY_SIZE(8)) my_big_array (...);

// 16×16 array = 256 MAC units!!
mac_array #(.ARRAY_SIZE(16)) my_huge_array (...);
```

---

## Visual Comparison

### One Cycle of Operation:

**Single Multiplier:**
```
Cycle 1: [a=5, b=6] → Multiplier → [product=30]
         1 operation done ✓
```

**MAC Array:**
```
Cycle 1: 
  [a[0][0]=2, b[0][0]=3] → MAC[0][0] → [result=6]
  [a[0][1]=5, b[0][1]=4] → MAC[0][1] → [result=20]
  [a[0][2]=1, b[0][2]=7] → MAC[0][2] → [result=7]
  ... (13 more)
  16 operations done simultaneously! ✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓✓
```

---

## Hardware Area

### Resource Usage (approximate):

| Module | Logic Gates | Registers | Multipliers |
|--------|-------------|-----------|-------------|
| Single Multiplier | Small | ~20 | 1 |
| MAC Unit | Medium | ~70 | 1 |
| **MAC Array (4×4)** | **Large** | **~1120** | **16** 🔥 |

The MAC array uses **16× more resources** but gives **16× throughput**!

---

## Summary

**Your MAC Array (`mac_array.v`):**
- ✅ Is an array of **16 independent MAC units**
- ✅ Each MAC unit does **8-bit × 8-bit** multiplication
- ✅ Can perform **16 operations in parallel**
- ✅ Perfect for **accelerating matrix math**
- ❌ Is NOT a single 8×8 multiplier
- ❌ Is NOT an 8-bit by 8-bit sized multiplier

**Think of it as:**
- 16 workers, each with an 8-bit calculator
- NOT: 1 worker with a bigger calculator

---

## Next Question?

Want to see:
1. How to use the MAC array for actual matrix multiplication?
2. How to test the MAC array?
3. How the MAC array compares to other AI accelerators?
4. How to optimize it further?


