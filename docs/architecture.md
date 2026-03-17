# Architecture Specification

## Overview
This document describes the architecture of the 8-bit MAC array accelerator.

## System Architecture

### Data Flow
1. **Main Memory → DMA**: Data is fetched from main memory
2. **DMA → Scratchpad**: Data is transferred to scratchpad memory
3. **Scratchpad → MAC Array**: Input matrices read from scratchpad
4. **MAC Array → Scratchpad**: Results written back to scratchpad
5. **Scratchpad → DMA → Main Memory**: Results transferred back to main memory

## Component Specifications

### 8-bit Multiplier
- **Inputs**: Two 8-bit unsigned integers
- **Output**: 16-bit product
- **Latency**: 1 cycle (combinational with registered output)

### MAC Unit
- **Operation**: result = a × b + accumulator
- **Inputs**: 
  - a, b: 8-bit operands
  - acc: 32-bit accumulator input
- **Output**: 32-bit accumulated result
- **Features**: Overflow detection, reset capability

### MAC Array (4×4)
- **Configuration**: 4×4 array of MAC units
- **Operation**: Performs parallel multiply-accumulate operations
- **Use Case**: Accelerates matrix multiplication with blocking
- **Control**: Enable, reset, accumulate control signals

### Scratchpad Memory
- **Size**: 1KB (configurable)
- **Ports**: Dual-port for simultaneous read/write
- **Width**: 32-bit data width
- **Organization**: Byte-addressable

### DMA Controller
- **Features**:
  - Configurable source/destination addresses
  - Configurable transfer size
  - Burst transfer support
  - Status reporting (idle, busy, done)
- **Interface**: Simple handshaking protocol

## Memory Map
```
0x0000 - 0x03FF: Scratchpad Memory (1KB)
0x0400 - 0x040F: DMA Registers
  0x0400: DMA Control Register
  0x0404: Source Address
  0x0408: Destination Address
  0x040C: Transfer Size
```

## Timing
- **Clock**: Single clock domain
- **Reset**: Synchronous active-high reset
- **Pipeline**: MAC operations are pipelined (1 cycle per operation)

## Future Enhancements
- Double buffering for scratchpad
- Support for different data types (int16, int32)
- Systolic array architecture
- Advanced DMA with 2D transfer support


