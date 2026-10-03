# Game Boy Color for Analogue Pocket, with the TPP1 mapper

This branch (`tpp1`) is [budude2/openfpga-GBC](https://github.com/budude2/openfpga-GBC)
1.4.0 plus the [TPP1](https://github.com/aaaaaa123456789/tpp1) mapper. It installs
beside the stock core as `CSE.GBCTPP1` and shares its platform (`gbc`), ROM folder
and BIOS file.

* **TPP1** (`src/gb/mappers/tpp1.v`): 16-bit ROM bank, register read-back, read-only
  and read/write SRAM, the real-time clock with latch/set/stop/start/overflow.
  Detected from the header (`$0147 = $BC`, `$0149 = $C1`, `$014A = $65`).
* **ROM size:** the cartridge address path is 25 bits (it was 23), so ROMs up to
  32 MiB load and bank; TPP1 bank numbers above 2047 wrap. 16 MiB is tested in
  simulation; nothing above 16 MiB has run on hardware.
* **SRAM:** up to 128 KiB (TPP1 size codes above that are capped).
* **Clock:** kept in the save file tail exactly like the MBC3 clock, and advanced
  by the Pocket's clock on the next start.
* **Rumble:** commands are accepted, MR4 reports speed 0 (no motor).
* Every other mapper is unchanged: `sim/compare_upstream.sh` runs random bus
  traffic against 19 mapper configurations on this tree and on upstream and
  requires identical output.

Install: unzip the release onto the SD card root, merging with the existing
`Assets`, `Cores` and `Platforms` folders (Finder replaces folders: copy the
contents by hand). The BIOS is the stock core's `/Assets/gbc/common/gbc_bios.bin`.

Build: the `Build` workflow simulates the cartridge logic (Icarus Verilog),
compiles with Quartus 21.1 Lite in Docker, reverses the bitstream and uploads the
core folder; a `tpp1-v*` tag publishes it as a release.

The upstream README follows.

---

# Gameboy/Game Boy Color for Analogue Pocket
Ported from the original core developed at https://github.com/MiSTer-devel/Gameboy_MiSTer

Please report any issues encountered to this repo. Issues will be upstreamed as necessary.

## Installation
To install the core, copy the `Assets`, `Cores`, and `Platform` folders over to the root of your SD card. Please note that Finder on macOS automatically _replaces_ folders, rather than merging them like Windows does, so you have to manually merge the folders.

Place the GBC bios in `/Assets/gbc/common` named "gbc_bios.bin", the GB bios in `/Assets/gb/common` named "gb_bios.bin", and the SGB bios in `/Assets/gb/common` named "sgb_boot.bin".


## Usage
ROMs should be placed in `/Assets/gbc/common`, and `/Assets/gb/common`

## Features

### Supported
* Real-Time Clock
* Fastforward
* Original Gameboy display modes
* Super Gameboy Emulation
* Custom Borders (SGB)
* Custom Palettes (SGB)
* Enhance GBA features
* Save States and Sleep
* External Cartridges

### In Progress
¯\\_(ツ)_/¯
