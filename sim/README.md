# Cartridge simulation

Icarus Verilog benches for `src/gb/cart.v` and the mappers (the two VHDL modules
`cart.v` instantiates are replaced by `stubs.v`; `prep_for_icarus.py` makes
simulation copies of the sources that Icarus accepts, without changing logic).

* `./run.sh`: `tb_tpp1.v`, the directed TPP1 test (register reset values, bank
  select through all 11 bits, register read-back, SRAM modes, the clock, rollover
  and overflow, the save-file tail and the catch-up after a reload). Prints `PASS`.
* `./compare_upstream.sh <upstream tree>`: `tb_trace.v` on this tree and on
  upstream, 20,000 random accesses for each of 19 mapper configurations; every
  trace must be identical.

`core_top.sv` and `sdram.sv` are not simulated.
