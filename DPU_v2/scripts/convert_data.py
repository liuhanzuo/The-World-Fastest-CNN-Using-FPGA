#!/usr/bin/env python3
"""
将data目录中的二进制数据转换为Verilog可读的hex格式
支持完整的CNN网络仿真

重要：硬件期望的数据布局：
- 激活数据：CHW格式（直接使用）
- 权重数据：需要按照TILE_C分组，布局为 (oc_tile, ic, kh, kw, oc_local)
  其中 oc_tile = oc // TILE_C, oc_local = oc % TILE_C
"""

import numpy as np
from pathlib import Path
import os

# 使用绝对路径
SCRIPT_DIR = Path(__file__).parent.resolve()
DATA_ROOT = SCRIPT_DIR.parent.parent / "data"
OUTPUT_ROOT = SCRIPT_DIR / "sim_data"

TILE_C = 8  # 与硬件一致

def load_bin(path, shape=None):
    """加载二进制数据文件"""
    arr = np.fromfile(path, dtype=np.int8)
    if shape is not None:
        arr = arr.reshape(shape)
    return arr

def save_hex_byte(path, data):
    """
    保存为hex格式，每行一个字节
    适用于 reg signed [7:0] array[] 类型
    """
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    data_flat = data.flatten().astype(np.uint8)
    
    with open(path, 'w') as f:
        for b in data_flat:
            f.write(f'{b:02x}\n')

def save_hex_packed64(path, data):
    """
    保存为hex格式，每行8个字节 (64-bit)
    适用于 reg [63:0] array[] 类型
    数据布局：低地址在低位（小端格式）
    """
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    data_flat = data.flatten().astype(np.uint8)
    
    with open(path, 'w') as f:
        for i in range(0, len(data_flat), 8):
            chunk = data_flat[i:i+8]
            # 小端格式：低地址在低位
            hex_str = ''.join([f'{b:02x}' for b in reversed(chunk)])
            # 如果不足8字节，高位补零
            if len(chunk) < 8:
                hex_str = '00' * (8 - len(chunk)) + hex_str
            f.write(hex_str + '\n')

def reorder_weights_for_hw(weights, tile_c=TILE_C):
    """
    将权重从标准布局转换为硬件期望的布局
    
    输入布局：(OC, IC, KH, KW) - 标准PyTorch格式
    输出布局：按字节顺序为 (oc_tile, ic, kh, kw, oc_local)
              其中地址 = oc_tile * IC * K * K * TILE_C + ic * K * K * TILE_C + kh * K * TILE_C + kw * TILE_C + oc_local
    
    这样，当硬件按地址 wgt_word_addr = (cnt_base_c / TILE_C) * (C_IN * K * K) + cnt_ci * (K * K) + cnt_hk * K + cnt_wk
    读取时，可以一次获取 TILE_C 个连续的权重字节（对应不同的输出通道）
    """
    OC, IC, KH, KW = weights.shape
    oc_tiles = (OC + tile_c - 1) // tile_c
    
    # 创建输出数组
    result = np.zeros(oc_tiles * IC * KH * KW * tile_c, dtype=np.int8)
    
    idx = 0
    for oc_tile in range(oc_tiles):
        for ic in range(IC):
            for kh in range(KH):
                for kw in range(KW):
                    for oc_local in range(tile_c):
                        oc = oc_tile * tile_c + oc_local
                        if oc < OC:
                            result[idx] = weights[oc, ic, kh, kw]
                        else:
                            result[idx] = 0  # padding
                        idx += 1
    
    return result

def convert_all_data(img_id="im1"):
    """转换指定图像的所有数据"""
    
    output_dir = OUTPUT_ROOT / img_id
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"\n===== Converting data for {img_id} =====")
    
    # ========== Conv1 ==========
    print("\n--- Conv1: 1x32x32 -> 32x32x32, K=5, stride=1, pad=2 ---")
    conv1_in = load_bin(DATA_ROOT / img_id / "conv1.input.dat", (1, 32, 32))
    conv1_wgt = load_bin(DATA_ROOT / "parameters" / "conv1.dat", (32, 1, 5, 5))
    conv1_out = load_bin(DATA_ROOT / img_id / "conv1.output.dat", (32, 32, 32))
    
    # 重新排列权重为硬件格式
    conv1_wgt_hw = reorder_weights_for_hw(conv1_wgt)
    
    # 保存为64-bit打包格式
    save_hex_packed64(output_dir / "conv1_act.hex", conv1_in.flatten())
    save_hex_packed64(output_dir / "conv1_wgt.hex", conv1_wgt_hw)
    save_hex_packed64(output_dir / "conv1_exp.hex", conv1_out.flatten())
    print(f"  Input:  {conv1_in.shape}, {conv1_in.size} bytes -> {(conv1_in.size+7)//8} words")
    print(f"  Weight: {conv1_wgt.shape} -> HW layout: {conv1_wgt_hw.size} bytes -> {(conv1_wgt_hw.size+7)//8} words")
    print(f"  Output: {conv1_out.shape}, {conv1_out.size} bytes -> {(conv1_out.size+7)//8} words")
    
    # ========== MaxPool ==========
    print("\n--- MaxPool: 32x32x32 -> 32x16x16, 2x2 kernel ---")
    pool1_out = load_bin(DATA_ROOT / img_id / "pool1.output.dat", (32, 16, 16))
    save_hex_packed64(output_dir / "pool1_exp.hex", pool1_out.flatten())
    print(f"  Output: {pool1_out.shape}, {pool1_out.size} bytes -> {(pool1_out.size+7)//8} words")
    
    # ========== Conv2 ==========
    print("\n--- Conv2: 32x16x16 -> 64x16x16, K=3, stride=1, pad=1 ---")
    conv2_in = load_bin(DATA_ROOT / img_id / "conv2.input.dat", (32, 16, 16))
    conv2_wgt = load_bin(DATA_ROOT / "parameters" / "conv2.dat", (64, 32, 3, 3))
    conv2_out = load_bin(DATA_ROOT / img_id / "conv2.output.dat", (64, 16, 16))
    
    conv2_wgt_hw = reorder_weights_for_hw(conv2_wgt)
    
    save_hex_packed64(output_dir / "conv2_wgt.hex", conv2_wgt_hw)
    save_hex_packed64(output_dir / "conv2_exp.hex", conv2_out.flatten())
    print(f"  Input:  {conv2_in.shape}, {conv2_in.size} bytes")
    print(f"  Weight: {conv2_wgt.shape} -> HW layout: {conv2_wgt_hw.size} bytes -> {(conv2_wgt_hw.size+7)//8} words")
    print(f"  Output: {conv2_out.shape}, {conv2_out.size} bytes -> {(conv2_out.size+7)//8} words")
    
    # ========== Conv3 ==========
    print("\n--- Conv3: 64x16x16 -> 64x8x8, K=3, stride=2, pad=1 ---")
    conv3_in = load_bin(DATA_ROOT / img_id / "conv3.input.dat", (64, 16, 16))
    conv3_wgt = load_bin(DATA_ROOT / "parameters" / "conv3.dat", (64, 64, 3, 3))
    conv3_out = load_bin(DATA_ROOT / img_id / "conv3.output.dat", (64, 8, 8))
    
    conv3_wgt_hw = reorder_weights_for_hw(conv3_wgt)
    
    save_hex_packed64(output_dir / "conv3_wgt.hex", conv3_wgt_hw)
    save_hex_packed64(output_dir / "conv3_exp.hex", conv3_out.flatten())
    print(f"  Input:  {conv3_in.shape}, {conv3_in.size} bytes")
    print(f"  Weight: {conv3_wgt.shape} -> HW layout: {conv3_wgt_hw.size} bytes -> {(conv3_wgt_hw.size+7)//8} words")
    print(f"  Output: {conv3_out.shape}, {conv3_out.size} bytes -> {(conv3_out.size+7)//8} words")
    
    # ========== Conv4 ==========
    print("\n--- Conv4: 64x8x8 -> 128x4x4, K=3, stride=2, pad=1 ---")
    conv4_in = load_bin(DATA_ROOT / img_id / "conv4.input.dat", (64, 8, 8))
    conv4_wgt = load_bin(DATA_ROOT / "parameters" / "conv4.dat", (128, 64, 3, 3))
    conv4_out = load_bin(DATA_ROOT / img_id / "conv4.output.dat", (128, 4, 4))
    
    conv4_wgt_hw = reorder_weights_for_hw(conv4_wgt)
    
    save_hex_packed64(output_dir / "conv4_wgt.hex", conv4_wgt_hw)
    save_hex_packed64(output_dir / "conv4_exp.hex", conv4_out.flatten())
    print(f"  Input:  {conv4_in.shape}, {conv4_in.size} bytes")
    print(f"  Weight: {conv4_wgt.shape} -> HW layout: {conv4_wgt_hw.size} bytes -> {(conv4_wgt_hw.size+7)//8} words")
    print(f"  Output: {conv4_out.shape}, {conv4_out.size} bytes -> {(conv4_out.size+7)//8} words")
    
    # ========== AvgPool ==========
    print("\n--- AvgPool: 128x4x4 -> 128x1x1, 4x4 global ---")
    fc_in = load_bin(DATA_ROOT / img_id / "fc.input.dat", (128,))
    save_hex_packed64(output_dir / "avgpool_exp.hex", fc_in.flatten())
    print(f"  Output: {fc_in.shape}, {fc_in.size} bytes -> {(fc_in.size+7)//8} words")
    
    # ========== FC ==========
    print("\n--- FC: 128 -> 10 ---")
    fc_wgt = load_bin(DATA_ROOT / "parameters" / "fc.dat", (10, 128))
    fc_out = load_bin(DATA_ROOT / img_id / "fc.output.dat", (10,))
    
    # FC层使用单字节格式
    save_hex_byte(output_dir / "fc_wgt.hex", fc_wgt.flatten())
    save_hex_byte(output_dir / "fc_act.hex", fc_in.flatten())
    save_hex_byte(output_dir / "fc_exp.hex", fc_out.flatten())
    print(f"  Input:  {fc_in.shape}")
    print(f"  Weight: {fc_wgt.shape}, {fc_wgt.size} bytes")
    print(f"  Output: {fc_out.shape}, {fc_out.size} bytes")
    print(f"  Expected class: {np.argmax(fc_out)}, score: {fc_out[np.argmax(fc_out)]}")
    
    # 打印 FC 输出详情
    print(f"  FC output scores: {fc_out.tolist()}")
    
    return True

if __name__ == "__main__":
    # 转换im1的数据
    convert_all_data("im1")
    print("\n===== Data conversion complete! =====")
