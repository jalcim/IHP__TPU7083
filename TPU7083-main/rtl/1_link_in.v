`ifndef __LINK_IN__
`define __LINK_IN__

`include "00_params.vh"

/* Interface d'entrée de la tuile : capture DDR du lien, décodage DBI, synchroniseur de RST_N, READY_IN,
 * sélecteur d'écho et séquenceur d'état, contrat 1 de rtl/contrats.md,
 * amendé par le dépôt de travail non publié.
 * Une section citée seule est une section de spec/03_interfaces.md.
 *
 * ÉCARTS E1 ET E2 DE L'ÉTAPE 5. Le lien compte ⌈PINS / 8⌉ groupes DBI, le groupe j couvrant les broches 8 j à
 * 8 j + n_j − 1 avec n_j = min(8, PINS − 8 j) : quand PINS n'est pas multiple de 8, le dernier groupe est court, de
 * PINS mod 8 broches, et son bit DBI n'inverse que celles-là (E1). ECHO_SEL tient sur ECHO_SEL_W = ⌈log2 ECHO_N⌉
 * bits, ECHO_N = ⌈RAW_W / 8⌉ étant le nombre d'octets du mot brut w_raw, et une sélection de ECHO_N à 2^ECHO_SEL_W − 1 rend 0
 * (E2). Le module du commit 5bcb0b8 comptait ⌊PINS / 8⌋ groupes et 5 bits de sélection, d'où W multiple de 16 et
 * ECHO_N ≤ 32 : à W multiple de 16 avec ECHO_N de 17 à 32, ce module rend les mêmes sorties que lui.
 *
 * DEUX REGISTRES DE CAPTURE. Chaque demi-cycle est pris par le front montant de son propre plot, CLK_IN pour
 * le premier, CLK_IN_N pour le second. La distorsion de rapport cyclique du plot, de la carte fille et des
 * traducteurs reste ainsi hors de la fenêtre, ce qu'un registre sur les deux fronts d'une même horloge ne
 * garantirait pas (section 3.1, etudes/spec/ddr.md section 3.3).
 *
 * POURQUOI r_f. r_cap_p et r_cap_n sont sur des branches d'horloge courtes, près des plots, et le cœur sur
 * un arbre profond. Avec Δ le retard de l'arbre du cœur moins celui des branches courtes, r_f, sur le front
 * descendant de clk, donne à chaque transfert une demi-période plus ou moins Δ, en setup comme en hold, et
 * tout tient pour |Δ| < 2,5 ns à 150 MHz (section 4.2). Sans r_f, le transfert de r_cap_p vers r_raw_rest serait
 * une course dès que Δ approche le clk→q, de 0,13 à 0,39 ns selon le coin (section 3.1).
 *
 * POURQUOI AUCUN MODE DBI. Le décodage est toujours actif : un FPGA qui ne code pas tient DBI_IN à 0, et
 * les données passent telles quelles. Ni mode ni broche de configuration, contrairement au tirage au reset
 * de 031_data_bus_inversion.md, dépôt de travail non publié (section 3.2).
 *
 * LATENCE. Le mot dont le premier demi-cycle est centré sur le front e_k de CLK_IN est dans o_in_word
 * pendant le cycle k + 1, par r_cap_p, r_f puis r_raw_rest, le décodage DBI étant combinatoire (trou 2 du plan).
 *
 * RESET. RST_N agit dès son assertion et se relâche par deux bascules sur clk (section 4.11). READY_IN est
 * remis à 0 par RST_N lui-même, donc tombe dès l'assertion, puis suit rst_n_sync, sauf en ERREUR : seuls
 * in_overflow et hdr_err y mènent, eux seuls désalignant le flux (section 4.3). Des bascules du mot brut, seule
 * celle de in_valid a un reset : les données, réécrites à chaque cycle, ne servent que sous in_valid. Elle
 * forme donc son propre registre, r_raw_valid, et le reste r_raw_rest, chacun dans un seul processus.
 * Le fil w_raw, que sonde le banc, ne fait que les regrouper.
 *
 * ÉCHO ET ÉTAT. L'écho est combinatoire depuis w_raw, octet brut avant DBI, les bits au-delà de RAW_W à 0.
 * Le séquenceur d'état émet ses 8 octets pendant les 8 cycles qui suivent le front de i_stat_req, chaque
 * valeur lue au cycle de son octet, sans copie (section 4.7). Le contrat arme le séquenceur au front de
 * chaque demande : une i_stat_req pendant l'émission la reprend donc à l'octet 0, lecture acceptée le 13/10/2026. L'état passe avant l'écho s'ils tombent au même cycle, cas que le contrat du
 * FPGA exclut. */

module link_in #(parameter W          = `TILE_W,
                 parameter BPP        = `TILE_BPP,
                 parameter PINS       = W / BPP,
                 parameter DBI_PINS   = (PINS + 7) / 8,
                 parameter RAW_W      = 2 * (PINS + DBI_PINS + 1),
                 parameter ECHO_N     = (RAW_W + 7) / 8,
                 parameter ECHO_SEL_W = $clog2(ECHO_N))
                (input                   i_clk_pad_p,
                 input                   i_clk_pad_n,
                 input                   i_clk,
                 input                   i_rst_n,
                 input  [PINS-1:0]       i_d_in,
                 input  [DBI_PINS-1:0]   i_dbi_in,
                 input                   i_valid_in,
                 input                   i_err_state,
                 input  [ECHO_SEL_W-1:0] i_echo_sel,
                 input                   i_echo_take,
                 input                   i_stat_req,
                 input  [15:0]           i_last_pass_id,
                 input  [31:0]           i_mac_wait_count,
                 input                   i_in_overflow,
                 input                   i_hdr_err,
                 input                   i_out_overflow,
                 input                   i_out_collide,
                 output                  o_rst_n_sync,
                 output [W-1:0]          o_in_word,
                 output                  o_in_valid,
                 output                  o_in_type,
                 output                  o_ready_in,
                 output [7:0]            o_echo_byte,
                 output                  o_echo_valid);

    reg  [PINS+DBI_PINS:0]       r_cap_p;
    reg  [PINS+DBI_PINS:0]       r_cap_n;
    reg  [PINS+DBI_PINS:0]       r_f;
    reg  [RAW_W-2:0]             r_raw_rest;
    reg                          r_raw_valid;
    wire [RAW_W-1:0]             w_raw;
    reg                          r_sync_first;
    reg                          r_rst_n_sync;
    reg                          r_ready_in;
    reg                          r_stat_busy;
    reg  [2:0]                   r_stat_idx;
    wire [8*(1<<ECHO_SEL_W)-1:0] w_echo_bus;
    wire [7:0]                   w_echo_byte;
    wire [63:0]                  w_stat_bytes;
    wire [7:0]                   w_stat_byte;

    always @(posedge i_clk_pad_p)
        r_cap_p <= {i_valid_in, i_dbi_in, i_d_in};

    always @(posedge i_clk_pad_n)
        r_cap_n <= {i_valid_in, i_dbi_in, i_d_in};

    always @(negedge i_clk)
        r_f <= r_cap_p;

    always @(posedge i_clk)
        r_raw_rest <= {r_cap_n[PINS+DBI_PINS], r_cap_n[PINS+DBI_PINS-1:0], r_f[PINS+DBI_PINS-1:0]};

    always @(posedge i_clk or negedge r_rst_n_sync)
        if (!r_rst_n_sync)
            r_raw_valid <= 1'b0;
        else
            r_raw_valid <= r_f[PINS+DBI_PINS];

    assign w_raw = {r_raw_rest[RAW_W-2], r_raw_valid, r_raw_rest[RAW_W-3:0]};

    /* Groupe DBI j, broches 8 j à 8 j + n_j − 1 de chaque demi-cycle : n_j = 8, sauf pour le dernier groupe quand PINS
     * n'est pas multiple de 8, court de PINS mod 8 broches (écart E1). */
    genvar group_idx;
    generate
        for (group_idx = 0; group_idx < DBI_PINS; group_idx = group_idx + 1)
            begin : g_dbi
                if (8*group_idx + 8 <= PINS)
                    begin : g_full
                        assign o_in_word[8*group_idx +: 8] = w_raw[8*group_idx +: 8] ^ {8{w_raw[PINS + group_idx]}};
                        assign o_in_word[PINS + 8*group_idx +: 8] = w_raw[PINS + DBI_PINS + 8*group_idx +: 8]
                                                                    ^ {8{w_raw[2*PINS + DBI_PINS + group_idx]}};
                    end
                else
                    begin : g_short
                        assign o_in_word[8*group_idx +: PINS % 8] =
                            w_raw[8*group_idx +: PINS % 8] ^ {(PINS % 8){w_raw[PINS + group_idx]}};
                        assign o_in_word[PINS + 8*group_idx +: PINS % 8] =
                            w_raw[PINS + DBI_PINS + 8*group_idx +: PINS % 8]
                            ^ {(PINS % 8){w_raw[2*PINS + DBI_PINS + group_idx]}};
                    end
            end
    endgenerate

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_sync_first <= 1'b0;
                r_rst_n_sync <= 1'b0;
            end
        else
            begin
                r_sync_first <= 1'b1;
                r_rst_n_sync <= r_sync_first;
            end

    /* rst_n_sync est le reset asynchrone du cœur et la donnée de READY_IN, qui monte dès son relâchement
     * (section 4.11) : Verilator y voit un reset tantôt synchrone, tantôt asynchrone. */
    /* verilator lint_off SYNCASYNCNET */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_ready_in <= 1'b0;
        else
            r_ready_in <= r_rst_n_sync & ~i_err_state;
    /* verilator lint_on SYNCASYNCNET */

    /* 2^ECHO_SEL_W octets adressables par ECHO_SEL, ceux au-delà de RAW_W à 0 : une sélection de ECHO_N à
     * 2^ECHO_SEL_W − 1 rend 0 (écart E2). */
    genvar echo_bit;
    generate
        for (echo_bit = 0; echo_bit < 8*(1<<ECHO_SEL_W); echo_bit = echo_bit + 1)
            begin : g_echo
                if (echo_bit < RAW_W)
                    begin : g_raw
                        assign w_echo_bus[echo_bit] = w_raw[echo_bit];
                    end
                else
                    begin : g_pad
                        assign w_echo_bus[echo_bit] = 1'b0;
                    end
            end
    endgenerate

    assign w_echo_byte = w_echo_bus[{i_echo_sel, 3'b000} +: 8];

    always @(posedge i_clk or negedge r_rst_n_sync)
        if (!r_rst_n_sync)
            begin
                r_stat_busy <= 1'b0;
                r_stat_idx  <= 3'd0;
            end
        else if (i_stat_req)
            begin
                r_stat_busy <= 1'b1;
                r_stat_idx  <= 3'd0;
            end
        else if (r_stat_busy)
            begin
                r_stat_busy <= r_stat_idx != 3'd7;
                r_stat_idx  <= r_stat_idx + 3'd1;
            end

    assign w_stat_bytes = {i_mac_wait_count, i_last_pass_id[15:8], i_last_pass_id[7:0], 3'b000, i_err_state,
                           i_out_collide, i_hdr_err, i_in_overflow, i_out_overflow, 8'h5A};
    assign w_stat_byte  = w_stat_bytes[{r_stat_idx, 3'b000} +: 8];

    assign o_rst_n_sync = r_rst_n_sync;
    assign o_in_valid   = w_raw[RAW_W-2];
    assign o_in_type    = w_raw[RAW_W-1];
    assign o_ready_in   = r_ready_in;
    assign o_echo_valid = r_stat_busy | i_echo_take;
    assign o_echo_byte  = r_stat_busy ? w_stat_byte : w_echo_byte;

endmodule

`endif
