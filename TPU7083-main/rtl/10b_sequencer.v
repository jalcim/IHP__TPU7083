`ifndef __SEQUENCER__
`define __SEQUENCER__

`include "00_params.vh"
`include "00_variantes.vh"

/* Séquenceur de la tuile : descripteurs desc_tap, desc_mac et desc_out, et desc_drain en variante G1,
 * compteurs de prises, machine des MAC, calendrier de ⑥ et ⑦
 * (spec/12_controle.md sections 3.2 à 4.7, contrat 10b de
 * rtl/contrats.md, amendé par la section des contrats
 * amendés du dépôt de travail non publié, et par les amendements
 * A14, A15 et A16 du 28/10/2026 de rtl/contrats.md).
 *
 * LA RÈGLE ULTIME. Les MAC ne s'arrêtent jamais en régime : une fenêtre tous les G_PASS cycles, sans
 * trou (décision d'architecture du 09/10/2026, spec/12_controle.md section 4.1).
 * Tout le module en découle.
 * Une fenêtre part au premier cycle où elle est prête, un col_shift au premier cycle où il est
 * permis, et ce qui peut se préparer pendant une fenêtre s'y prépare : les colonnes de la
 * suivante, les poids de la passe suivante, le bloc de seuils. Les deux décisions se prennent
 * dans le cycle, depuis l'état et les entrées du cycle, sans latence ajoutée.
 *
 * POURQUOI CHAQUE ÉCHÉANCE.
 * - col_shift : s par fenêtre, 3 au changement de rangée et après VIDE (trou 5), espacés de M
 *   cycles parce que ③ porte ses deux phases sur deux cycles
 *   (spec/05_memoire_ligne.md section 3.5).
 *   Jamais au cycle d'un win_load, ② lisant les prises et line_out pendant ce cycle (même
 *   fichier, section 5). Un win_load suit le dernier col_shift dès le cycle suivant (trou 6,
 *   décision du 12/10/2026), seule lecture qui tient R1 à G = 6.
 * - poids : ④ n'a de mux qu'à l'entrée de sa dernière position, si bien que wgt_xfer couvre la
 *   dernière fenêtre de p, le groupe g de p lu au cycle g puis remplacé derrière lui
 *   (spec/07_poids.md section 4.3).
 *   Les mots de poids de p + 1 doivent donc être dans ⑤ à la capture de cette fenêtre.
 *   Hors régime, un déversement seul de G_MAX cycles part dès que ⑤ est plein (trou 11).
 * - seuils : le bloc d'une passe qui seuille est complet à sa première capture W0, et thr_xfer
 *   le verse à W0 + L_MAC + G_PASS, avec l'acc_done du premier pixel de la passe, quand les
 *   banques ne servent plus la passe précédente
 *   (spec/10_seuillage.md section 4.2).
 *   Sous ⑦ coupé (THR_CUT = 1), r_crossed tient les comparaisons un cycle avant le compteur de bits : thr_xfer part
 *   THR_XFER_LEAD = THR_CUT cycles plus tôt, la réservation des banques courant toujours jusqu'à W0 + L_MAC + G_PASS
 *   (amendement A16 de rtl/contrats.md).
 * - anneau ⑥ : la phase de classe 0 du pas d'échange tombe au cycle d'acc_win, d'où l'échange
 *   M_E − 1 cycles avant acc_win, et le saut au cycle qui suit
 *   (spec/09_accumulation.md section 4.1).
 * - fin de passe : pass_done au dernier niveau sorti du sérialiseur de ⑦ pour une passe qui
 *   seuille, à l'entrée de sa dernière somme dans ⑥ sinon
 *   (spec/12_controle.md section 4.7).
 * - attentes : tout écart entre la fin d'une fenêtre et la capture suivante compte, sauf s'il
 *   contient une commande ÉCHO, ÉTAT ou EFFACE, comme un recalibrage entre deux images (trou 7).
 *   L'écart couvre les cycles de W + G_PASS à la capture suivante exclue : un i_cmd_seen au
 *   cycle même de cette capture ne l'annule pas.
 * Les trous sont ceux du tableau « Lectures retenues des trous de la spécification » du
 * dépôt de travail non publié.
 *
 * VARIANTE G1, G1 ≠ 0 et G1 ≠ G, écrite sous generate if : une passe au pas 1 tient chaque fenêtre
 * G1 cycles et une passe au pas 2 G cycles. Ce G_PASS se lit sur le bit de pas de desc_tap, tenu
 * depuis son win_load pour la fenêtre dans les MAC et depuis son pass_start pour la dernière passe
 * entrée dans les MAC, deux bits remis à 0 au reset là où desc_mac n'en a pas, et ④ et ⑤ ont
 * G_MAX = max(G, G1) positions.
 * Les fenêtres durent G_PASS cycles, le déversement seul G_MAX, et thr_xfer, la fin des MAC,
 * pass_done, l'écart du trou 7 et la sortie vide en ERREUR prennent le G_PASS de leur passe.
 * Le trou 24 se lit au plus tôt, lecture de la section des lectures du
 * dépôt de travail non publié retenue par levier technique
 * du 15/10/2026 : ⑤ s'aligne de lui-même, le pré-transfert des H(p) = G_MAX − G_PASS(p) positions
 * hautes de ④ part dès que ⑤ est plein, et la dernière fenêtre de p attend sa fin.
 * Commencé, il va à son terme, ERREUR comprise, comme le déversement seul.
 * L'avance ne joue qu'au passage vers une passe qui charge ses poids, levier technique 2 du
 * même jour : la dernière fenêtre n'attend le pré-transfert et ne transfère que si desc_rx porte
 * wgt_load. Le pré-transfert, lui, ne lit pas desc_rx (amendement A7 du 16/10/2026) :
 * tant que desc_tap porte p et que ④ tient ses poids, ⑤ plein ne tient que les poids de p + 1.
 * desc_drain garde la passe qui seuille quand desc_out se recharge avant son pass_done, et les
 * pass_done restent dans l'ordre des passes, amendements A1 et A2 du 15/10/2026 à la
 * fin du même fichier. w_done_pass_id porte le pass_id que last_pass_id prend à pass_done, dans
 * toutes les variantes, pour la sonde PDONE de la tuile (amendement A6 du 16/10/2026).
 * Hors variante G1, G_MAX vaut G, aucun registre ne s'ajoute, et wgt_pre, ring_stride1 et
 * acc_stride1 valent 0.
 *
 * VARIANTE WIN_LOAD, ② capturée au front ou suivie du registre d'opérandes, WIN_LAG = 1, écrite sous generate if
 * (contrat D.4 de rtl/contrats.md) : les MAC voient la fenêtre du
 * cycle W de son win_load de W + 1 à W + G_PASS, et le séquenceur décale de WIN_LAG cycles wgt_rot et wgt_xfer, la
 * prise de ④ restant P_0, sans mux (levier technique du 17/10/2026).
 * L_MAC compte l'étage de ②, si bien que acc_win, acc_step, thr_xfer, pass_done et la sortie vide en
 * ERREUR gardent leurs formules, comme les conditions de fenêtre prête et l'écart du trou 7 (levier technique A1 du 16/10/2026). L'âge de la fenêtre court jusqu'à G_PASS + WIN_LAG, la fin de sa rotation : un
 * déversement seul n'y part qu'après, le pré-transfert attend la fin du transfert décalé, ring_stride1 suit la
 * fenêtre qui tourne et desc_out prend desc_mac au front qui clôt W_last + G_PASS − 1 + WIN_LAG
 * (spec/12_controle.md sections 4.1 à 4.3 et 4.7).
 * À WIN_LAG = 0, le RTL est celui de ② transparente.
 *
 * ② OUVERTE. o_win_open, registré, commande la capture de ② et, sous ② transparente, son mux de sortie. Il vaut
 * ~w_win_busy, prédit au cycle d'avant depuis l'âge et le G_PASS que la fenêtre aura au cycle suivant : haut au
 * cycle de chaque win_load, qui exige les MAC libres, bas tant que les MAC tiennent la fenêtre, de W + 1 à
 * W + G_PASS − 1, et haut hors fenêtre, où ② recharge sans que ⑥ lise de somme. Le cône de win_load sort ainsi de
 * l'étage 1 des MAC et des validations de ②, sans rien changer à ce que voient les MAC aux cycles que ⑥ lit
 * (point 4_window.v:258 de la revue du RTL d'af5ab629, levier technique du 14/10/2026 sur ② transparente au
 * cycle du win_load).
 *
 * ② OUVERTE PAR AVANCE. Les copies de ② (contrat 4, WIN_COPIES, amendement A15 de rtl/contrats.md) prennent leurs
 * commandes en registre un cycle avant
 * de s'en servir. o_win_open_early, combinatoire sur registres et hors du cône de win_load, leur annonce o_win_open :
 * ~(r_win_age + 1 < w_win_g) sur PHASE_W + 1 bits. Hors du cycle d'un win_load, il vaut ~w_win_busy_next, donc
 * o_win_open du cycle suivant. Au cycle W d'un win_load, il peut rester haut alors que o_win_open tombe à W + 1 : cette
 * chute tardive est admise, aucun col_shift ne tombant au cycle W, si bien que les sources de ② à W + 1 égalent celles
 * de W et qu'une copie qui capture encore à W + 1 reprend la même fenêtre. Les copies reposent aussi sur la stabilité
 * de top_sel et top_zero, égaux au cycle d'un win_load à ceux du cycle d'avant. Ils ne lisent que desc_tap et ses
 * compteurs de rangée et de carte, qui n'avancent qu'au front d'un win_load ou d'une prise de desc_tap, et aucun
 * win_load ne suit l'un ou l'autre au cycle suivant. Le banc du bloc vérifie les deux règles à chaque cycle.
 *
 * SORTIES ANTICIPÉES. Les arbres de registres de la tuile (0b_bcast_tree.v) portent acc_win, acc_step, thr_xfer et la
 * sélection de ④ à leurs consommateurs en DIFF_DEPTH étages (famille A des coupes de pipeline du 28/10/2026,
 * amendement A14 de rtl/contrats.md). Le
 * séquenceur leur donne chaque signal en avance d'autant : o_acc_win_pre de WIN_LEAD cycles, o_acc_step_pre de
 * STEP_LEAD, o_thr_xfer_pre de THR_LEAD et o_wgt_xsel_pre de XSEL_LEAD. Les feuilles égalent ainsi les sorties
 * d'origine au cycle près, inchangées, et le calendrier vu du lien ne bouge pas. Chaque avance s'arrête à ce qui la
 * laisse exacte et lue sur des registres :
 * - acc_win à L_MAC − 1, sa racine restant r_date, ligne à retard de win_load, à un indice d'au moins 1 ;
 * - acc_step à L_MAC − M_E, et à 0 quand M_E − 1 = L_MAC, pour que la racine de l'échange reste r_date[STEP_J] avec
 *   STEP_J ≥ 1, jamais o_win_load, dont le cône lit les entrées du routeur et des banques ; le saut lit la même ligne,
 *   et r_acc_multi et r_acc_skip ne changent qu'au win_load suivant, plus de L_MAC + 1 cycles plus tard ;
 * - thr_xfer à L_MAC + G_PASS − 1 − THR_XFER_LEAD du plus petit G_PASS, r_thr_left ne se chargeant qu'à 0, de
 *   L_MAC + G_PASS, et o_thr_xfer tombant déjà THR_XFER_LEAD cycles avant sa fin ;
 * - la sélection à 1, sous ② au front ou au registre (WIN_LAG = 1) hors variante G1, et 0 ailleurs, où
 *   o_wgt_xsel_pre vaut o_wgt_xfer.
 * La sélection spéculée vaut au cycle t + 1 o_wgt_xfer quand o_wgt_rot y est haut, et ne lit que des registres et les
 * sorties rx du routeur. Fenêtre tenue en t, sans win_load possible, la rotation continue sans relance et r_xfer
 * décide. Un win_load en t, qui exige les MAC libres et aucun déversement, donne r_xfer à t + 1, la valeur exacte du
 * premier terme, et annule les trois autres. Hors des deux, la rotation sous WIN_LAG = 1 est finie en t + 1, et tout
 * déversement actif en t + 1 rend vrai en t l'un des trois autres termes. Sous WIN_LAG ≥ 2, un win_load peut tomber
 * dans la queue d'une rotation et la formule ne tient plus.
 * Deux drapeaux sortent les comparaisons de l'âge du cône de ④ et de la fenêtre prête : r_rot_busy, la rotation en
 * cours, et r_dev_on, le déversement seul en cours, pris au front sur l'état suivant et exacts au cycle près.
 * r_dev_on prend sur cet état suivant la plage légale de l'âge, de 1 à G_MAX − 1, si bien qu'un âge posé à une valeur
 * illégale revient seul au repos (correctif des compteurs, 61fedaa3).
 * w_rot_busy, lu partout, est r_rot_busy, et w_rot_busy_cmp garde la comparaison d'origine pour le banc du bloc.
 *
 * ERREUR. Plus aucune capture, aucun col_shift ni aucun départ de déversement seul ou de
 * pré-transfert. Les fenêtres déjà capturées finissent leur chemin, avec leurs wgt_rot, acc_step,
 * acc_win, thr_xfer et pass_done, et un déversement seul ou un pré-transfert déjà parti va à son
 * terme, le contrat n'en interdisant que le départ.
 * Ces deux lectures, l'écart et l'ERREUR, sont des leviers techniques du 13/10/2026.
 *
 * LE PIÈGE DE ⑥. La règle de saut porte sur c = n mod (R − 1), et c ne revient à 0 qu'à la
 * première fenêtre d'une passe hdr_first_tranche, jamais d'une tranche à l'autre. n mod R passe
 * sur les régions de 196 pixels, qui ne sautent jamais, et rend 11 776 niveaux faux sur conv3 à
 * régions de 126 et 140 pixels (spec/09_accumulation.md
 * section 7).
 *
 * Reset : bits de validité, compteurs, drapeaux, o_win_open, la ligne à retard des dates de ⑥, last_pass_id et
 * mac_wait_count, la liste de
 * spec/03_interfaces.md section 4.11, plus line_len, et en
 * variante G1 le pas de la fenêtre, celui de la dernière passe entrée dans les MAC, le pré-transfert et
 * desc_drain, six descripteurs vidés.
 * Le contenu des descripteurs n'en a pas, toujours réécrit avant usage, et top_sel et top_zero
 * ne sortent qu'avec un desc_tap valide. Toute sortie vaut donc 0 pendant le reset, sauf
 * out_empty à 1 (contrat 10b, levier technique du 13/10/2026), et o_win_open et o_win_open_early à 1, aucune fenêtre
 * n'étant tenue et r_win_age valant G + WIN_LAG. o_wgt_xsel_pre y vaut 1 sous XSEL_LEAD = 1, aucun desc_tap n'étant
 * valide, et les drapeaux r_rot_busy et r_dev_on 0, comme les comparaisons qu'ils remplacent.
 */

module sequencer #(parameter G        = `TILE_G,
                   parameter G1       = `TILE_G1,
                   parameter L_MAC    = `TILE_L_MAC,
                   parameter M_E      = `TILE_M_E,
                   parameter M        = `TILE_M,
                   parameter P_ACC    = `TILE_P_ACC,
                   parameter WIN_LOAD = `TILE_WIN_LOAD,
                   parameter WIN_LAG  = (WIN_LOAD != 0) ? 1 : 0,
                   parameter DESC_W   = 48,
                   parameter LEN_W    = `TILE_HDR_NCOLS_W,
                   parameter ROWS_W   = `TILE_HDR_ROWS_W,
                   parameter LOT_W    = `TILE_HDR_LOT_W,
                   parameter NPIX_W   = `TILE_HDR_NPIX_W,
                   parameter G_S1     = groups_stride1(G, G1),
                   parameter G_MAX    = groups_max(G, G1),
                   parameter PHASE_W  = $clog2(G_MAX + WIN_LAG + 1),
                   parameter AGE_W    = $clog2(M + 1),
                   parameter THR_XFER_LEAD = `TILE_THR_CUT,
                   parameter CNT_W    = $clog2(L_MAC + 2 * G_MAX + 2),
                   parameter DIFF_DEPTH = `TILE_DIFF_DEPTH,
                   parameter WIN_LEAD   = (DIFF_DEPTH < L_MAC - 1) ? DIFF_DEPTH : L_MAC - 1,
                   parameter STEP_LEAD  = (L_MAC <= M_E) ? 0 : ((DIFF_DEPTH < L_MAC - M_E) ? DIFF_DEPTH : L_MAC - M_E),
                   parameter THR_LEAD   = (DIFF_DEPTH < L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD)
                                          ? DIFF_DEPTH : L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD,
                   parameter XSEL_LEAD  = (DIFF_DEPTH > 0 && WIN_LAG == 1 && G1 == 0) ? 1 : 0)
                  (input               i_clk,
                   input               i_rst_n,
                   input  [DESC_W-1:0] i_rx_desc,
                   input               i_rx_desc_valid,
                   input               i_err_state,
                   input               i_cmd_seen,
                   input               i_tap_valid,
                   input               i_shift_ok,
                   input               i_wgt_cache_full,
                   input               i_thr_cache_full,
                   output              o_col_shift,
                   output [LEN_W-1:0]  o_line_len,
                   output              o_top_sel,
                   output              o_top_zero,
                   output              o_win_load,
                   output              o_wgt_xfer,
                   output              o_wgt_rot,
                   output              o_acc_step,
                   output              o_acc_win,
                   output              o_acc_first,
                   output              o_acc_last,
                   output              o_thr_xfer,
                   output              o_pass_start,
                   output              o_pass_done,
                   output [15:0]       o_last_pass_id,
                   output [31:0]       o_mac_wait_count,
                   output              o_out_empty,
                   output              o_wgt_pre,
                   output              o_ring_stride1,
                   output              o_acc_stride1,
                   output              o_win_open,
                   output              o_win_open_early,
                   output              o_acc_win_pre,
                   output              o_acc_step_pre,
                   output              o_thr_xfer_pre,
                   output              o_wgt_xsel_pre);

    `include "00_groups.vh"

    reg  [DESC_W-1:0]  r_desc_tap;
    reg  [DESC_W-1:0]  r_desc_mac;
    /* desc_out garde le descripteur entier, au format du contrat 10a, et la trace de la tuile le
     * sonde, mais ce module n'en lit que pass_id hors variante G1 : exception de lint, justifiée ici. En variante G1, desc_drain le reprend entier. */
    /* verilator lint_off UNUSEDSIGNAL */
    reg  [DESC_W-1:0]  r_desc_out;
    /* verilator lint_on UNUSEDSIGNAL */
    reg                r_desc_tap_valid;
    reg                r_desc_mac_valid;
    reg                r_desc_out_valid;
    reg  [LEN_W-1:0]   r_line_len;
    reg  [LEN_W-1:0]   r_tap_col;
    reg  [ROWS_W-1:0]  r_tap_row;
    reg  [LOT_W-1:0]   r_tap_map;
    reg                r_wgt_loaded;
    reg  [1:0]         r_shift_count;
    reg  [AGE_W-1:0]   r_shift_age;
    reg  [PHASE_W-1:0] r_win_age;
    reg                r_win_open;
    reg                r_rot_busy;
    reg  [PHASE_W-1:0] r_dev_age;
    reg                r_dev_on;
    reg                r_acc_multi;
    reg                r_acc_skip;
    reg                r_acc_first;
    reg                r_acc_last;
    reg                r_win_end;
    reg                r_xfer;
    reg  [NPIX_W-1:0]  r_rank;
    reg  [CNT_W-1:0]   r_thr_left;
    reg  [CNT_W-1:0]   r_done_left;
    reg  [CNT_W-1:0]   r_err_age;
    reg  [15:0]        r_last_id;
    reg  [31:0]        r_wait;
    reg  [31:0]        r_wait_live;
    reg                r_gap_cmd;
    reg                r_seen_window;

    wire               w_dev;
    wire               w_step_skip;
    /* Fenêtre capturée, selon WIN_LAG, blocs g_lag et g_no_lag : MAC occupés, ④ qui tourne encore pour elle après
     * le cycle de son win_load, fin de ses MAC pour desc_out, et compte à rebours que desc_out prend à cette fin. */
    wire               w_win_busy;
    wire               w_win_busy_next;
    wire               w_rot_busy;
    wire               w_rot_busy_next;
    /* Comparaison d'origine de la rotation, que seul le banc du bloc lit contre r_rot_busy : exception de lint,
     * justifiée ici. */
    /* verilator lint_off UNUSEDSIGNAL */
    wire               w_rot_busy_cmp;
    /* verilator lint_on UNUSEDSIGNAL */
    wire               w_mac_end;
    wire [CNT_W-1:0]   w_out_left;
    /* G_PASS de la passe de desc_tap, de la dernière passe entrée dans les MAC, celle de desc_mac,
     * et de la fenêtre dans les MAC : G hors variante G1, sinon tirés du bloc g_g1. */
    wire [PHASE_W-1:0] w_tap_g;
    wire [PHASE_W-1:0] w_mac_g;
    wire [PHASE_W-1:0] w_win_g;
    /* Variante G1, 1 ou 0 hors d'elle : la dernière fenêtre de p n'a pas de pré-transfert à
     * attendre, desc_drain tient une passe, et cette passe finit ce cycle, avec son pass_id. */
    wire               w_pre_clear;
    wire               w_drain_valid;
    wire               w_drain_end;
    wire [15:0]        w_drain_id;

    /* Champs du descripteur, mot PASSE[63:16] au format du contrat 10a, positions de
     * rtl/00_params.vh. */
    wire               w_tap_stride   = r_desc_tap[`TILE_HDR_STRIDE_POS - 16];
    wire [LEN_W-1:0]   w_tap_ncols    = r_desc_tap[`TILE_HDR_NCOLS_POS - 16 +: LEN_W];
    wire [ROWS_W-1:0]  w_tap_rows     = r_desc_tap[`TILE_HDR_ROWS_POS - 16 +: ROWS_W];
    wire [LOT_W-1:0]   w_tap_lot      = r_desc_tap[`TILE_HDR_LOT_POS - 16 +: LOT_W];
    wire               w_tap_top_real = r_desc_tap[`TILE_HDR_TOP_POS - 16];
    wire               w_tap_first    = r_desc_tap[`TILE_HDR_FIRST_POS - 16];
    wire               w_tap_last     = r_desc_tap[`TILE_HDR_LAST_POS - 16];
    wire               w_tap_wgt_load = r_desc_tap[`TILE_HDR_WGT_POS - 16];
    wire [NPIX_W-1:0]  w_tap_npix     = r_desc_tap[`TILE_HDR_NPIX_POS - 16 +: NPIX_W];
    wire               w_rx_wgt_load  = i_rx_desc[`TILE_HDR_WGT_POS - 16];
    wire               w_mac_last     = r_desc_mac[`TILE_HDR_LAST_POS - 16];

    /* Prochaine fenêtre de la passe de desc_tap : colonne de fenêtre, rangée, carte.
     * rw − 1 = (ncols − 3) / s, s valant 1 ou 2. */
    wire [LEN_W-1:0]   w_col_last  = (w_tap_ncols - LEN_W'(3)) >> w_tap_stride;
    wire               w_col_end   = (r_tap_col == w_col_last);
    wire               w_row_end   = (r_tap_row == w_tap_rows - 1'b1);
    wire               w_map_end   = (r_tap_map == w_tap_lot);
    wire               w_first_win = (r_tap_col == 0) & (r_tap_row == 0) & (r_tap_map == 0);
    wire               w_last_win  = w_col_end & w_row_end & w_map_end;

    /* col_shift. La règle de spec/05_memoire_ligne.md section 5, jamais
     * au cycle d'un win_load, ② lisant les prises et line_out pendant ce cycle, tient par le compte : un
     * win_load exige le compte atteint et un col_shift un compte en dessous. Le terme ~o_win_load qui
     * l'écrivait aussi faisait entrer tout le cône de win_load dans col_shift, sans rien changer : il
     * est retiré, et le banc du bloc vérifie la règle à chaque cycle (point 10b_sequencer.v:241 de la
     * revue du RTL d'af5ab629). */
    wire [1:0]         w_shift_need   = (r_tap_col == 0) ? 2'd3 : (w_tap_stride ? 2'd2 : 2'd1);
    wire               w_shifts_in    = (r_shift_count >= w_shift_need);
    wire               w_shift_spaced = (r_shift_age == AGE_W'(M));

    assign o_col_shift = r_desc_tap_valid & ~i_err_state & (r_shift_count < w_shift_need) & w_shift_spaced
                         & i_shift_ok;

    /* Fenêtre prête. Les MAC sont libres G_PASS cycles après la dernière capture, le G de la passe de
     * cette fenêtre, hors déversement seul.
     * Première fenêtre : poids dans ④ et, si elle seuille, bloc de seuils complet et non réservé.
     * Dernière fenêtre : si l'en-tête suivant charge des poids, ⑤ plein, car wgt_xfer les déverse
     * pendant cette fenêtre, et en variante G1 son pré-transfert fait. */
    /* Déversement en cours, r_dev_on : âge de 1 à G_MAX − 1, tout autre code que G_MAX, illégal, comptant comme repos
     * et revenant à G_MAX au front suivant sans faire tourner ④ (compteurs posés à une valeur illégale). La règle se
     * prend sur l'état suivant, à l'entrée de r_dev_on, plus bas. */
    wire               w_mac_free     = ~w_win_busy & ~r_dev_on;
    wire               w_thr_pending  = (r_thr_left != 0);
    wire               w_wgt_ready    = ~w_tap_wgt_load | r_wgt_loaded;
    wire               w_thr_ready    = ~w_tap_last | (i_thr_cache_full & ~w_thr_pending);
    wire               w_next_wgt     = ~(i_rx_desc_valid & w_rx_wgt_load) | i_wgt_cache_full;
    wire               w_win_ready    = r_desc_tap_valid & w_mac_free & i_tap_valid & w_shifts_in
                                        & (~w_first_win | (w_wgt_ready & w_thr_ready))
                                        & (~w_last_win | (w_next_wgt & w_pre_clear));

    assign o_win_load   = w_win_ready & ~i_err_state;
    assign o_pass_start = o_win_load & w_first_win;
    assign o_top_sel    = r_desc_tap_valid & (r_tap_row == 0) & (r_tap_map == 0) & w_tap_top_real;
    assign o_top_zero   = r_desc_tap_valid & (r_tap_row == 0) & ~o_top_sel;

    /* Déversement seul : première fenêtre d'une passe qui charge ses poids, absents de ④, et ④ qui ne tourne plus pour
     * la dernière fenêtre, au plus tôt à W + G_PASS + WIN_LAG (contrat D.4), terme redondant sous ② transparente, où
     * la rotation finit avec les MAC. */
    wire               w_dev_start = w_mac_free & ~w_rot_busy & r_desc_tap_valid & w_first_win & w_tap_wgt_load
                                     & ~r_wgt_loaded & i_wgt_cache_full & ~i_err_state;

    assign w_dev      = w_dev_start | r_dev_on;
    assign w_rot_busy = r_rot_busy;

    wire               w_xfer_start = o_win_load & w_last_win & i_rx_desc_valid & w_rx_wgt_load;

    /* Âge et G_PASS de la fenêtre au cycle suivant : r_win_age prend le premier au front, et r_win_open l'état ouvert
     * qu'ils donnent, w_win_busy_next écrit dans g_lag et g_no_lag comme w_win_busy. */
    wire [PHASE_W-1:0] w_win_age_next = o_win_load ? PHASE_W'(1) : (w_rot_busy ? r_win_age + 1'b1 : r_win_age);
    wire [PHASE_W-1:0] w_win_g_next   = o_win_load ? w_tap_g : w_win_g;

    /* Rotation et transfert de ④ pendant G_PASS cycles par fenêtre : sous ② transparente du cycle W de son win_load
     * à W + G_PASS − 1, sous ② au front ou au registre WIN_LAG cycles plus tard, l'âge de la fenêtre courant alors
     * jusqu'à G_PASS + WIN_LAG (contrat D.4). Sous ② au front, une fenêtre capturée à W + G_PASS, au dernier cycle de
     * la rotation de la précédente, prend la suite sans trou. La dernière fenêtre d'une passe finit ses MAC au front
     * qui clôt W_last + G_PASS − 1 + WIN_LAG, et pass_done garde ses formules en L_MAC : le compte à rebours de
     * desc_out, pris WIN_LAG cycles plus tard, vaut STAGES − 1 ou STAGES + G_PASS + 1
     * (spec/12_controle.md section 4.7). */
    generate if (WIN_LAG != 0)
        begin : g_lag
            assign w_win_busy      = (r_win_age < w_win_g);
            assign w_win_busy_next = (w_win_age_next < w_win_g_next);
            assign w_rot_busy_cmp  = (r_win_age != w_win_g + PHASE_W'(WIN_LAG));
            assign w_rot_busy_next = (w_win_age_next != w_win_g_next + PHASE_W'(WIN_LAG));
            assign w_mac_end  = r_win_end & (r_win_age == w_win_g + PHASE_W'(WIN_LAG) - 1'b1);
            assign w_out_left = w_mac_last ? CNT_W'(L_MAC + 1 - WIN_LAG) + CNT_W'(w_mac_g)
                                           : CNT_W'(L_MAC - 1 - WIN_LAG);
            assign o_wgt_rot  = w_rot_busy | w_dev;
            assign o_wgt_xfer = w_dev | (r_xfer & w_rot_busy);
            /* Sélection spéculée, justifiée en tête du module. */
            if (XSEL_LEAD != 0)
                begin : g_xsel
                    assign o_wgt_xsel_pre = w_win_busy ? r_xfer
                                          : ((w_last_win & i_rx_desc_valid & w_rx_wgt_load) | ~r_desc_tap_valid
                                             | (w_first_win & w_tap_wgt_load & ~r_wgt_loaded) | r_dev_on);
                end
            else
                begin : g_xsel_exact
                    assign o_wgt_xsel_pre = o_wgt_xfer;
                end
        end
    else
        begin : g_no_lag
            assign w_win_busy      = (r_win_age != w_win_g);
            assign w_win_busy_next = (w_win_age_next != w_win_g_next);
            assign w_rot_busy_cmp  = w_win_busy;
            assign w_rot_busy_next = w_win_busy_next;
            assign w_mac_end  = r_win_end & (r_win_age == w_win_g - 1'b1);
            assign w_out_left = w_mac_last ? CNT_W'(L_MAC + 1) + CNT_W'(w_mac_g) : CNT_W'(L_MAC - 1);
            assign o_wgt_rot  = o_win_load | w_win_busy | w_dev;
            assign o_wgt_xfer = w_dev | w_xfer_start | (r_xfer & w_win_busy);
            assign o_wgt_xsel_pre = o_wgt_xfer;
        end
    endgenerate

    /* Rang de la fenêtre pour la règle de saut, c = n mod (R − 1), et saut si c < P_ACC − R. */
    wire [NPIX_W-1:0]  w_rank      = (o_pass_start & w_tap_first) ? {NPIX_W{1'b0}} : r_rank;
    wire [NPIX_W-1:0]  w_rank_inc  = w_rank + 1'b1;
    wire [NPIX_W-1:0]  w_rank_next = (w_rank_inc == w_tap_npix - 1'b1) ? {NPIX_W{1'b0}} : w_rank_inc;
    wire               w_skip_rule = ({1'b0, w_rank} + {1'b0, w_tap_npix}) < {1'b0, NPIX_W'(P_ACC)};
    wire               w_tap_multi = ~(w_tap_first & w_tap_last);

    /* Calendrier de ⑥ : une ligne à retard d'o_win_load, r_date[k] haut k cycles après une capture, remise à zéro avec
     * le séquenceur. L'âge de la fenêtre avance sans relance de 1 à G_PASS + WIN_LAG, et L_MAC + 1 < min(G, G_S1)
     * (param_check) : r_date[k] vaut r_win_age == k pour k de 1 à L_MAC + 1, si bien que les dates de ⑥ sortent de
     * bascules au lieu d'une comparaison de l'âge suivie de toute leur sortance, ce que prouve le banc test/equiv_seq
     * (levier technique du 21/10/2026). Aucune capture ne tombe à une date d'au moins 1 : l'échange y lit
     * r_acc_multi, et o_win_load avec w_tap_multi seulement quand M_E − 1 = L_MAC. */
    reg  [L_MAC+1:1]   r_date;
    wire [L_MAC+1:0]   w_date      = {r_date, o_win_load};
    wire               w_step_swap = (L_MAC - M_E + 1 == 0) ? (w_tap_multi & o_win_load)
                                                            : (r_acc_multi & w_date[L_MAC - M_E + 1]);

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_date <= {(L_MAC + 1){1'b0}};
        else
            r_date <= w_date[L_MAC:0];

    assign w_step_skip = r_acc_skip & w_date[L_MAC + 1];
    assign o_acc_step  = w_step_swap | w_step_skip;
    assign o_acc_win   = w_date[L_MAC];
    assign o_acc_first = r_acc_first;
    assign o_acc_last  = r_acc_last;

    /* Sorties anticipées, en-tête du module : lues plus tôt sur la même ligne à retard, l'échange sur r_date[STEP_J],
     * le saut sur r_date[L_MAC + 1 − STEP_LEAD] et acc_win sur r_date[L_MAC − WIN_LEAD]. */
    localparam STEP_J = L_MAC - M_E + 1 - STEP_LEAD;

    wire               w_swap_pre = (STEP_J == 0) ? (w_tap_multi & o_win_load) : (r_acc_multi & w_date[STEP_J]);

    assign o_acc_step_pre = w_swap_pre | (r_acc_skip & w_date[L_MAC + 1 - STEP_LEAD]);
    assign o_acc_win_pre  = w_date[L_MAC - WIN_LEAD];

    /* Fin de passe : desc_out au bout de son compte à rebours. En variante G1, cette fin attend celle
     * de desc_drain quand elle tombe avant ou au même cycle, et les deux passes finissent par une
     * seule impulsion de pass_done, last_pass_id prenant la plus récente (amendement A2).
     * w_done_pass_id, pass_id que prend last_pass_id au front de pass_done, est la sonde PDONE de la
     * tuile (amendement A6) : desc_out tient déjà la passe suivante quand desc_drain finit seul. */
    wire               w_out_end      = r_desc_out_valid & (r_done_left == 0);
    wire               w_out_done     = w_out_end & ~(w_drain_valid & ~w_drain_end);
    wire [15:0]        w_done_pass_id = w_out_done ? r_desc_out[`TILE_HDR_PASS_ID_POS - 16 +: `TILE_HDR_PASS_ID_W] : w_drain_id;

    assign o_thr_xfer  = (r_thr_left == CNT_W'(1 + THR_XFER_LEAD));
    assign o_pass_done = w_out_done | w_drain_end;

    assign o_thr_xfer_pre = (r_thr_left == CNT_W'(1 + THR_XFER_LEAD + THR_LEAD));

    wire               w_err_drained = (r_err_age == CNT_W'(L_MAC + 1) + CNT_W'(w_mac_g) + CNT_W'(w_mac_g));

    assign o_out_empty      = (~r_desc_mac_valid & ~r_desc_out_valid & ~w_drain_valid) | w_err_drained;
    assign o_line_len       = r_line_len;
    assign o_win_open       = r_win_open;
    assign o_win_open_early = ~({1'b0, r_win_age} + 1'b1 < {1'b0, w_win_g});
    assign o_last_pass_id   = r_last_id;
    assign o_mac_wait_count = r_wait;

    wire               w_tap_take = i_rx_desc_valid & (~r_desc_tap_valid | (o_win_load & w_last_win));

    always @(posedge i_clk)
        begin
            if (w_tap_take)
                r_desc_tap <= i_rx_desc;
            if (o_pass_start)
                r_desc_mac <= r_desc_tap;
            if (w_mac_end)
                r_desc_out <= r_desc_mac;
        end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_line_len <= {LEN_W{1'b0}};
        else if (o_pass_start)
            r_line_len <= w_tap_ncols;

    /* desc_tap, ses compteurs de prises et l'état des poids de sa passe dans ④. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_desc_tap_valid <= 1'b0;
                r_tap_col        <= {LEN_W{1'b0}};
                r_tap_row        <= {ROWS_W{1'b0}};
                r_tap_map        <= {LOT_W{1'b0}};
                r_wgt_loaded     <= 1'b0;
            end
        else if (o_win_load & w_last_win)
            begin
                r_desc_tap_valid <= i_rx_desc_valid;
                r_tap_col        <= {LEN_W{1'b0}};
                r_tap_row        <= {ROWS_W{1'b0}};
                r_tap_map        <= {LOT_W{1'b0}};
                r_wgt_loaded     <= w_xfer_start;
            end
        else if (~r_desc_tap_valid & i_rx_desc_valid)
            begin
                r_desc_tap_valid <= 1'b1;
                r_wgt_loaded     <= 1'b0;
            end
        else if (o_win_load)
            begin
                if (w_col_end)
                    begin
                        r_tap_col <= {LEN_W{1'b0}};
                        if (w_row_end)
                            begin
                                r_tap_row <= {ROWS_W{1'b0}};
                                r_tap_map <= r_tap_map + 1'b1;
                            end
                        else
                            r_tap_row <= r_tap_row + 1'b1;
                    end
                else
                    r_tap_col <= r_tap_col + 1'b1;
            end
        else if (w_dev_start)
            r_wgt_loaded <= 1'b1;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_shift_count <= 2'd0;
                r_shift_age   <= AGE_W'(M);
            end
        else
            begin
                if (o_win_load)
                    r_shift_count <= 2'd0;
                else if (o_col_shift)
                    r_shift_count <= r_shift_count + 1'b1;
                if (o_col_shift)
                    r_shift_age <= AGE_W'(1);
                else if (~w_shift_spaced)
                    r_shift_age <= r_shift_age + 1'b1;
            end

    /* Fenêtre en cours dans les MAC : son âge et ce que la capture en a retenu. L'âge s'arrête au
     * G_PASS + WIN_LAG de la fenêtre, fin de sa rotation, G + WIN_LAG au reset, le pas d'une fenêtre G1 revenant au
     * pas 2 au reset, et ② est ouverte au reset. r_rot_busy prend la rotation que donnent l'âge et le G_PASS suivants,
     * nulle au reset. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_win_age  <= PHASE_W'(G + WIN_LAG);
                r_win_open <= 1'b1;
                r_rot_busy <= 1'b0;
            end
        else
            begin
                r_win_age  <= w_win_age_next;
                r_win_open <= ~w_win_busy_next;
                r_rot_busy <= w_rot_busy_next;
            end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_acc_multi <= 1'b0;
                r_acc_skip  <= 1'b0;
                r_acc_first <= 1'b0;
                r_acc_last  <= 1'b0;
                r_win_end   <= 1'b0;
                r_xfer      <= 1'b0;
                r_rank      <= {NPIX_W{1'b0}};
            end
        else if (o_win_load)
            begin
                r_acc_multi <= w_tap_multi;
                r_acc_skip  <= w_tap_multi & w_skip_rule;
                r_acc_first <= w_tap_first;
                r_acc_last  <= w_tap_last;
                r_win_end   <= w_last_win;
                r_xfer      <= w_xfer_start;
                r_rank      <= w_rank_next;
            end

    /* Déversement seul de G_MAX cycles. w_dev_age_next est l'état que r_dev_age prend au même front, et r_dev_on y
     * prend la règle du retour à un état légal (correctif des compteurs du 28/10/2026, 61fedaa3) : déversement en
     * cours pour un âge de 1 à G_MAX − 1, repos pour tout autre code. Sur les états atteignables, l'âge vaut G_MAX
     * quand r_dev_on est bas et l'âge suivant reste dans 1 à G_MAX, si bien que r_dev_on y vaut r_dev_age != G_MAX en
     * registre. Un âge posé à une valeur illégale au repos laisse r_dev_on bas et revient à G_MAX au front suivant. */
    wire [PHASE_W-1:0] w_dev_age_next = w_dev_start ? PHASE_W'(1) : (r_dev_on ? r_dev_age + 1'b1 : PHASE_W'(G_MAX));

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_dev_age <= PHASE_W'(G_MAX);
        else if (w_dev_start)
            r_dev_age <= PHASE_W'(1);
        else if (r_dev_on)
            r_dev_age <= r_dev_age + 1'b1;
        else
            r_dev_age <= PHASE_W'(G_MAX);

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_dev_on <= 1'b0;
        else
            r_dev_on <= (w_dev_age_next != {PHASE_W{1'b0}}) & (w_dev_age_next < PHASE_W'(G_MAX));

    /* desc_mac de W0 à W_last + G_PASS − 1 + WIN_LAG, desc_out jusqu'à la fin de sa passe. pass_done d'une passe
     * qui seuille à W_last + L_MAC + 2 G_PASS + 1, W_last + L_MAC + G_PASS − 1 sinon, son compte à
     * rebours w_out_left partant de W_last + G_PASS + WIN_LAG, et un compte au bout qui attend desc_drain s'arrête
     * à 0. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_desc_mac_valid <= 1'b0;
                r_desc_out_valid <= 1'b0;
                r_done_left      <= {CNT_W{1'b0}};
                r_last_id        <= 16'd0;
            end
        else
            begin
                if (o_pass_start)
                    r_desc_mac_valid <= 1'b1;
                else if (w_mac_end)
                    r_desc_mac_valid <= 1'b0;
                if (o_pass_done)
                    r_last_id <= w_done_pass_id;
                if (w_out_done)
                    r_desc_out_valid <= 1'b0;
                else if (r_desc_out_valid & ~w_out_end)
                    r_done_left <= r_done_left - 1'b1;
                if (w_mac_end)
                    begin
                        r_desc_out_valid <= 1'b1;
                        r_done_left      <= w_out_left;
                    end
            end

    /* thr_xfer à W0 + L_MAC + G_PASS − THR_XFER_LEAD d'une passe qui seuille, réservé de W0 jusqu'à W0 + L_MAC + G_PASS. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_thr_left <= {CNT_W{1'b0}};
        else if (o_pass_start & w_tap_last)
            r_thr_left <= CNT_W'(L_MAC) + CNT_W'(w_tap_g);
        else if (w_thr_pending)
            r_thr_left <= r_thr_left - 1'b1;

    /* En ERREUR, desc_mac ne se libère plus : la sortie est réputée vide L_MAC + 2 G_PASS + 1 cycles
     * après l'entrée en ERREUR, G_PASS de la dernière passe entrée dans les MAC
     * (spec/12_controle.md section 4.7). En variante G1, la
     * garde G_MAX ≤ 2 min(G, G1) de rtl/0_param_check.v fait
     * couvrir à ce délai une passe antérieure au plus grand G_PASS. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_err_age <= {CNT_W{1'b0}};
        else if (i_err_state & ~w_err_drained)
            r_err_age <= r_err_age + 1'b1;

    /* Attentes, règle du trou 7 : l'écart court de W + G_PASS à la capture suivante, et ne compte
     * pas s'il a vu une commande. r_wait_live tient r_wait plus l'écart en cours, modulo 2^32 : il
     * avance d'un à chaque cycle d'écart, et la capture qui clôt l'écart le copie dans r_wait, ou le
     * ramène à r_wait si l'écart a vu une commande. Aucun additionneur de 32 bits, et le cône de
     * win_load ne commande plus que le choix final, sa branche passant avant celle de l'écart, qui
     * ne le lit donc pas (point 10b_sequencer.v des compteurs d'attente, relevé de rtl-coupe du
     * 21/10/2026). */
    wire               w_gap_cycle = r_seen_window & ~w_win_busy;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_wait        <= 32'd0;
                r_wait_live   <= 32'd0;
                r_gap_cmd     <= 1'b0;
                r_seen_window <= 1'b0;
            end
        else if (o_win_load)
            begin
                if (~r_gap_cmd)
                    r_wait <= r_wait_live;
                else
                    r_wait_live <= r_wait;
                r_gap_cmd     <= 1'b0;
                r_seen_window <= 1'b1;
            end
        else if (w_gap_cycle)
            begin
                r_wait_live <= r_wait_live + 1'b1;
                if (i_cmd_seen)
                    r_gap_cmd <= 1'b1;
            end

    /* Variante G1, G_LOW < G_MAX : G_PASS de chaque passe, pré-transfert, pas de la passe servie par
     * ④ et ⑥, et desc_drain. Hors d'elle, les G valent G et les sorties ajoutées 0. */
    generate if (G_S1 != G)
        begin : g_g1
            /* Pas de la fenêtre capturée, 1 au pas 1, lu sur desc_tap au cycle de son win_load, et pas de la
             * dernière passe entrée dans les MAC, lu au cycle de son pass_start : desc_mac, sans reset,
             * figerait le compte de la sortie vide d'une ERREUR qui précède le premier pass_start. */
            reg                r_win_stride1;
            reg                r_mac_stride1;
            /* Pré-transfert de la passe de desc_tap : commencé, et ses cycles restants après le cycle en cours. */
            reg                r_pre_started;
            reg  [PHASE_W-1:0] r_pre_left;
            /* desc_drain garde le descripteur entier, comme desc_out, et ce module n'en lit que
             * pass_id : exception de lint, justifiée ici. */
            /* verilator lint_off UNUSEDSIGNAL */
            reg  [DESC_W-1:0]  r_desc_drain;
            /* verilator lint_on UNUSEDSIGNAL */
            reg                r_drain_valid;
            reg  [CNT_W-1:0]   r_drain_left;

            assign w_tap_g = w_tap_stride ? PHASE_W'(G) : PHASE_W'(G_S1);
            assign w_mac_g = r_mac_stride1 ? PHASE_W'(G_S1) : PHASE_W'(G);
            assign w_win_g = r_win_stride1 ? PHASE_W'(G_S1) : PHASE_W'(G);

            always @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n)
                    begin
                        r_win_stride1 <= 1'b0;
                        r_mac_stride1 <= 1'b0;
                    end
                else
                    begin
                        if (o_win_load)
                            r_win_stride1 <= ~w_tap_stride;
                        if (o_pass_start)
                            r_mac_stride1 <= ~w_tap_stride;
                    end

            /* Pré-transfert de p, passe de desc_tap, quand H(p) > 0 : H(p) cycles consécutifs de wgt_pre,
             * à partir du premier cycle où ④ tient les poids de p, sans wgt_xfer ni déversement seul, la
             * dernière fenêtre de p n'étant pas capturée, ⑤ plein, aucun pré-transfert de p commencé et hors
             * ERREUR, sans lire desc_rx (amendement A7).
             * Quand desc_rx porte wgt_load, la dernière fenêtre de p ne part qu'au cycle qui suit son
             * dernier cran (contrat 10b amendé, trou 24 lu au plus tôt). */
            wire               w_tap_hold  = (w_tap_g != PHASE_W'(G_MAX));
            wire               w_pre_wait  = w_tap_hold & i_rx_desc_valid & w_rx_wgt_load;
            wire               w_pre_done  = r_pre_started & (r_pre_left == 0);
            wire               w_pre_start = w_tap_hold & r_desc_tap_valid & w_wgt_ready & ~o_wgt_xfer & i_wgt_cache_full
                                             & ~(o_win_load & w_last_win) & ~r_pre_started & ~i_err_state;

            assign w_pre_clear = ~w_pre_wait | w_pre_done;
            assign o_wgt_pre   = w_pre_start | (r_pre_left != 0);

            always @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n)
                    begin
                        r_pre_started <= 1'b0;
                        r_pre_left    <= {PHASE_W{1'b0}};
                    end
                else
                    begin
                        if (o_win_load & w_last_win)
                            r_pre_started <= 1'b0;
                        else if (w_pre_start)
                            r_pre_started <= 1'b1;
                        if (w_pre_start)
                            r_pre_left <= PHASE_W'(G_MAX) - w_tap_g - 1'b1;
                        else if (r_pre_left != 0)
                            r_pre_left <= r_pre_left - 1'b1;
                    end

            /* ④ sert la fenêtre en cours pendant une rotation, celle de desc_tap au cycle de son win_load
             * puis la fenêtre capturée, ou la passe du déversement seul, celle de desc_tap, et hors
             * rotation celle de desc_tap. Sous ② au front, la rotation de la fenêtre capturée part WIN_LAG cycles
             * après son win_load et finit au cycle W + G_PASS, le premier où la suivante peut être capturée : ④ suit
             * la fenêtre qui tourne (contrat D.4). ⑥ prend le pas de la fenêtre au cycle de son acc_win. */
            assign o_ring_stride1 = w_rot_busy ? r_win_stride1 : (r_desc_tap_valid & ~w_tap_stride);
            assign o_acc_stride1  = r_win_stride1;

            /* desc_drain (amendement A1) : au front où desc_out se recharge sans finir ce cycle, il prend
             * son descripteur, sa validité et son compte à rebours, et les garde jusqu'au pass_done de sa
             * passe. Un seul registre suffit sur le domaine de la garde G_MAX ≤ 2 min(G, G1), jamais trois
             * passes ne se trouvant en sortie à la fois : desc_drain est libre quand desc_out le recharge. */
            wire               w_drain_take = w_mac_end & r_desc_out_valid & ~w_out_done;

            assign w_drain_valid = r_drain_valid;
            assign w_drain_end   = r_drain_valid & (r_drain_left == 0);
            assign w_drain_id    = r_desc_drain[`TILE_HDR_PASS_ID_POS - 16 +: `TILE_HDR_PASS_ID_W];

            always @(posedge i_clk)
                if (w_drain_take)
                    r_desc_drain <= r_desc_out;

            always @(posedge i_clk or negedge i_rst_n)
                if (!i_rst_n)
                    begin
                        r_drain_valid <= 1'b0;
                        r_drain_left  <= {CNT_W{1'b0}};
                    end
                else if (w_drain_take)
                    begin
                        r_drain_valid <= 1'b1;
                        r_drain_left  <= r_done_left - 1'b1;
                    end
                else if (w_drain_end)
                    r_drain_valid <= 1'b0;
                else if (r_drain_valid)
                    r_drain_left <= r_drain_left - 1'b1;
        end
    else
        begin : g_uniform
            assign w_tap_g        = PHASE_W'(G);
            assign w_mac_g        = PHASE_W'(G);
            assign w_win_g        = PHASE_W'(G);
            assign w_pre_clear    = 1'b1;
            assign w_drain_valid  = 1'b0;
            assign w_drain_end    = 1'b0;
            assign w_drain_id     = 16'd0;
            assign o_wgt_pre      = 1'b0;
            assign o_ring_stride1 = 1'b0;
            assign o_acc_stride1  = 1'b0;
        end
    endgenerate

endmodule

`endif
