#!/usr/bin/env python3
"""
bin_to_mem.py
Convert a binary file (byte stream) into a $readmemh-style mem file (one 2-digit hex per line).
Usage:
    python tools/bin_to_mem.py --in data/parameters/conv1.dat --out data/parameters/conv1_bin_for_tb.mem
"""
import argparse
import os

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--in', dest='infile', required=True)
    p.add_argument('--out', dest='outfile', required=True)
    args = p.parse_args()

    with open(args.infile, 'rb') as f:
        data = f.read()

    os.makedirs(os.path.dirname(args.outfile), exist_ok=True)
    with open(args.outfile, 'w') as f:
        for b in data:
            f.write(f"{b:02x}\n")

    print(f"Wrote {len(data)} bytes to {args.outfile}")

if __name__ == '__main__':
    main()
