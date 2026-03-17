#!/usr/bin/env python3
"""
RISC-V Firmware Hex Generator for GEMM SoC Testbench

Generates firmware matching the C driver flow (main.c):
  1. CPU writes test matrices A and B to memory via SW instructions
  2. Configures GEMM accelerator via PCPI custom instructions
  3. Starts computation and waits for completion
  4. Reads results back and verifies against expected values
  5. Writes PASS/FAIL/DONE markers to debug port

This validates the complete driver logic without requiring the RISC-V toolchain.
"""

import os, sys

# ================================================================
# RISC-V instruction encoders
# ================================================================

def lui(rd, imm20):
    return ((imm20 & 0xFFFFF) << 12) | ((rd & 0x1F) << 7) | 0x37

def addi(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (0b000 << 12) | ((rd & 0x1F) << 7) | 0x13

def sw(rs2, rs1, imm12):
    imm_hi = (imm12 >> 5) & 0x7F
    imm_lo = imm12 & 0x1F
    return (imm_hi << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | (0b010 << 12) | (imm_lo << 7) | 0x23

def lw(rd, rs1, imm12):
    return ((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) | (0b010 << 12) | ((rd & 0x1F) << 7) | 0x03

def bne(rs1, rs2, imm13):
    imm = imm13 & 0x1FFF
    return (((imm>>12)&1)<<31) | (((imm>>5)&0x3F)<<25) | ((rs2&0x1F)<<20) | \
           ((rs1&0x1F)<<15) | (0b001<<12) | (((imm>>1)&0xF)<<8) | (((imm>>11)&1)<<7) | 0x63

def jal(rd, imm21):
    imm = imm21 & 0x1FFFFF
    bit20    = (imm >> 20) & 1
    bit10_1  = (imm >> 1)  & 0x3FF
    bit11    = (imm >> 11) & 1
    bit19_12 = (imm >> 12) & 0xFF
    enc = (bit20 << 31) | (bit10_1 << 21) | (bit11 << 20) | (bit19_12 << 12) | ((rd & 0x1F) << 7) | 0x6F
    return enc & 0xFFFFFFFF

def nop():
    return addi(0, 0, 0)

# GEMM custom instructions: opcode=0x0B, funct7=0x08
GEMM_FUNCT7 = 0b0001000

def gemm_cfg(rd, rs1, rs2):
    return (GEMM_FUNCT7 << 25) | ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
           (0b000 << 12) | ((rd & 0x1F) << 7) | 0x0B

def gemm_start(rd):
    return (GEMM_FUNCT7 << 25) | (0b001 << 12) | ((rd & 0x1F) << 7) | 0x0B

def gemm_wait(rd):
    return (GEMM_FUNCT7 << 25) | (0b010 << 12) | ((rd & 0x1F) << 7) | 0x0B

# Register aliases
zero, ra, sp = 0, 1, 2
t0, t1, t2 = 5, 6, 7
s0, s1 = 8, 9
a0, a1 = 10, 11

# GEMM register offsets
REG_DIM_MK   = 0x08
REG_DIM_N    = 0x0C
REG_SRC_A    = 0x10
REG_SRC_B    = 0x14
REG_DST_C    = 0x18
REG_STRIDE_A = 0x1C
REG_STRIDE_B = 0x20
REG_STRIDE_C = 0x24

# Memory layout
ADDR_A     = 0x00010000
ADDR_B     = 0x00010100
ADDR_C     = 0x00010200
ADDR_DEBUG = 0x10000000
M, K, N = 4, 4, 4

MARKER_PASS = 0x0000600D
MARKER_FAIL = 0x0000FA11
MARKER_DONE = 0x0000DEAD

# Test matrices (matching main.c)
A = [[1, 2, 0, 0], [0, 1, 2, 0], [0, 0, 1, 2], [1, 0, 0, 1]]
B = [[1, 1, 0, 0], [0, 1, 1, 0], [0, 0, 1, 1], [1, 0, 0, 1]]

def pack4_u8(a, b, c, d):
    return (a & 0xFF) | ((b & 0xFF) << 8) | ((c & 0xFF) << 16) | ((d & 0xFF) << 24)

# Compute expected result
C_exp = [[0]*N for _ in range(M)]
for i in range(M):
    for j in range(N):
        for k in range(K):
            C_exp[i][j] += A[i][k] * B[k][j]
C_exp_packed = [pack4_u8(*row) for row in C_exp]


def build_firmware():
    prog = []

    def li(rd, value):
        """Load 32-bit immediate into rd using LUI + ADDI."""
        value = value & 0xFFFFFFFF
        upper = (value + 0x800) >> 12
        lower = value & 0xFFF
        if upper & 0x100000:
            upper &= 0xFFFFF
        adj = upper << 12
        lower = (value - adj) & 0xFFF
        if upper != 0:
            prog.append(lui(rd, upper & 0xFFFFF))
            if lower != 0:
                prog.append(addi(rd, rd, lower))
        else:
            prog.append(addi(rd, zero, lower))

    def cfg_reg(offset, value):
        li(t0, value)
        li(t1, offset)
        prog.append(gemm_cfg(zero, t0, t1))

    def store_word(base_reg, offset, value):
        """Store a 32-bit value to mem[base_reg + offset]."""
        li(t0, value)
        prog.append(sw(t0, base_reg, offset))

    # ---- Reset vector (0x0000) ----
    prog.append(jal(zero, 0x40))   # jump to main at 0x40
    prog.append(nop())
    prog.append(nop())
    prog.append(nop())

    # ---- IRQ handler (0x0010) ----
    prog.append(0x0020000B)        # picorv32 retirq
    prog.append(nop())
    prog.append(nop())
    prog.append(nop())

    # ---- Padding to 0x0040 ----
    while len(prog) < 16:
        prog.append(nop())

    # ---- MAIN (0x0040) ----

    # -- Step 1: Write matrix A to memory --
    li(s0, ADDR_A)
    for r in range(M):
        packed = pack4_u8(*A[r])
        store_word(s0, r * 4, packed)

    # -- Step 2: Write matrix B to memory --
    li(s0, ADDR_B)
    for r in range(K):
        packed = pack4_u8(*B[r])
        store_word(s0, r * 4, packed)

    # -- Step 3: Configure GEMM accelerator via PCPI --
    cfg_reg(REG_DIM_MK, (M << 16) | K)
    cfg_reg(REG_DIM_N, N)
    cfg_reg(REG_SRC_A, ADDR_A)
    cfg_reg(REG_SRC_B, ADDR_B)
    cfg_reg(REG_DST_C, ADDR_C)
    cfg_reg(REG_STRIDE_A, K)
    cfg_reg(REG_STRIDE_B, N)
    cfg_reg(REG_STRIDE_C, N)

    # -- Step 4: Start and wait --
    prog.append(gemm_start(t2))
    prog.append(gemm_wait(t2))

    # -- Step 5: Write cycle count to debug port --
    li(s0, ADDR_DEBUG)
    prog.append(sw(t2, s0, 0))

    # -- Step 6: Verify results --
    # Load result words from ADDR_C, compare against expected.
    # s1 = error count (0 = pass)
    prog.append(addi(s1, zero, 0))   # s1 = 0 (error count)
    li(a0, ADDR_C)

    for r in range(M):
        # Load actual result word
        prog.append(lw(t0, a0, r * 4))      # t0 = C[r]
        # Load expected value
        li(t1, C_exp_packed[r])               # t1 = expected
        # if (t0 != t1) s1++
        # BNE t0, t1, +8  (skip the jump that skips the increment)
        # J +8             (skip increment)
        # ADDI s1, s1, 1   (increment error count)
        # We use: BEQ t0, t1, +8 (skip increment if equal)
        #         ADDI s1, s1, 1
        prog.append(0x00728463)  # BEQ t0, t1, +8  -- skip next insn if equal
        # ^ Encoding: beq(t0, t1, 8) but let me compute properly
        # Actually let me just compute it:

    # Wait, I need to be more careful with branch encoding. Let me redo this.
    # Remove the last 4 appended instructions and redo the verification loop properly.

    # Remove the bad entries
    for _ in range(M):
        prog.pop()  # remove the bad beq
        # Also remove the LW and LI instructions for this iteration
        # This is getting messy. Let me restructure.

    # Actually, let me restart the verification section cleanly.
    # Remove everything from "Step 6" onwards
    # Find where step 6 started: after sw(t2, s0, 0)
    # Count back: sw + li(s0) was 2-3 insns, then addi s1, li a0, then loop body
    # This is error-prone. Let me just rebuild the whole firmware.

    # ---- RESTART: clean approach ----
    prog_clean = []

    def li_c(rd, value, p=None):
        if p is None:
            p = prog_clean
        value = value & 0xFFFFFFFF
        upper = (value + 0x800) >> 12
        upper &= 0xFFFFF
        adj = upper << 12
        lower = (value - adj) & 0xFFF
        if upper != 0:
            p.append(lui(rd, upper))
            if lower != 0:
                p.append(addi(rd, rd, lower))
        else:
            p.append(addi(rd, zero, lower))

    def cfg_c(offset, value):
        li_c(t0, value)
        li_c(t1, offset)
        prog_clean.append(gemm_cfg(zero, t0, t1))

    # Reset vector
    prog_clean.append(jal(zero, 0x40))
    prog_clean.append(nop())
    prog_clean.append(nop())
    prog_clean.append(nop())

    # IRQ handler at 0x10
    prog_clean.append(0x0020000B)
    prog_clean.append(nop())
    prog_clean.append(nop())
    prog_clean.append(nop())

    # Padding to 0x40
    while len(prog_clean) < 16:
        prog_clean.append(nop())

    # ---- MAIN ----

    # Write matrix A
    li_c(s0, ADDR_A)
    for r in range(M):
        packed = pack4_u8(*A[r])
        li_c(t0, packed)
        prog_clean.append(sw(t0, s0, r * 4))

    # Write matrix B
    li_c(s0, ADDR_B)
    for r in range(K):
        packed = pack4_u8(*B[r])
        li_c(t0, packed)
        prog_clean.append(sw(t0, s0, r * 4))

    # Configure GEMM
    cfg_c(REG_DIM_MK, (M << 16) | K)
    cfg_c(REG_DIM_N, N)
    cfg_c(REG_SRC_A, ADDR_A)
    cfg_c(REG_SRC_B, ADDR_B)
    cfg_c(REG_DST_C, ADDR_C)
    cfg_c(REG_STRIDE_A, K)
    cfg_c(REG_STRIDE_B, N)
    cfg_c(REG_STRIDE_C, N)

    # Start and wait
    prog_clean.append(gemm_start(t2))
    prog_clean.append(gemm_wait(t2))

    # Write cycle count to debug
    li_c(s0, ADDR_DEBUG)
    prog_clean.append(sw(t2, s0, 0))

    # Verify results: compare each result word against expected
    prog_clean.append(addi(s1, zero, 0))   # s1 = error count
    li_c(a0, ADDR_C)                        # a0 = &C[0]

    for r in range(M):
        prog_clean.append(lw(t0, a0, r * 4))  # t0 = actual C[r]
        li_c(t1, C_exp_packed[r])               # t1 = expected C[r]
        # BEQ t0, t1, +8 → skip the ADDI (branch over 2 instructions = 8 bytes)
        prog_clean.append(bne(t0, t1, 8))       # if not equal, fall through to increment
        prog_clean.append(jal(zero, 8))          # else skip increment (jump +8 = skip 2 insns)
        prog_clean.append(addi(s1, s1, 1))       # s1++ (error)

    # Write PASS or FAIL marker
    # if s1 == 0: write MARKER_PASS, else write MARKER_FAIL
    li_c(s0, ADDR_DEBUG)
    li_c(t0, MARKER_PASS)
    prog_clean.append(bne(s1, zero, 8))  # if errors != 0, skip to FAIL path
    prog_clean.append(jal(zero, 12))     # skip FAIL, go to store
    li_c(t0, MARKER_FAIL)                # overwrite t0 with FAIL marker
    prog_clean.append(sw(t0, s0, 0))     # store PASS or FAIL to debug

    # Write DONE marker
    li_c(t0, MARKER_DONE)
    prog_clean.append(sw(t0, s0, 0))

    # Infinite loop
    prog_clean.append(jal(zero, 0))

    return prog_clean


def write_hex(prog, filename, total_words=32768):
    """Write memory image as hex file. Only firmware, no pre-loaded matrices."""
    with open(filename, 'w') as f:
        for addr in range(total_words):
            if addr < len(prog):
                val = prog[addr] & 0xFFFFFFFF
            else:
                val = 0
            f.write(f"{val:08X}\n")


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)

    firmware = build_firmware()

    hex_path = os.path.join(project_dir, "testbench", "firmware.hex")
    write_hex(firmware, hex_path)

    print(f"Firmware: {len(firmware)} instructions ({len(firmware)*4} bytes)")
    print(f"Wrote {hex_path}")

    print("\nExpected C matrix:")
    for row in C_exp:
        print(f"  {row}")
    print(f"\nExpected packed: {[f'0x{w:08X}' for w in C_exp_packed]}")

    print("\nDisassembly:")
    for i, insn in enumerate(firmware):
        print(f"  0x{i*4:04X}: 0x{insn:08X}")


if __name__ == "__main__":
    main()
