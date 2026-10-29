# Map memory implementation

`level_map.v` uses `rom_style = "block", cascade_height = 1` on both map
arrays. Keep the cascade setting when changing the map artwork. It tells
Vivado to use separate block RAMs with an output selector instead of the
dedicated cascade connections that produced REQP-1962 on the Cave Flight ROM.
Map data, coordinates and the one-clock read latency are unchanged.

After updating this source in Vivado, reset the synthesis run and generate
the bitstream again. Reusing an older synthesized checkpoint will retain
the faulty memory layout. No constraint changes or DRC severity overrides
are needed.

`sim/level_map_tb.v` checks every pixel in both maps, the four outside edges,
and both independently clocked read ports against the original `.mem` files.
Run it with `scripts/run_simulations.ps1 -Benches level_map_tb`.

AMD reference: [CASCADE_HEIGHT](https://docs.amd.com/r/en-US/ug912-vivado-properties/CASCADE_HEIGHT).
