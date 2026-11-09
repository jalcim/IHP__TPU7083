# Release v.1.0.0

First submission for the IHP Open-Silicon MPW run of November 2026 (SG13CMOS5L).

## Files

- gds/TPU7083.gds.gz, single top cell TPU7083
  - SHA-256 of TPU7083.gds: a95126420c26e4c5353246e6f81cb73b9be241bee263829b9a6098f3d6dc299e
  - SHA-256 of TPU7083.gds.gz: 7403fe1de9065c6b35bce02fcca796cb454f13159d20bfac8923ab33313be4d8
- netlist/TPU7083.spice, LVS netlist extracted from the layout
- netlist/TPU7083.nl.v and netlist/TPU7083.pnl.v, gate-level netlists

## Checks

- LVS with Netgen: circuits match uniquely
- Setup slack: +0.549 ns typical, +0.650 ns fast, -0.617 ns slow. Hold met at all three corners.
- IHP minimum DRC precheck, main and density checks: 0 violations, run on the original GDS (md5 154b7c1f430dc31406e8b27b2824e5ad, top cell chip_top). Only the top cell name differs in the released file.
