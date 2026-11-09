# IHP__TPU7083

Tensor processing chip from Nebula Microsystems, submitted to the IHP Open-Silicon MPW run of November 2026 in SG13CMOS5L.

## Chip

- Process: IHP SG13CMOS5L, PDK commit 7bbb4b5a5b64c446fedc64eacadc33fa65ade276
- Die: 2342 x 2308 um (5.41 mm2), seal ring and metal fill included
- Top cell: TPU7083
- Clock period: 10 ns (100 MHz) at the typical corner
- Core: one tile of the Nebula Microsystems tensor processing architecture with 64-bit links.
  The tile parameters are in TPU7083-main/rtl/TPU7083_defines.vh.
- Macros: bond pad bondpad_70x70_5L, decoupling cells decapd55_8, decapd55_16 and decapd55_32, Nebula logo.
  The IO cells come from the IHP sg13cmos5l IO library.

## Contents

- release/v.1.0.0/gds/TPU7083.gds.gz: final GDS, gzip compressed
- release/v.1.0.0/netlist/TPU7083.spice: netlist extracted from the layout, used for LVS
- release/v.1.0.0/netlist/TPU7083.nl.v and TPU7083.pnl.v: gate-level netlists, without and with power pins
- TPU7083-main/rtl: Verilog sources, top module TPU7083 in TPU7083.v
- dependencies: views of the macros listed above

The flow configuration will be added later.

## Verification status

- LVS with Netgen: circuits match uniquely
- Setup slack: +0.549 ns typical, +0.650 ns fast, -0.617 ns slow. Hold is met at all three corners.
- IHP minimum DRC precheck (run_drc.py --minimum_drc, main and density checks): 0 violations.
  It ran on the original GDS (md5 154b7c1f430dc31406e8b27b2824e5ad), whose top cell is named chip_top.
  The released file differs from it only by the top cell name, TPU7083.
  Reports are in release/v.1.0.0/doc/drc.

## Third-party code

The S4xU4 multiplier in TPU7083-main/rtl/6a_mul_s4xu4.v and 6a_sg13_cells.v is derived from github.com/ygdes/S4xU4 at commit c5c0377, (c) 2026 Yann Guidon, Apache-2.0. Its license text is in TPU7083-main/rtl/LICENCE-S4xU4.

## License

Apache License 2.0, see LICENSE.
