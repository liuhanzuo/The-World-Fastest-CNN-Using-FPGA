import numpy as np
from pathlib import Path

# ========== 量化工具 ==========
def sat8(x):
    return np.clip(x, -127, 127).astype(np.int8)

def quant_floor_shift(x, shift):
    """floor quantization, equivalent to arithmetic right shift"""
    if shift > 0:
        return np.floor_divide(x, 2 ** shift)
    elif shift < 0:
        return x * (2 ** (-shift))
    else:
        return x

def relu(x):
    return np.maximum(x, 0)

def calc_shift(Qin, Qw, Qout):
    return Qin + Qw - Qout


# ========== 卷积层 ==========
def conv2d_int8(x, w, stride=1, pad=0, Qin=7, Qw=7, Qout=5, relu_en=True):
    OC, IC, KH, KW = w.shape
    ICx, H, W = x.shape
    assert IC == ICx, f"in_channel mismatch: {ICx} vs {IC}"
    Hout = (H + 2 * pad - KH) // stride + 1
    Wout = (W + 2 * pad - KW) // stride + 1

    y = np.zeros((OC, Hout, Wout), dtype=np.int8)
    x_pad = np.pad(x, ((0, 0), (pad, pad), (pad, pad)), mode="constant")

    shift = calc_shift(Qin, Qw, Qout)
    for oc in range(OC):
        for oh in range(Hout):
            for ow in range(Wout):
                region = x_pad[:, oh*stride:oh*stride+KH, ow*stride:ow*stride+KW]
                acc = np.sum(region.astype(np.int32) * w[oc].astype(np.int32))
                acc = quant_floor_shift(acc, shift)
                if relu_en:
                    acc = max(0, acc)
                y[oc, oh, ow] = np.int8(np.clip(acc, -127, 127))
    return y


# ========== 最大池化 ==========
def maxpool2x2(x):
    C, H, W = x.shape
    Hout, Wout = H // 2, W // 2
    y = np.zeros((C, Hout, Wout), dtype=np.int8)
    for c in range(C):
        for i in range(Hout):
            for j in range(Wout):
                y[c, i, j] = np.max(x[c, i*2:i*2+2, j*2:j*2+2])
    return y


# ========== 平均池化 ==========
def avgpool4x4(x):
    C, H, W = x.shape
    assert H == 4 and W == 4
    y = np.zeros((C, 1, 1), dtype=np.int8)
    for c in range(C):
        acc = np.sum(x[c].astype(np.int32))
        acc = quant_floor_shift(acc, 4)  # divide by 16
        y[c, 0, 0] = np.int8(np.clip(acc, -127, 127))
    return y


# ========== 全连接层 ==========
def fc_int8(x, w, Qin=5, Qw=6, Qout=5):
    OC, IC = w.shape
    x_flat = x.reshape(-1).astype(np.int32)
    y = np.zeros(OC, dtype=np.int8)
    shift = calc_shift(Qin, Qw, Qout)
    for o in range(OC):
        acc = np.sum(x_flat * w[o].astype(np.int32))
        acc = quant_floor_shift(acc, shift)
        y[o] = np.int8(np.clip(acc, -127, 127))
    return y


# ========== 文件辅助 ==========
def load_bin(path, shape):
    arr = np.fromfile(path, dtype=np.int8)
    return arr.reshape(shape)

def save_bin(path, arr):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    arr.astype(np.int8).tofile(path)


# ========== 主程序 ==========
if __name__ == "__main__":
    print("===== DNN Simulator Start =====")

    # Layer 1: Conv1
    x = load_bin("im1/input.dat", (1, 32, 32))
    w1 = load_bin("conv1.dat", (32, 1, 5, 5))
    y1 = conv2d_int8(x, w1, stride=1, pad=2, Qin=7, Qw=7, Qout=5, relu_en=True)
    save_bin("im1/conv1.output.dat", y1)
    print("Conv1 done:", y1.shape)

    # Layer 2: MaxPool
    y2 = maxpool2x2(y1)
    save_bin("im1/pool1.output.dat", y2)
    print("Pool1 done:", y2.shape)

    # Layer 3: Conv2
    w2 = load_bin("conv2.dat", (64, 32, 3, 3))
    y3 = conv2d_int8(y2, w2, stride=1, pad=1, Qin=5, Qw=8, Qout=5, relu_en=True)
    save_bin("im1/conv2.output.dat", y3)
    print("Conv2 done:", y3.shape)

    # Layer 4: Conv3
    w3 = load_bin("conv3.dat", (64, 64, 3, 3))
    y4 = conv2d_int8(y3, w3, stride=2, pad=1, Qin=5, Qw=8, Qout=5, relu_en=True)
    save_bin("im1/conv3.output.dat", y4)
    print("Conv3 done:", y4.shape)

    # Layer 5: Conv4
    w4 = load_bin("conv4.dat", (128, 64, 3, 3))
    y5 = conv2d_int8(y4, w4, stride=2, pad=1, Qin=5, Qw=8, Qout=5, relu_en=True)
    save_bin("im1/conv4.output.dat", y5)
    print("Conv4 done:", y5.shape)

    # Layer 6: AvgPool 4×4 → 1×1
    y6 = avgpool4x4(y5)
    save_bin("im1/avgpool.output.dat", y6)
    print("AvgPool done:", y6.shape)

    # Layer 7: FC
    wfc = load_bin("fc.dat", (10, 128))
    y7 = fc_int8(y6, wfc, Qin=5, Qw=6, Qout=5)
    save_bin("im1/fc.output.dat", y7)
    print("FC done:", y7.shape)

    print("===== Simulation Complete =====")
