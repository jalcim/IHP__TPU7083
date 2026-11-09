`ifndef __PARAM_CHECK__
`define __PARAM_CHECK__

`include "00_params.vh"
`include "00_variantes.vh"

/* Contraintes d'élaboration de la tuile, au temps 0 et avant tout cycle.
 * Instancié par la tuile et par chaque banc : un jeu de paramètres hors bornes
 * s'arrête ici avec la règle de la spécification qu'il enfreint, au lieu de
 * donner un RTL qui compile et calcule faux (un bus [BA-1:0] à BA = 0 devient
 * [-1:0], large de deux bits, et compile).
 * La règle des bornes vient en premier : les grandeurs dérivées, LEVELS à C = 0
 * par exemple, n'ont de sens que si elle passe, et elle seule doit alors parler.
 * L, P_ACC et LOTMAX n'ont ici que des bornes basses : leurs largeurs de champ en sont
 * dérivées dans 00_params.vh et ne se surchargent pas, si bien qu'une borne haute par
 * largeur serait inatteignable. Leur seule borne haute est celle du mot PASSE, qui doit
 * tenir dans ses 64 bits bas. Ils doivent aussi valoir leurs macros, TILE_L, TILE_P_ACC et
 * TILE_LOTMAX, dont ces largeurs dérivent : une tuile qui les surcharge sans elles garderait les
 * champs de la tuile par défaut et compterait faux, sans arrêt (point 11_tile.v:76 de la revue
 * du RTL d'af5ab629). hdr_pass_id garde 16 bits, ceux de last_pass_id et d'ÉTAT, même si sa macro
 * se surcharge (point 10b_sequencer.v:326 de la même revue).
 * Depuis le lot 0 des accords (rtl/bancs.md), la variante G1, la troisième coupe des MAC et le
 * format (fh, aligned) s'élaborent, et W n'a plus qu'à être pair et d'au moins 64 bits :
 * ⌈PINS / 8⌉ groupes DBI et ECHO_SEL sur ⌈log2 ECHO_N⌉ bits (écarts E1 et E2 de l'étape 5).
 * En variante G1, G_MAX ≤ 2 min(G, G1) : la sortie vide en ERREUR, comptée au G_PASS de la
 * dernière passe entrée dans les MAC, couvre ainsi une passe antérieure au plus grand G_PASS
 * (spec de l'étape 5, chapitre du contrôle).
 * Depuis le lot 8 des suites, les options MAC_TREE, MAC_MODEL, FINAL_ADDER, WIN_LOAD et
 * REG_COPIES entrent en fin d'en-tête et leurs règles suivent celles d'avant (section D.0 du
 * dépôt de travail non publié). Wallace, bw_fused, bk_inv, le front et la coupe nulle de l'arbre binaire ont
 * leurs branches dans 6_mac.v, 4_window.v, 10b_sequencer.v et 11_tile.v, et la garde refuse les
 * options sans branche, Dadda, bw_ripple, bk, ks, ks_inv et le registre d'opérandes (suite :
 * TODO/options_gardees.md). 6_mac.v lit MAC_TREE, MAC_MODEL, FINAL_ADDER, REG_COPIES et
 * STAGES, et sa garde CUT_X != 0 ôte le registre des produits à une coupe nulle, si bien que CUT1
 * et l'arbre binaire sans coupe tiennent leurs STAGES étages. L_MAC compte
 * l'étage de la fenêtre au front ou au registre, WIN_LAG, et les MAC ont STAGES = L_MAC - WIN_LAG
 * étages. Les deux règles des coupes d'avant, L_MAC de 3 à 4 et deux coupes croissantes, cèdent
 * la place à celle de l'arbre binaire, STAGES - 1 coupes écrites en tête, et à celle des arbres
 * 3:2, sans coupe du jeu, qui les contiennent. L_MAC + 1 < min(G, G_S1) : le pas de saut de
 * l'anneau tombe à l'âge L_MAC + 1 d'une fenêtre, que le compteur d'âge borne à G_PASS
 * (constat 12 des suites).
 * Corrigé le 26/10/2026 (tâche 1 du plan A8) : les arbres 3:2 admettent des coupes du jeu, un registre
 * après chaque niveau de réduction d'une coupe non nulle (6_mac.v). La règle des arbres 3:2 sans coupe
 * du jeu ne garde que les 4 étages au plus des coupes nominales, trois coupes nulles, et la règle neuve
 * des coupes du jeu les veut non nulles en tête, strictement croissantes, de 1 à L_CSA - 1, au nombre
 * de STAGES - 1, L_CSA calculé ici comme mac_csa le calcule. mac_csa tient aussi cette règle lui-même,
 * le rejeu de rtl/pnr/pnr_bloc.py synthétisant 6_mac.v sans param_check.
 * MAC_MODEL = 3, le multiplieur S4xU4 de Yann Guidon en portes, a sa
 * branche sous l'arbre 3:2, et L_CSA suit son profil, un bit par terme dans chaque colonne de 0 à BA + BW − 1 et la
 * constante (−2^(BA + BW − 1) × 9 C) mod 2^CSA_W. */

module param_check #(parameter C           = `TILE_C,
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
                     parameter THR_FMT     = `TILE_THR_FMT,
                     parameter COL_FMT     = `TILE_COL_FMT,
                     parameter OUT_BUF     = `TILE_OUT_BUF,
                     parameter HDR_END     = `TILE_HDR_END,
                     parameter PASS_ID_W   = `TILE_HDR_PASS_ID_W,
                     parameter LEVELS      = $clog2(9 * C),
                     parameter MAC_TREE    = `TILE_MAC_TREE,
                     parameter MAC_MODEL   = `TILE_MAC_MODEL,
                     parameter FINAL_ADDER = `TILE_FINAL_ADDER,
                     parameter WIN_LOAD    = `TILE_WIN_LOAD,
                     parameter REG_COPIES  = `TILE_REG_COPIES,
                     parameter THR_SHARE   = `TILE_THR_SHARE,
                     parameter DIFF_DEPTH  = `TILE_DIFF_DEPTH,
                     parameter DIFF_SLICE  = `TILE_DIFF_SLICE,
                     parameter WIN_COPIES  = `TILE_WIN_COPIES,
                     parameter THR_CUT     = `TILE_THR_CUT,
                     parameter THR_XFER_LEAD = THR_CUT,
                     parameter WIN_LEAD    = (DIFF_DEPTH < L_MAC - 1) ? DIFF_DEPTH : L_MAC - 1,
                     parameter STEP_LEAD   = (L_MAC <= M_E) ? 0
                                             : ((DIFF_DEPTH < L_MAC - M_E) ? DIFF_DEPTH : L_MAC - M_E),
                     parameter THR_LEAD    = (DIFF_DEPTH < L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD)
                                             ? DIFF_DEPTH : L_MAC + groups_low(G, G1) - 1 - THR_XFER_LEAD,
                     parameter XSEL_LEAD   = (DIFF_DEPTH > 0 && WIN_LOAD != 0 && G1 == 0) ? 1 : 0,
                     parameter ACC_REP     = (DIFF_SLICE != 0 && G1 == 0) ? K : 1,
                     parameter WGT_REP     = (DIFF_SLICE != 0 && G1 == 0) ? K : 1,
                     parameter THR_REP     = (DIFF_SLICE != 0 && G1 == 0 && THR_SHARE == 0) ? groups_max(G, G1) : 1)
                    ();

    `include "00_groups.vh"

    localparam WIN_LAG   = (WIN_LOAD != 0) ? 1 : 0;
    localparam STAGES    = L_MAC - WIN_LAG;
    localparam CUT_COUNT = ((MAC_CUT_A != 0) ? 1 : 0) + ((MAC_CUT_B != 0) ? 1 : 0) + ((MAC_CUT_C != 0) ? 1 : 0);

    /* L_CSA, niveaux de la réduction 3:2 d'un filtre, calculé comme mac_csa de 6_mac.v, par csa_start puis csa_levels_to
     * (tâche 1 du plan A8, 26/10/2026). Chaque terme verse ses produits partiels de Baugh-Wooley dans CSA_W colonnes,
     * ACC sous FINAL_ADDER = 5 comme mac_array les pose, et la constante (−(2^BA − 1) × 2^(BW − 1) × 9 C) mod 2^CSA_W
     * un bit à 1 dans chaque colonne où elle en a un. Sous MAC_MODEL = 3, chaque terme verse un bit dans chaque colonne de
     * 0 à BA + BW − 1, et la constante vaut (−2^(BA + BW − 1) × 9 C) mod 2^CSA_W (tâche 2 du plan A10).
     * Chaque niveau de Wallace ramène une colonne de hauteur h à
     * h − 2 ⌊h / 3⌋ − [h mod 3 = 2] bits, plus les retenues de sa voisine de droite, jusqu'à deux bits au plus par colonne.
     * Nul sous l'arbre binaire, dont aucune règle ne le lit, comme sous un multiplieur sans branche 3:2, et hors des
     * bornes de C, BA et BW, que la règle des bornes refuse la première : aucune hauteur n'y est négative.
     * Hauteurs sur 32 bits par colonne, lues dans un integer avant toute comparaison, signée. */
    localparam CSA_W    = (FINAL_ADDER == 5) ? ACC : BA + BW + LEVELS;
    localparam CSA_COLS = (CSA_W > 0) ? CSA_W : 1;
    localparam CSA_FED  = (MAC_MODEL == 2 || MAC_MODEL == 3) && C >= 1 && BA >= 1 && BW >= 2 && CSA_W < 31;

    function integer csa_levels_to(input integer target);
        reg [CSA_COLS*32-1:0] heights;
        integer               col;
        integer               first;
        integer               last;
        integer               bits;
        integer               constant;
        integer               height;
        integer               carries;
        integer               tallest;
        begin
            constant = CSA_FED ? ((1 << CSA_W) - (((MAC_MODEL == 3) ? 1 << (BA + BW - 1) : ((1 << BA) - 1) * (1 << (BW - 1)))
                                                  * 9 * C) % (1 << CSA_W)) % (1 << CSA_W) : 0;
            tallest  = 0;
            for (col = 0; col < CSA_COLS; col = col + 1)
                begin
                    first  = (col > BA - 1) ? col - (BA - 1) : 0;
                    last   = (col < BW - 2) ? col : BW - 2;
                    bits   = (MAC_MODEL == 3) ? ((col < BA + BW) ? 1 : 0)
                             : ((last >= first) ? last - first + 1 : 0) + ((col >= BW - 1 && col < BW - 1 + BA) ? 1 : 0);
                    height = (CSA_FED && col < CSA_W) ? 9 * C * bits + ((constant >> col) & 1) : 0;
                    heights[col*32 +: 32] = height;
                    if (height > tallest)
                        tallest = height;
                end
            csa_levels_to = 0;
            while (tallest > target)
                begin
                    carries = 0;
                    tallest = 0;
                    for (col = 0; col < CSA_COLS; col = col + 1)
                        begin
                            height                = heights[col*32 +: 32];
                            heights[col*32 +: 32] = height - 2 * (height / 3) - ((height % 3 == 2) ? 1 : 0) + carries;
                            carries               = height / 3 + ((height % 3 == 2) ? 1 : 0);
                            height                = heights[col*32 +: 32];
                            if (height > tallest)
                                tallest = height;
                        end
                    csa_levels_to = csa_levels_to + 1;
                end
        end
    endfunction

    localparam L_CSA = (MAC_TREE != 0) ? csa_levels_to(2) : 0;

    /* La dernière coupe non nulle, que la règle des coupes du jeu sous l'arbre 3:2 borne par L_CSA − 1. */
    localparam CSA_LAST_CUT = (MAC_CUT_C != 0) ? MAC_CUT_C : (MAC_CUT_B != 0) ? MAC_CUT_B : MAC_CUT_A;

    /* Avances et tranches des arbres de diffusion (0b_bcast_tree.v), que la tuile tire de DIFF_DEPTH, DIFF_SLICE et
     * THR_CUT et passe au séquenceur, aux consommateurs et ici. Chacune doit égaler sa règle, celle du défaut de
     * 10b_sequencer.v, 7_acc_ring.v, 5_weights.v ou 8_threshold.v, pour qu'une formule de la tuile qui s'en écarte
     * s'arrête avant tout cycle au lieu de livrer une feuille décalée. thr_xfer garde au plus L_MAC + G_PASS − 1 cycles
     * d'avance du plus petit G_PASS, celle de la coupe de ⑦ comprise : r_thr_left ne se charge qu'à 0. */
    localparam LEAD_THR_BOUND = L_MAC + groups_low(G, G1) - 1;
    localparam WIN_LEAD_RULE  = (DIFF_DEPTH < L_MAC - 1) ? DIFF_DEPTH : L_MAC - 1;
    localparam STEP_LEAD_RULE = (L_MAC <= M_E) ? 0 : ((DIFF_DEPTH < L_MAC - M_E) ? DIFF_DEPTH : L_MAC - M_E);
    localparam THR_LEAD_RULE  = (DIFF_DEPTH < LEAD_THR_BOUND - THR_CUT) ? DIFF_DEPTH : LEAD_THR_BOUND - THR_CUT;
    localparam XSEL_LEAD_RULE = (DIFF_DEPTH > 0 && WIN_LAG == 1 && G1 == 0) ? 1 : 0;
    localparam SLICE_REP_RULE = (DIFF_SLICE != 0 && G1 == 0) ? K : 1;
    localparam THR_REP_RULE   = (DIFF_SLICE != 0 && G1 == 0 && THR_SHARE == 0) ? groups_max(G, G1) : 1;

    initial
        begin
            if (T != (1 << BA) - 1 || ACC < 2 || THR_W < 2 || C < 1 || K < 1 || BW < 2 || M < 1 || BA < 1)
                $fatal(1, "ECHEC parametres : T, ACC, THR_W, C, K, BW, M ou BA hors bornes");
            if (G < 2 * M + 2 || G < 3 * M)
                $fatal(1, "ECHEC parametres : G = %0d < max(2 M + 2, 3 M), rythme des col_shift d'un changement de rangee (trou 6)", G);
            if (G1 != 0 && (G1 < 2 * M + 2 || G1 < 3 * M))
                $fatal(1, "ECHEC parametres : G1 = %0d < max(2 M + 2, 3 M), changement de rangee des passes au pas 1 (trou 6, variante G1)", G1);
            if (G1 != 0 && (G > 2 * G1 || G1 > 2 * G))
                $fatal(1, "ECHEC parametres : G = %0d et G1 = %0d, G_MAX au-dela de 2 min(G, G1), la sortie vide en ERREUR au G_PASS de la derniere passe ne couvre pas une passe au plus grand G_PASS (variante G1, chapitre du controle de l'etape 5)", G, G1);
            if (M_E < 2 || 2 * M_E > G || (G1 != 0 && 2 * M_E > G1))
                $fatal(1, "ECHEC parametres : M_E = %0d hors de 2 a min(G, G1) / 2 (09_accumulation.md section 8)", M_E);
            if ((P_ACC - 1) % (M_E - 1) != 0)
                $fatal(1, "ECHEC parametres : P_ACC - 1 = %0d pas multiple de M_E - 1 (09_accumulation.md section 3.1)", P_ACC - 1);
            if (M_E - 1 > L_MAC)
                $fatal(1, "ECHEC parametres : M_E - 1 > L_MAC, pas d'echange avant le win_load (09 sections 4.1 et 5, 12 section 4.2)");
            if (D_COL < 4)
                $fatal(1, "ECHEC parametres : D_COL = %0d < 4 (05_memoire_ligne.md section 3.2)", D_COL);
            if (L < 3)
                $fatal(1, "ECHEC parametres : L = %0d < 3, hdr_ncols compte 3 colonnes au moins (03_interfaces.md section 4.6)", L);
            if (P_ACC < 3)
                $fatal(1, "ECHEC parametres : P_ACC = %0d < 3", P_ACC);
            if (LOTMAX < 1)
                $fatal(1, "ECHEC parametres : LOTMAX = %0d < 1, une passe compte une carte au moins (03_interfaces.md section 4.6)", LOTMAX);
            if (L != `TILE_L || P_ACC != `TILE_P_ACC || LOTMAX != `TILE_LOTMAX)
                $fatal(1, "ECHEC parametres : L = %0d, P_ACC = %0d ou LOTMAX = %0d hors de TILE_L = %0d, TILE_P_ACC = %0d et TILE_LOTMAX = %0d, dont 00_params.vh tire les largeurs du mot PASSE (03_interfaces.md section 4.6)", L, P_ACC, LOTMAX, `TILE_L, `TILE_P_ACC, `TILE_LOTMAX);
            if (HDR_END > 64)
                $fatal(1, "ECHEC parametres : mot PASSE de %0d bits, au-dela de ses 64 bits bas (03_interfaces.md section 4.6)", HDR_END);
            if (PASS_ID_W != 16)
                $fatal(1, "ECHEC parametres : HDR_PASS_ID_W = %0d, last_pass_id porte 16 bits vers ETAT (12_controle.md, 03_interfaces.md)", PASS_ID_W);
            if (BPP != 2)
                $fatal(1, "ECHEC parametres : BPP = %0d, seul le DDR est garde (00_objet.md)", BPP);
            if (W % BPP != 0 || W < 64)
                $fatal(1, "ECHEC parametres : W = %0d, multiple de BPP et au moins 64, le mot PASSE ayant 64 bits", W);
            if (9 * C * K * BW <= W)
                $fatal(1, "ECHEC parametres : 9 C K BW = %0d <= W = %0d, le chargeur de poids doit avoir deux mots au moins (07_poids.md)", 9 * C * K * BW, W);
            if (OUT_W < K * BA)
                $fatal(1, "ECHEC parametres : OUT_W = %0d < K BA, sortie sans tampon (00_conception.md section 5)", OUT_W);
            if (OUT_W < 8)
                $fatal(1, "ECHEC parametres : OUT_W = %0d < 8, l'octet d'echo et d'etat doit tenir dans un mot de sortie (11_sortie.md)", OUT_W);
            if (THR_FMT != 0 || COL_FMT < 0 || COL_FMT > 2 || OUT_BUF != 0)
                $fatal(1, "ECHEC parametres : variante non ecrite (THR_FMT, tache V2 ; COL_FMT hors de 0 a 2 ; OUT_BUF, sans tache)");
            if (!(MAC_TREE == 0 || MAC_TREE == 1) || !(MAC_MODEL == 0 || MAC_MODEL == 2 || MAC_MODEL == 3)
                || !(FINAL_ADDER == 0 || FINAL_ADDER == 3 || FINAL_ADDER == 5) || !(WIN_LOAD == 0 || WIN_LOAD == 1))
                $fatal(1, "ECHEC parametres : variante non ecrite, MAC_TREE = %0d, MAC_MODEL = %0d, FINAL_ADDER = %0d ou WIN_LOAD = %0d sans branche ecrite (dépôt de travail non publié section D.0)", MAC_TREE, MAC_MODEL, FINAL_ADDER, WIN_LOAD);
            if ((MAC_TREE == 0) != (MAC_MODEL == 0))
                $fatal(1, "ECHEC parametres : MAC_TREE = %0d et MAC_MODEL = %0d, l'arbre binaire au seul multiplieur de reference, un arbre 3:2 au seul multiplieur de Baugh-Wooley ou S4xU4 (mac.key de l'accordeur)", MAC_TREE, MAC_MODEL);
            if (MAC_TREE == 0 && FINAL_ADDER != 0)
                $fatal(1, "ECHEC parametres : FINAL_ADDER = %0d sous l'arbre binaire, qui n'a pas d'additionneur final", FINAL_ADDER);
            if (MAC_TREE != 0 && (BA != 4 || BW != 4))
                $fatal(1, "ECHEC parametres : BA = %0d et BW = %0d sous un arbre 3:2, le u4 x s4 de Baugh-Wooley et ses constantes ecrits pour BA = BW = 4", BA, BW);
            if ((WIN_LOAD != 2 && REG_COPIES != 1)
                || (WIN_LOAD == 2 && !((REG_COPIES == 1 || REG_COPIES == 2 || REG_COPIES == 4 || REG_COPIES == 8)
                                       && REG_COPIES <= K)))
                $fatal(1, "ECHEC parametres : REG_COPIES = %0d a WIN_LOAD = %0d, une copie hors du registre d'operandes, 1, 2, 4 ou 8 copies au plus K sous lui", REG_COPIES, WIN_LOAD);
            if (THR_SHARE != 0 && THR_SHARE != 1)
                $fatal(1, "ECHEC parametres : THR_SHARE = %0d, forme de seuillage hors de 0 (cardinale) et 1 (partage dans le temps, 00_variantes.vh)", THR_SHARE);
            if (THR_CUT != 0 && THR_CUT != 1)
                $fatal(1, "ECHEC parametres : THR_CUT = %0d, coupe de seuillage hors de 0 (sans coupe) et 1 (comparaisons au cycle de acc_done, 00_variantes.vh)", THR_CUT);
            if (THR_CUT != 0 && THR_SHARE != 0)
                $fatal(1, "ECHEC parametres : THR_CUT = %0d avec THR_SHARE = %0d, la coupe de 7 ne vaut que sous la forme cardinale", THR_CUT, THR_SHARE);
            if (WIN_COPIES < 1 || WIN_COPIES > K || (WIN_COPIES > 1 && WIN_LOAD != 1))
                $fatal(1, "ECHEC parametres : WIN_COPIES = %0d a WIN_LOAD = %0d, copies de la fenetre au front seulement, de 1 a K", WIN_COPIES, WIN_LOAD);
            if (DIFF_DEPTH < 0 || DIFF_DEPTH > 3)
                $fatal(1, "ECHEC parametres : DIFF_DEPTH = %0d, profondeur des arbres de diffusion hors de 0 a 3", DIFF_DEPTH);
            if (DIFF_SLICE != 0 && DIFF_SLICE != 1)
                $fatal(1, "ECHEC parametres : DIFF_SLICE = %0d, hors de 0 et 1", DIFF_SLICE);
            if (THR_XFER_LEAD != THR_CUT || WIN_LEAD != WIN_LEAD_RULE || STEP_LEAD != STEP_LEAD_RULE
                || THR_LEAD != THR_LEAD_RULE || XSEL_LEAD != XSEL_LEAD_RULE || ACC_REP != SLICE_REP_RULE
                || WGT_REP != SLICE_REP_RULE || THR_REP != THR_REP_RULE || THR_XFER_LEAD + THR_LEAD > LEAD_THR_BOUND)
                $fatal(1, "ECHEC parametres : avances des arbres de diffusion hors de leurs regles, WIN_LEAD = %0d, STEP_LEAD = %0d, THR_LEAD = %0d, XSEL_LEAD = %0d, THR_XFER_LEAD = %0d, ACC_REP = %0d, WGT_REP = %0d, THR_REP = %0d (defauts de 10b_sequencer.v, 7_acc_ring.v, 5_weights.v et 8_threshold.v)", WIN_LEAD, STEP_LEAD, THR_LEAD, XSEL_LEAD, THR_XFER_LEAD, ACC_REP, WGT_REP, THR_REP);
            if (STAGES < 1)
                $fatal(1, "ECHEC parametres : STAGES = L_MAC - WIN_LAG = %0d < 1, les MAC ont un etage au moins", STAGES);
            if (L_MAC + 1 >= G || (G1 != 0 && L_MAC + 1 >= G1))
                $fatal(1, "ECHEC parametres : L_MAC + 1 = %0d >= min(G, G_S1), le pas de saut de l'anneau tombe a un age que le compteur borne a G_PASS (constat 12)", L_MAC + 1);
            if (MAC_TREE == 0 && !((MAC_CUT_A != 0 || MAC_CUT_B == 0) && (MAC_CUT_B != 0 || MAC_CUT_C == 0)
                                   && (MAC_CUT_A == 0 || (MAC_CUT_A >= 1 && MAC_CUT_A < LEVELS))
                                   && (MAC_CUT_B == 0 || (MAC_CUT_B > MAC_CUT_A && MAC_CUT_B < LEVELS))
                                   && (MAC_CUT_C == 0 || (MAC_CUT_C > MAC_CUT_B && MAC_CUT_C < LEVELS))
                                   && CUT_COUNT == STAGES - 1))
                $fatal(1, "ECHEC parametres : coupes %0d, %0d et %0d de l'arbre binaire, non nulles en tete, croissantes, de 1 a %0d, au nombre de STAGES - 1 = %0d", MAC_CUT_A, MAC_CUT_B, MAC_CUT_C, LEVELS - 1, STAGES - 1);
            if (MAC_TREE != 0 && CUT_COUNT == 0 && STAGES > 4)
                $fatal(1, "ECHEC parametres : arbre 3:2 aux coupes %0d, %0d et %0d a STAGES = %0d, coupes nominales du RTL sans coupe du jeu et 4 etages au plus", MAC_CUT_A, MAC_CUT_B, MAC_CUT_C, STAGES);
            if (MAC_TREE != 0 && CUT_COUNT != 0
                && !(MAC_CUT_A >= 1 && (MAC_CUT_C == 0 || MAC_CUT_B != 0) && (MAC_CUT_B == 0 || MAC_CUT_B > MAC_CUT_A)
                     && (MAC_CUT_C == 0 || MAC_CUT_C > MAC_CUT_B) && CSA_LAST_CUT < L_CSA && CUT_COUNT + 1 == STAGES))
                $fatal(1, "ECHEC parametres : coupes de l'arbre 3:2 hors regle, %0d, %0d et %0d, non nulles en tete, strictement croissantes, de 1 a L_CSA - 1 = %0d, au nombre de STAGES - 1 = %0d", MAC_CUT_A, MAC_CUT_B, MAC_CUT_C, L_CSA - 1, STAGES - 1);
        end

endmodule

`endif
