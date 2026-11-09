# Release v.1.0.0

First submission for the IHP Open-Silicon MPW run of November 2026 (SG13CMOS5L).

## Files

- gds/TPU7083.gds.gz, single top cell TPU7083
  - SHA-256 of TPU7083.gds: a95126420c26e4c5353246e6f81cb73b9be241bee263829b9a6098f3d6dc299e
  - SHA-256 of TPU7083.gds.gz: 7403fe1de9065c6b35bce02fcca796cb454f13159d20bfac8923ab33313be4d8
- netlist/TPU7083.spice, LVS netlist extracted from the layout
- netlist/TPU7083.nl.v and netlist/TPU7083.pnl.v, gate-level netlists

## Checks

- IHP minimum DRC precheck of the released GDS, main and density checks: 0 violations, see doc/drc/precheck.txt

## Seal ring text

The seal ring text on layer 63/0 reads "Calculated area: 5.4e-06 sq mm" and "PDK version: Unknown".
Both strings come from the seal ring PCell of the PDK. The area is given in square metres, which is 5.41 mm2, and the PDK revision is the one in doc/info.json.
The GDS is not modified.
