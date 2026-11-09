`ifndef __ROUTER__
`define __ROUTER__

`include "00_params.vh"

/* Aiguilleur et décodeur de commandes du contrôleur ⑫ : il aiguille chaque mot du lien entrant, décode
 * PASSE, ÉCHO, ÉTAT et EFFACE, tient desc_pre et desc_rx, compte la réception des unités de colonnes et lève
 * les drapeaux d'entrée (spec/12_controle.md sections 3.1 à 3.3,
 * spec/03_interfaces.md sections 3.4 et 4.3 à 4.7).
 *
 * AIGUILLAGE PAR VALIDATIONS, SANS MUX DE DONNÉES. Les W fils de in_word vont à toutes les destinations,
 * assembleur de colonnes, cache de poids ⑤, cache de seuils et ce décodeur. Un seul prend le mot, celui dont
 * l'aiguilleur lève la validation (03_interfaces.md section 3.4). Une validation vaut écriture : elle ne monte
 * que si la destination accepte le mot, si bien qu'un mot refusé n'écrit nulle part.
 *
 * POURQUOI UN MOT REFUSÉ ARRÊTE LA TUILE JUSQU'AU RESET. Le FPGA rejoue un flux préparé hors ligne, cycle par
 * cycle, sans poignée de main ni tampon : in_ready surveille, il ne freine pas (03_interfaces.md section 4.3).
 * Un mot refusé est perdu et désaligne tout le flux qui suit, qui ne se rattrape pas sans repère.
 * in_overflow (mot refusé) et hdr_err (commande illisible, en-tête incohérent) mettent donc en ERREUR jusqu'à
 * RST_N. Plus rien n'y est écrit, et seuls ÉTAT et EFFACE, reconnus sur SYNC, y sont encore lus : le FPGA lit
 * et efface les drapeaux, puis remet la tuile à zéro.
 *
 * LES CONTRÔLES D'EN-TÊTE arrêtent par hdr_err un en-tête écrit pour un autre accord ou incohérent avec la
 * tuile gravée, au lieu de laisser sortir des niveaux faux sans bruit (levier technique du 12/10/2026,
 * propriété P2 des bancs du RTL (rtl/bancs.md)). Un PASSE refusé faute de place n'est pas contrôlé : il lève in_overflow.
 *
 * EN UNITÉS, COL_FMT = 0, LA SUITE DES UNITÉS SE DÉDUIT DES COMPTEURS DE RÉCEPTION SUR desc_rx, JAMAIS DU
 * CONTENU DES MOTS. Le mot n de l'unité en cours est le bit n de r_rx_word, qui sert directement de validation
 * (03_interfaces.md section 4.4).
 *
 * EN FLUX, COL_FMT = 1 (partie (3l, stream) de la variante V3), plus d'unités : les colonnes d'une carte forment un
 * seul flux de bits coupé en mots de W bits, et la carte suivante part d'un mot neuf. Avec chaque mot,
 * l'aiguilleur donne à l'assembleur ses bits utiles, au-delà desquels le dernier mot d'une carte porte son
 * bourrage, et ses bits de colonnes à 3 lignes, d'où la taille de chaque colonne. La carte compte
 * ncols (2 rows + t) PIX_W bits, t valant 1 pour la carte 0 d'une passe à top_real : un multiplieur sur les
 * champs de desc_rx, dont MAP_W borne le produit pour ncols ≤ L, seul cas qu'un en-tête accepté laisse passer.
 *
 * EN (fh, aligned), COL_FMT = 2 (trous 22 et 23, contrat 10a amendé de
 * rtl/contrats.md), aucune rangée n'a 3 lignes : un en-tête à
 * top_real lève hdr_err, hors lot comme dans un lot, et toute rangée envoie une unité AB par colonne. Ni unité CC
 * ni unité C1 : o_cc_we, o_c1_we, o_col_lines et o_word_we restent à 0, i_cc_free et i_word_free sont ignorés.
 *
 * LE PASSE ACCEPTÉ AU CYCLE MÊME DE i_pass_start (lecture du trou 9) est un chemin combinatoire du séquenceur
 * vers in_ready, sans coût pour le séquenceur puisque in_ready ne fait que surveiller.
 *
 * ÉCHO SUR ECHO_SEL_W BITS (écart E2, contrat 10a amendé) : echo_sel prend les bits 16 à 16 + ECHO_SEL_W − 1 du
 * mot ÉCHO, ECHO_SEL_W = ⌈log2 ECHO_N⌉ pour les ECHO_N octets bruts du lien entrant, et les bits au-dessus,
 * jusqu'au bit 31, sont réservés et ignorés.
 *
 * EN VARIANTE G1, G1 ≠ 0 ET G1 ≠ G (contrat 10a amendé), un bloc de poids ou de seuils compte les mots du G de
 * l'en-tête qui le porte, G_S1 au pas 1 et G au pas 2 (trou 21) : WGT_WORDS_S1 ou WGT_WORDS mots de poids,
 * THR_WORDS_S1 ou THR_WORDS mots de seuils. L'en-tête porteur est le PASSE qui ouvre le préchargement, que
 * desc_pre garde jusqu'au dernier mot de ses seuils, aucun PASSE n'étant décodé avant. Pour les seuils, cette
 * règle réduite rend celle du trou 21 sur tout flux que la tuile accepte : le bloc d'une passe décodée arrive
 * derrière son propre en-tête, celui d'une passe pas encore décodée derrière l'en-tête d'une tranche de sa région,
 * au même pas (trou 9 et condition de première fenêtre du contrat 10b). o_wgt_stride1 et
 * o_thr_stride1 portent ce pas pendant chaque mot de poids et de seuils, que ⑤ et le cache de seuils lisent au
 * premier mot d'un bloc : ils sont égaux, poids et seuils d'un préchargement ayant le même en-tête porteur. Hors
 * variante G1, les comptes sont ceux du contrat 10a et les deux sorties valent 0.
 *
 * UN SEUL COMPTEUR sert les trois phases exclusives du préchargement : chargé du compte d'un bloc de poids, de
 * celui d'un bloc de seuils ou de LEN, il finit la phase sur le mot qui le trouve à 1. LEN = 0 laisse donc en
 * COMMANDE sans consommer de mot (03_interfaces.md section 4.6). Sa largeur COUNT_W couvre LEN, champ de 16 bits,
 * et le plus long bloc de poids ou de seuils, aux deux pas : 16 bits fixes tronqueraient sans bruit un compte
 * au-delà de 65 535, que le lint ne voit pas, la largeur que Verilator prête à un paramètre calculé ne suivant pas
 * sa valeur. */

module router #(parameter W            = `TILE_W,
                parameter C            = `TILE_C,
                parameter K            = `TILE_K,
                parameter G            = `TILE_G,
                parameter G1           = `TILE_G1,
                parameter BA           = `TILE_BA,
                parameter BW           = `TILE_BW,
                parameter BPP          = `TILE_BPP,
                parameter T            = `TILE_T,
                parameter THR_W        = `TILE_THR_W,
                parameter L            = `TILE_L,
                parameter P_ACC        = `TILE_P_ACC,
                parameter LOTMAX       = `TILE_LOTMAX,
                parameter COL_FMT      = `TILE_COL_FMT,
                parameter DESC_W       = 48,
                parameter PIX_W        = C * BA,
                parameter AB_WORDS     = (2 * PIX_W + W - 1) / W,
                parameter C1_WORDS     = (PIX_W + W - 1) / W,
                parameter G_S1         = (G1 != 0) ? G1 : G,
                parameter GROUP_WORDS  = (9 * C * K * BW + W - 1) / W,
                parameter WGT_WORDS    = G * GROUP_WORDS,
                parameter WGT_WORDS_S1 = G_S1 * GROUP_WORDS,
                parameter THR_WORDS    = (K * G * T * THR_W + W - 1) / W,
                parameter THR_WORDS_S1 = (K * G_S1 * T * THR_W + W - 1) / W,
                parameter R_MIN        = (P_ACC + 2) / 2,
                parameter WGT_MAX      = (WGT_WORDS_S1 > WGT_WORDS) ? WGT_WORDS_S1 : WGT_WORDS,
                parameter THR_MAX      = (THR_WORDS_S1 > THR_WORDS) ? THR_WORDS_S1 : THR_WORDS,
                parameter WORDS_MAX    = (WGT_MAX > THR_MAX) ? WGT_MAX : THR_MAX,
                parameter COUNT_W      = $clog2(((WORDS_MAX > 65535) ? WORDS_MAX : 65535) + 1),
                parameter WB_W         = $clog2(W + 1),
                parameter MAP_MAX      = L * (2 * ((1 << `TILE_HDR_ROWS_W) - 1) + 1) * PIX_W,
                parameter MAP_W        = $clog2(MAP_MAX + 1),
                parameter PINS         = W / BPP,
                parameter DBI_PINS     = (PINS + 7) / 8,
                parameter RAW_W        = 2 * (PINS + DBI_PINS + 1),
                parameter ECHO_N       = (RAW_W + 7) / 8,
                parameter ECHO_SEL_W   = $clog2(ECHO_N))
               (input                   i_clk,
                input                   i_rst_n,
                /* Exception de lint : le décodeur ne lit que SYNC, CMD et le descripteur [63:16] ; les bits
                 * réservés [15:12] et ceux au-delà du bit 63 sont ignorés (03_interfaces.md section 4.6). */
                /* verilator lint_off UNUSEDSIGNAL */
                input  [W-1:0]          i_in_word,
                /* verilator lint_on UNUSEDSIGNAL */
                input                   i_in_valid,
                input                   i_in_type,
                input                   i_ab_free,
                input                   i_cc_free,
                input                   i_wgt_cache_ready,
                input                   i_thr_cache_ready,
                input                   i_pass_start,
                input                   i_out_empty,
                output [AB_WORDS-1:0]   o_ab_we,
                output [AB_WORDS-1:0]   o_cc_we,
                output [C1_WORDS-1:0]   o_c1_we,
                output                  o_col_lines,
                output                  o_wgt_cache_valid,
                output                  o_thr_cache_valid,
                output [DESC_W-1:0]     o_rx_desc,
                output                  o_rx_desc_valid,
                output                  o_cmd_seen,
                output                  o_echo_take,
                output [ECHO_SEL_W-1:0] o_echo_sel,
                output                  o_stat_req,
                output                  o_flags_clr,
                output                  o_in_overflow,
                output                  o_hdr_err,
                output                  o_err_state,
                input                   i_word_free,
                output                  o_word_we,
                output [WB_W-1:0]       o_word_bits,
                output [WB_W-1:0]       o_word_three,
                output                  o_wgt_stride1,
                output                  o_thr_stride1);

    localparam [1:0] S_COMMAND    = 2'd0;
    localparam [1:0] S_WEIGHTS    = 2'd1;
    localparam [1:0] S_THRESHOLDS = 2'd2;
    localparam [1:0] S_ECHO       = 2'd3;

    localparam [2:0] D_NONE       = 3'd0;
    localparam [2:0] D_ACT        = 3'd1;
    localparam [2:0] D_PASS       = 3'd2;
    localparam [2:0] D_CMD        = 3'd3;
    localparam [2:0] D_WEIGHTS    = 3'd4;
    localparam [2:0] D_THRESHOLDS = 3'd5;
    localparam [2:0] D_ECHO       = 3'd6;
    localparam [2:0] D_IGNORED    = 3'd7;

    localparam [7:0] SYNC         = 8'hA5;
    localparam [3:0] CMD_PASS     = 4'd1;
    localparam [3:0] CMD_ECHO     = 4'd2;
    localparam [3:0] CMD_STAT     = 4'd3;
    localparam [3:0] CMD_CLEAR    = 4'd4;

    reg  [1:0]                   r_state;
    reg  [COUNT_W-1:0]           r_count;
    reg                          r_thr_next;
    reg                          r_err_state;
    reg                          r_in_overflow;
    reg                          r_hdr_err;
    reg                          r_stat_wait;
    reg                          r_wait_start;
    reg                          r_pass_seen;
    reg  [DESC_W-1:0]            r_desc_pre;
    reg                          r_desc_pre_valid;
    reg  [DESC_W-1:0]            r_desc_rx;
    reg                          r_desc_rx_valid;
    reg                          r_rx_held;
    reg  [ECHO_SEL_W-1:0]        r_echo_sel;
    wire                         w_act_take;
    wire                         w_rx_last;

    /* Amendement A13 : i_in_valid vaut déjà 0 pendant le reset (contrat 1), la remise n'entre pas dans les données. */
    wire                         w_valid     = i_in_valid;
    wire                         w_live      = w_valid & ~r_err_state;
    wire                         w_act       = w_live & ~i_in_type;
    wire                         w_pre       = w_live & i_in_type;
    wire                         w_command   = w_pre & (r_state == S_COMMAND);
    wire                         w_weight    = w_pre & (r_state == S_WEIGHTS);
    wire                         w_threshold = w_pre & (r_state == S_THRESHOLDS);
    wire                         w_echo_word = w_pre & (r_state == S_ECHO);

    wire                         w_sync      = i_in_word[7:0] == SYNC;
    wire [3:0]                   w_code      = i_in_word[11:8];
    wire                         w_is_pass   = w_sync & (w_code == CMD_PASS);
    wire                         w_is_echo   = w_sync & (w_code == CMD_ECHO);
    wire                         w_is_stat   = w_sync & (w_code == CMD_STAT);
    wire                         w_is_clear  = w_sync & (w_code == CMD_CLEAR);
    wire                         w_unreadable = ~(w_is_pass | w_is_echo | w_is_stat | w_is_clear);
    wire [15:0]                  w_echo_len  = i_in_word[47:32];

    /* En ERREUR, tout mot de préchargement est relu comme une commande, quelle que soit l'étape interrompue. */
    wire                         w_decoder   = w_valid & i_in_type & (r_err_state | (r_state == S_COMMAND));
    wire                         w_stat      = w_decoder & w_is_stat;
    wire                         w_clear     = w_decoder & w_is_clear;

    wire                         w_hdr_stride2 = i_in_word[`TILE_HDR_STRIDE_POS];
    wire [`TILE_HDR_NCOLS_W-1:0] w_hdr_ncols   = i_in_word[`TILE_HDR_NCOLS_POS +: `TILE_HDR_NCOLS_W];
    wire [`TILE_HDR_ROWS_W-1:0]  w_hdr_rows    = i_in_word[`TILE_HDR_ROWS_POS +: `TILE_HDR_ROWS_W];
    wire [`TILE_HDR_LOT_W-1:0]   w_hdr_lot     = i_in_word[`TILE_HDR_LOT_POS +: `TILE_HDR_LOT_W];
    wire                         w_hdr_top     = i_in_word[`TILE_HDR_TOP_POS];
    wire                         w_hdr_first   = i_in_word[`TILE_HDR_FIRST_POS];
    wire                         w_hdr_last    = i_in_word[`TILE_HDR_LAST_POS];
    wire                         w_hdr_wgt     = i_in_word[`TILE_HDR_WGT_POS];
    wire                         w_hdr_thr     = i_in_word[`TILE_HDR_THR_POS];
    wire [`TILE_HDR_NPIX_W-1:0]  w_hdr_npix    = i_in_word[`TILE_HDR_NPIX_POS +: `TILE_HDR_NPIX_W];

    /* Une passe à plusieurs tranches, ¬(first ∧ last), accumule dans ⑥ : R = npix y est borné par
     * R_MIN ≤ R ≤ P_ACC (spec/09_accumulation.md section 4.2). lot + 1 se
     * compare sur un bit de plus que le champ, LOTMAX pouvant ne pas y tenir. */
    wire                         w_bad_ncols  = (w_hdr_ncols < 3) | (w_hdr_ncols > L);
    wire                         w_bad_stride = w_hdr_stride2 & ~w_hdr_ncols[0];
    wire                         w_bad_rows   = w_hdr_rows == 0;
    wire                         w_bad_lot    = {1'b0, w_hdr_lot} + 1'b1 > LOTMAX;
    wire                         w_bad_top    = w_hdr_top & (w_hdr_lot != 0);
    wire                         w_bad_r1     = (w_hdr_ncols == 3) & (w_hdr_rows == 1) & (w_hdr_lot == 0);
    wire                         w_bad_npix   = ~(w_hdr_first & w_hdr_last) & ((w_hdr_npix < R_MIN) | (w_hdr_npix > P_ACC));
    wire                         w_bad_start  = ~r_pass_seen & ~(w_hdr_wgt & w_hdr_first);
    wire                         w_bad_halo;
    wire                         w_hdr_bad    = w_bad_ncols | w_bad_stride | w_bad_rows | w_bad_lot | w_bad_top
                                              | w_bad_halo | w_bad_r1 | w_bad_npix | w_bad_start;

    /* (fh, aligned) n'a aucune rangée à 3 lignes : tout halo haut réel y lève hdr_err, hors lot comme dans un lot
     * (trou 22, contrat 10a amendé). Les autres formats le reçoivent hors lot. */
    generate
        if (COL_FMT == 2)
            begin : g_halo_refused
                assign w_bad_halo = w_hdr_top;
            end
        else
            begin : g_halo_allowed
                assign w_bad_halo = 1'b0;
            end
    endgenerate

    wire                         w_pass_ready     = ~r_desc_pre_valid & (~r_wait_start | i_pass_start);
    wire                         w_pass_take      = w_command & w_is_pass & w_pass_ready & ~w_hdr_bad;
    wire                         w_echo_cmd_take  = w_command & w_is_echo & i_out_empty;
    wire                         w_hdr_fail       = w_command & (w_unreadable | (w_is_pass & w_pass_ready & w_hdr_bad));
    wire                         w_weight_take    = w_weight & i_wgt_cache_ready;
    wire                         w_threshold_take = w_threshold & i_thr_cache_ready;

    /* Compte d'un bloc de poids ou de seuils, et pas donné aux caches, au G de l'en-tête porteur en variante G1. En
     * COMMANDE, un compte ne se charge qu'au PASSE que w_pass_take accepte, et l'en-tête porteur est le mot présenté.
     * À la fin des poids, c'est desc_pre, qui garde ce PASSE jusqu'au dernier mot de ses seuils. Le pas est le bit 0
     * du descripteur, hdr_stride, à 0 au pas 1. */
    wire [COUNT_W-1:0]           w_wgt_words;
    wire [COUNT_W-1:0]           w_thr_words;
    wire                         w_wgt_stride1;
    wire                         w_thr_stride1;

    generate
        if (G_S1 != G)
            begin : g_g1
                wire w_count_stride1 = (r_state == S_COMMAND) ? ~w_hdr_stride2 : ~r_desc_pre[0];

                assign w_wgt_words   = w_count_stride1 ? COUNT_W'(WGT_WORDS_S1) : COUNT_W'(WGT_WORDS);
                assign w_thr_words   = w_count_stride1 ? COUNT_W'(THR_WORDS_S1) : COUNT_W'(THR_WORDS);
                assign w_wgt_stride1 = ~r_desc_pre[0];
                assign w_thr_stride1 = ~r_desc_pre[0];
            end
        else
            begin : g_uniform
                assign w_wgt_words   = COUNT_W'(WGT_WORDS);
                assign w_thr_words   = COUNT_W'(THR_WORDS);
                assign w_wgt_stride1 = 1'b0;
                assign w_thr_stride1 = 1'b0;
            end
    endgenerate

    wire [`TILE_HDR_NCOLS_W-1:0] w_rx_ncols    = r_desc_rx[`TILE_HDR_NCOLS_POS - `TILE_HDR_STRIDE_POS +: `TILE_HDR_NCOLS_W];
    wire [`TILE_HDR_ROWS_W-1:0]  w_rx_rows     = r_desc_rx[`TILE_HDR_ROWS_POS - `TILE_HDR_STRIDE_POS +: `TILE_HDR_ROWS_W];
    wire [`TILE_HDR_LOT_W-1:0]   w_rx_lot      = r_desc_rx[`TILE_HDR_LOT_POS - `TILE_HDR_STRIDE_POS +: `TILE_HDR_LOT_W];

    /* desc_rx garde sa passe jusqu'à son début et refuse tout mot d'activations pendant ce maintien : une passe
     * courte qui charge ses poids, reçue entière avant son début, perdait sinon son descripteur (levier technique du 13/10/2026). Elle a commencé si desc_pre est valide, le PASSE suivant n'étant accepté
     * qu'après ce début, ou si le bit d'attente est à 0, ce bit ne la concernant que desc_pre vide. Le bit seul
     * retiendrait desc_rx en régime, où le PASSE de q + 1 précède le dernier mot de q. */
    wire                         w_rx_started  = r_desc_pre_valid | ~r_wait_start | i_pass_start;
    wire                         w_rx_done     = (w_rx_last | r_rx_held) & w_rx_started;
    wire                         w_rx_load     = r_desc_pre_valid & (~r_desc_rx_valid | w_rx_done);

    wire                         w_in_ready = w_act_take | w_pass_take | w_echo_cmd_take | w_stat | w_clear
                                            | w_weight_take | w_threshold_take | w_echo_word;
    wire                         w_refused  = w_live & ~w_in_ready & ~w_hdr_fail;

    /* Sonde de la trace, lue par référence hiérarchique depuis le banc et depuis la tuile (lot 11) :
     * exception de lint, rien ne la lit dans ce module. */
    /* verilator lint_off UNUSEDSIGNAL */
    wire [2:0]                   w_dest = ~w_valid                     ? D_NONE :
                                          r_err_state                  ? ((w_stat | w_clear) ? D_CMD : D_IGNORED) :
                                          ~i_in_type                   ? D_ACT :
                                          (r_state == S_WEIGHTS)       ? D_WEIGHTS :
                                          (r_state == S_THRESHOLDS)    ? D_THRESHOLDS :
                                          (r_state == S_ECHO)          ? D_ECHO :
                                          w_is_pass                    ? D_PASS : D_CMD;
    /* verilator lint_on UNUSEDSIGNAL */

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_state    <= S_COMMAND;
                r_count    <= 0;
                r_thr_next <= 1'b0;
            end
        else if (w_pass_take)
            begin
                r_thr_next <= w_hdr_thr;
                if (w_hdr_wgt)
                    begin
                        r_state <= S_WEIGHTS;
                        r_count <= w_wgt_words;
                    end
                else
                    begin
                        r_state <= w_hdr_thr ? S_THRESHOLDS : S_COMMAND;
                        r_count <= w_thr_words;
                    end
            end
        else if (w_echo_cmd_take)
            begin
                r_state <= (w_echo_len == 16'd0) ? S_COMMAND : S_ECHO;
                r_count <= COUNT_W'(w_echo_len);
            end
        else if (w_weight_take | w_threshold_take | w_echo_word)
            begin
                if (r_count != 1)
                    r_count <= r_count - 1'b1;
                else if (w_weight_take & r_thr_next)
                    begin
                        r_state <= S_THRESHOLDS;
                        r_count <= w_thr_words;
                    end
                else
                    r_state <= S_COMMAND;
            end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_in_overflow <= 1'b0;
                r_hdr_err     <= 1'b0;
                r_err_state   <= 1'b0;
                r_stat_wait   <= 1'b0;
            end
        else
            begin
                r_in_overflow <= w_refused | (r_in_overflow & ~w_clear);
                r_hdr_err     <= w_hdr_fail | (r_hdr_err & ~w_clear);
                r_err_state   <= r_err_state | w_refused | w_hdr_fail;
                r_stat_wait   <= w_stat | (r_stat_wait & ~o_stat_req);
            end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_wait_start     <= 1'b0;
                r_pass_seen      <= 1'b0;
                r_desc_pre_valid <= 1'b0;
                r_desc_rx_valid  <= 1'b0;
                r_rx_held        <= 1'b0;
            end
        else
            begin
                r_wait_start     <= w_pass_take | (r_wait_start & ~i_pass_start);
                r_pass_seen      <= r_pass_seen | w_pass_take;
                r_desc_pre_valid <= w_pass_take | (r_desc_pre_valid & ~w_rx_load);
                r_desc_rx_valid  <= w_rx_load | (r_desc_rx_valid & ~w_rx_done);
                r_rx_held        <= (w_rx_last | r_rx_held) & ~w_rx_started;
            end

    always @(posedge i_clk)
        begin
            if (w_pass_take)
                r_desc_pre <= i_in_word[`TILE_HDR_STRIDE_POS +: DESC_W];
            if (w_rx_load)
                r_desc_rx <= r_desc_pre;
            if (w_echo_cmd_take)
                r_echo_sel <= i_in_word[16 +: ECHO_SEL_W];
        end

    generate
        if (COL_FMT == 1)
            begin : g_stream
                /* La carte c compte ncols (2 rows + t) PIX_W bits, envoyés en mots de W bits dont le dernier est
                 * bourré, et sa rangée 0 ouvre le flux par ses 3 ncols PIX_W bits si t = 1.
                 *
                 * LE CHEMIN DU MOT EST COUPÉ EN REGISTRES (coupes B et C de l'étude de réalisabilité,
                 * rapport.md, dépôt de travail non publié, sections « Couper le chemin du flux » et « Poignée de
                 * main du flux »). Compter les bits reçus de la carte, puis tirer le reste et les marques du mot du
                 * produit des champs de desc_rx et de deux soustractions, laissait le multiplieur, les soustractions
                 * et la comparaison à W derrière chaque mot : avec l'assembleur, 150 MHz n'y tenait au coin lent pour
                 * aucun des 9 accords en flux. r_rest et r_rest_three tiennent donc les bits de la carte et les bits
                 * de colonnes à 3 lignes qui restent à recevoir, et r_marks les marques du prochain mot. Les trois se
                 * calculent au cycle d'avant pour chaque issue : depuis desc_pre au chargement de desc_rx, par un pas
                 * de W après un mot qui n'est pas le dernier de sa carte, depuis desc_rx au dernier mot d'une carte,
                 * pour la carte suivante ou, après la dernière, pour la carte 0 et son halo haut. Le mot ne lit plus
                 * que ces registres.
                 *
                 * ILS VALENT À CHAQUE CYCLE OÙ desc_rx EST VALIDE LES RESTES ET LES MARQUES DE L'ANCIEN COMPTE des
                 * bits reçus, puisque leurs issues ne lisent que desc_pre et desc_rx, qui ne changent qu'au
                 * chargement, et r_rx_map, qui ne change qu'au dernier mot d'une carte. Un registre de la taille de
                 * la carte recopié à chaque front la lirait un cycle trop tard, le premier mot d'une passe arrivant
                 * au cycle qui suit le chargement de desc_rx (flux préparé,
                 * spec/03_interfaces.md section 4.3). L'équivalence au RTL
                 * d'af5ab629 est prouvée par un banc, test/equiv/prove.py sous test/cmake/14_equiv_flux.cmake.
                 *
                 * SANS RESET. Après un reset, desc_rx est vide, w_act_take le lit et o_word_bits comme o_word_three en
                 * sont masqués : aucune sortie ne lit ces registres avant le chargement suivant, qui les réécrit. */
                reg  [`TILE_HDR_LOT_W-1:0]   r_rx_map;
                reg  [MAP_W-1:0]             r_rest;
                reg  [MAP_W-1:0]             r_rest_three;
                reg  [2*WB_W:0]              r_marks;
                wire [`TILE_HDR_NCOLS_W-1:0] w_pre_ncols   = r_desc_pre[`TILE_HDR_NCOLS_POS - `TILE_HDR_STRIDE_POS +: `TILE_HDR_NCOLS_W];
                wire [`TILE_HDR_ROWS_W-1:0]  w_pre_rows    = r_desc_pre[`TILE_HDR_ROWS_POS - `TILE_HDR_STRIDE_POS +: `TILE_HDR_ROWS_W];
                wire                         w_pre_top     = r_desc_pre[`TILE_HDR_TOP_POS - `TILE_HDR_STRIDE_POS];
                wire                         w_rx_top      = r_desc_rx[`TILE_HDR_TOP_POS - `TILE_HDR_STRIDE_POS];
                wire [MAP_W-1:0]             w_pre_bits    = MAP_W'(w_pre_ncols) * MAP_W'({w_pre_rows, w_pre_top}) * MAP_W'(PIX_W);
                wire [MAP_W-1:0]             w_pre_three   = w_pre_top ? MAP_W'(w_pre_ncols) * MAP_W'(3 * PIX_W) : {MAP_W{1'b0}};
                wire [MAP_W-1:0]             w_first_bits  = MAP_W'(w_rx_ncols) * MAP_W'({w_rx_rows, w_rx_top}) * MAP_W'(PIX_W);
                wire [MAP_W-1:0]             w_first_three = w_rx_top ? MAP_W'(w_rx_ncols) * MAP_W'(3 * PIX_W) : {MAP_W{1'b0}};
                wire [MAP_W-1:0]             w_next_bits   = MAP_W'(w_rx_ncols) * MAP_W'({w_rx_rows, 1'b0}) * MAP_W'(PIX_W);
                wire [MAP_W-1:0]             w_rest_down   = r_rest - MAP_W'(W);
                wire [MAP_W-1:0]             w_three_down  = (r_rest_three > MAP_W'(W)) ? r_rest_three - MAP_W'(W) : {MAP_W{1'b0}};
                wire                         w_last_word   = r_marks[2*WB_W];
                wire [WB_W-1:0]              w_word_bits   = r_marks[WB_W +: WB_W];
                wire [WB_W-1:0]              w_word_three  = r_marks[0 +: WB_W];
                wire                         w_last_map    = r_rx_map == w_rx_lot;
                /* En flux, i_ab_free et i_cc_free sont ignorés (contrat de V3) : exception de lint de cette seule
                 * branche, où rien ne les lit. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire                         w_unit_free_ignored = i_ab_free | i_cc_free;
                /* verilator lint_on UNUSEDSIGNAL */

                /* Marques d'un mot, {dernier mot de sa carte, bits utiles, bits de colonnes à 3 lignes}, depuis les
                 * bits de la carte et les bits de colonnes à 3 lignes qui restent à recevoir. Les bits à 3 lignes
                 * passent par une variable à part : l'outil de synthèse générique, en 0.62 comme en 0.63, rend fausse
                 * une concaténation dont un opérande est un ternaire qui tronque par un cast un signal plus large,
                 * {b, c ? N'(x) : b} y valant {0, ...} (rapport de la coupe du flux,
                 * rapport.md, dépôt de travail non publié). */
                function [2*WB_W:0] word_marks(input [MAP_W-1:0] rest, input [MAP_W-1:0] rest_three);
                    reg            last;
                    reg [WB_W-1:0] bits;
                    reg [WB_W-1:0] three;
                    begin
                        last       = rest <= MAP_W'(W);
                        bits       = last ? WB_W'(rest) : WB_W'(W);
                        three      = (rest_three < MAP_W'(bits)) ? WB_W'(rest_three) : bits;
                        word_marks = {last, bits, three};
                    end
                endfunction

                assign w_act_take = w_act & r_desc_rx_valid & ~r_rx_held & i_word_free;
                assign w_rx_last  = w_act_take & w_last_word & w_last_map;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_rx_map <= 0;
                    else if (w_act_take && w_last_word)
                        r_rx_map <= w_last_map ? 0 : r_rx_map + 1'b1;

                always @(posedge i_clk)
                    if (w_rx_load)
                        begin
                            r_rest       <= w_pre_bits;
                            r_rest_three <= w_pre_three;
                            r_marks      <= word_marks(w_pre_bits, w_pre_three);
                        end
                    else if (w_act_take)
                        begin
                            if (!w_last_word)
                                begin
                                    r_rest       <= w_rest_down;
                                    r_rest_three <= w_three_down;
                                    r_marks      <= word_marks(w_rest_down, w_three_down);
                                end
                            else
                                begin
                                    r_rest       <= w_last_map ? w_first_bits : w_next_bits;
                                    r_rest_three <= w_last_map ? w_first_three : {MAP_W{1'b0}};
                                    r_marks      <= w_last_map ? word_marks(w_first_bits, w_first_three)
                                                               : word_marks(w_next_bits, {MAP_W{1'b0}});
                                end
                        end

                assign o_ab_we      = {AB_WORDS{1'b0}};
                assign o_cc_we      = {AB_WORDS{1'b0}};
                assign o_c1_we      = {C1_WORDS{1'b0}};
                assign o_col_lines  = 1'b0;
                assign o_word_we    = w_act_take;
                assign o_word_bits  = {WB_W{r_desc_rx_valid}} & w_word_bits;
                assign o_word_three = {WB_W{r_desc_rx_valid}} & w_word_three;
            end
        else if (COL_FMT == 2)
            begin : g_aligned
                /* (fh, aligned) : la suite des unités du chemin en unités, sans rangée à 3 lignes, l'en-tête à
                 * top_real étant refusé. Toute rangée envoie une unité AB par colonne, de AB_WORDS mots, ni unité CC
                 * ni unité C1, si bien que la fin d'une unité est celle de sa colonne. */
                reg  [AB_WORDS-1:0]          r_rx_word;
                reg  [`TILE_HDR_NCOLS_W-1:0] r_rx_col;
                reg  [`TILE_HDR_ROWS_W-1:0]  r_rx_row;
                reg  [`TILE_HDR_LOT_W-1:0]   r_rx_map;
                wire                         w_last_col = r_rx_col == w_rx_ncols - 1'b1;
                wire                         w_last_row = r_rx_row == w_rx_rows - 1'b1;
                wire                         w_last_map = r_rx_map == w_rx_lot;
                wire                         w_col_end  = w_act_take & r_rx_word[AB_WORDS-1];
                /* En (fh, aligned), i_cc_free et i_word_free sont ignorés (contrat 10a amendé) : exception de lint
                 * de cette seule branche, où rien ne les lit. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire                         w_free_ignored = i_cc_free | i_word_free;
                /* verilator lint_on UNUSEDSIGNAL */

                assign w_act_take = w_act & r_desc_rx_valid & ~r_rx_held & (~r_rx_word[0] | i_ab_free);
                assign w_rx_last  = w_col_end & w_last_col & w_last_row & w_last_map;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        begin
                            r_rx_word <= 1;
                            r_rx_col  <= 0;
                            r_rx_row  <= 0;
                            r_rx_map  <= 0;
                        end
                    else if (w_act_take)
                        begin
                            if (!w_col_end)
                                r_rx_word <= r_rx_word << 1;
                            else
                                begin
                                    r_rx_word <= 1;
                                    if (!w_last_col)
                                        r_rx_col <= r_rx_col + 1'b1;
                                    else
                                        begin
                                            r_rx_col <= 0;
                                            if (!w_last_row)
                                                r_rx_row <= r_rx_row + 1'b1;
                                            else
                                                begin
                                                    r_rx_row <= 0;
                                                    r_rx_map <= w_last_map ? 0 : r_rx_map + 1'b1;
                                                end
                                        end
                                end
                        end

                assign o_ab_we      = {AB_WORDS{w_act_take}} & r_rx_word;
                assign o_cc_we      = {AB_WORDS{1'b0}};
                assign o_c1_we      = {C1_WORDS{1'b0}};
                assign o_col_lines  = 1'b0;
                assign o_word_we    = 1'b0;
                assign o_word_bits  = {WB_W{1'b0}};
                assign o_word_three = {WB_W{1'b0}};
            end
        else
            begin : g_units
                /* Une rangée à 3 lignes, la rangée 0 de la carte 0 d'une passe à top_real, envoie avant l'unité AB
                 * de chaque colonne paire l'unité C de sa paire : CC de AB_WORDS mots, ou C1 de C1_WORDS mots quand
                 * cette colonne est la dernière, ncols impair. r_rx_c_done dit que ce C est reçu. */
                reg  [AB_WORDS-1:0]          r_rx_word;
                reg                          r_rx_c_done;
                reg  [`TILE_HDR_NCOLS_W-1:0] r_rx_col;
                reg  [`TILE_HDR_ROWS_W-1:0]  r_rx_row;
                reg  [`TILE_HDR_LOT_W-1:0]   r_rx_map;
                wire                         w_rx_top      = r_desc_rx[`TILE_HDR_TOP_POS - `TILE_HDR_STRIDE_POS];
                wire                         w_three_lines = r_desc_rx_valid & w_rx_top & (r_rx_row == 0) & (r_rx_map == 0);
                wire                         w_last_col    = r_rx_col == w_rx_ncols - 1'b1;
                wire                         w_last_row    = r_rx_row == w_rx_rows - 1'b1;
                wire                         w_last_map    = r_rx_map == w_rx_lot;
                wire                         w_unit_c      = w_three_lines & ~r_rx_col[0] & ~r_rx_c_done;
                wire                         w_unit_c1     = w_unit_c & w_last_col;
                wire                         w_unit_end    = w_unit_c1 ? r_rx_word[C1_WORDS-1] : r_rx_word[AB_WORDS-1];
                wire                         w_unit_free   = w_unit_c ? i_cc_free : i_ab_free;
                wire                         w_col_end     = w_act_take & w_unit_end & ~w_unit_c;
                /* En unités, i_word_free est ignoré (contrat de V3) : exception de lint de cette seule branche, où
                 * rien ne le lit. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire                         w_word_free_ignored = i_word_free;
                /* verilator lint_on UNUSEDSIGNAL */

                assign w_act_take = w_act & r_desc_rx_valid & ~r_rx_held & (~r_rx_word[0] | w_unit_free);
                assign w_rx_last  = w_col_end & w_last_col & w_last_row & w_last_map;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        begin
                            r_rx_word   <= 1;
                            r_rx_c_done <= 1'b0;
                            r_rx_col    <= 0;
                            r_rx_row    <= 0;
                            r_rx_map    <= 0;
                        end
                    else if (w_act_take)
                        begin
                            if (!w_unit_end)
                                r_rx_word <= r_rx_word << 1;
                            else
                                begin
                                    r_rx_word   <= 1;
                                    r_rx_c_done <= w_unit_c;
                                    if (w_col_end)
                                        begin
                                            if (!w_last_col)
                                                r_rx_col <= r_rx_col + 1'b1;
                                            else
                                                begin
                                                    r_rx_col <= 0;
                                                    if (!w_last_row)
                                                        r_rx_row <= r_rx_row + 1'b1;
                                                    else
                                                        begin
                                                            r_rx_row <= 0;
                                                            r_rx_map <= w_last_map ? 0 : r_rx_map + 1'b1;
                                                        end
                                                end
                                        end
                                end
                        end

                assign o_ab_we      = {AB_WORDS{w_act_take & ~w_unit_c}} & r_rx_word;
                assign o_cc_we      = {AB_WORDS{w_act_take & w_unit_c & ~w_last_col}} & r_rx_word;
                assign o_c1_we      = {C1_WORDS{w_act_take & w_unit_c1}} & r_rx_word[C1_WORDS-1:0];
                assign o_col_lines  = w_three_lines;
                assign o_word_we    = 1'b0;
                assign o_word_bits  = {WB_W{1'b0}};
                assign o_word_three = {WB_W{1'b0}};
            end
    endgenerate

    assign o_wgt_cache_valid = w_weight_take;
    assign o_thr_cache_valid = w_threshold_take;
    assign o_rx_desc         = r_desc_rx;
    assign o_rx_desc_valid   = r_desc_rx_valid;
    /* cmd_seen dit au séquenceur qu'une commande a interrompu le flux (règle de l'écart, trou 7) : il monte sur
     * toute commande reconnue, refusée comprise (levier technique du 13/10/2026). */
    assign o_cmd_seen        = (w_command & w_is_echo) | w_stat | w_clear;
    assign o_echo_take       = w_echo_word;
    assign o_echo_sel        = r_echo_sel;
    assign o_stat_req        = r_stat_wait & i_out_empty;
    assign o_flags_clr       = w_clear;
    assign o_in_overflow     = r_in_overflow;
    assign o_hdr_err         = r_hdr_err;
    assign o_err_state       = r_err_state;
    assign o_wgt_stride1     = w_wgt_stride1;
    assign o_thr_stride1     = w_thr_stride1;

endmodule

`endif
