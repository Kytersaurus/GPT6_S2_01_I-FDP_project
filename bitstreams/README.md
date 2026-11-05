# Bitstreams Directory

This directory stores pre-built FPGA bitstreams (`.bit`) for the **Digilent Basys 3 (`XC7A35T-1CPG236C`)** board.

## Building a Fresh Bitstream

To synthesize, place, route, and generate a fresh bitstream from the current RTL sources, run:

```powershell
vivado -mode batch -source scripts/build_bitstream.tcl
```

The build script outputs:
- Routed bitstream: `tmp/bitstream_build/My_Top_Module.bit`
- Resource utilization report: `tmp/bitstream_build/utilization_routed.rpt`
- Timing summary report: `tmp/bitstream_build/timing_routed.rpt`

### Target Hardware Verification Metrics
- **Slice LUTs:** $\le 20,800$ (current build: ~17,199 LUTs / 82.69%)
- **Block RAM Tiles (`RAMB36E1`):** $48 / 50$ (96.00%)
- **DSP48E1 Slices:** $16 / 90$ (17.78%)
- **Worst Negative Slack (WNS):** $> 0.000\text{ ns}$ (0 failing endpoints at 100 MHz logic / 6.25 MHz SPI)
