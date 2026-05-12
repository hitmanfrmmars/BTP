#!/usr/bin/env python3
"""
Golden Model for GEMM Accelerator Stress Test

Computes the mathematically correct output for each of the 21 stress test
patterns. These are the REAL correct answers -- the same result you'd get
from any correct matrix multiplication implementation.

Usage:
    python golden_model.py              # run all 21 tests, print summary
    python golden_model.py --dump 7     # dump full matrices for test 7
    python golden_model.py --header     # generate C header with checksums

The firmware (stress_test_fast.c) uses all-ones matrices so the expected
output is trivially: C[i][j] = K (truncated to uint8).  This script also
supports arbitrary patterns for cross-validation.
"""

import numpy as np
import sys

# ============================================================
# Test pattern generators (identical logic to stress_test.c)
# ============================================================

def init_pattern(rows, cols, seed=0):
    """Same as init_matrix_pattern: (seed + r*3 + c*7) & 0xFF"""
    A = np.zeros((rows, cols), dtype=np.uint8)
    for r in range(rows):
        for c in range(cols):
            A[r, c] = (seed + r * 3 + c * 7) & 0xFF
    return A

def init_ones(rows, cols):
    return np.ones((rows, cols), dtype=np.uint8)

def init_identity(rows, cols):
    A = np.zeros((rows, cols), dtype=np.uint8)
    for i in range(min(rows, cols)):
        A[i, i] = 1
    return A

def init_max(rows, cols):
    return np.full((rows, cols), 0xFF, dtype=np.uint8)

def golden_gemm_int8(A, B):
    """Compute C = A @ B with uint32 accumulation, truncated to uint8."""
    M, K1 = A.shape
    K2, N = B.shape
    assert K1 == K2, f"K mismatch: A is {A.shape}, B is {B.shape}"
    C = np.zeros((M, N), dtype=np.uint8)
    for i in range(M):
        for j in range(N):
            acc = np.uint32(0)
            for k in range(K1):
                acc += np.uint32(A[i, k]) * np.uint32(B[k, j])
            C[i, j] = np.uint8(acc & 0xFF)
    return C

def golden_gemm_int8_acc32(A, B):
    """Compute C = A @ B with uint32 accumulation, full 32-bit output."""
    M, K1 = A.shape
    K2, N = B.shape
    assert K1 == K2, f"K mismatch: A is {A.shape}, B is {B.shape}"
    C = np.zeros((M, N), dtype=np.uint32)
    for i in range(M):
        for j in range(N):
            acc = np.uint32(0)
            for k in range(K1):
                acc += np.uint32(A[i, k]) * np.uint32(B[k, j])
            C[i, j] = acc
    return C

# ============================================================
# 21 stress test definitions
# ============================================================

TESTS = [
    # (test_num, M, K, N, pattern, description)
    ( 1,  1,  1,  1, "seq",   "1x1x1 trivial"),
    ( 2,  2,  2,  2, "seq",   "2x2x2 tiny"),
    ( 3,  3,  3,  3, "seq",   "3x3x3 small odd"),
    ( 4,  4,  4,  4, "seq",   "4x4x4 sub-tile"),
    ( 5,  5,  5,  5, "seq",   "5x5x5 non-aligned"),
    ( 6,  7,  7,  7, "seq",   "7x7x7 near boundary"),
    ( 7,  8,  8,  8, "seq",   "8x8x8 exact tile"),
    ( 8,  9,  9,  9, "seq",   "9x9x9 over one tile"),
    ( 9, 15, 15, 15, "seq",   "15x15x15 multi-tile"),
    (10, 16, 16, 16, "seq",   "16x16x16 exact multi-tile"),
    (11,  1,  8,  1, "seq",   "1x8x1 single row/col"),
    (12,  8,  1,  8, "seq",   "8x1x8 single K"),
    (13,  3,  5,  7, "seq",   "3x5x7 non-square"),
    (14,  7,  9,  3, "seq",   "7x9x3 non-square multi-K"),
    (15,  1, 16,  1, "seq",   "1x16x1 long K"),
    (16,  8,  8,  8, "ones",  "8x8x8 all-ones"),
    (17,  8,  8,  8, "ident", "8x8x8 identity A"),
    (18,  4,  4,  4, "max",   "4x4x4 max values"),
    (19,  8,  8,  8, "seq",   "8x8x8 back-to-back"),
    (20, 16,  8, 16, "seq",   "16x8x16 wide multi-tile"),
    (21,  8, 16,  8, "seq",   "8x16x8 tall K multi-tile"),
]


def generate_matrices(M, K, N, pattern, seed_a=0, seed_b=0):
    """Generate A and B matrices for a given pattern type."""
    if pattern == "seq":
        A = init_pattern(M, K, seed_a)
        B = init_pattern(K, N, seed_b)
    elif pattern == "ones":
        A = init_ones(M, K)
        B = init_ones(K, N)
    elif pattern == "ident":
        A = init_identity(M, K)
        B = init_pattern(K, N, seed_b)
    elif pattern == "max":
        A = init_max(M, K)
        B = init_max(K, N)
    else:
        raise ValueError(f"Unknown pattern: {pattern}")
    return A, B


def compute_checksum(C):
    """Simple checksum: sum of all elements as uint32."""
    return int(np.sum(C.astype(np.uint32)))


def run_all_tests(verbose=True):
    """Run golden model for all 21 tests."""
    results = []
    all_pass = True

    if verbose:
        print("=" * 72)
        print("  GEMM Golden Model -- All 21 Stress Test Patterns")
        print("=" * 72)
        print(f"{'#':>3} {'Dims':>12} {'Pattern':>7} {'Checksum':>10} {'C[0][0]':>8} {'Description'}")
        print("-" * 72)

    for num, M, K, N, pat, desc in TESTS:
        A, B = generate_matrices(M, K, N, pat)
        C = golden_gemm_int8(A, B)
        chk = compute_checksum(C)
        c00 = int(C[0, 0])

        results.append({
            "num": num, "M": M, "K": K, "N": N,
            "pattern": pat, "desc": desc,
            "checksum": chk, "c00": c00,
            "A": A, "B": B, "C": C,
        })

        if verbose:
            print(f"{num:3d} {M:3d}x{K:3d}x{N:3d} {pat:>7} {chk:10d} {c00:8d}   {desc}")

    if verbose:
        print("=" * 72)
        print(f"  All {len(TESTS)} golden results computed successfully.")
        print()

    return results


def dump_test(test_num, results):
    """Print full matrices for a specific test."""
    r = results[test_num - 1]
    print(f"\n=== Test {r['num']}: {r['desc']} ({r['M']}x{r['K']}x{r['N']}, {r['pattern']}) ===\n")
    print("A =")
    print(r['A'])
    print(f"\nB =")
    print(r['B'])
    print(f"\nC = A * B (uint8 truncated) =")
    print(r['C'])
    print(f"\nChecksum: {r['checksum']}")
    print(f"C[0][0] = {r['c00']}")


def generate_c_header(results):
    """Generate a C header with checksums and C[0][0] for firmware verification."""
    print("/* Auto-generated by golden_model.py -- DO NOT EDIT */")
    print("#ifndef GOLDEN_EXPECTED_H")
    print("#define GOLDEN_EXPECTED_H")
    print()
    print("#include <stdint.h>")
    print()
    print("typedef struct {")
    print("    uint16_t M, K, N;")
    print("    uint8_t  pattern;   /* 0=seq, 1=ones, 2=ident, 3=max */")
    print("    uint32_t checksum;  /* sum of all output bytes as uint32 */")
    print("    uint8_t  c00;       /* expected C[0][0] */")
    print("} golden_test_t;")
    print()
    print(f"#define NUM_GOLDEN_TESTS {len(results)}")
    print()
    print("static const golden_test_t golden_tests[NUM_GOLDEN_TESTS] = {")

    pat_map = {"seq": 0, "ones": 1, "ident": 2, "max": 3}
    for r in results:
        p = pat_map[r['pattern']]
        print(f"    {{ {r['M']:3d}, {r['K']:3d}, {r['N']:3d}, {p}, "
              f"0x{r['checksum']:08X}, 0x{r['c00']:02X} }},  "
              f"/* #{r['num']:2d}: {r['desc']} */")

    print("};")
    print()
    print("#endif /* GOLDEN_EXPECTED_H */")


def generate_ones_header():
    """Generate expected values for all-ones-only stress test (simplest)."""
    print("/* Expected values for all-ones stress test */")
    print("/* For all-ones A and B: C[i][j] = K & 0xFF */")
    print()
    dims = [
        (1,1,1), (2,2,2), (3,3,3), (4,4,4), (5,5,5),
        (7,7,7), (8,8,8), (9,9,9), (15,15,15), (16,16,16),
        (1,8,1), (8,1,8), (3,5,7), (7,9,3), (1,16,1),
        (8,8,8), (8,8,8), (4,4,4), (8,8,8),
        (16,8,16), (8,16,8),
    ]
    for i, (M, K, N) in enumerate(dims, 1):
        expected = K & 0xFF
        print(f"  Test {i:2d}: {M:2d}x{K:2d}x{N:2d}  ->  "
              f"every C[i][j] = {K} & 0xFF = {expected}")


# ============================================================
# Main
# ============================================================

if __name__ == "__main__":
    results = run_all_tests(verbose=True)

    if len(sys.argv) > 1:
        if sys.argv[1] == "--dump" and len(sys.argv) > 2:
            dump_test(int(sys.argv[2]), results)
        elif sys.argv[1] == "--header":
            print()
            generate_c_header(results)
        elif sys.argv[1] == "--ones":
            generate_ones_header()
