#!/usr/bin/env python3
"""
convert_output_to_mem.py
Simple converter: reads a whitespace-or-line separated integer file (signed or unsigned)
and writes an 8-bit hex-per-line mem file for `$readmemh`.

Usage:
  python tools/convert_output_to_mem.py --in conv1.output.data --out conv1_output_for_tb.mem --signed

By default interprets values as signed 8-bit integers and outputs two-digit hex per line.
"""
import argparse

p = argparse.ArgumentParser()
p.add_argument('--in', dest='infile', required=True)
p.add_argument('--out', dest='outfile', required=True)
p.add_argument('--signed', action='store_true', help='interpret values as signed 8-bit')
args = p.parse_args()

vals = []
try:
    with open(args.infile, 'r', encoding='utf-8') as f:
        for line in f:
            for tok in line.strip().split():
                if tok == '':
                    continue
                try:
                    v = int(tok, 0)
                except ValueError:
                    v = int(float(tok))
                vals.append(v)
except UnicodeDecodeError:
    # Binary file: read raw bytes
    with open(args.infile, 'rb') as f:
        data = f.read()
    for b in data:
        # b is 0..255
        if args.signed:
            # convert to signed 8-bit integer
            vb = b if b < 128 else b - 256
            vals.append(vb)
        else:
            vals.append(b)

with open(args.outfile, 'w', encoding='utf-8') as f:
    for v in vals:
        if args.signed:
            # wrap to signed 8-bit
            v = (v + 256) & 0xff
        else:
            v = v & 0xff
        f.write(f"{v:02x}\n")

print(f"Wrote {len(vals)} words to {args.outfile}")
