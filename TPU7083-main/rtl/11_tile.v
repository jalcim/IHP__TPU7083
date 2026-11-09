`ifndef __TILE__
`define __TILE__

`include "00_params.vh"
`include "00_variantes.vh"
`include "0_param_check.v"
`include "0b_bcast_tree.v"
`include "1_link_in.v"
`include "1b_column_asm.v"
`include "2_column_fifo.v"
`include "3_line_mem.v"
`include "4_window.v"
`include "5_weights.v"
`include "6_mac.v"
`include "7_acc_ring.v"
`include "8_threshold.v"
`include "9_link_out.v"
`include "10a_router.v"
`include "10b_sequencer.v"

/* Tuile NebulaCore : assemblage des blocs aux broches de 03_interfaces.md section 2.1.
 * Aucune logique ici, tout comportement vit dans un bloc, sous son banc.
 * Les fils internes portent les noms que sonde le banc de la tuile, contrat 11 du plan :
 * le flot physique ne doit pas les renommer (14_verification.md section 2.3).
 * Les trois formats de colonnes passent par les mêmes fils : en (3l, cc) les ports du flux restent à zéro dans
 * l'aiguilleur et l'assembleur, en (3l, stream) ce sont ab_we, cc_we, c1_we, ab_free et cc_free (variante V3), et en
 * (fh, aligned) l'aiguilleur n'écrit que des unités AB, COL_W valant 2 PIX_W dans l'assembleur, la file et la fenêtre.
 * Écarts et variantes câblés selon le contrat 11 amendé de
 * rtl/contrats.md (lot 16) :
 * - E1, ⌈PINS / 8⌉ groupes DBI, le dernier court quand PINS n'est pas multiple de 8, et E2, ECHO_SEL sur
 *   ECHO_SEL_W = ⌈log2 ECHO_N⌉ bits de l'aiguilleur au lien entrant ;
 * - G1, le pas des mots de poids et de seuils de l'aiguilleur vers ⑤ et ⑦, le pré-transfert et le pas de la passe
 *   que sert ④ du séquenceur vers ④ et ⑤, le pas de la fenêtre vers ⑥, le pas du pixel de ⑥ vers ⑦, et acc_word sur
 *   K G_MAX ACC bits, ces fils valant 0 hors variante G1, où les blocs les ignorent ;
 * - V4, la troisième coupe MAC_CUT_C vers param_check et les MAC ;
 * - (fh, aligned), COL_FMT vers param_check, l'aiguilleur, l'assembleur, la file et la fenêtre.
 * Options de complete5 câblées selon le contrat D.5 de rtl/contrats.md
 * :
 * - MAC_TREE, MAC_MODEL, FINAL_ADDER, WIN_LOAD et REG_COPIES vers param_check ;
 * - WIN_LOAD vers la fenêtre et le séquenceur, ② capturée au front décalant de WIN_LAG cycles la rotation et le
 *   transfert de ④, si bien que XFER de la trace suit o_wgt_xfer WIN_LAG cycles plus tard ;
 * - TREE, MODEL, FINAL et STAGES = L_MAC - WIN_LAG vers les MAC, L_MAC comptant l'étage de ② au front ;
 * - WIN_COPIES vers param_check, la fenêtre et les MAC, le filtre k lisant la copie ⌊k WIN_COPIES / K⌋ de ②
 *   (contrat 4) ;
 * - THR_CUT vers param_check, ⑦ et le séquenceur, où il devient THR_XFER_LEAD : sous la coupe de ⑦, thr_xfer tombe
 *   un cycle plus tôt, niveaux et réservation des banques aux mêmes cycles ;
 * - DIFF_DEPTH et DIFF_SLICE, dont la tuile tire les avances WIN_LEAD, STEP_LEAD, THR_LEAD et XSEL_LEAD vers le
 *   séquenceur et les tranches ACC_REP, WGT_REP et THR_REP vers ⑥, ⑤ et ⑦, les huit valeurs vers param_check : des
 *   arbres de diffusion (0b_bcast_tree.v) ramènent les sorties anticipées du séquenceur à leur cycle, une feuille par
 *   tranche, et les sorties d'origine ne servent plus qu'aux sondes.
 * Chaque paramètre d'une variante passe à chaque bloc qui le lit, G1 compris, même s'il le prend par défaut de la
 * même macro que la tuile. */

module tile #(parameter C           = `TILE_C,
              parameter K           = `TILE_K,
              parameter G           = `TILE_G,
              parameter G1          = `TILE_G1,
              parameter W           = `TILE_W,
              parameter BPP         = `TILE_BPP,
              parameter L           = `TILE_L,
              parameter P_ACC       = `TILE_P_ACC,
              parameter M_E         = `TILE_M_E,
              parameter D_COL       = `TILE_D_COL,
              parameter ACC         = `TILE_ACC,
              parameter THR_W       = `TILE_THR_W,
              parameter LOTMAX      = `TILE_LOTMAX,
              parameter BA          = `TILE_BA,
              parameter BW          = `TILE_BW,
              parameter T           = `TILE_T,
              parameter OUT_W       = `TILE_OUT_W,
              parameter L_MAC       = `TILE_L_MAC,
              parameter M           = `TILE_M,
              parameter MAC_CUT_A   = `TILE_MAC_CUT_A,
              parameter MAC_CUT_B   = `TILE_MAC_CUT_B,
              parameter MAC_CUT_C   = `TILE_MAC_CUT_C,
              parameter WIN_LOAD    = `TILE_WIN_LOAD,
              parameter REG_COPIES  = `TILE_REG_COPIES,
              parameter MAC_TREE    = `TILE_MAC_TREE,
              parameter MAC_MODEL   = `TILE_MAC_MODEL,
              parameter FINAL_ADDER = `TILE_FINAL_ADDER,
              parameter WIN_LAG     = (WIN_LOAD != 0) ? 1 : 0,
              parameter STAGES      = L_MAC - WIN_LAG,
              parameter MAC_ROWS    = (FINAL_ADDER == 5) ? 2 : 1,
              parameter THR_FMT     = `TILE_THR_FMT,
              parameter THR_SHARE   = `TILE_THR_SHARE,
              parameter DIFF_DEPTH  = `TILE_DIFF_DEPTH,
              parameter DIFF_SLICE  = `TILE_DIFF_SLICE,
              parameter WIN_COPIES  = `TILE_WIN_COPIES,
              parameter THR_CUT     = `TILE_THR_CUT,
              parameter COL_FMT     = `TILE_COL_FMT,
              parameter OUT_BUF     = `TILE_OUT_BUF,
              parameter LEN_W       = `TILE_HDR_NCOLS_W,
              parameter PINS        = W / BPP,
              parameter DBI_PINS    = (PINS + 7) / 8,
              parameter DBI_N       = (OUT_W + 7) / 8,
              parameter PIX_W       = C * BA,
              parameter COL_W       = (COL_FMT == 2) ? 2 * PIX_W : 3 * PIX_W,
              parameter AB_WORDS    = (2 * PIX_W + W - 1) / W,
              parameter C1_WORDS    = (PIX_W + W - 1) / W,
              parameter GROUP_BITS  = 9 * C * K * BW,
              parameter WB_W        = $clog2(W + 1),
              parameter ECHO_N      = (2 * (PINS + DBI_PINS + 1) + 7) / 8,
              parameter ECHO_SEL_W  = $clog2(ECHO_N),
              parameter G_MAX       = groups_max(G, G1))
             (input  [PINS-1:0]     i_d_in,
              input  [DBI_PINS-1:0] i_dbi_in,
              input                 i_clk_in,
              input                 i_clk_in_n,
              input                 i_valid_in,
              output                o_ready_in,
              output [OUT_W-1:0]    o_q_out,
              output [DBI_N-1:0]    o_dbi_out,
              output                o_clk_out,
              output                o_valid_out,
              input                 i_ready_out,
              input                 i_rst_n);

    `include "00_groups.vh"

    /* Avances et tranches des arbres de diffusion aux règles des défauts du séquenceur, de ⑥, ⑤ et ⑦, que param_check
     * juge. Chacune passe explicitement à son bloc : une surcharge de DIFF_DEPTH, DIFF_SLICE ou THR_CUT sur tile les
     * atteint toutes. */
    localparam THR_XFER_LEAD = THR_CUT;
    localparam WIN_LEAD      = (DIFF_DEPTH < L_MAC - 1) ? DIFF_DEPTH : L_MAC - 1;
    localparam STEP_LEAD     = (L_MAC <= M_E) ? 0 : ((DIFF_DEPTH < L_MAC - M_E) ? DIFF_DEPTH : L_MAC - M_E);
    localparam THR_LEAD      = (DIFF_DEPTH < L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD)
                               ? DIFF_DEPTH : L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD;
    localparam XSEL_LEAD     = (DIFF_DEPTH > 0 && WIN_LAG == 1 && G1 == 0) ? 1 : 0;
    localparam ACC_REP       = (DIFF_SLICE != 0 && G1 == 0) ? K : 1;
    localparam WGT_REP       = (DIFF_SLICE != 0 && G1 == 0) ? K : 1;
    localparam THR_REP       = (DIFF_SLICE != 0 && G1 == 0 && THR_SHARE == 0) ? G_MAX : 1;

    wire                  w_rst_n;
    wire [W-1:0]          w_in_word;
    wire                  w_in_valid;
    wire                  w_in_type;
    wire [7:0]            w_echo_byte;
    wire                  w_echo_valid;
    wire [AB_WORDS-1:0]   w_ab_we;
    wire [AB_WORDS-1:0]   w_cc_we;
    wire [C1_WORDS-1:0]   w_c1_we;
    wire                  w_col_lines;
    wire                  w_ab_free;
    wire                  w_cc_free;
    wire                  w_word_we;
    wire [WB_W-1:0]       w_word_bits;
    wire [WB_W-1:0]       w_word_three;
    wire                  w_word_free;
    wire [COL_W-1:0]      w_col_data;
    wire                  w_col_valid;
    wire                  w_col_ready;
    wire                  w_tap_valid;
    wire                  w_shift_ok;
    wire [3*COL_W-1:0]    w_fifo_tap;
    wire [PIX_W-1:0]      w_line_in;
    wire [3*PIX_W-1:0]    w_line_out;
    wire [WIN_COPIES*9*PIX_W-1:0] w_win_copies;
    /* Exception de lint : les MAC lisent w_win_copies. w_win_data, la copie 0, garde le nom que lisent les sondes
     * (contrat 11) et les budgets du flot physique. */
    /* verilator lint_off UNUSEDSIGNAL */
    wire [9*PIX_W-1:0]    w_win_data;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  w_wgt_cache_valid;
    wire                  w_wgt_cache_full;
    wire                  w_wgt_cache_ready;
    wire [GROUP_BITS-1:0] w_wgt_head;
    wire [MAC_ROWS*K*ACC-1:0] w_mac_sum;
    wire [K*G_MAX*ACC-1:0] w_acc_word;
    wire                  w_acc_done;
    wire                  w_done_stride1;
    wire                  w_thr_cache_valid;
    wire                  w_thr_cache_full;
    wire                  w_thr_cache_ready;
    wire [K*BA-1:0]       w_lvl_out;
    wire [OUT_W-1:0]      w_lvl_wide;
    wire                  w_lvl_valid;
    wire                  w_out_overflow;
    wire                  w_out_collide;
    wire                  w_lvl_collide;
    wire [47:0]           w_rx_desc;
    wire                  w_rx_desc_valid;
    wire                  w_cmd_seen;
    wire                  w_echo_take;
    wire [ECHO_SEL_W-1:0] w_echo_sel;
    wire                  w_stat_req;
    wire                  w_flags_clr;
    wire                  w_in_overflow;
    wire                  w_hdr_err;
    wire                  w_err_state;
    wire                  w_wgt_stride1;
    wire                  w_thr_stride1;
    wire                  w_col_shift;
    wire [LEN_W-1:0]      w_line_len;
    wire                  w_top_sel;
    wire                  w_top_zero;
    /* Exception de lint : ② lit o_win_open, et aucun bloc ne consomme plus win_load hors du séquenceur. Le fil reste
     * pour les sondes WIN et de calendrier de la trace (contrat 11). */
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  w_win_load;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  w_win_open;
    wire                  w_win_open_early;
    wire                  w_wgt_xfer;
    wire                  w_wgt_rot;
    /* Exception de lint : ⑥ et ⑦ lisent les feuilles des arbres de diffusion, nourris des sorties anticipées. Les
     * sorties d'origine restent pour les sondes STEP, ACCW et THR de la trace et pour le banc, qui leur compare chaque
     * feuille (contrat 11). */
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  w_acc_step;
    wire                  w_acc_win;
    wire                  w_thr_xfer;
    /* verilator lint_on UNUSEDSIGNAL */
    wire                  w_acc_first;
    wire                  w_acc_last;
    wire                  w_pass_start;
    /* Exception de lint : aucun bloc ne consomme pass_done, que le séquenceur rend dans last_pass_id et out_empty.
     * Le fil reste pour la sonde PDONE de la trace (contrat 11). */
    /* verilator lint_off UNUSEDSIGNAL */
    wire                  w_pass_done;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [15:0]           w_last_pass_id;
    wire [31:0]           w_mac_wait_count;
    wire                  w_out_empty;
    /* Sorties du séquenceur en variante G1 (contrat 11 amendé de rtl/contrats.md), 0 hors variante G1. */
    wire                  w_wgt_pre;
    wire                  w_ring_stride1;
    wire                  w_acc_stride1;
    /* Sorties anticipées du séquenceur, racines des arbres de diffusion, et feuilles, une par tranche de ⑥, ⑤ ou ⑦,
     * que sonde le banc de la tuile. */
    wire                  w_acc_win_pre;
    wire                  w_acc_step_pre;
    wire                  w_thr_xfer_pre;
    wire                  w_wgt_xsel_pre;
    wire [ACC_REP-1:0]    w_acc_win_leaf;
    wire [ACC_REP-1:0]    w_acc_step_leaf;
    wire [ACC_REP-1:0]    w_acc_first_leaf;
    wire [ACC_REP-1:0]    w_acc_last_leaf;
    wire [ACC_REP-1:0]    w_acc_stride1_leaf;
    wire [THR_REP-1:0]    w_thr_xfer_leaf;
    wire [WGT_REP-1:0]    w_wgt_xsel_leaf;

    genvar leaf;

    param_check #(.C(C), .K(K), .G(G), .G1(G1), .W(W), .BPP(BPP), .L(L), .P_ACC(P_ACC), .M_E(M_E), .D_COL(D_COL),
                  .ACC(ACC), .THR_W(THR_W), .LOTMAX(LOTMAX), .BA(BA), .BW(BW), .T(T), .OUT_W(OUT_W), .L_MAC(L_MAC),
                  .M(M), .MAC_CUT_A(MAC_CUT_A), .MAC_CUT_B(MAC_CUT_B), .MAC_CUT_C(MAC_CUT_C), .THR_FMT(THR_FMT),
                  .COL_FMT(COL_FMT), .OUT_BUF(OUT_BUF), .MAC_TREE(MAC_TREE), .MAC_MODEL(MAC_MODEL),
                  .FINAL_ADDER(FINAL_ADDER), .WIN_LOAD(WIN_LOAD), .REG_COPIES(REG_COPIES),
                  .THR_SHARE(THR_SHARE), .DIFF_DEPTH(DIFF_DEPTH), .DIFF_SLICE(DIFF_SLICE), .WIN_COPIES(WIN_COPIES),
                  .THR_CUT(THR_CUT), .THR_XFER_LEAD(THR_XFER_LEAD), .WIN_LEAD(WIN_LEAD), .STEP_LEAD(STEP_LEAD),
                  .THR_LEAD(THR_LEAD), .XSEL_LEAD(XSEL_LEAD), .ACC_REP(ACC_REP), .WGT_REP(WGT_REP),
                  .THR_REP(THR_REP)) u_check ();

    link_in #(.W(W), .BPP(BPP)) u_link_in (
        .i_clk_pad_p(i_clk_in), .i_clk_pad_n(i_clk_in_n), .i_clk(i_clk_in), .i_rst_n(i_rst_n), .i_d_in(i_d_in),
        .i_dbi_in(i_dbi_in), .i_valid_in(i_valid_in), .i_err_state(w_err_state), .i_echo_sel(w_echo_sel),
        .i_echo_take(w_echo_take), .i_stat_req(w_stat_req), .i_last_pass_id(w_last_pass_id),
        .i_mac_wait_count(w_mac_wait_count), .i_in_overflow(w_in_overflow), .i_hdr_err(w_hdr_err),
        .i_out_overflow(w_out_overflow), .i_out_collide(w_out_collide), .o_rst_n_sync(w_rst_n),
        .o_in_word(w_in_word), .o_in_valid(w_in_valid), .o_in_type(w_in_type), .o_ready_in(o_ready_in),
        .o_echo_byte(w_echo_byte), .o_echo_valid(w_echo_valid));

    router #(.W(W), .C(C), .K(K), .G(G), .G1(G1), .BA(BA), .BW(BW), .BPP(BPP), .T(T), .THR_W(THR_W), .L(L),
             .P_ACC(P_ACC), .LOTMAX(LOTMAX), .COL_FMT(COL_FMT)) u_router (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_in_word(w_in_word), .i_in_valid(w_in_valid), .i_in_type(w_in_type),
        .i_ab_free(w_ab_free), .i_cc_free(w_cc_free), .i_wgt_cache_ready(w_wgt_cache_ready),
        .i_thr_cache_ready(w_thr_cache_ready), .i_pass_start(w_pass_start), .i_out_empty(w_out_empty),
        .o_ab_we(w_ab_we), .o_cc_we(w_cc_we), .o_c1_we(w_c1_we), .o_col_lines(w_col_lines),
        .o_wgt_cache_valid(w_wgt_cache_valid), .o_thr_cache_valid(w_thr_cache_valid), .o_rx_desc(w_rx_desc),
        .o_rx_desc_valid(w_rx_desc_valid), .o_cmd_seen(w_cmd_seen), .o_echo_take(w_echo_take),
        .o_echo_sel(w_echo_sel), .o_stat_req(w_stat_req), .o_flags_clr(w_flags_clr), .o_in_overflow(w_in_overflow),
        .o_hdr_err(w_hdr_err), .o_err_state(w_err_state), .i_word_free(w_word_free), .o_word_we(w_word_we),
        .o_word_bits(w_word_bits), .o_word_three(w_word_three), .o_wgt_stride1(w_wgt_stride1),
        .o_thr_stride1(w_thr_stride1));

    sequencer #(.G(G), .G1(G1), .L_MAC(L_MAC), .M_E(M_E), .M(M), .P_ACC(P_ACC), .WIN_LOAD(WIN_LOAD),
                .LEN_W(LEN_W), .THR_XFER_LEAD(THR_XFER_LEAD), .DIFF_DEPTH(DIFF_DEPTH), .WIN_LEAD(WIN_LEAD),
                .STEP_LEAD(STEP_LEAD), .THR_LEAD(THR_LEAD), .XSEL_LEAD(XSEL_LEAD)) u_seq (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_rx_desc(w_rx_desc), .i_rx_desc_valid(w_rx_desc_valid),
        .i_err_state(w_err_state), .i_cmd_seen(w_cmd_seen), .i_tap_valid(w_tap_valid), .i_shift_ok(w_shift_ok),
        .i_wgt_cache_full(w_wgt_cache_full), .i_thr_cache_full(w_thr_cache_full), .o_col_shift(w_col_shift),
        .o_line_len(w_line_len), .o_top_sel(w_top_sel), .o_top_zero(w_top_zero), .o_win_load(w_win_load),
        .o_wgt_xfer(w_wgt_xfer), .o_wgt_rot(w_wgt_rot), .o_acc_step(w_acc_step), .o_acc_win(w_acc_win),
        .o_acc_first(w_acc_first), .o_acc_last(w_acc_last), .o_thr_xfer(w_thr_xfer), .o_pass_start(w_pass_start),
        .o_pass_done(w_pass_done), .o_last_pass_id(w_last_pass_id), .o_mac_wait_count(w_mac_wait_count),
        .o_out_empty(w_out_empty), .o_wgt_pre(w_wgt_pre), .o_ring_stride1(w_ring_stride1),
        .o_acc_stride1(w_acc_stride1), .o_win_open(w_win_open), .o_win_open_early(w_win_open_early),
        .o_acc_win_pre(w_acc_win_pre), .o_acc_step_pre(w_acc_step_pre), .o_thr_xfer_pre(w_thr_xfer_pre),
        .o_wgt_xsel_pre(w_wgt_xsel_pre));

    /* Arbres de diffusion : chaque sortie anticipée revient à son cycle sur une feuille par tranche, chaque registre
     * d'un arbre en pilotant au plus quatre. Les passagers de acc_win, acc_first, acc_last et acc_stride1, entrent à la
     * racine sans avance : chargés au win_load, ils ne changent pas avant acc_win, que ⑥ seul les fait lire. Un arbre
     * de largeur 5 sert ⑥ quand WIN_LEAD égale STEP_LEAD, deux sinon. La sélection d'entrée de l'anneau se remet à 1,
     * la valeur de o_wgt_xsel_pre pendant la remise. */
    generate
        if (WIN_LEAD == STEP_LEAD)
            begin : g_acc_tree
                wire [5*ACC_REP-1:0] w_leaves;

                bcast_tree #(.WIDTH(5), .DEPTH(WIN_LEAD), .LEAVES(ACC_REP), .FANOUT(4)) u_acc_tree (
                    .i_clk(i_clk_in), .i_rst_n(w_rst_n),
                    .i_root({w_acc_step_pre, w_acc_stride1, w_acc_last, w_acc_first, w_acc_win_pre}),
                    .o_leaf(w_leaves));

                for (leaf = 0; leaf < ACC_REP; leaf = leaf + 1)
                    begin : g_leaf
                        assign w_acc_win_leaf[leaf]     = w_leaves[5*leaf];
                        assign w_acc_first_leaf[leaf]   = w_leaves[5*leaf+1];
                        assign w_acc_last_leaf[leaf]    = w_leaves[5*leaf+2];
                        assign w_acc_stride1_leaf[leaf] = w_leaves[5*leaf+3];
                        assign w_acc_step_leaf[leaf]    = w_leaves[5*leaf+4];
                    end
            end
        else
            begin : g_acc_trees
                wire [4*ACC_REP-1:0] w_leaves;

                bcast_tree #(.WIDTH(4), .DEPTH(WIN_LEAD), .LEAVES(ACC_REP), .FANOUT(4)) u_acc_win_tree (
                    .i_clk(i_clk_in), .i_rst_n(w_rst_n),
                    .i_root({w_acc_stride1, w_acc_last, w_acc_first, w_acc_win_pre}), .o_leaf(w_leaves));

                bcast_tree #(.WIDTH(1), .DEPTH(STEP_LEAD), .LEAVES(ACC_REP), .FANOUT(4)) u_acc_step_tree (
                    .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_root(w_acc_step_pre), .o_leaf(w_acc_step_leaf));

                for (leaf = 0; leaf < ACC_REP; leaf = leaf + 1)
                    begin : g_leaf
                        assign w_acc_win_leaf[leaf]     = w_leaves[4*leaf];
                        assign w_acc_first_leaf[leaf]   = w_leaves[4*leaf+1];
                        assign w_acc_last_leaf[leaf]    = w_leaves[4*leaf+2];
                        assign w_acc_stride1_leaf[leaf] = w_leaves[4*leaf+3];
                    end
            end
    endgenerate

    bcast_tree #(.WIDTH(1), .DEPTH(THR_LEAD), .LEAVES(THR_REP), .FANOUT(4)) u_thr_tree (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_root(w_thr_xfer_pre), .o_leaf(w_thr_xfer_leaf));

    bcast_tree #(.WIDTH(1), .DEPTH(XSEL_LEAD), .LEAVES(WGT_REP), .FANOUT(4), .RESET_VALUE(1)) u_xsel_tree (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_root(w_wgt_xsel_pre), .o_leaf(w_wgt_xsel_leaf));

    column_asm #(.C(C), .BA(BA), .W(W), .COL_FMT(COL_FMT)) u_asm (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_in_word(w_in_word), .i_ab_we(w_ab_we), .i_cc_we(w_cc_we),
        .i_c1_we(w_c1_we), .i_col_lines(w_col_lines), .i_col_ready(w_col_ready), .o_col_data(w_col_data),
        .o_col_valid(w_col_valid), .o_ab_free(w_ab_free), .o_cc_free(w_cc_free), .i_word_we(w_word_we),
        .i_word_bits(w_word_bits), .i_word_three(w_word_three), .o_word_free(w_word_free));

    column_fifo #(.C(C), .BA(BA), .D_COL(D_COL), .COL_FMT(COL_FMT)) u_fifo (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_col_data(w_col_data), .i_col_valid(w_col_valid),
        .i_col_shift(w_col_shift), .o_col_ready(w_col_ready), .o_tap_valid(w_tap_valid), .o_shift_ok(w_shift_ok),
        .o_fifo_tap(w_fifo_tap), .o_line_in(w_line_in));

    line_mem #(.C(C), .BA(BA), .L(L), .LEN_W(LEN_W)) u_line (
        .i_clk(i_clk_in), .i_line_in(w_line_in), .i_col_shift(w_col_shift), .i_line_len(w_line_len),
        .o_line_out(w_line_out));

    window_reg #(.C(C), .BA(BA), .COL_FMT(COL_FMT), .WIN_LOAD(WIN_LOAD), .WIN_COPIES(WIN_COPIES)) u_win (
        .i_clk(i_clk_in), .i_fifo_tap(w_fifo_tap), .i_line_out(w_line_out), .i_top_sel(w_top_sel),
        .i_top_zero(w_top_zero), .i_win_open(w_win_open), .i_win_open_early(w_win_open_early),
        .o_win_data(w_win_copies));

    assign w_win_data = w_win_copies[9*PIX_W-1:0];

    weight_ring #(.C(C), .K(K), .G(G), .G1(G1), .BW(BW), .W(W), .REP(WGT_REP)) u_wgt (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_wgt_cache_data(w_in_word), .i_wgt_cache_valid(w_wgt_cache_valid),
        .i_wgt_xfer(w_wgt_xfer), .i_wgt_xsel(w_wgt_xsel_leaf), .i_wgt_rot(w_wgt_rot),
        .o_wgt_cache_full(w_wgt_cache_full),
        .o_wgt_cache_ready(w_wgt_cache_ready), .o_wgt_head(w_wgt_head), .i_wgt_stride1(w_wgt_stride1),
        .i_wgt_pre(w_wgt_pre), .i_ring_stride1(w_ring_stride1));

    /* Chaque filtre lit la copie de ② qui lui fait face, capturée au même front que la ② unique : L_MAC et le
     * calendrier ne bougent pas. param_check n'admet les copies qu'au front et refuse WIN_LOAD = 2, le registre
     * d'opérandes et ses REG_COPIES (option non retenue : spec/06_fenetre.md, section 8, point 4). */
    mac_array #(.C(C), .K(K), .BA(BA), .BW(BW), .ACC(ACC), .CUT_A(MAC_CUT_A), .CUT_B(MAC_CUT_B),
                .CUT_C(MAC_CUT_C), .TREE(MAC_TREE), .MODEL(MAC_MODEL), .FINAL(FINAL_ADDER), .STAGES(STAGES),
                .COPIES(WIN_COPIES)) u_mac (
        .i_clk(i_clk_in), .i_win_data(w_win_copies), .i_wgt_head(w_wgt_head), .o_mac_sum(w_mac_sum));

    /* Pas de la fenêtre pour ⑥, o_acc_stride1 du séquenceur. */
    acc_ring #(.K(K), .G(G), .G1(G1), .ACC(ACC), .P_ACC(P_ACC), .M_E(M_E), .ROWS(MAC_ROWS), .REP(ACC_REP)) u_acc (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_mac_sum(w_mac_sum), .i_acc_win(w_acc_win_leaf),
        .i_acc_step(w_acc_step_leaf), .i_acc_first(w_acc_first_leaf), .i_acc_last(w_acc_last_leaf),
        .o_acc_word(w_acc_word), .o_acc_done(w_acc_done), .i_acc_stride1(w_acc_stride1_leaf),
        .o_done_stride1(w_done_stride1));

    /* i_done_stride1 de threshold_unit prend w_done_stride1, tiré de o_done_stride1 de ⑥, et i_thr_stride1 le pas
     * des mots de seuils de l'aiguilleur. */
    threshold_unit #(.K(K), .G(G), .G1(G1), .T(T), .BA(BA), .ACC(ACC), .THR_W(THR_W), .W(W),
                     .THR_SHARE(THR_SHARE), .THR_CUT(THR_CUT), .REP(THR_REP)) u_thr (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_acc_word(w_acc_word), .i_acc_done(w_acc_done),
        .i_thr_cache_data(w_in_word), .i_thr_cache_valid(w_thr_cache_valid), .i_thr_xfer(w_thr_xfer_leaf),
        .o_thr_cache_full(w_thr_cache_full), .o_thr_cache_ready(w_thr_cache_ready), .o_lvl_out(w_lvl_out),
        .o_lvl_valid(w_lvl_valid), .i_thr_stride1(w_thr_stride1), .i_done_stride1(w_done_stride1),
        .o_lvl_collide(w_lvl_collide));

    /* Une réplication de largeur nulle est illégale même jamais exécutée : la branche
     * du generate n'est élaborée que si OUT_W dépasse K BA (notes de conventions Verilog, hors du dépôt). */
    generate
        if (OUT_W > K * BA)
            begin : g_lvl_pad
                assign w_lvl_wide = {{(OUT_W - K * BA){1'b0}}, w_lvl_out};
            end
        else
            begin : g_lvl_same
                assign w_lvl_wide = w_lvl_out;
            end
    endgenerate

    link_out #(.OUT_W(OUT_W), .OUT_BUF(OUT_BUF)) u_link_out (
        .i_clk(i_clk_in), .i_rst_n(w_rst_n), .i_lvl_out(w_lvl_wide), .i_lvl_valid(w_lvl_valid),
        .i_echo_byte(w_echo_byte), .i_echo_valid(w_echo_valid), .i_flags_clr(w_flags_clr),
        .i_ready_out(i_ready_out), .o_q_out(o_q_out), .o_dbi_out(o_dbi_out), .o_valid_out(o_valid_out),
        .o_clk_out(o_clk_out), .o_out_overflow(w_out_overflow), .o_out_collide(w_out_collide),
        .i_lvl_collide(w_lvl_collide));

endmodule

`endif
