#!/usr/bin/env python3
"""
将真实的二进制数据转换为Verilog仿真所需的mem格式
网络结构：
  Conv1: 1x32x32 -> 32x32x32, K=5, stride=1, pad=2, shift=9
  MaxPool 2x2: 32x32x32 -> 32x16x16
  Conv2: 32x16x16 -> 64x16x16, K=3, stride=1, pad=1, shift=8
  Conv3: 64x16x16 -> 64x8x8, K=3, stride=2, pad=1, shift=8
  Conv4: 64x8x8 -> 128x4x4, K=3, stride=2, pad=1, shift=8
  AvgPool 4x4: 128x4x4 -> 128x1x1
  FC: 128 -> 10, shift=6
"""

import numpy as np
from pathlib import Path
import os

# 数据目录
DATA_DIR = Path("../../data")
OUT_DIR = Path("real_data")

def load_bin(path, dtype=np.int8):
    """加载二进制文件"""
    return np.fromfile(path, dtype=dtype)

def save_mem_64bit(path, data):
    """将数据保存为64位宽度的mem文件（8个字节一行）"""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w') as f:
        # 确保数据是uint8类型用于写入
        data_u8 = data.view(np.uint8)
        # 按8字节分组
        n_words = (len(data_u8) + 7) // 8
        for i in range(n_words):
            start = i * 8
            end = min(start + 8, len(data_u8))
            word = 0
            for j, idx in enumerate(range(start, end)):
                word |= int(data_u8[idx]) << (j * 8)
            f.write(f"{word:016x}\n")
    print(f"  Saved: {path} ({n_words} words)")

def save_mem_8bit(path, data):
    """将数据保存为8位宽度的mem文件"""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, 'w') as f:
        data_u8 = data.view(np.uint8)
        for byte in data_u8:
            f.write(f"{byte:02x}\n")
    print(f"  Saved: {path} ({len(data_u8)} bytes)")

def convert_activation(bin_path, shape, out_path):
    """转换激活数据（CHW格式）"""
    data = load_bin(bin_path)
    expected_size = np.prod(shape)
    assert len(data) == expected_size, f"Size mismatch: {len(data)} vs {expected_size}"
    save_mem_64bit(out_path, data)
    return data.reshape(shape)

def convert_weight_conv(bin_path, shape, out_path):
    """
    转换卷积权重
    输入格式: OIHW (OC, IC, KH, KW)
    输出格式: 按照硬件需要的tile_c=8布局
    """
    data = load_bin(bin_path)
    OC, IC, KH, KW = shape
    expected_size = np.prod(shape)
    assert len(data) == expected_size, f"Size mismatch: {len(data)} vs {expected_size}"
    
    w = data.reshape(shape)
    
    # 硬件权重布局: 按tile_c=8分组
    # 对于每个输出通道，权重按 [ic_tile][kh][kw][ic_in_tile] 组织
    TILE_C = 8
    ic_tiles = (IC + TILE_C - 1) // TILE_C
    oc_tiles = (OC + TILE_C - 1) // TILE_C
    
    # Pad IC to multiple of TILE_C
    ic_padded = ic_tiles * TILE_C
    w_padded = np.zeros((OC, ic_padded, KH, KW), dtype=np.int8)
    w_padded[:, :IC, :, :] = w
    
    # 重排列为硬件格式
    # 对于每个输出通道组
    hw_weights = []
    for oc in range(OC):
        for ic_t in range(ic_tiles):
            for kh in range(KH):
                for kw in range(KW):
                    for ic_in in range(TILE_C):
                        ic = ic_t * TILE_C + ic_in
                        hw_weights.append(w_padded[oc, ic, kh, kw])
    
    hw_weights = np.array(hw_weights, dtype=np.int8)
    save_mem_64bit(out_path, hw_weights)
    return w

def convert_weight_fc(bin_path, shape, out_path):
    """转换全连接权重"""
    data = load_bin(bin_path)
    OUT_SIZE, IN_SIZE = shape
    expected_size = np.prod(shape)
    assert len(data) == expected_size, f"Size mismatch: {len(data)} vs {expected_size}"
    
    # FC权重直接按行存储
    save_mem_8bit(out_path, data)
    return data.reshape(shape)

def convert_image(img_name):
    """转换单张图片的所有数据"""
    img_dir = DATA_DIR / img_name
    out_img_dir = OUT_DIR / img_name
    
    print(f"\n=== Converting {img_name} ===")
    
    # Conv1 input: 1x32x32 = 1024 bytes
    convert_activation(img_dir / "conv1.input.dat", (1, 32, 32), 
                      out_img_dir / "conv1_act.mem")
    
    # Conv1 output: 32x32x32 = 32768 bytes
    convert_activation(img_dir / "conv1.output.dat", (32, 32, 32),
                      out_img_dir / "conv1_exp.mem")
    
    # Pool1 output: 32x16x16 = 8192 bytes (可选，等同于conv2.input)
    pool1_path = img_dir / "pool1.output.dat"
    if pool1_path.exists():
        convert_activation(pool1_path, (32, 16, 16),
                          out_img_dir / "pool1_exp.mem")
    else:
        # 使用conv2.input作为pool1输出
        print(f"  Note: pool1.output.dat missing, using conv2.input.dat as pool1 expected")
        convert_activation(img_dir / "conv2.input.dat", (32, 16, 16),
                          out_img_dir / "pool1_exp.mem")
    
    # Conv2 input: 32x16x16 = 8192 bytes
    convert_activation(img_dir / "conv2.input.dat", (32, 16, 16),
                      out_img_dir / "conv2_act.mem")
    
    # Conv2 output: 64x16x16 = 16384 bytes
    convert_activation(img_dir / "conv2.output.dat", (64, 16, 16),
                      out_img_dir / "conv2_exp.mem")
    
    # Conv3 input: 64x16x16 = 16384 bytes
    convert_activation(img_dir / "conv3.input.dat", (64, 16, 16),
                      out_img_dir / "conv3_act.mem")
    
    # Conv3 output: 64x8x8 = 4096 bytes
    convert_activation(img_dir / "conv3.output.dat", (64, 8, 8),
                      out_img_dir / "conv3_exp.mem")
    
    # Conv4 input: 64x8x8 = 4096 bytes
    convert_activation(img_dir / "conv4.input.dat", (64, 8, 8),
                      out_img_dir / "conv4_act.mem")
    
    # Conv4 output: 128x4x4 = 2048 bytes
    convert_activation(img_dir / "conv4.output.dat", (128, 4, 4),
                      out_img_dir / "conv4_exp.mem")
    
    # AvgPool output: 128x1x1 = 128 bytes (可选，等同于fc.input)
    avgpool_path = img_dir / "avgpool.output.dat"
    if avgpool_path.exists():
        convert_activation(avgpool_path, (128, 1, 1),
                          out_img_dir / "avgpool_exp.mem")
    else:
        # 使用fc.input作为avgpool输出
        print(f"  Note: avgpool.output.dat missing, using fc.input.dat as avgpool expected")
        convert_activation(img_dir / "fc.input.dat", (128,),
                          out_img_dir / "avgpool_exp.mem")
    
    # FC input: 128 bytes
    convert_activation(img_dir / "fc.input.dat", (128,),
                      out_img_dir / "fc_act.mem")
    
    # FC output: 10 bytes
    convert_activation(img_dir / "fc.output.dat", (10,),
                      out_img_dir / "fc_exp.mem")

def convert_weights():
    """转换所有权重"""
    param_dir = DATA_DIR / "parameters"
    out_wgt_dir = OUT_DIR / "weights"
    
    print("\n=== Converting Weights ===")
    
    # Conv1: 32 output, 1 input, 5x5 kernel = 800 bytes
    convert_weight_conv(param_dir / "conv1.dat", (32, 1, 5, 5),
                       out_wgt_dir / "conv1_wgt.mem")
    
    # Conv2: 64 output, 32 input, 3x3 kernel = 18432 bytes
    convert_weight_conv(param_dir / "conv2.dat", (64, 32, 3, 3),
                       out_wgt_dir / "conv2_wgt.mem")
    
    # Conv3: 64 output, 64 input, 3x3 kernel = 36864 bytes
    convert_weight_conv(param_dir / "conv3.dat", (64, 64, 3, 3),
                       out_wgt_dir / "conv3_wgt.mem")
    
    # Conv4: 128 output, 64 input, 3x3 kernel = 73728 bytes
    convert_weight_conv(param_dir / "conv4.dat", (128, 64, 3, 3),
                       out_wgt_dir / "conv4_wgt.mem")
    
    # FC: 10 output, 128 input = 1280 bytes
    convert_weight_fc(param_dir / "fc.dat", (10, 128),
                     out_wgt_dir / "fc_wgt.mem")

def main():
    # 创建输出目录
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # 转换权重
    convert_weights()
    
    # 转换所有图片数据
    for i in range(1, 9):
        convert_image(f"im{i}")
    
    print("\n=== Conversion Complete ===")

if __name__ == "__main__":
    os.chdir(Path(__file__).parent)
    main()
