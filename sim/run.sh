#!/bin/sh
# Simulation of the cartridge side of the core (Icarus Verilog 13).
#   ./run.sh          directed TPP1 test (tb_tpp1.v)
#   ./run.sh trace T  print the bus trace of tb_trace.v for mapper case T
# SRC=<tree>/src selects another source tree (used to compare against upstream).
set -e
cd "$(dirname "$0")"
SRC=${SRC:-../src}
B=${BUILD:-build}
python3 prep_for_icarus.py "$B/src" "$SRC"/gb/cart.v "$SRC"/gb/mappers/*.v "$SRC"/gb/mappers/*.sv
if [ "$1" = trace ]; then
	iverilog -g2012 -DMAW=${MAW:-25} -DCASE=$2 -o "$B/tb_trace.vvp" stubs.v tb_trace.v "$B"/src/*
	vvp -n "$B/tb_trace.vvp"
else
	iverilog -g2012 -o "$B/tb_tpp1.vvp" stubs.v tb_tpp1.v "$B"/src/*
	vvp -n "$B/tb_tpp1.vvp"
fi
