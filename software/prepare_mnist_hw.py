#!/usr/bin/env python3
"""
Prepare MNIST data for hardware GEMM accelerator.

Extracts TFLite-quantized weights, computes intermediate activations,
and generates a C header for firmware verification.
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '3'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

import numpy as np
import tensorflow as tf
import warnings
warnings.filterwarnings('ignore')

NUM_IMAGES = 3
PAD4 = lambda x: (x + 3) & ~3


def im2col_np(input_hwc_flat, w_in, c_in, kh, kw, stride, h_out, w_out):
    rows = h_out * w_out
    cols = kh * kw * c_in
    buf = np.zeros((rows, cols), dtype=np.uint8)
    for oh in range(h_out):
        for ow in range(w_out):
            row = oh * w_out + ow
            col = 0
            for fh in range(kh):
                for fw in range(kw):
                    for fc in range(c_in):
                        ih = oh * stride + fh
                        iw = ow * stride + fw
                        buf[row, col] = input_hwc_flat[(ih * w_in + iw) * c_in + fc]
                        col += 1
    return buf


def hw_gemm_acc32(A, B):
    """Our HW in acc32 mode: uint8 * uint8, full 32-bit accumulator output."""
    M, K = A.shape
    _, N = B.shape
    C = np.zeros((M, N), dtype=np.uint32)
    for i in range(M):
        for j in range(N):
            acc = np.uint32(0)
            for k in range(K):
                acc += np.uint32(A[i, k]) * np.uint32(B[k, j])
            C[i, j] = acc
    return C


def compute_requant_params(acc32_matrix):
    """Compute per-layer fixed-point requantization params from actual acc range.
    Returns (multiplier, shift) such that:
        output_u8 = clamp((acc32 * multiplier) >> shift, 0, 255)
    """
    max_val = int(np.max(acc32_matrix))
    if max_val == 0:
        return 1, 0
    shift = 16
    multiplier = int(round(255.0 * (1 << shift) / max_val))
    while multiplier > 0x7FFF and shift < 24:
        shift += 1
        multiplier = int(round(255.0 * (1 << shift) / max_val))
    return multiplier, shift


def requantize_u8(acc32_matrix, multiplier, shift):
    """Fixed-point requantization to uint8."""
    out = np.zeros(acc32_matrix.shape, dtype=np.uint8)
    for i in range(acc32_matrix.shape[0]):
        for j in range(acc32_matrix.shape[1]):
            val = (int(acc32_matrix[i, j]) * multiplier) >> shift
            out[i, j] = min(val, 255)
    return out


def quantized_conv2d_numpy(input_uint8, weights_int8, bias_int32,
                           in_scale, w_scales, out_scale, out_zp,
                           kh, kw, stride, h_out, w_out, w_in, c_in, c_out):
    """Full quantized Conv2D with proper requantization (numpy reference)."""
    col = im2col_np(input_uint8.flatten(), w_in, c_in, kh, kw, stride, h_out, w_out)
    W = weights_int8.reshape(c_out, kh * kw * c_in).T  # [K, C_out]

    rows = h_out * w_out
    output = np.zeros((rows, c_out), dtype=np.int8)

    for i in range(rows):
        for f in range(c_out):
            acc = np.int32(0)
            for k in range(kh * kw * c_in):
                acc += np.int32(col[i, k]) * np.int32(W[k, f])
            acc += bias_int32[f]
            M = float(in_scale) * float(w_scales[f]) / float(out_scale)
            val = int(round(float(acc) * M)) + int(out_zp)
            val = max(-128, min(127, val))
            val = max(int(out_zp), val)  # ReLU in quantized domain
            output[i, f] = np.int8(val)

    return output


def checksum_uint8(arr):
    return int(np.sum(arr.flatten().astype(np.uint32)))


def main():
    print("Loading TFLite model...")
    tflite = open('build/mnist_quant.tflite', 'rb').read()
    (_, _), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_test_float = x_test.astype(np.float32) / 255.0

    interp = tf.lite.Interpreter(model_content=tflite)
    interp.allocate_tensors()

    inp_det = interp.get_input_details()[0]
    out_det = interp.get_output_details()[0]
    in_scale = float(inp_det['quantization_parameters']['scales'][0])

    # Get tensor details for quantization params
    td_map = {}
    for td in interp.get_tensor_details():
        td_map[td['index']] = td

    # Extract constant weights
    conv1_w = interp.get_tensor(9).copy()   # [8, 3, 3, 1] int8
    conv1_b = interp.get_tensor(8).copy()   # [8] int32
    conv1_w_scales = np.array(td_map[9]['quantization_parameters']['scales'])

    conv2_w = interp.get_tensor(7).copy()   # [16, 3, 3, 8] int8
    conv2_b = interp.get_tensor(6).copy()   # [16] int32
    conv2_w_scales = np.array(td_map[7]['quantization_parameters']['scales'])

    fc_w = interp.get_tensor(5).copy()      # [10, 576] int8
    fc_b = interp.get_tensor(4).copy()      # [10] int32
    fc_w_scales = np.array(td_map[5]['quantization_parameters']['scales'])

    # Conv1 output quantization (tensor 11)
    conv1_out_scale = float(td_map[11]['quantization_parameters']['scales'][0])
    conv1_out_zp = int(td_map[11]['quantization_parameters']['zero_points'][0])

    # Conv2 output quantization (tensor 12)
    conv2_out_scale = float(td_map[12]['quantization_parameters']['scales'][0])
    conv2_out_zp = int(td_map[12]['quantization_parameters']['zero_points'][0])

    # FC output quantization (tensor 17)
    fc_out_scale = float(td_map[17]['quantization_parameters']['scales'][0])
    fc_out_zp = int(td_map[17]['quantization_parameters']['zero_points'][0])

    print(f"  Conv1 weights: {conv1_w.shape}, bias: {conv1_b.shape}")
    print(f"  Conv2 weights: {conv2_w.shape}, bias: {conv2_b.shape}")
    print(f"  FC weights:    {fc_w.shape}, bias: {fc_b.shape}")
    print(f"  Conv1 output: scale={conv1_out_scale:.6f}, zp={conv1_out_zp}")
    print(f"  Conv2 output: scale={conv2_out_scale:.6f}, zp={conv2_out_zp}")
    print(f"  FC output:    scale={fc_out_scale:.6f}, zp={fc_out_zp}")

    # Convert weights to uint8 for HW GEMM: int8 + 128
    conv1_w_gemm = conv1_w.reshape(8, 9).T  # [9, 8]
    conv1_w_uint8 = (conv1_w_gemm.astype(np.int16) + 128).astype(np.uint8)

    conv2_w_gemm = conv2_w.reshape(16, 72).T  # [72, 16]
    conv2_w_uint8 = (conv2_w_gemm.astype(np.int16) + 128).astype(np.uint8)

    fc_w_gemm = fc_w.T  # [576, 10]
    fc_w_uint8_raw = (fc_w_gemm.astype(np.int16) + 128).astype(np.uint8)
    # Pad FC weights: stride from 10 to PAD4(10)=12 for DMA alignment
    fc_w_uint8 = np.zeros((576, 12), dtype=np.uint8)
    fc_w_uint8[:, :10] = fc_w_uint8_raw

    print(f"\n  HW weight shapes: Conv1={conv1_w_uint8.shape}, Conv2={conv2_w_uint8.shape}, FC={fc_w_uint8.shape} (padded)")

    # Select test images and compute everything
    results = []
    for i in range(len(x_test)):
        if len(results) >= NUM_IMAGES:
            break

        img_float = x_test_float[i:i+1][..., np.newaxis]
        img_uint8 = np.clip(np.round(img_float / in_scale), 0, 255).astype(np.uint8)

        # Run TFLite reference
        interp.set_tensor(inp_det['index'], img_uint8)
        interp.invoke()
        tflite_output = interp.get_tensor(out_det['index'])[0]
        tflite_pred = int(np.argmax(tflite_output))

        if tflite_pred != int(y_test[i]):
            continue

        img_flat = img_uint8[0, :, :, 0]  # [28, 28] uint8
        print(f"\n--- Image {len(results)+1}: digit={y_test[i]}, TFLite pred={tflite_pred} ---")

        # === Conv1 GEMM on HW (acc32 + requantize) ===
        col1 = im2col_np(img_flat.flatten(), 28, 1, 3, 3, 2, 13, 13)  # [169, 9]
        conv1_acc32 = hw_gemm_acc32(col1, conv1_w_uint8)  # [169, 8] uint32
        c1_mult, c1_shift = compute_requant_params(conv1_acc32)
        conv1_hw = requantize_u8(conv1_acc32, c1_mult, c1_shift)
        conv1_hw_chk = checksum_uint8(conv1_hw)
        print(f"  Conv1: acc32 range=[{int(np.min(conv1_acc32))},{int(np.max(conv1_acc32))}]")
        print(f"    requant: mult={c1_mult}, shift={c1_shift}, chk=0x{conv1_hw_chk:08X}")

        # Conv1 proper output for chaining (from TFLite requantization)
        conv1_act_int8 = quantized_conv2d_numpy(
            img_flat.flatten(), conv1_w, conv1_b,
            in_scale, conv1_w_scales, conv1_out_scale, conv1_out_zp,
            3, 3, 2, 13, 13, 28, 1, 8
        )
        conv1_act_uint8 = (conv1_act_int8.astype(np.int16) + 128).astype(np.uint8)

        # === Conv2 GEMM on HW (acc32 + requantize) ===
        col2 = im2col_np(conv1_act_uint8.flatten(), 13, 8, 3, 3, 2, 6, 6)  # [36, 72]
        conv2_acc32 = hw_gemm_acc32(col2, conv2_w_uint8)
        c2_mult, c2_shift = compute_requant_params(conv2_acc32)
        conv2_hw = requantize_u8(conv2_acc32, c2_mult, c2_shift)
        conv2_hw_chk = checksum_uint8(conv2_hw)
        print(f"  Conv2: acc32 range=[{int(np.min(conv2_acc32))},{int(np.max(conv2_acc32))}]")
        print(f"    requant: mult={c2_mult}, shift={c2_shift}, chk=0x{conv2_hw_chk:08X}")

        conv2_act_int8 = quantized_conv2d_numpy(
            conv1_act_uint8.flatten(), conv2_w, conv2_b,
            conv1_out_scale, conv2_w_scales, conv2_out_scale, conv2_out_zp,
            3, 3, 2, 6, 6, 13, 8, 16
        )
        conv2_act_uint8 = (conv2_act_int8.astype(np.int16) + 128).astype(np.uint8)

        # === FC GEMM on HW (acc32 + requantize) ===
        fc_in_uint8 = conv2_act_uint8.reshape(1, -1)  # [1, 576]
        fc_acc32 = hw_gemm_acc32(fc_in_uint8, fc_w_uint8_raw)
        fc_mult, fc_shift = compute_requant_params(fc_acc32)
        fc_hw = requantize_u8(fc_acc32, fc_mult, fc_shift)
        fc_hw_chk = checksum_uint8(fc_hw)
        print(f"  FC: acc32 range=[{int(np.min(fc_acc32))},{int(np.max(fc_acc32))}]")
        print(f"    requant: mult={fc_mult}, shift={fc_shift}, chk=0x{fc_hw_chk:08X}")
        print(f"    requant scores: {list(fc_hw[0])}")
        print(f"    TFLite label: {tflite_pred}")

        results.append({
            'image': img_flat,
            'label': int(y_test[i]),
            'tflite_pred': tflite_pred,
            'conv1_hw_chk': conv1_hw_chk,
            'c1_mult': c1_mult, 'c1_shift': c1_shift,
            'conv1_act_uint8': conv1_act_uint8.flatten(),
            'conv2_hw_chk': conv2_hw_chk,
            'c2_mult': c2_mult, 'c2_shift': c2_shift,
            'conv2_act_uint8': conv2_act_uint8.flatten(),
            'fc_hw_chk': fc_hw_chk,
            'fc_mult': fc_mult, 'fc_shift': fc_shift,
        })

    # Generate C header
    print("\n\nGenerating C header...")
    generate_header(results, conv1_w_uint8, conv2_w_uint8, fc_w_uint8)
    print("Done!")

    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    for i, r in enumerate(results):
        print(f"  Image {i+1}: digit={r['label']}, pred={r['tflite_pred']}")
        print(f"    Conv1 chk=0x{r['conv1_hw_chk']:08X}, Conv2 chk=0x{r['conv2_hw_chk']:08X}, FC chk=0x{r['fc_hw_chk']:08X}")


def generate_header(results, conv1_w, conv2_w, fc_w):
    n = len(results)
    path = "include/mnist_hw.h"
    os.makedirs("include", exist_ok=True)

    with open(path, 'w') as f:
        f.write("/* Auto-generated by prepare_mnist_hw.py -- DO NOT EDIT */\n")
        f.write("/* Real TFLite-quantized MNIST weights + golden values */\n")
        f.write("#ifndef MNIST_HW_H\n#define MNIST_HW_H\n#include <stdint.h>\n\n")

        f.write(f"#define MNIST_N_IMAGES {n}\n\n")

        # Network constants
        f.write("/* Conv1: 3x3, 1->8, stride 2 */\n")
        f.write("#define C1_HOUT 13\n#define C1_WOUT 13\n#define C1_COUT 8\n")
        f.write("#define C1_IM2COL_ROWS 169\n#define C1_IM2COL_COLS 9\n")
        f.write("#define C1_IM2COL_STRIDE 12\n#define C1_ACT_SIZE 1352\n\n")

        f.write("/* Conv2: 3x3, 8->16, stride 2 */\n")
        f.write("#define C2_HOUT 6\n#define C2_WOUT 6\n#define C2_COUT 16\n#define C2_CIN 8\n")
        f.write("#define C2_IM2COL_ROWS 36\n#define C2_IM2COL_COLS 72\n")
        f.write("#define C2_IM2COL_STRIDE 72\n#define C2_ACT_SIZE 576\n\n")

        f.write("/* FC: 576 -> 10 (B stride padded to 12 for DMA alignment) */\n")
        f.write("#define FC_DIM_IN 576\n#define FC_DIM_OUT 10\n")
        f.write("#define FC_W_STRIDE 12\n#define FC_OUT_STRIDE 12\n\n")

        def write_arr(name, data, dtype_c):
            flat = data.flatten()
            f.write(f"static const {dtype_c} {name}[{len(flat)}] = {{\n")
            for i in range(0, len(flat), 16):
                chunk = flat[i:i+16]
                vals = ", ".join(f"{int(v):4d}" for v in chunk)
                f.write(f"  {vals},\n")
            f.write("};\n\n")

        write_arr("conv1_w", conv1_w, "uint8_t")
        write_arr("conv2_w", conv2_w, "uint8_t")
        write_arr("fc_w", fc_w, "uint8_t")

        # Test images
        for i, r in enumerate(results):
            write_arr(f"mnist_img{i}", r['image'], "uint8_t")

        # Precomputed intermediate activations
        for i, r in enumerate(results):
            write_arr(f"conv1_act{i}", r['conv1_act_uint8'], "uint8_t")
            write_arr(f"conv2_act{i}", r['conv2_act_uint8'], "uint8_t")

        # Requantization parameters per image (computed from acc32 ranges)
        f.write("/* Per-image requantization: output_u8 = clamp((acc32 * mult) >> shift, 0, 255) */\n")
        f.write("static const uint32_t c1_requant_mult[] = { ")
        f.write(", ".join(f"{r['c1_mult']}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t c1_requant_shift[] = { ")
        f.write(", ".join(f"{r['c1_shift']}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t c2_requant_mult[] = { ")
        f.write(", ".join(f"{r['c2_mult']}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t c2_requant_shift[] = { ")
        f.write(", ".join(f"{r['c2_shift']}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t fc_requant_mult[] = { ")
        f.write(", ".join(f"{r['fc_mult']}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t fc_requant_shift[] = { ")
        f.write(", ".join(f"{r['fc_shift']}u" for r in results))
        f.write(" };\n\n")

        # Golden checksums (now computed WITH requantization, not truncation)
        f.write("/* Golden checksums (computed with requantization, not truncation) */\n")
        f.write("static const uint32_t golden_c1_chk[] = { ")
        f.write(", ".join(f"0x{r['conv1_hw_chk']:08X}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t golden_c2_chk[] = { ")
        f.write(", ".join(f"0x{r['conv2_hw_chk']:08X}u" for r in results))
        f.write(" };\n")
        f.write("static const uint32_t golden_fc_chk[] = { ")
        f.write(", ".join(f"0x{r['fc_hw_chk']:08X}u" for r in results))
        f.write(" };\n\n")

        # Expected labels
        f.write("static const uint8_t mnist_labels[] = { ")
        f.write(", ".join(str(r['tflite_pred']) for r in results))
        f.write(" };\n\n")

        # Pointer arrays for easy indexing
        f.write("static const uint8_t * const mnist_imgs[] = { ")
        f.write(", ".join(f"mnist_img{i}" for i in range(n)))
        f.write(" };\n")
        f.write("static const uint8_t * const conv1_acts[] = { ")
        f.write(", ".join(f"conv1_act{i}" for i in range(n)))
        f.write(" };\n")
        f.write("static const uint8_t * const conv2_acts[] = { ")
        f.write(", ".join(f"conv2_act{i}" for i in range(n)))
        f.write(" };\n\n")

        f.write("#endif\n")

    sz = os.path.getsize(path)
    print(f"  Generated {path} ({sz} bytes)")


if __name__ == "__main__":
    main()
