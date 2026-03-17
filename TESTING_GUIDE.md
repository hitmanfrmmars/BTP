# Testing Guide - Module by Module

## Prerequisites: Install a Verilog Simulator

You need one of these simulators installed:

### Option 1: Icarus Verilog (Free, Open Source)
- **Download**: http://bleyer.org/icarus/
- **Windows installer**: iverilog-*-setup.exe
- **After install**: Add to PATH or use full path
- **Script to use**: `run_sim.bat`

### Option 2: ModelSim/QuestaSim (Commercial/Student)
- **Intel**: Part of Intel Quartus
- **Mentor**: ModelSim DE/SE
- **Script to use**: `run_modelsim.bat`

### Option 3: Xilinx Vivado (Free with account)
- **Download**: Xilinx Vivado Design Suite
- **Includes**: XSIM simulator
- **Script to use**: `run_vivado.bat`

---

## Testing Module 1: 8-bit Multiplier

### Files Needed:
- `rtl/multiplier_8bit.v` (module)
- `testbench/tb_multiplier_8bit.v` (testbench)

### How to Run:

**With Icarus Verilog:**
```cmd
.\run_sim.bat tb_multiplier_8bit
```

**With ModelSim:**
```cmd
.\run_modelsim.bat tb_multiplier_8bit
```

**With Vivado:**
```cmd
.\run_vivado.bat tb_multiplier_8bit
```

**Manual (any simulator):**
```cmd
iverilog -o sim.vvp rtl/multiplier_8bit.v testbench/tb_multiplier_8bit.v
vvp sim.vvp
```

### Expected Output:

```
Test 1: 5 * 6
PASS: 5 * 6 = 30

Test 2: 15 * 10
PASS: 15 * 10 = 150

Test 3: 255 * 255
PASS: 255 * 255 = 65025

Test 4: 0 * 100
PASS: 0 * 100 = 0

=== Multiplier Tests Complete ===
```

### What the Test Does:
1. **Test 1**: Basic multiplication (5 × 6 = 30)
2. **Test 2**: Larger numbers (15 × 10 = 150)
3. **Test 3**: Maximum values (255 × 255 = 65,025) - tests 16-bit output
4. **Test 4**: Zero multiplication (0 × 100 = 0) - edge case

### If All Tests PASS:
✅ Your `multiplier_8bit.v` works correctly!

### If Tests FAIL:
- Check the output value reported
- Look at waveform: `gtkwave tb_multiplier_8bit.vcd` (if using Icarus)
- Verify clock and reset timing

---

## Testing Module 2: MAC Unit

### Files Needed:
- `rtl/multiplier_8bit.v` (dependency)
- `rtl/mac_unit.v` (module)
- `testbench/tb_mac_unit.v` (need to create - see below)

### Test Cases for MAC Unit:
1. **Multiply only**: 5 × 6 = 30
2. **Accumulate**: 30 + (4 × 5) = 50
3. **Accumulate again**: 50 + (2 × 3) = 56
4. **Reset and multiply**: 10 × 10 = 100

---

## Testing Module 3: MAC Array (4×4)

### Files Needed:
- `rtl/multiplier_8bit.v`
- `rtl/mac_unit.v`
- `rtl/mac_array.v`
- `testbench/tb_mac_array.v`

### How to Run:
```cmd
.\run_sim.bat tb_mac_array
```

### Expected Output:

```
=== Test 1: Simple Multiplication ===
All elements: a=2, b=3, expected result=6

MAC Array Results:
result[0][0] = 6
result[0][1] = 6
result[0][2] = 6
result[0][3] = 6
result[1][0] = 6
...
(16 results total, all should be 6)
PASS: Multiplication working correctly

=== Test 2: Accumulation ===
First operation: 2*3=6, then accumulate: 6 + (2*3) = 12
After first mult: result[0][0] = 6
...
PASS: Accumulation working correctly

=== Test 3: Identity-like Pattern ===
...
PASS: Identity pattern working correctly

=== MAC Array Tests Complete ===
```

### What the Test Does:
1. **Test 1**: All 16 MACs multiply 2×3, expect all results = 6
2. **Test 2**: Tests accumulation mode (6 + 6 = 12)
3. **Test 3**: Tests diagonal pattern (identity matrix behavior)

---

## Testing Module 4: Scratchpad Memory

### Create Simple Testbench:

You can create `testbench/tb_scratchpad.v` to test:
1. Write to Port A, read from Port A
2. Write to Port B, read from Port B
3. Write to Port A, read from Port B (dual-port test)
4. Simultaneous read/write on both ports

---

## Testing Module 5: DMA Controller

### Test Sequence:
1. Configure source/destination addresses
2. Start transfer
3. Monitor `busy` signal
4. Wait for `done` signal
5. Verify data moved to scratchpad

---

## Testing Module 6: Top-level Integration

### Files Needed:
- All RTL files
- `testbench/tb_top.v`

### How to Run:
```cmd
.\run_sim.bat tb_top
```

### Expected Output:

```
=== Test 1: DMA Transfer from Main Memory to Scratchpad ===
DMA Transfer Complete!

=== Test 2: MAC Array Operation ===
MAC Result [0][0] = [some value]

=== Test 3: MAC with Accumulation ===
MAC Result [0][0] after accumulation = [accumulated value]

=== Test 4: Write Result to Scratchpad ===
Result written to scratchpad at address [addr]

=== Top-level Integration Tests Complete ===

Summary:
  - DMA successfully transferred data from main memory to scratchpad
  - MAC array performed multiplication and accumulation
  - Results written back to scratchpad

Next steps:
  - Verify scratchpad contents manually if needed
  - Add more comprehensive matrix multiplication tests
  - Implement full matrix computation flow
```

---

## Viewing Waveforms (Debugging)

### With Icarus Verilog + GTKWave:
```cmd
gtkwave tb_multiplier_8bit.vcd
```

### With ModelSim:
- Waveforms automatically open in GUI mode
- Or use: `vsim -view vsim.wlf`

### With Vivado:
- Use Vivado GUI to open `.wdb` file
- Or run with `-gui` flag

### What to Look For:
1. **Clock**: Regular toggling
2. **Reset**: Asserted for first few cycles
3. **Inputs**: Change at expected times
4. **Outputs**: Correct values, correct timing
5. **Valid signals**: Proper handshaking

---

## Quick Verification Checklist

### ✅ Multiplier Test:
- [ ] Compiles without errors
- [ ] All 4 tests PASS
- [ ] Product values are correct
- [ ] valid_out follows valid_in with 1 cycle delay

### ✅ MAC Array Test:
- [ ] Compiles without errors
- [ ] Element-wise multiplication works
- [ ] Accumulation mode works
- [ ] All 16 MACs produce correct results

### ✅ Top-level Test:
- [ ] DMA completes transfer
- [ ] MAC array produces results
- [ ] No compilation warnings

---

## Troubleshooting

### Problem: "iverilog not found"
**Solution**: Install Icarus Verilog or use different simulator

### Problem: "module not found"
**Solution**: Check file paths in compile command

### Problem: "Test FAIL"
**Solution**: 
1. Check expected vs actual value
2. Open waveform viewer
3. Verify timing (clock edges, reset)
4. Check for X (unknown) or Z (high-impedance) values

### Problem: Simulation hangs
**Solution**: 
1. Check for missing `$finish` in testbench
2. Add timeout: `initial begin #10000; $display("TIMEOUT"); $finish; end`

### Problem: "syntax error"
**Solution**: 
1. Check Verilog version (SystemVerilog vs Verilog-2001)
2. Look at line number in error message
3. Check for missing semicolons, endmodule statements

---

## Next Steps After Testing

Once all individual modules pass:
1. ✅ Understand each module's functionality
2. ✅ Verify timing diagrams
3. 🔨 Add proper data loading controller
4. 🔨 Implement matrix multiplication sequencer
5. 🔨 Add RISC-V interface
6. 🔨 Optimize for performance

---

## Summary

**To test the 8-bit multiplier right now:**

1. **Install a simulator** (Icarus Verilog recommended for beginners)
2. **Run**: `.\run_sim.bat tb_multiplier_8bit`
3. **Check output**: Should see 4 PASS messages
4. **View waveform**: `gtkwave tb_multiplier_8bit.vcd` (optional)

That's it! The testbench I provided does everything automatically. 🎯


