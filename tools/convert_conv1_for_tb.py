#!/usr/bin/env python3
"""
convert_conv1_for_tb.py

Convert original conv1 weight and input files into memory files suitable for $readmemh in tb_top_sim.v.

Usage:
    python convert_conv1_for_tb.py \
        --act-in data/im1/conv1.input.dat \
        --wgt-in data/parameters/conv1.real.dat \
        --act-out data/im1/conv1_for_tb.mem \
        --wgt-out data/parameters/conv1_for_tb.mem \
        --c_in 16 --c_out 16 --h 3 --w 3 --h_in 10 --w_in 10

Assumptions:
 - Input activation file is flattened as I[c, h, w] in row-major order (c major then h then w).
 - Original weight file is flattened as [c_out, c_in, h, w] in row-major order.
 - We convert weights to layout per-`c_in` blocks: for each c_in, list K*K*C_out elements in order (hk, wk, co).
 - Output files are hex two's-complement words (8-bit) one per line for $readmemh.

Clip range to [-128,127].
"""
import argparse
import os
import sys

import math


def to_uint8_hex(x):
    # x is signed integer
    xi = int(x)
    if xi < 0:
        xi = (xi + 256) & 0xff
    return "%02x" % (xi & 0xff)


def read_numbers_from_file(path):
    # Read all numeric tokens from a text file
    nums = []
    with open(path, 'r') as f:
        for line in f:
            # remove comments
            line = line.split('#',1)[0]
            toks = line.strip().split()
            for t in toks:
                try:
                    if '.' in t or 'e' in t or 'E' in t:
                        v = float(t)
                    else:
                        v = int(t,0)
                    nums.append(v)
                except Exception:
                    # skip non-numeric
                    pass
    return nums


def write_mem_file(path, arr):
    with open(path, 'w') as f:
        for v in arr:
            f.write(v + '\n')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--act-in', required=True)
    p.add_argument('--wgt-in', required=True)
    p.add_argument('--act-out', required=True)
    p.add_argument('--wgt-out', required=True)
    p.add_argument('--c_in', type=int, required=True)
    p.add_argument('--c_out', type=int, required=True)
    p.add_argument('--k', type=int, default=3)
    p.add_argument('--h_in', type=int, required=True)
    p.add_argument('--w_in', type=int, required=True)
    args = p.parse_args()

    C_IN = args.c_in
    C_OUT = args.c_out
    K = args.k
    H_IN = args.h_in
    W_IN = args.w_in

    # Read activation
    act_nums = read_numbers_from_file(args.act_in)
    expected_act = C_IN * H_IN * W_IN
    if len(act_nums) < expected_act:
        print(f"Warning: activation file contains {len(act_nums)} elements, expected {expected_act}")
    # Truncate or pad
    act_nums = act_nums[:expected_act] + [0] * max(0, expected_act - len(act_nums))

    # Convert activations to hex (8-bit signed)
    act_hex = []
    for v in act_nums:
        # round floats
        if isinstance(v, float):
            v = int(round(v))
        # clip
        if v < -128: v = -128
        if v > 127: v = 127
        act_hex.append(to_uint8_hex(v))

    os.makedirs(os.path.dirname(args.act_out), exist_ok=True)
    write_mem_file(args.act_out, act_hex)
    print(f"Wrote activation mem to {args.act_out} ({len(act_hex)} words)")

    # Read weights
    wgt_nums = read_numbers_from_file(args.wgt_in)
    expected_wgt = C_OUT * C_IN * K * K
    if len(wgt_nums) < expected_wgt:
        print(f"Warning: weight file contains {len(wgt_nums)} elements, expected {expected_wgt}")
    wgt_nums = wgt_nums[:expected_wgt] + [0] * max(0, expected_wgt - len(wgt_nums))

    # Original layout: [c_out, c_in, hk, wk]
    # Build 4D list for easier transpose
    W = [[[ [0 for _ in range(K)] for _ in range(K)] for _ in range(C_IN)] for _ in range(C_OUT)]
    idx = 0
    for co in range(C_OUT):
        for ci in range(C_IN):
            for hk in range(K):
                for wk in range(K):
                    v = wgt_nums[idx]
                    idx += 1
                    W[co][ci][hk][wk] = v

    # Desired layout: per ci, for hk in 0..K-1, wk in 0..K-1, co in 0..C_OUT-1
    out_list = []
    for ci in range(C_IN):
        for hk in range(K):
            for wk in range(K):
                for co in range(C_OUT):
                    v = W[co][ci][hk][wk]
                    if isinstance(v, float):
                        v = int(round(v))
                    if v < -128: v = -128
                    if v > 127: v = 127
                    out_list.append(to_uint8_hex(v))

    os.makedirs(os.path.dirname(args.wgt_out), exist_ok=True)
    write_mem_file(args.wgt_out, out_list)
    print(f"Wrote weight mem to {args.wgt_out} ({len(out_list)} words)")

if __name__ == '__main__':
    main()
