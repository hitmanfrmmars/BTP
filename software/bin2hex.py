#!/usr/bin/env python3
"""
Convert a flat binary file to Verilog $readmemh hex format.

Usage:  python bin2hex.py firmware.bin firmware.hex [total_words]

The output has one 32-bit hex word per line (little-endian byte order,
matching RISC-V's native endianness).  Unused words are filled with zero.
"""

import sys, struct, os

def bin2hex(bin_path, hex_path, total_words=32768):
    with open(bin_path, "rb") as f:
        data = f.read()

    # Pad to word boundary
    while len(data) % 4 != 0:
        data += b'\x00'

    n_words = len(data) // 4

    with open(hex_path, "w") as f:
        for i in range(total_words):
            if i < n_words:
                word = struct.unpack_from("<I", data, i * 4)[0]
            else:
                word = 0
            f.write(f"{word:08X}\n")

    print(f"Converted {bin_path} ({len(data)} bytes, {n_words} words) -> {hex_path} ({total_words} words)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.bin> <output.hex> [total_words]")
        sys.exit(1)

    total = int(sys.argv[3]) if len(sys.argv) > 3 else 32768
    bin2hex(sys.argv[1], sys.argv[2], total)
