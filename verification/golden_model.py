#!/usr/bin/env python3
"""
Golden model for GEMM Accelerator verification.
Generates random int8 matrix pairs, computes C = A*B (with uint8 truncation),
and writes Verilog $readmemh files + expected results for automated checking.

Usage:
  python golden_model.py [--count N] [--sizes "4,8,12"]
  
Generates:
  verification/test_<n>_A.hex   - Matrix A in hex (word-packed, little-endian)
  verification/test_<n>_B.hex   - Matrix B in hex
  verification/test_<n>_C.hex   - Expected C in hex
  verification/test_summary.txt - Human-readable summary of all tests
"""

import numpy as np
import os
import argparse

def pack_row_to_words(row, elems_per_word=4):
    """Pack a row of uint8 values into 32-bit words (little-endian)."""
    words = []
    for i in range(0, len(row), elems_per_word):
        chunk = row[i:i+elems_per_word]
        word = 0
        for j, val in enumerate(chunk):
            word |= (int(val) & 0xFF) << (j * 8)
        words.append(word)
    return words

def matrix_to_hex_words(mat, stride_words):
    """Convert matrix to list of hex words with given stride (in words)."""
    rows, cols = mat.shape
    words_per_row = (cols + 3) // 4
    all_words = []
    for r in range(rows):
        row_words = pack_row_to_words(mat[r])
        # Pad to stride_words
        while len(row_words) < stride_words:
            row_words.append(0)
        all_words.extend(row_words)
    return all_words

def gemm_uint8_truncated(A, B):
    """Compute C = A @ B with full precision, then truncate to uint8."""
    C_full = A.astype(np.int32) @ B.astype(np.int32)
    C_trunc = C_full & 0xFF
    return C_trunc.astype(np.uint8)

def write_hex_file(filepath, words):
    """Write words as hex file for $readmemh."""
    with open(filepath, 'w') as f:
        for w in words:
            f.write(f"{w:08x}\n")

def generate_test(test_id, M, K, N, out_dir, max_val=15):
    """Generate one random GEMM test case."""
    np.random.seed(test_id * 1000 + M * 100 + K * 10 + N)
    
    A = np.random.randint(0, max_val + 1, size=(M, K), dtype=np.uint8)
    B = np.random.randint(0, max_val + 1, size=(K, N), dtype=np.uint8)
    C = gemm_uint8_truncated(A, B)
    
    stride_a_words = (K + 3) // 4
    stride_b_words = (N + 3) // 4
    stride_c_words = (N + 3) // 4
    
    a_words = matrix_to_hex_words(A, stride_a_words)
    b_words = matrix_to_hex_words(B, stride_b_words)
    c_words = matrix_to_hex_words(C, stride_c_words)
    
    write_hex_file(os.path.join(out_dir, f"test_{test_id}_A.hex"), a_words)
    write_hex_file(os.path.join(out_dir, f"test_{test_id}_B.hex"), b_words)
    write_hex_file(os.path.join(out_dir, f"test_{test_id}_C.hex"), c_words)
    
    return {
        'id': test_id,
        'M': M, 'K': K, 'N': N,
        'stride_a': stride_a_words * 4,
        'stride_b': stride_b_words * 4,
        'stride_c': stride_c_words * 4,
        'A': A, 'B': B, 'C': C,
        'a_words': len(a_words),
        'b_words': len(b_words),
        'c_words': len(c_words),
    }

def main():
    parser = argparse.ArgumentParser(description='GEMM golden model generator')
    parser.add_argument('--count', type=int, default=10, help='Number of random tests')
    parser.add_argument('--sizes', type=str, default='4,8,12', help='Comma-separated matrix sizes')
    parser.add_argument('--max-val', type=int, default=15, help='Max element value')
    args = parser.parse_args()
    
    out_dir = os.path.dirname(os.path.abspath(__file__))
    sizes = [int(s) for s in args.sizes.split(',')]
    
    summary_lines = []
    summary_lines.append("GEMM Golden Model Test Summary")
    summary_lines.append("=" * 60)
    
    test_id = 0
    all_pass = True
    
    # Fixed known-good tests
    known_tests = [
        (4, 4, 4),
        (8, 8, 8),
        (4, 8, 4),
        (8, 4, 8),
        (12, 12, 12),
        (4, 12, 4),
    ]
    
    for M, K, N in known_tests:
        info = generate_test(test_id, M, K, N, out_dir, args.max_val)
        line = f"Test {test_id:3d}: {M:2d}x{K:2d} * {K:2d}x{N:2d} -> {M:2d}x{N:2d}  stride_a={info['stride_a']:3d}  stride_b={info['stride_b']:3d}  stride_c={info['stride_c']:3d}"
        summary_lines.append(line)
        
        # Self-check
        C_check = gemm_uint8_truncated(info['A'], info['B'])
        if not np.array_equal(C_check, info['C']):
            summary_lines.append(f"  ** SELF-CHECK FAILED **")
            all_pass = False
        
        test_id += 1
    
    # Random tests
    for i in range(args.count):
        M = np.random.choice(sizes)
        K = np.random.choice(sizes)
        N = np.random.choice(sizes)
        
        info = generate_test(test_id, M, K, N, out_dir, args.max_val)
        line = f"Test {test_id:3d}: {M:2d}x{K:2d} * {K:2d}x{N:2d} -> {M:2d}x{N:2d}  stride_a={info['stride_a']:3d}  stride_b={info['stride_b']:3d}  stride_c={info['stride_c']:3d}"
        summary_lines.append(line)
        
        C_check = gemm_uint8_truncated(info['A'], info['B'])
        if not np.array_equal(C_check, info['C']):
            summary_lines.append(f"  ** SELF-CHECK FAILED **")
            all_pass = False
        
        test_id += 1
    
    summary_lines.append("=" * 60)
    if all_pass:
        summary_lines.append(f"All {test_id} golden model self-checks PASSED")
    else:
        summary_lines.append("SOME SELF-CHECKS FAILED")
    
    summary_path = os.path.join(out_dir, "test_summary.txt")
    with open(summary_path, 'w') as f:
        f.write('\n'.join(summary_lines) + '\n')
    
    # Print detailed first test for manual verification
    print('\n'.join(summary_lines))
    
    info = generate_test(0, 4, 4, 4, out_dir, args.max_val)
    print(f"\nDetailed Test 0 (4x4):")
    print(f"A =\n{info['A']}")
    print(f"B =\n{info['B']}")
    print(f"C = A*B (uint8 truncated) =\n{info['C']}")
    print(f"\nA packed words: {[f'0x{w:08x}' for w in matrix_to_hex_words(info['A'], 1)]}")
    print(f"B packed words: {[f'0x{w:08x}' for w in matrix_to_hex_words(info['B'], 1)]}")
    print(f"C packed words: {[f'0x{w:08x}' for w in matrix_to_hex_words(info['C'], 1)]}")

if __name__ == '__main__':
    main()
