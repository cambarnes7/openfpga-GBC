#!/usr/bin/env python3
"""Turn a Quartus .rbf into the .rbf_r the Analogue Pocket loads: the same bytes,
each with its bit order reversed.   usage: reverse_bits.py in.rbf out.rbf_r"""
import sys
table = bytes(int(f'{b:08b}'[::-1], 2) for b in range(256))
data = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'wb').write(data.translate(table))
print(f'{sys.argv[2]}: {len(data)} bytes')
