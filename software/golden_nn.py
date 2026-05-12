#!/usr/bin/env python3
"""
Golden Model for a complete 3-layer neural network on the GEMM accelerator.

Network architecture:
    Input   : 8x8x1 grayscale image
    Conv1   : 3x3, 1 -> 4 channels, stride 1  =>  6x6x4
    ReLU
    Conv2   : 3x3, 4 -> 8 channels, stride 1  =>  4x4x8
    ReLU
    FC      : 128 -> 4 classes
    Argmax  -> predicted class

DMA constraint: all row strides must be multiples of 4 bytes.

Usage:
    python golden_nn.py             # run full inference, print expected values
    python golden_nn.py --header    # print C constants for firmware embedding
"""

import numpy as np
import sys

PAD4 = lambda x: (x + 3) & ~3

# ============================================================
# Network parameters
# ============================================================
INPUT_H, INPUT_W, INPUT_C = 8, 8, 1

CONV1_KH, CONV1_KW = 3, 3
CONV1_C_IN, CONV1_C_OUT = 1, 4
CONV1_STRIDE = 1
CONV1_H_OUT = (INPUT_H - CONV1_KH) // CONV1_STRIDE + 1  # 6
CONV1_W_OUT = (INPUT_W - CONV1_KW) // CONV1_STRIDE + 1  # 6

CONV2_KH, CONV2_KW = 3, 3
CONV2_C_IN, CONV2_C_OUT = 4, 8
CONV2_STRIDE = 1
CONV2_H_OUT = (CONV1_H_OUT - CONV2_KH) // CONV2_STRIDE + 1  # 4
CONV2_W_OUT = (CONV1_W_OUT - CONV2_KW) // CONV2_STRIDE + 1  # 4

FC_IN = CONV2_H_OUT * CONV2_W_OUT * CONV2_C_OUT  # 128
FC_OUT = 4

# ============================================================
# Weight/input initialization (deterministic, same as firmware)
# ============================================================

def make_input():
    """8x8 image with a gradient + cross pattern."""
    img = np.zeros((INPUT_H, INPUT_W), dtype=np.uint8)
    for r in range(INPUT_H):
        for c in range(INPUT_W):
            img[r, c] = ((r * 17 + c * 13 + 5) & 0x1F)
    return img

def make_conv1_weights():
    """4 filters of 3x3x1, stored as (K_h*K_w*C_in) x C_out = 9 x 4."""
    W = np.zeros((9, 4), dtype=np.uint8)
    patterns = [
        [0,1,0, 1,2,1, 0,1,0],   # cross/Laplacian
        [1,1,1, 1,0,1, 1,1,1],   # box
        [1,2,1, 0,0,0, 0,0,0],   # top edge
        [0,0,1, 0,1,0, 1,0,0],   # diagonal
    ]
    for f in range(4):
        for k in range(9):
            W[k, f] = patterns[f][k]
    return W

def make_conv2_weights():
    """8 filters of 3x3x4, stored as (K_h*K_w*C_in) x C_out = 36 x 8."""
    W = np.zeros((36, 8), dtype=np.uint8)
    for k in range(36):
        for f in range(8):
            W[k, f] = ((k * 3 + f * 7 + 1) & 0x07)
    return W

def make_fc_weights():
    """FC: 128 x 4."""
    W = np.zeros((128, 4), dtype=np.uint8)
    for i in range(128):
        for j in range(4):
            W[i, j] = ((i * (j + 3) + j * j * 7 + 2) & 0x0F)
    return W

# ============================================================
# im2col (matches firmware logic)
# ============================================================

def im2col(input_hwc, kh, kw, c_in, stride, h_out, w_out, w_in):
    """
    Transform input patches into a matrix for GEMM-based convolution.
    input_hwc: stored as flat array in HWC order
    Returns: (h_out * w_out) x (kh * kw * c_in) matrix
    """
    rows = h_out * w_out
    cols = kh * kw * c_in
    col_buf = np.zeros((rows, cols), dtype=np.uint8)

    for oh in range(h_out):
        for ow in range(w_out):
            row = oh * w_out + ow
            col = 0
            for fh in range(kh):
                for fw in range(kw):
                    for fc in range(c_in):
                        ih = oh * stride + fh
                        iw = ow * stride + fw
                        col_buf[row, col] = input_hwc[(ih * w_in + iw) * c_in + fc]
                        col += 1
    return col_buf

def gemm_acc32(A, B):
    """C = A @ B with uint32 accumulation, full 32-bit output."""
    M, K1 = A.shape
    K2, N = B.shape
    assert K1 == K2
    C = np.zeros((M, N), dtype=np.uint32)
    for i in range(M):
        for j in range(N):
            acc = np.uint32(0)
            for k in range(K1):
                acc += np.uint32(A[i, k]) * np.uint32(B[k, j])
            C[i, j] = acc
    return C

def compute_requant_params(acc32_matrix):
    """Compute TFLite-style fixed-point requantization parameters.

    Given the actual range of accumulator values, find (multiplier, shift)
    such that: output_u8 = clamp((acc32 * multiplier) >> shift, 0, 255)
    maps the accumulator range into [0, 255].
    """
    max_val = int(np.max(acc32_matrix))
    if max_val == 0:
        return 1, 0  # identity

    # We want: max_val * multiplier >> shift ≈ 255
    # Choose shift = 16 (Q16 fixed point), solve for multiplier
    shift = 16
    multiplier = int(round(255.0 * (1 << shift) / max_val))
    # Clamp multiplier to fit in 16 bits for safe 32-bit multiply
    if multiplier > 0x7FFF:
        shift += 1
        multiplier = int(round(255.0 * (1 << shift) / max_val))
    if multiplier > 0x7FFF:
        shift += 1
        multiplier = int(round(255.0 * (1 << shift) / max_val))
    return multiplier, shift

def requantize(acc32_matrix, multiplier, shift):
    """Apply fixed-point requantization: clamp((acc * multiplier) >> shift, 0, 255)."""
    out = np.zeros(acc32_matrix.shape, dtype=np.uint8)
    for i in range(acc32_matrix.shape[0]):
        for j in range(acc32_matrix.shape[1]):
            val = (int(acc32_matrix[i, j]) * multiplier) >> shift
            if val < 0: val = 0
            if val > 255: val = 255
            out[i, j] = val
    return out

def relu_uint8(x):
    """ReLU for uint8: clamp values below zero_point to zero_point.
    For unsigned uint8, this is effectively a no-op since all values >= 0.
    Included for architectural completeness."""
    return x.copy()

def checksum(arr):
    return int(np.sum(arr.astype(np.uint32)))

# ============================================================
# Full inference pipeline
# ============================================================

def run_inference():
    # Input
    img = make_input()
    img_flat = img.reshape(-1)
    print(f"Input: {INPUT_H}x{INPUT_W}x{INPUT_C}")
    print(f"  checksum = {checksum(img_flat)}, first 8 = {list(img_flat[:8])}")

    # --- Conv1: acc32 -> requantize -> ReLU ---
    conv1_w = make_conv1_weights()
    im2col1_cols = CONV1_KH * CONV1_KW * CONV1_C_IN  # 9
    im2col1_rows = CONV1_H_OUT * CONV1_W_OUT          # 36
    im2col1_stride = PAD4(im2col1_cols)                # 12

    print(f"\nConv1: {CONV1_KH}x{CONV1_KW}, {CONV1_C_IN}->{CONV1_C_OUT}")

    col1 = im2col(img_flat, CONV1_KH, CONV1_KW, CONV1_C_IN,
                  CONV1_STRIDE, CONV1_H_OUT, CONV1_W_OUT, INPUT_W)
    conv1_acc32 = gemm_acc32(col1, conv1_w)
    conv1_mult, conv1_shift = compute_requant_params(conv1_acc32)
    conv1_out = requantize(conv1_acc32, conv1_mult, conv1_shift)
    conv1_relu = relu_uint8(conv1_out)

    print(f"  acc32 range: [{int(np.min(conv1_acc32))}, {int(np.max(conv1_acc32))}]")
    print(f"  requant params: mult={conv1_mult}, shift={conv1_shift}")
    print(f"  output: checksum={checksum(conv1_relu)}, C[0]={list(conv1_relu[0])}")

    # --- Conv2: acc32 -> requantize -> ReLU ---
    conv2_w = make_conv2_weights()
    im2col2_cols = CONV2_KH * CONV2_KW * CONV2_C_IN  # 36
    im2col2_rows = CONV2_H_OUT * CONV2_W_OUT          # 16
    im2col2_stride = PAD4(im2col2_cols)                # 36

    print(f"\nConv2: {CONV2_KH}x{CONV2_KW}, {CONV2_C_IN}->{CONV2_C_OUT}")

    conv1_flat = conv1_relu.reshape(-1)
    col2 = im2col(conv1_flat, CONV2_KH, CONV2_KW, CONV2_C_IN,
                  CONV2_STRIDE, CONV2_H_OUT, CONV2_W_OUT, CONV1_W_OUT)
    conv2_acc32 = gemm_acc32(col2, conv2_w)
    conv2_mult, conv2_shift = compute_requant_params(conv2_acc32)
    conv2_out = requantize(conv2_acc32, conv2_mult, conv2_shift)
    conv2_relu = relu_uint8(conv2_out)

    print(f"  acc32 range: [{int(np.min(conv2_acc32))}, {int(np.max(conv2_acc32))}]")
    print(f"  requant params: mult={conv2_mult}, shift={conv2_shift}")
    print(f"  output: checksum={checksum(conv2_relu)}, C[0]={list(conv2_relu[0])}")

    # --- FC: acc32 -> requantize ---
    fc_w = make_fc_weights()
    fc_input = conv2_relu.reshape(1, -1)  # 1 x 128
    print(f"\nFC: {FC_IN} -> {FC_OUT}")

    fc_acc32 = gemm_acc32(fc_input, fc_w)
    fc_mult, fc_shift = compute_requant_params(fc_acc32)
    fc_out = requantize(fc_acc32, fc_mult, fc_shift)

    print(f"  acc32 range: [{int(np.min(fc_acc32))}, {int(np.max(fc_acc32))}]")
    print(f"  acc32 raw: {[int(v) for v in fc_acc32[0]]}")
    print(f"  requant params: mult={fc_mult}, shift={fc_shift}")
    print(f"  output: {list(fc_out[0])}, checksum={checksum(fc_out)}")

    # --- Argmax ---
    predicted = int(np.argmax(fc_out[0]))
    print(f"\nArgmax: class {predicted} (value {fc_out[0, predicted]})")

    # --- Summary ---
    print("\n" + "=" * 60)
    print("GOLDEN VALUES FOR FIRMWARE (with requantization):")
    print("=" * 60)
    print(f"  Conv1: mult={conv1_mult}, shift={conv1_shift}")
    print(f"    checksum = 0x{checksum(conv1_relu):08X}  C[0][0] = 0x{int(conv1_relu[0,0]):02X}")
    print(f"  Conv2: mult={conv2_mult}, shift={conv2_shift}")
    print(f"    checksum = 0x{checksum(conv2_relu):08X}  C[0][0] = 0x{int(conv2_relu[0,0]):02X}")
    print(f"  FC:    mult={fc_mult}, shift={fc_shift}")
    print(f"    checksum = 0x{checksum(fc_out):08X}")
    print(f"    outputs  = [{', '.join(f'0x{int(v):02X}' for v in fc_out[0])}]")
    print(f"  predicted_class = {predicted}")

    return {
        'conv1_chk': checksum(conv1_relu), 'conv1_c00': int(conv1_relu[0, 0]),
        'conv1_mult': conv1_mult, 'conv1_shift': conv1_shift,
        'conv2_chk': checksum(conv2_relu), 'conv2_c00': int(conv2_relu[0, 0]),
        'conv2_mult': conv2_mult, 'conv2_shift': conv2_shift,
        'fc_chk': checksum(fc_out), 'fc_out': [int(v) for v in fc_out[0]],
        'fc_mult': fc_mult, 'fc_shift': fc_shift,
        'predicted': predicted,
    }


if __name__ == "__main__":
    result = run_inference()

    if len(sys.argv) > 1 and sys.argv[1] == "--header":
        print("\n/* C constants for firmware (requantization) */")
        print(f"#define CONV1_REQUANT_MULT   {result['conv1_mult']}u")
        print(f"#define CONV1_REQUANT_SHIFT  {result['conv1_shift']}u")
        print(f"#define GOLDEN_CONV1_CHECKSUM  0x{result['conv1_chk']:08X}u")
        print(f"#define GOLDEN_CONV1_C00       0x{result['conv1_c00']:02X}u")
        print(f"#define CONV2_REQUANT_MULT   {result['conv2_mult']}u")
        print(f"#define CONV2_REQUANT_SHIFT  {result['conv2_shift']}u")
        print(f"#define GOLDEN_CONV2_CHECKSUM  0x{result['conv2_chk']:08X}u")
        print(f"#define GOLDEN_CONV2_C00       0x{result['conv2_c00']:02X}u")
        print(f"#define FC_REQUANT_MULT      {result['fc_mult']}u")
        print(f"#define FC_REQUANT_SHIFT     {result['fc_shift']}u")
        print(f"#define GOLDEN_FC_CHECKSUM     0x{result['fc_chk']:08X}u")
        fc_str = ', '.join(f"0x{v:02X}" for v in result['fc_out'])
        print(f"#define GOLDEN_FC_OUT          {{ {fc_str} }}")
        print(f"#define GOLDEN_CLASS           {result['predicted']}u")
