#!/usr/bin/env python3
"""
gen_cnn_test.py

完整CNN仿真测试数据生成器
支持所有网络层: Conv1, Pool1, Conv2, Conv3, Conv4, AvgPool, FC
生成用于硬件仿真的测试向量
"""

import numpy as np
from pathlib import Path

# ========== 全局路径 ==========
DATA_DIR = Path("d:/FPGA/DPU_project/data")
OUT_DIR = Path("d:/FPGA/DPU_project/DPU_v2/scripts/cnn_data")

# ========== 量化工具 ==========
def calc_shift(Qin, Qw, Qout):
    return Qin + Qw - Qout

def quant_shift(x, shift):
    """算术右移量化"""
    return x >> shift

def relu(x):
    return np.maximum(x, 0)

def saturate_int8(x):
    return np.clip(x, -128, 127).astype(np.int8)


# ========== 卷积层（Python参考实现）==========
def conv2d_int8(x, w, stride=1, pad=0, shift=8, relu_en=True):
    """
    Int8 卷积 - 硬件模拟实现
    x: (C_IN, H, W) int8
    w: (C_OUT, C_IN, K, K) int8
    """
    C_OUT, C_IN_W, K_H, K_W = w.shape
    C_IN_X, H, W = x.shape
    assert C_IN_W == C_IN_X, f"channel mismatch: {C_IN_X} vs {C_IN_W}"
    
    H_out = (H + 2 * pad - K_H) // stride + 1
    W_out = (W + 2 * pad - K_W) // stride + 1
    
    # 填充
    x_pad = np.pad(x, ((0, 0), (pad, pad), (pad, pad)), mode='constant', constant_values=0)
    
    # 卷积计算
    psum = np.zeros((C_OUT, H_out, W_out), dtype=np.int32)
    for co in range(C_OUT):
        for ho in range(H_out):
            for wo in range(W_out):
                for ci in range(C_IN_W):
                    for kh in range(K_H):
                        for kw in range(K_W):
                            hi = ho * stride + kh
                            wi = wo * stride + kw
                            psum[co, ho, wo] += int(x_pad[ci, hi, wi]) * int(w[co, ci, kh, kw])
    
    # 量化
    out = quant_shift(psum, shift)
    if relu_en:
        out = relu(out)
    out = saturate_int8(out)
    
    return out


# ========== 池化层 ==========
def maxpool2x2(x):
    """2x2 最大池化"""
    C, H, W = x.shape
    H_out, W_out = H // 2, W // 2
    y = np.zeros((C, H_out, W_out), dtype=np.int8)
    for c in range(C):
        for i in range(H_out):
            for j in range(W_out):
                y[c, i, j] = np.max(x[c, i*2:i*2+2, j*2:j*2+2])
    return y


def avgpool(x):
    """全局平均池化 -> 1x1"""
    C, H, W = x.shape
    y = np.zeros(C, dtype=np.int8)
    for c in range(C):
        acc = np.sum(x[c].astype(np.int32))
        shift = int(np.log2(H * W))
        y[c] = saturate_int8(acc >> shift)
    return y


# ========== 全连接层 ==========
def fc_int8(x, w, shift=6):
    """全连接层"""
    OC, IC = w.shape
    x_flat = x.flatten().astype(np.int32)
    y = np.zeros(OC, dtype=np.int8)
    for o in range(OC):
        acc = np.sum(x_flat * w[o].astype(np.int32))
        y[o] = saturate_int8(quant_shift(acc, shift))
    return y


# ========== 数据格式转换工具 ==========
def save_hex(filename, data, layout='chw', tile_c=8):
    """保存数据为hex格式"""
    lines = []
    
    if layout == 'chw':
        # Activation/Output: flatten to bytes, pack 8 bytes per line
        flat = data.flatten().astype(np.uint8)
        pad_len = (8 - len(flat) % 8) % 8
        if pad_len > 0:
            flat = np.concatenate([flat, np.zeros(pad_len, dtype=np.uint8)])
        for i in range(0, len(flat), 8):
            word = flat[i:i+8]
            hex_val = ''.join(f'{b:02x}' for b in reversed(word))
            lines.append(hex_val)
    
    elif layout == 'weight':
        # Weight layout: [N_TILE_C][C_IN][K][K][TILE_C]
        C_OUT, C_IN, K_H, K_W = data.shape
        n_tile_c = (C_OUT + tile_c - 1) // tile_c
        for tc in range(n_tile_c):
            for ci in range(C_IN):
                for kh in range(K_H):
                    for kw in range(K_W):
                        word = []
                        for co in range(tile_c):
                            co_global = tc * tile_c + co
                            if co_global < C_OUT:
                                word.append(data[co_global, ci, kh, kw].astype(np.uint8))
                            else:
                                word.append(0)
                        hex_val = ''.join(f'{b:02x}' for b in reversed(word))
                        lines.append(hex_val)
    
    elif layout == 'fc_weight':
        # FC权重: [OUT][IN] -> 逐字节
        flat = data.flatten().astype(np.uint8)
        for b in flat:
            lines.append(f'{b:02x}')
    
    with open(filename, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    
    # Also save .mem file
    mem_file = str(filename).replace('.hex', '.mem')
    with open(mem_file, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    
    return len(lines)


def load_bin(path, shape):
    """加载二进制文件"""
    arr = np.fromfile(path, dtype=np.int8)
    return arr.reshape(shape)


# ========== 网络层定义 ==========
LAYERS = {
    'conv1': {
        'type': 'conv',
        'input_shape': (1, 32, 32),
        'weight_shape': (32, 1, 5, 5),
        'output_shape': (32, 32, 32),
        'stride': 1, 'pad': 2,
        'shift': 9,  # Qin=7, Qw=7, Qout=5
        'relu_en': True,
        'hw_support': True,
    },
    'pool1': {
        'type': 'maxpool',
        'input_shape': (32, 32, 32),
        'output_shape': (32, 16, 16),
        'hw_support': True,  # 有硬件模块
    },
    'conv2': {
        'type': 'conv',
        'input_shape': (32, 16, 16),
        'weight_shape': (64, 32, 3, 3),
        'output_shape': (64, 16, 16),
        'stride': 1, 'pad': 1,
        'shift': 8,  # Qin=5, Qw=8, Qout=5
        'relu_en': True,
        'hw_support': True,
    },
    'conv3': {
        'type': 'conv',
        'input_shape': (64, 16, 16),
        'weight_shape': (64, 64, 3, 3),
        'output_shape': (64, 8, 8),
        'stride': 2, 'pad': 1,
        'shift': 8,
        'relu_en': True,
        'hw_support': True,  # 添加了stride支持
    },
    'conv4': {
        'type': 'conv',
        'input_shape': (64, 8, 8),
        'weight_shape': (128, 64, 3, 3),
        'output_shape': (128, 4, 4),
        'stride': 2, 'pad': 1,
        'shift': 8,
        'relu_en': True,
        'hw_support': True,
    },
    'avgpool': {
        'type': 'avgpool',
        'input_shape': (128, 4, 4),
        'output_shape': (128,),
        'hw_support': True,
    },
    'fc': {
        'type': 'fc',
        'input_shape': (128,),
        'weight_shape': (10, 128),
        'output_shape': (10,),
        'shift': 6,  # Qin=5, Qw=6, Qout=5
        'hw_support': True,
    },
}


def run_full_network(image_id='im1'):
    """运行完整网络并生成所有层的测试数据"""
    print(f"\n{'='*60}")
    print(f"Generating test data for {image_id}")
    print('='*60)
    
    # 创建输出目录
    for layer_name in LAYERS:
        layer_dir = OUT_DIR / layer_name
        layer_dir.mkdir(parents=True, exist_ok=True)
    
    # 加载输入图像
    x = load_bin(DATA_DIR / f"{image_id}/conv1.input.dat", (1, 32, 32))
    print(f"Input loaded: shape={x.shape}, range=[{x.min()}, {x.max()}]")
    
    # 保存输入
    save_hex(OUT_DIR / 'conv1' / f'act_{image_id}.hex', x)
    
    layer_outputs = {'input': x}
    
    # ========== Conv1 ==========
    print("\n--- Conv1 ---")
    w = load_bin(DATA_DIR / "parameters/conv1.dat", (32, 1, 5, 5))
    y = conv2d_int8(x, w, stride=1, pad=2, shift=9, relu_en=True)
    print(f"  Output: {y.shape}, range=[{y.min()}, {y.max()}]")
    
    save_hex(OUT_DIR / 'conv1' / 'wgt.hex', w, layout='weight')
    save_hex(OUT_DIR / 'conv1' / f'exp_{image_id}.hex', y)
    layer_outputs['conv1'] = y
    
    # ========== Pool1 ==========
    print("\n--- Pool1 (MaxPool 2x2) ---")
    y_pool = maxpool2x2(y)
    print(f"  Output: {y_pool.shape}, range=[{y_pool.min()}, {y_pool.max()}]")
    
    save_hex(OUT_DIR / 'pool1' / f'act_{image_id}.hex', y)
    save_hex(OUT_DIR / 'pool1' / f'exp_{image_id}.hex', y_pool)
    layer_outputs['pool1'] = y_pool
    
    # ========== Conv2 ==========
    print("\n--- Conv2 ---")
    w2 = load_bin(DATA_DIR / "parameters/conv2.dat", (64, 32, 3, 3))
    y2 = conv2d_int8(y_pool, w2, stride=1, pad=1, shift=8, relu_en=True)
    print(f"  Output: {y2.shape}, range=[{y2.min()}, {y2.max()}]")
    
    save_hex(OUT_DIR / 'conv2' / f'act_{image_id}.hex', y_pool)
    save_hex(OUT_DIR / 'conv2' / 'wgt.hex', w2, layout='weight')
    save_hex(OUT_DIR / 'conv2' / f'exp_{image_id}.hex', y2)
    layer_outputs['conv2'] = y2
    
    # ========== Conv3 (stride=2) ==========
    print("\n--- Conv3 (stride=2) ---")
    w3 = load_bin(DATA_DIR / "parameters/conv3.dat", (64, 64, 3, 3))
    y3 = conv2d_int8(y2, w3, stride=2, pad=1, shift=8, relu_en=True)
    print(f"  Output: {y3.shape}, range=[{y3.min()}, {y3.max()}]")
    
    save_hex(OUT_DIR / 'conv3' / f'act_{image_id}.hex', y2)
    save_hex(OUT_DIR / 'conv3' / 'wgt.hex', w3, layout='weight')
    save_hex(OUT_DIR / 'conv3' / f'exp_{image_id}.hex', y3)
    layer_outputs['conv3'] = y3
    
    # ========== Conv4 (stride=2) ==========
    print("\n--- Conv4 (stride=2) ---")
    w4 = load_bin(DATA_DIR / "parameters/conv4.dat", (128, 64, 3, 3))
    y4 = conv2d_int8(y3, w4, stride=2, pad=1, shift=8, relu_en=True)
    print(f"  Output: {y4.shape}, range=[{y4.min()}, {y4.max()}]")
    
    save_hex(OUT_DIR / 'conv4' / f'act_{image_id}.hex', y3)
    save_hex(OUT_DIR / 'conv4' / 'wgt.hex', w4, layout='weight')
    save_hex(OUT_DIR / 'conv4' / f'exp_{image_id}.hex', y4)
    layer_outputs['conv4'] = y4
    
    # ========== AvgPool ==========
    print("\n--- AvgPool (Global) ---")
    y_avg = avgpool(y4)
    print(f"  Output: {y_avg.shape}, range=[{y_avg.min()}, {y_avg.max()}]")
    
    save_hex(OUT_DIR / 'avgpool' / f'act_{image_id}.hex', y4)
    save_hex(OUT_DIR / 'avgpool' / f'exp_{image_id}.hex', y_avg)
    layer_outputs['avgpool'] = y_avg
    
    # ========== FC ==========
    print("\n--- FC ---")
    wfc = load_bin(DATA_DIR / "parameters/fc.dat", (10, 128))
    yfc = fc_int8(y_avg, wfc, shift=6)
    print(f"  Output: {yfc.shape}")
    print(f"  Scores: {yfc}")
    pred_class = np.argmax(yfc)
    print(f"  Prediction: class {pred_class}")
    
    save_hex(OUT_DIR / 'fc' / f'act_{image_id}.hex', y_avg)
    save_hex(OUT_DIR / 'fc' / 'wgt.hex', wfc, layout='fc_weight')
    save_hex(OUT_DIR / 'fc' / f'exp_{image_id}.hex', yfc)
    layer_outputs['fc'] = yfc
    
    return layer_outputs, pred_class


def print_summary():
    """打印生成的文件汇总"""
    print("\n" + "="*60)
    print("Generated Files Summary")
    print("="*60)
    
    for layer_name, cfg in LAYERS.items():
        layer_dir = OUT_DIR / layer_name
        if layer_dir.exists():
            files = list(layer_dir.glob('*'))
            print(f"\n{layer_name}/")
            for f in sorted(files):
                size = f.stat().st_size
                print(f"  {f.name}: {size} bytes")


def main():
    print("="*60)
    print("Complete CNN Test Data Generator")
    print("="*60)
    
    # 确保输出目录存在
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # 运行网络并生成数据
    outputs, pred = run_full_network('im1')
    
    # 打印汇总
    print_summary()
    
    print("\n" + "="*60)
    print(f"Network prediction: class {pred}")
    print("="*60)
    print("\nTest data generated successfully!")
    print(f"Output directory: {OUT_DIR}")


if __name__ == '__main__':
    main()
