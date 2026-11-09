`ifndef __CHIP_TOP__
`define __CHIP_TOP__

`include "11_tile.v"

`ifndef CHIP_CORE_PAIRS
  `define CHIP_CORE_PAIRS 3
`endif
`ifndef CHIP_OUT_PAD
  `define CHIP_OUT_PAD sg13cmos5l_IOPadOut30mA
`endif

`default_nettype none

/* Puce à plat : la tuile de rtl/11_tile.v et son ring de plots dans un seul Verilog structurel, que Yosys synthétise
 * d'un bloc, sur le modèle de src/chip_top.v de tensorcore à 9161e77 (plan des puces à plat, tâche 3).
 * La tuile prend ses paramètres des défines TILE_<clé> de l'accord, et les largeurs des ports de plots en dérivent
 * comme dans la tuile (rtl/11_tile.v:80-82).
 *
 * NOMS. Chaque plot porte le nom que rtl/pnr/die/ring.py à 4e33dec lui donne : u_<nom> pour un signal seul,
 * g_<rôle>[i].u_pad pour un bit de bus ou une paire de rails, que aides.ring_name ramène au nom de ring.py.
 * Le rang de chaque plot dans le ring revient à la config de chaque puce, par ring.pad_lists.
 *
 * CELLULES. Entrées par sg13cmos5l_IOPadIn, p2c vers la tuile. Sorties par CHIP_OUT_PAD, c2p depuis la tuile, le plot
 * de 30 mA par défaut pour les puces 2 et 3, de même empreinte que celui de 4 mA de ring.tcl (décision du 30/10 à
 * 5 h 41). Rails iovdd, iovss, vdd et vss de chaque plot sous USE_POWER_PINS, comme tensorcore.
 *
 * POLARITÉ. Câblage droit, sans inverseur : le plot d'entrée d'IHP rend p2c = pad (function "pad" de sa Liberty), et
 * rtl/1_link_in.v prend chaque demi-cycle au front montant de son propre plot, CLK_P vers i_clk_in pour le premier,
 * CLK_N vers i_clk_in_n pour le second. Les anneaux croisés et les données inversées du câblage de Lionel supposent
 * un plot qui inverse, et ne valent que pour lui (question 3 de la MR !9 de hexeract, relayée le 30/10).
 *
 * RAILS. IO_PAIRS paires IOVDD et IOVSS, une par 12 signaux (règle 4 de ring.py, ring.tcl:75-81), et CHIP_CORE_PAIRS
 * paires VDD et VSS du cœur, trois par défaut comme ring.CORE_PAIRS. Plots de rails et logo sous (* keep *), aucune
 * broche de signal ne les retenant, comme tensorcore. Le logo n'est pas déclaré ici : sa boîte noire vient de
 * ip/logo_nebula/vh/, comme le vh du MACROS de tensorcore. */
module TPU7083 #(parameter PINS     = `TILE_W / `TILE_BPP,
                  parameter DBI_PINS = (PINS + 7) / 8,
                  parameter OUT_W    = `TILE_OUT_W,
                  parameter DBI_N    = (OUT_W + 7) / 8)
                 (
`ifdef USE_POWER_PINS
                  inout wire                VDD,
                  inout wire                VSS,
                  inout wire                IOVDD,
                  inout wire                IOVSS,
`endif
                  inout wire [PINS-1:0]     D_PAD,
                  inout wire [DBI_PINS-1:0] DBI_PAD,
                  inout wire                CLK_P_PAD,
                  inout wire                CLK_N_PAD,
                  inout wire                VALID_PAD,
                  inout wire                READY_IN_PAD,
                  inout wire [OUT_W-1:0]    Q_PAD,
                  inout wire [DBI_N-1:0]    DBI_OUT_PAD,
                  inout wire                CLK_OUT_PAD,
                  inout wire                VALID_OUT_PAD,
                  inout wire                READY_OUT_PAD,
                  inout wire                RST_N_PAD);

    /* Signaux du ring : les bus de données et de DBI, puis CLK_P, VALID, CLK_N, RST_N, READY_OUT, READY_IN, CLK_OUT et
     * VALID_OUT (ring.signals). */
    localparam SIGNALS  = PINS + DBI_PINS + OUT_W + DBI_N + 8;
    localparam IO_PAIRS = (SIGNALS + 11) / 12;

    wire [PINS-1:0]     w_d_in;
    wire [DBI_PINS-1:0] w_dbi_in;
    wire                w_clk_in;
    wire                w_clk_in_n;
    wire                w_valid_in;
    wire                w_ready_in;
    wire [OUT_W-1:0]    w_q_out;
    wire [DBI_N-1:0]    w_dbi_out;
    wire                w_clk_out;
    wire                w_valid_out;
    wire                w_ready_out;
    wire                w_rst_n;

    tile u_tile (.i_d_in(w_d_in), .i_dbi_in(w_dbi_in), .i_clk_in(w_clk_in), .i_clk_in_n(w_clk_in_n),
                 .i_valid_in(w_valid_in), .o_ready_in(w_ready_in), .o_q_out(w_q_out), .o_dbi_out(w_dbi_out),
                 .o_clk_out(w_clk_out), .o_valid_out(w_valid_out), .i_ready_out(w_ready_out), .i_rst_n(w_rst_n));

    sg13cmos5l_IOPadIn u_CLK_P (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .pad(CLK_P_PAD), .p2c(w_clk_in));

    sg13cmos5l_IOPadIn u_CLK_N (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .pad(CLK_N_PAD), .p2c(w_clk_in_n));

    sg13cmos5l_IOPadIn u_VALID (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .pad(VALID_PAD), .p2c(w_valid_in));

    sg13cmos5l_IOPadIn u_RST_N (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .pad(RST_N_PAD), .p2c(w_rst_n));

    sg13cmos5l_IOPadIn u_READY_OUT (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .pad(READY_OUT_PAD), .p2c(w_ready_out));

    `CHIP_OUT_PAD u_READY_IN (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .c2p(w_ready_in), .pad(READY_IN_PAD));

    `CHIP_OUT_PAD u_CLK_OUT (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .c2p(w_clk_out), .pad(CLK_OUT_PAD));

    `CHIP_OUT_PAD u_VALID_OUT (
`ifdef USE_POWER_PINS
        .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
        .c2p(w_valid_out), .pad(VALID_OUT_PAD));

    genvar pin_idx;
    generate
        for (pin_idx = 0; pin_idx < PINS; pin_idx = pin_idx + 1)
            begin : g_D
                sg13cmos5l_IOPadIn u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
                    .pad(D_PAD[pin_idx]), .p2c(w_d_in[pin_idx]));
            end
    endgenerate

    genvar group_idx;
    generate
        for (group_idx = 0; group_idx < DBI_PINS; group_idx = group_idx + 1)
            begin : g_DBI
                sg13cmos5l_IOPadIn u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
                    .pad(DBI_PAD[group_idx]), .p2c(w_dbi_in[group_idx]));
            end
    endgenerate

    genvar out_idx;
    generate
        for (out_idx = 0; out_idx < OUT_W; out_idx = out_idx + 1)
            begin : g_Q
                `CHIP_OUT_PAD u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
                    .c2p(w_q_out[out_idx]), .pad(Q_PAD[out_idx]));
            end
    endgenerate

    genvar out_group_idx;
    generate
        for (out_group_idx = 0; out_group_idx < DBI_N; out_group_idx = out_group_idx + 1)
            begin : g_DBI_OUT
                `CHIP_OUT_PAD u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS),
`endif
                    .c2p(w_dbi_out[out_group_idx]), .pad(DBI_OUT_PAD[out_group_idx]));
            end
    endgenerate

    genvar io_pair;
    generate
        for (io_pair = 0; io_pair < IO_PAIRS; io_pair = io_pair + 1)
            begin : g_IOVDD
                (* keep *) sg13cmos5l_IOPadIOVdd u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS)
`endif
                    );
            end
        for (io_pair = 0; io_pair < IO_PAIRS; io_pair = io_pair + 1)
            begin : g_IOVSS
                (* keep *) sg13cmos5l_IOPadIOVss u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS)
`endif
                    );
            end
    endgenerate

    genvar core_pair;
    generate
        for (core_pair = 0; core_pair < `CHIP_CORE_PAIRS; core_pair = core_pair + 1)
            begin : g_VDD
                (* keep *) sg13cmos5l_IOPadVdd u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS)
`endif
                    );
            end
        for (core_pair = 0; core_pair < `CHIP_CORE_PAIRS; core_pair = core_pair + 1)
            begin : g_VSS
                (* keep *) sg13cmos5l_IOPadVss u_pad (
`ifdef USE_POWER_PINS
                    .vdd(VDD), .vss(VSS), .iovdd(IOVDD), .iovss(IOVSS)
`endif
                    );
            end
    endgenerate

    (* keep *) logo_nebula u_logo ();

endmodule

`default_nettype wire

`endif
