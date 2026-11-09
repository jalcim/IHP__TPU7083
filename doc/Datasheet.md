# TPU7083 datasheet

## Summary

| Item | Value |
| --- | --- |
| Process | IHP SG13CMOS5L |
| Die size | 2342 x 2308 um (5.41 mm2), seal ring included |
| Bond pads | 71, 70 x 70 um |
| Signal pads | 41 inputs (sg13cmos5l_IOPadIn), 12 outputs (sg13cmos5l_IOPadOut30mA) |
| Supply pads | 4 VDD, 4 VSS, 5 IOVDD, 5 IOVSS |
| Core supply VDD | 1.2 V nominal, timing libraries at 1.08 V, 1.20 V and 1.32 V |
| IO supply IOVDD | 3.3 V nominal, IO libraries at 3.0 V, 3.3 V and 3.6 V |

## Pins

| Pin | Direction | IO cell | Function |
| --- | --- | --- | --- |
| D_PAD[31:0] | input | sg13cmos5l_IOPadIn | Data bus, two bits per pad and per clock period |
| DBI_PAD[3:0] | input | sg13cmos5l_IOPadIn | Data bus inversion flags, one per group of 8 data pads |
| CLK_P_PAD | input | sg13cmos5l_IOPadIn | Input clock for the first half of each period |
| CLK_N_PAD | input | sg13cmos5l_IOPadIn | Input clock for the second half of each period |
| VALID_PAD | input | sg13cmos5l_IOPadIn | Input data valid |
| READY_OUT_PAD | input | sg13cmos5l_IOPadIn | The downstream device is ready to take output data |
| RST_N_PAD | input | sg13cmos5l_IOPadIn | Reset, active low |
| Q_PAD[7:0] | output | sg13cmos5l_IOPadOut30mA | Output data bus |
| DBI_OUT_PAD[0] | output | sg13cmos5l_IOPadOut30mA | Data bus inversion flag of Q_PAD |
| CLK_OUT_PAD | output | sg13cmos5l_IOPadOut30mA | Output clock sent with Q_PAD |
| VALID_OUT_PAD | output | sg13cmos5l_IOPadOut30mA | Output data valid |
| READY_IN_PAD | output | sg13cmos5l_IOPadOut30mA | The chip is ready to take input data |

## Supplies

| Pin | Function |
| --- | --- |
| VDD, VSS | Core supply and ground |
| IOVDD, IOVSS | Supply and ground of the IO ring |

No measured silicon data is available yet.
