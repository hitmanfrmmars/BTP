# Quick Start Guide

## Project Setup Complete! 🎉

Your 8-bit MAC array accelerator project is now set up with the following architecture:

```
Main Memory <--> DMA Controller <--> Scratchpad Memory <--> MAC Array
```

## What's Included

### RTL Modules (`rtl/`)
1. **multiplier_8bit.v** - Basic 8×8 bit multiplier
2. **mac_unit.v** - Multiply-Accumulate unit with overflow detection
3. **mac_array.v** - 4×4 array of MAC units for parallel operations
4. **scratchpad_mem.v** - 1KB dual-port SRAM for data buffering
5. **dma_controller.v** - Simple DMA for data transfer between main memory and scratchpad
6. **top.v** - Top-level integration of all components

### Testbenches (`testbench/`)
1. **tb_multiplier_8bit.v** - Tests basic 8-bit multiplication
2. **tb_mac_array.v** - Tests MAC array operations and accumulation
3. **tb_top.v** - System-level integration tests

### Documentation (`docs/`)
- **architecture.md** - Detailed architecture specification

## How to Run Simulations

### Option 1: Using the provided scripts

**On Linux/Mac:**
```bash
chmod +x run_sim.sh
./run_sim.sh tb_multiplier_8bit   # Test multiplier
./run_sim.sh tb_mac_array          # Test MAC array
./run_sim.sh tb_top                # Test full system
```

**On Windows:**
```cmd
run_sim.bat tb_multiplier_8bit     # Test multiplier
run_sim.bat tb_mac_array           # Test MAC array
run_sim.bat tb_top                 # Test full system
```

### Option 2: Manual compilation (Icarus Verilog)

```bash
# Compile and run multiplier test
iverilog -o sim rtl/multiplier_8bit.v testbench/tb_multiplier_8bit.v
vvp sim

# Compile and run MAC array test
iverilog -o sim rtl/multiplier_8bit.v rtl/mac_unit.v rtl/mac_array.v testbench/tb_mac_array.v
vvp sim

# Compile and run full system test
iverilog -o sim rtl/*.v testbench/tb_top.v
vvp sim
```

### Option 3: Using ModelSim/QuestaSim

```bash
vlog rtl/*.v testbench/tb_top.v
vsim -c tb_top -do "run -all; quit"
```

## Viewing Waveforms

After running simulations, waveform files (`.vcd`) are generated. View them with GTKWave:

```bash
gtkwave tb_multiplier_8bit.vcd
gtkwave tb_mac_array.vcd
gtkwave tb_top.vcd
```

## Key Features

### Current Implementation
- ✅ 8-bit × 8-bit multiplication
- ✅ 4×4 MAC array for parallel operations
- ✅ 32-bit accumulation with overflow detection
- ✅ 1KB dual-port scratchpad memory
- ✅ Simple DMA controller with configurable transfers
- ✅ Integrated system with testbenches

### Architecture Highlights
- **MAC Array**: Performs 16 multiply-accumulate operations in parallel
- **Dual-Port Memory**: Allows simultaneous DMA and MAC array access
- **Pipeline Ready**: Single-cycle operations ready for pipelining
- **Scalable Design**: Easy to extend array size and data width

## Next Steps for Extension

To match the RISC-V accelerator reference project, you can:

1. **Add RISC-V Interface**
   - Custom instruction decoder
   - Memory-mapped register file
   - Bus interface (AXI/AHB/Wishbone)

2. **Enhance Data Types**
   - Add int16 support
   - Add signed/unsigned modes
   - Configurable precision

3. **Optimize Performance**
   - Add pipeline stages to MAC units
   - Implement double buffering in scratchpad
   - Add 2D DMA for matrix blocks

4. **Advanced Features**
   - Systolic array dataflow
   - Matrix tiling/blocking support
   - Power gating for unused MACs

5. **Software Integration**
   - C driver for hardware control
   - TensorFlow Lite Micro kernel
   - GEMM library implementation

6. **FPGA Implementation**
   - Synthesis constraints
   - Timing closure
   - Resource optimization
   - Power measurement

## File Structure

```
project_sim/
├── README.md              # Project overview
├── QUICKSTART.md         # This file
├── .gitignore           # Git ignore patterns
├── run_sim.sh           # Linux/Mac simulation script
├── run_sim.bat          # Windows simulation script
├── docs/
│   └── architecture.md  # Detailed architecture
├── rtl/
│   ├── multiplier_8bit.v
│   ├── mac_unit.v
│   ├── mac_array.v
│   ├── scratchpad_mem.v
│   ├── dma_controller.v
│   └── top.v
└── testbench/
    ├── tb_multiplier_8bit.v
    ├── tb_mac_array.v
    └── tb_top.v
```

## Testing Strategy

### Unit Tests
- `tb_multiplier_8bit.v`: Verifies basic multiplication with corner cases
- `tb_mac_array.v`: Tests MAC operations, accumulation, and matrix patterns

### Integration Test
- `tb_top.v`: Tests the complete data flow:
  1. DMA transfers data from main memory to scratchpad
  2. MAC array reads from scratchpad and performs computation
  3. Results are written back to scratchpad

## Troubleshooting

### Simulation doesn't run
- Ensure Icarus Verilog is installed: `iverilog -v`
- Check file paths in simulation scripts
- Verify all RTL files are present

### Compilation errors
- Check Verilog syntax
- Ensure module names match filenames
- Verify all dependencies are included

### Waveforms not generated
- Check if `$dumpfile` and `$dumpvars` are in testbench
- Ensure simulation runs to completion
- Look for `.vcd` files in the current directory

## Resources

- Icarus Verilog: http://iverilog.icarus.com/
- GTKWave: http://gtkwave.sourceforge.net/
- Verilog HDL: https://www.asic-world.com/verilog/

## Support

For questions or issues:
1. Check the documentation in `docs/architecture.md`
2. Review the testbenches for usage examples
3. Examine waveforms to debug hardware behavior

Happy designing! 🚀


