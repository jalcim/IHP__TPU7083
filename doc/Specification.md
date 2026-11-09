# TPU7083 specification

## Function

TPU7083 is a tensor processing test chip from Nebula Microsystems.
Its core is one tile of the Nebula Microsystems tensor processing architecture, synthesized from the Verilog in TPU7083-main/rtl.
The chip takes a stream of input words, computes on them in the core and sends the results on an 8 bit output bus.

## Input interface

The input link carries 64 bit words on 32 data pads, two bits per pad and per clock period.
The first half of each period is captured on CLK_P_PAD and the second half on CLK_N_PAD.
DBI_PAD carries one data bus inversion flag for each group of 8 data pads.
VALID_PAD marks valid input data, and READY_IN_PAD tells the sender that the chip can take data.

## Output interface

Q_PAD is an 8 bit output bus with one data bus inversion flag on DBI_OUT_PAD.
CLK_OUT_PAD is sent with the data, and VALID_OUT_PAD marks valid output data.
READY_OUT_PAD tells the chip that the receiver can take data.

## Reset

RST_N_PAD is an active low reset.

## Implementation

- Process IHP SG13CMOS5L, IO cells from the sg13cmos5l IO library.
- Macros: bondpad_70x70_5L, decapd55_8, decapd55_16, decapd55_32 and logo_nebula.
- Die 2342 x 2308 um (5.41 mm2), with seal ring and metal fill.
