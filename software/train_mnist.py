#!/usr/bin/env python3
"""
Train a tiny MNIST classifier, quantize to int8 via TFLite,
extract weights, run reference inference, and generate a C header
for the GEMM accelerator firmware.

Network (kept tiny for edge deployment):
    Input:  28x28x1  (MNIST digit)
    Conv2D: 3x3, 1->8 channels, stride 2, valid padding  =>  13x13x8
    ReLU
    Conv2D: 3x3, 8->16 channels, stride 2, valid padding =>  6x6x16
    ReLU
    Flatten: 576
    Dense:  576 -> 10 (digits 0-9)

After quantization, all weights/activations become int8/uint8.
The accelerator runs the GEMM portions; bias-add and requantization
are done in software on the CPU.

Usage:
    python train_mnist.py
    # Generates: mnist_model.h (C header with weights + test images + expected labels)
"""

import os
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'

import numpy as np
import tensorflow as tf

HEADER_PATH = "include/mnist_model.h"
NUM_TEST_IMAGES = 10
SEED = 42

np.random.seed(SEED)
tf.random.set_seed(SEED)


# ============================================================
# 1. Train a small model
# ============================================================
def train_model():
    print("=" * 60)
    print(" Step 1: Training MNIST model")
    print("=" * 60)

    (x_train, y_train), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train = x_train.astype(np.float32) / 255.0
    x_test  = x_test.astype(np.float32) / 255.0
    x_train = x_train[..., np.newaxis]
    x_test  = x_test[..., np.newaxis]

    model = tf.keras.Sequential([
        tf.keras.layers.Input(shape=(28, 28, 1)),
        tf.keras.layers.Conv2D(8, 3, strides=2, padding='valid', activation='relu'),
        tf.keras.layers.Conv2D(16, 3, strides=2, padding='valid', activation='relu'),
        tf.keras.layers.Flatten(),
        tf.keras.layers.Dense(10),
    ])

    model.compile(
        optimizer='adam',
        loss=tf.keras.losses.SparseCategoricalCrossentropy(from_logits=True),
        metrics=['accuracy'],
    )

    model.summary()
    model.fit(x_train, y_train, epochs=3, batch_size=128,
              validation_data=(x_test, y_test), verbose=1)

    loss, acc = model.evaluate(x_test, y_test, verbose=0)
    print(f"\n  Float32 accuracy: {acc*100:.1f}%")

    return model, x_test, y_test


# ============================================================
# 2. Quantize to int8 via TFLite
# ============================================================
def quantize_model(model, x_train_sample):
    print("\n" + "=" * 60)
    print(" Step 2: Quantizing to int8 (full integer)")
    print("=" * 60)

    def representative_dataset():
        for i in range(min(500, len(x_train_sample))):
            yield [x_train_sample[i:i+1].astype(np.float32)]

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = representative_dataset
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.uint8
    converter.inference_output_type = tf.int8

    tflite_model = converter.convert()

    model_path = "build/mnist_quant.tflite"
    os.makedirs("build", exist_ok=True)
    with open(model_path, "wb") as f:
        f.write(tflite_model)

    print(f"  Quantized model size: {len(tflite_model)} bytes")
    print(f"  Saved to: {model_path}")

    return tflite_model


# ============================================================
# 3. Extract quantized weights and run reference inference
# ============================================================
def extract_and_infer(tflite_model, x_test, y_test):
    print("\n" + "=" * 60)
    print(" Step 3: Extracting weights & running TFLite reference")
    print("=" * 60)

    interpreter = tf.lite.Interpreter(model_content=tflite_model)
    interpreter.allocate_tensors()

    input_details  = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    print(f"  Input:  shape={input_details['shape']}, "
          f"dtype={input_details['dtype'].__name__}, "
          f"quant={input_details['quantization_parameters']}")
    print(f"  Output: shape={output_details['shape']}, "
          f"dtype={output_details['dtype'].__name__}, "
          f"quant={output_details['quantization_parameters']}")

    # Get input quantization parameters
    in_scale  = input_details['quantization_parameters']['scales'][0]
    in_zp     = input_details['quantization_parameters']['zero_points'][0]

    # Extract all tensor details (weights, biases)
    tensor_details = interpreter.get_tensor_details()
    layers = []
    for td in tensor_details:
        name = td['name']
        shape = tuple(td['shape'])
        dtype = td['dtype']
        quant = td['quantization_parameters']

        try:
            data = interpreter.get_tensor(td['index'])
        except ValueError:
            continue

        is_weight = (len(shape) >= 2 and
                     ('kernel' in name.lower() or 'conv' in name.lower() or
                      'dense' in name.lower() or 'matmul' in name.lower()))
        is_bias = ('bias' in name.lower() or
                   (len(shape) == 1 and 'relu' in name.lower()))

        if is_weight or is_bias:
            scales = quant.get('scales', np.array([]))
            zps    = quant.get('zero_points', np.array([]))
            print(f"  Tensor: {name}")
            print(f"    shape={shape}, dtype={dtype.__name__}")
            if len(scales) > 0:
                print(f"    scales[0:3]={list(scales[:3])}")
            layers.append({
                'name': name, 'shape': shape, 'dtype': dtype,
                'data': data.copy(), 'scales': np.array(scales),
                'zero_points': np.array(zps)
            })

    # Pick test images (choose ones the model gets right)
    print(f"\n  Selecting {NUM_TEST_IMAGES} test images...")
    test_images = []
    test_labels = []
    tflite_preds = []
    correct = 0

    for i in range(len(x_test)):
        if len(test_images) >= NUM_TEST_IMAGES:
            break

        # Quantize input: uint8 = float / scale + zero_point
        img_float = x_test[i:i+1]
        img_uint8 = np.clip(
            np.round(img_float / in_scale + in_zp), 0, 255
        ).astype(np.uint8)

        interpreter.set_tensor(input_details['index'], img_uint8)
        interpreter.invoke()
        output = interpreter.get_tensor(output_details['index'])[0]
        pred = int(np.argmax(output))

        if pred == int(y_test[i]):
            test_images.append(img_uint8[0])
            test_labels.append(int(y_test[i]))
            tflite_preds.append(pred)
            raw_scores = output.copy()
            correct += 1
            print(f"    Image {len(test_images)}: digit={y_test[i]}, "
                  f"pred={pred}, scores={list(output[:5])}...")

    print(f"\n  Selected {len(test_images)} correctly-classified images")

    return layers, test_images, test_labels, tflite_preds, in_scale, in_zp


# ============================================================
# 4. Generate C header
# ============================================================
def generate_header(layers, test_images, test_labels, tflite_preds,
                    in_scale, in_zp):
    print("\n" + "=" * 60)
    print(" Step 4: Generating C header")
    print("=" * 60)

    os.makedirs(os.path.dirname(HEADER_PATH), exist_ok=True)

    with open(HEADER_PATH, "w") as f:
        f.write("/* Auto-generated by train_mnist.py -- DO NOT EDIT */\n")
        f.write("/* TFLite int8-quantized MNIST model weights + test data */\n")
        f.write("#ifndef MNIST_MODEL_H\n")
        f.write("#define MNIST_MODEL_H\n\n")
        f.write("#include <stdint.h>\n\n")

        f.write(f"#define NUM_TEST_IMAGES {len(test_images)}\n")
        f.write(f"#define INPUT_H         28\n")
        f.write(f"#define INPUT_W         28\n")
        f.write(f"#define INPUT_SCALE     {in_scale:.10f}f\n")
        f.write(f"#define INPUT_ZP        {in_zp}\n\n")

        # Write layer info
        layer_idx = 0
        weight_layers = []
        bias_layers = []

        for l in layers:
            name = l['name'].replace('/', '_').replace(':', '_')
            data = l['data']
            shape = l['shape']

            if 'bias' in l['name'].lower():
                bias_layers.append(l)
            elif len(shape) >= 2:
                weight_layers.append(l)

        # For each conv/dense weight tensor, write as flat array
        for idx, l in enumerate(weight_layers):
            data = l['data']
            shape = l['shape']
            flat = data.flatten()
            dtype_c = "int8_t" if data.dtype == np.int8 else "uint8_t"

            f.write(f"/* Layer {idx}: {l['name']}, shape={shape} */\n")

            if len(shape) == 4:
                # Conv2D: TFLite stores as [out_ch, kh, kw, in_ch]
                out_ch, kh, kw, in_ch = shape
                f.write(f"#define L{idx}_KH    {kh}\n")
                f.write(f"#define L{idx}_KW    {kw}\n")
                f.write(f"#define L{idx}_CIN   {in_ch}\n")
                f.write(f"#define L{idx}_COUT  {out_ch}\n")
                f.write(f"#define L{idx}_KCOLS ({kh}*{kw}*{in_ch})\n")

                # Rearrange from [out_ch, kh, kw, in_ch] to
                # [kh*kw*in_ch, out_ch] for GEMM (im2col_cols x C_out)
                w_reshaped = data.reshape(out_ch, kh * kw * in_ch).T
                flat_gemm = w_reshaped.flatten()
                total = len(flat_gemm)
                f.write(f"/* Reshaped to [{kh*kw*in_ch} x {out_ch}] for GEMM */\n")
            elif len(shape) == 2:
                # Dense: [in, out] -- already in GEMM format
                in_dim, out_dim = shape
                f.write(f"#define L{idx}_IN    {in_dim}\n")
                f.write(f"#define L{idx}_OUT   {out_dim}\n")
                flat_gemm = flat
                total = len(flat_gemm)
            else:
                flat_gemm = flat
                total = len(flat_gemm)

            f.write(f"static const {dtype_c} layer{idx}_weights[{total}] = {{\n")
            for i in range(0, total, 16):
                chunk = flat_gemm[i:i+16]
                vals = ", ".join(f"{int(v):4d}" for v in chunk)
                f.write(f"    {vals},\n")
            f.write(f"}};\n")

            # Write quantization parameters
            if len(l['scales']) > 0:
                f.write(f"static const float layer{idx}_scales[{len(l['scales'])}] = {{\n")
                for i in range(0, len(l['scales']), 4):
                    chunk = l['scales'][i:i+4]
                    vals = ", ".join(f"{v:.10e}" for v in chunk)
                    f.write(f"    {vals},\n")
                f.write(f"}};\n")

                f.write(f"static const int32_t layer{idx}_zp[{len(l['zero_points'])}] = {{\n")
                vals = ", ".join(str(int(v)) for v in l['zero_points'])
                f.write(f"    {vals}\n")
                f.write(f"}};\n")

            f.write(f"\n")

        # Write bias tensors
        for idx, l in enumerate(bias_layers):
            data = l['data']
            flat = data.flatten()
            dtype_c = "int32_t" if data.dtype == np.int32 else "int8_t"
            total = len(flat)

            f.write(f"/* Bias {idx}: {l['name']}, shape={l['shape']} */\n")
            f.write(f"static const {dtype_c} bias{idx}[{total}] = {{\n")
            for i in range(0, total, 8):
                chunk = flat[i:i+8]
                vals = ", ".join(f"{int(v)}" for v in chunk)
                f.write(f"    {vals},\n")
            f.write(f"}};\n\n")

        # Write test images (uint8, 28x28 = 784 bytes each)
        f.write(f"/* {len(test_images)} test images (28x28 uint8, quantized) */\n")
        f.write(f"static const uint8_t test_images[{len(test_images)}][784] = {{\n")
        for img_idx, img in enumerate(test_images):
            flat = img.flatten()
            f.write(f"  {{ /* digit {test_labels[img_idx]} */\n")
            for i in range(0, 784, 28):
                row = flat[i:i+28]
                vals = ", ".join(f"{int(v):3d}" for v in row)
                f.write(f"    {vals},\n")
            f.write(f"  }},\n")
        f.write(f"}};\n\n")

        # Write expected labels (from TFLite reference)
        f.write(f"/* Expected labels from TFLite reference interpreter */\n")
        labels_str = ", ".join(str(l) for l in tflite_preds)
        f.write(f"static const uint8_t expected_labels[{len(tflite_preds)}] = "
                f"{{ {labels_str} }};\n\n")

        # Write true labels
        true_str = ", ".join(str(l) for l in test_labels)
        f.write(f"static const uint8_t true_labels[{len(test_labels)}] = "
                f"{{ {true_str} }};\n\n")

        f.write("#endif /* MNIST_MODEL_H */\n")

    file_size = os.path.getsize(HEADER_PATH)
    print(f"  Generated: {HEADER_PATH} ({file_size} bytes)")
    print(f"  Contains: {len(weight_layers)} weight tensors, "
          f"{len(bias_layers)} bias tensors, "
          f"{len(test_images)} test images")


# ============================================================
# Main
# ============================================================
if __name__ == "__main__":
    # Load training data for representative dataset
    (x_train, _), (x_test, y_test) = tf.keras.datasets.mnist.load_data()
    x_train = x_train.astype(np.float32) / 255.0
    x_test  = x_test.astype(np.float32) / 255.0
    x_train = x_train[..., np.newaxis]
    x_test  = x_test[..., np.newaxis]

    model, _, _ = train_model()

    tflite_model = quantize_model(model, x_train[:500])

    layers, test_images, test_labels, tflite_preds, in_scale, in_zp = \
        extract_and_infer(tflite_model, x_test, y_test)

    generate_header(layers, test_images, test_labels, tflite_preds,
                    in_scale, in_zp)

    print("\n" + "=" * 60)
    print(" DONE! Next steps:")
    print("   1. Review include/mnist_model.h")
    print("   2. Compile mnist_inference.c firmware")
    print("   3. Run Verilog simulation")
    print("=" * 60)
