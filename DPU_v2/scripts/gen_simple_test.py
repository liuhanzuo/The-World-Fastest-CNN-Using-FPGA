#!/usr/bin/env python3
"""
gen_simple_test.py

Generate simple test data for debugging:
  - All activations = 1
  - All weights = 1
  - Expected output = K*K*C_IN / 2^SHIFT (should be 0 for small K)
  
  Or use identity-like pattern for easier debugging.
"""

import numpy as np
from pathlib import Path

# Parameters
DATA_W = 8
TILE_C = 8
TILE_W = 8
H_IN = 32
W_IN = 32
C_IN = 1
C_OUT = 32
K = 5
PAD = 2
SHIFT = 8

H_OUT = H_IN
W_OUT = W_IN
N_TILE_C = (C_OUT + TILE_C - 1) // TILE_C

OUT_DIR = Path(__file__).parent

def numpy_conv2d(act, wgt, pad=PAD):
    """Simple 2D convolution"""
    C_OUT, C_IN, K, _ = wgt.shape
    _, H_IN, W_IN = act.shape
    H_OUT = H_IN
    W_OUT = W_IN
    
    act_pad = np.pad(act, ((0, 0), (pad, pad), (pad, pad)), mode='constant', constant_values=0)
    
    out = np.zeros((C_OUT, H_OUT, W_OUT), dtype=np.int32)
    for co in range(C_OUT):
        for ci in range(C_IN):
            for h in range(H_OUT):
                for w in range(W_OUT):
                    for kh in range(K):
                        for kw in range(K):
                            out[co, h, w] += int(act_pad[ci, h+kh, w+kw]) * int(wgt[co, ci, kh, kw])
    
    return out

def quantize(psum, shift=SHIFT):
    shifted = psum >> shift
    clipped = np.clip(shifted, -128, 127)
    return clipped.astype(np.int8)

def save_hex(filename, data, is_weight=False):
    """Save data to hex/mem file"""
    if is_weight:
        # Weight layout: [N_TILE_C][C_IN][K][K][TILE_C]
        C_OUT, C_IN_W, K_H, K_W = data.shape
        lines = []
        for tile_c in range(N_TILE_C):
            for ci in range(C_IN_W):
                for hk in range(K_H):
                    for wk in range(K_W):
                        word = []
                        for co in range(TILE_C):
                            co_global = tile_c * TILE_C + co
                            if co_global < C_OUT:
                                word.append(data[co_global, ci, hk, wk].astype(np.uint8))
                            else:
                                word.append(0)
                        hex_val = ''.join(f'{b:02x}' for b in reversed(word))
                        lines.append(hex_val)
    else:
        # Activation/Output layout: flatten and pack into 8-byte words
        flat = data.flatten().astype(np.uint8)
        pad_len = (8 - len(flat) % 8) % 8
        if pad_len > 0:
            flat = np.concatenate([flat, np.zeros(pad_len, dtype=np.uint8)])
        lines = []
        for i in range(0, len(flat), 8):
            word = flat[i:i+8]
            hex_val = ''.join(f'{b:02x}' for b in reversed(word))
            lines.append(hex_val)
    
    # Save .hex
    with open(filename, 'w') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"Saved {filename}: {len(lines)} words")
    
    # Save .mem
    mem_filename = str(filename).replace('.hex', '.mem')
    with open(mem_filename, 'w') as f:
        for line in lines:
            f.write(line + '\n')

def main():
    print("=== Simple Test Data Generator ===")
    
    # Test 1: All ones
    # act = 1, wgt = 1 => psum = K*K*C_IN = 25, shifted = 0
    print("\n--- Test: Scaled pattern ---")
    
    # Use a pattern where output is predictable:
    # - Activation = position-dependent value
    # - Weight = simple pattern
    
    # Create activation: each position has a unique small value
    act = np.zeros((C_IN, H_IN, W_IN), dtype=np.int8)
    for ci in range(C_IN):
        for h in range(H_IN):
            for w in range(W_IN):
                # Use small values to avoid overflow
                act[ci, h, w] = ((h + w) % 16) - 8  # Range: -8 to 7
    
    # Create weight: only center weight = 256, others = 0
    # This means output = activation * 256 >> 8 = activation
    wgt = np.zeros((C_OUT, C_IN, K, K), dtype=np.int8)
    # Center position for 5x5 kernel is (2, 2)
    # We want wgt * act >> 8 to give a meaningful result
    # Let's use wgt[co][ci][2][2] = 1 for co == 0, else 0
    # Then out[0] = act (shifted), out[1..31] = 0
    
    # Actually, let's use: all weights = 1 at center
    # psum = act * 1 = act, shifted = act >> 8 = 0 (for small act)
    
    # Better: use weight = 16 for all, so psum = act * 16 * K * K = act * 400
    # shifted = act * 400 >> 8 = act * 1.56... 
    
    # Simplest test: wgt[co][ci][2][2] = 1 only at center, rest = 0
    # Then psum = sum over ci of act[ci][h][w] * 1 = act[0][h][w] (for C_IN=1)
    # shifted = act >> 8 = 0 for act in [-128, 127]
    
    # Let's use larger weight to get non-zero output:
    # wgt[co][ci][2][2] = 127 (center only)
    # psum = act * 127, shifted = act * 127 >> 8
    
    # Even simpler: just use all ones and check if the hardware works
    act = np.ones((C_IN, H_IN, W_IN), dtype=np.int8)
    wgt = np.ones((C_OUT, C_IN, K, K), dtype=np.int8)
    
    # Expected: psum = K*K*C_IN = 25, shifted = 25 >> 8 = 0
    # But we want non-zero output, so let's scale:
    # Use larger weight value
    wgt = wgt * 64  # wgt = 64
    # psum = 25 * 64 = 1600, shifted = 1600 >> 8 = 6
    
    print(f"Activation: all 1s, shape={act.shape}")
    print(f"Weight: all 64s, shape={wgt.shape}")
    
    # Compute golden output
    psum = numpy_conv2d(act, wgt)
    out = quantize(psum)
    
    print(f"Expected psum (interior): {K*K*C_IN*64} = {25*64}")
    print(f"Expected output (interior): {25*64 >> SHIFT} = {(25*64) >> SHIFT}")
    print(f"Actual psum[0,4,4]: {psum[0,4,4]}")  # Interior point (not affected by padding)
    print(f"Actual out[0,4,4]: {out[0,4,4]}")
    print(f"Psum range: [{psum.min()}, {psum.max()}]")
    print(f"Out range: [{out.min()}, {out.max()}]")
    
    # Save files
    save_hex(OUT_DIR / 'act_input.hex', act)
    save_hex(OUT_DIR / 'wgt_input.hex', wgt, is_weight=True)
    save_hex(OUT_DIR / 'exp_output.hex', out)
    
    print("\nFirst output row (co=0, h=0):")
    print(f"out[0,0,:8] = {out[0,0,:8]}")
    print(f"out[0,0,8:16] = {out[0,0,8:16]}")
    
    print("\nDone!")

if __name__ == '__main__':
    main()
