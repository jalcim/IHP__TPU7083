`ifndef __PARAMS__
`define __PARAMS__

/* Valeurs par défaut de la tuile, celles de l'accord par défaut de la liste, que nomme le bloc qui suit.
 * Un autre jeu se compile par -DTILE_<NOM>=<valeur>, d'où les ifndef.
 * Les modèles Python relisent ce fichier : il est la seule source des défauts.
 * Une valeur peut citer une macro définie plus haut, comme OUT_W.
 * Le bloc des défauts s'écrit par python3 test/accord_sets.py defaults, et check le compare au jeu
 * PARAMS_${ACCORD_DEFAULT} de rtl/accords.cmake.
 * MAC_TREE, MAC_MODEL, FINAL_ADDER, WIN_LOAD et REG_COPIES codent les options de la tuile, arbre des MAC,
 * multiplieur, additionneur final, capture de la fenêtre et copies du registre d'opérandes, dans l'ordre et aux codes
 * de la section C du dépôt de travail non publié, 0 et 1 copie valant la structure
 * écrite (section D.0, lot 8 des suites). */

// début du bloc des défauts, écrit par python3 test/accord_sets.py defaults et vérifié par check
/* Valeurs par défaut de la tuile : l'accord par défaut de la liste, 48-11-6 w392 DDR 3l cc,
 * jeu ACC_48_11_6_W392_CC_WA_BF_FR de accords.cmake, tiré par la
 * décision d'architecture du 23/10/2026, accord du cœur de accordeur/results/liste/coeur/liste.md de main au commit 2bfc430. */
`ifndef TILE_C
 `define TILE_C 48
`endif
`ifndef TILE_K
 `define TILE_K 11
`endif
`ifndef TILE_G
 `define TILE_G 6
`endif
`ifndef TILE_G1
 `define TILE_G1 0
`endif
`ifndef TILE_W
 `define TILE_W 392
`endif
`ifndef TILE_BPP
 `define TILE_BPP 2
`endif
`ifndef TILE_L
 `define TILE_L 15
`endif
`ifndef TILE_P_ACC
 `define TILE_P_ACC 99
`endif
`ifndef TILE_M_E
 `define TILE_M_E 3
`endif
`ifndef TILE_D_COL
 `define TILE_D_COL 4
`endif
`ifndef TILE_ACC
 `define TILE_ACC 19
`endif
`ifndef TILE_THR_W
 `define TILE_THR_W 19
`endif
`ifndef TILE_LOTMAX
 `define TILE_LOTMAX 4
`endif
`ifndef TILE_BA
 `define TILE_BA 4
`endif
`ifndef TILE_BW
 `define TILE_BW 4
`endif
`ifndef TILE_T
 `define TILE_T 15
`endif
`ifndef TILE_OUT_W
 `define TILE_OUT_W (`TILE_BA * `TILE_K)
`endif
`ifndef TILE_L_MAC
 `define TILE_L_MAC 4
`endif
`ifndef TILE_M
 `define TILE_M 2
`endif
`ifndef TILE_MAC_CUT_A
 `define TILE_MAC_CUT_A 5
`endif
`ifndef TILE_MAC_CUT_B
 `define TILE_MAC_CUT_B 15
`endif
`ifndef TILE_MAC_CUT_C
 `define TILE_MAC_CUT_C 0
`endif
`ifndef TILE_MAC_TREE
 `define TILE_MAC_TREE 1
`endif
`ifndef TILE_MAC_MODEL
 `define TILE_MAC_MODEL 2
`endif
`ifndef TILE_FINAL_ADDER
 `define TILE_FINAL_ADDER 0
`endif
`ifndef TILE_WIN_LOAD
 `define TILE_WIN_LOAD 1
`endif
`ifndef TILE_REG_COPIES
 `define TILE_REG_COPIES 1
`endif
`ifndef TILE_THR_FMT
 `define TILE_THR_FMT 0
`endif
`ifndef TILE_COL_FMT
 `define TILE_COL_FMT 0
`endif
`ifndef TILE_OUT_BUF
 `define TILE_OUT_BUF 0
`endif
// fin du bloc des défauts

/* Mot PASSE (spec/03_interfaces.md section 4.6) : les largeurs
 * de champ suivent L, P_ACC et LOTMAX, les positions suivent les largeurs depuis le bit 16, dans l'ordre
 * de la spécification, et le dernier champ doit finir dans les 64 bits bas du mot, ce que param_check
 * vérifie. Au jeu L122 (L = 122, P_ACC = 197), ces positions redonnent celles de la spécification.
 * Un champ garde au moins un bit, d'où le terme 2 / (LOTMAX + 1), qui vaut 1 à LOTMAX = 1 et 0 au-delà,
 * sans comparaison d'un bit qu'un lint relèverait.
 * Les largeurs de ncols, lot et npix, les positions et la fin sont dérivées : elles n'ont pas de ifndef,
 * une grandeur dérivée ne se surcharge nulle part. -DTILE_<NOM> y redéfinit la macro, Icarus
 * (redefinition of macro) et Verilator (DEFOVERRIDE) le signalent et la valeur de l'en-tête l'emporte,
 * params.py le refuse. hdr_rows et hdr_pass_id sont des constantes, surchargeables. */
`define TILE_HDR_NCOLS_W $clog2(`TILE_L + 1)
`ifndef TILE_HDR_ROWS_W
 `define TILE_HDR_ROWS_W 9
`endif
`define TILE_HDR_LOT_W ($clog2(`TILE_LOTMAX) + 2 / (`TILE_LOTMAX + 1))
`define TILE_HDR_NPIX_W $clog2(`TILE_P_ACC + 1)
`ifndef TILE_HDR_PASS_ID_W
 `define TILE_HDR_PASS_ID_W 16
`endif
`define TILE_HDR_STRIDE_POS 16
`define TILE_HDR_NCOLS_POS (`TILE_HDR_STRIDE_POS + 1)
`define TILE_HDR_ROWS_POS (`TILE_HDR_NCOLS_POS + `TILE_HDR_NCOLS_W)
`define TILE_HDR_LOT_POS (`TILE_HDR_ROWS_POS + `TILE_HDR_ROWS_W)
`define TILE_HDR_TOP_POS (`TILE_HDR_LOT_POS + `TILE_HDR_LOT_W)
`define TILE_HDR_FIRST_POS (`TILE_HDR_TOP_POS + 1)
`define TILE_HDR_LAST_POS (`TILE_HDR_TOP_POS + 2)
`define TILE_HDR_WGT_POS (`TILE_HDR_TOP_POS + 3)
`define TILE_HDR_THR_POS (`TILE_HDR_TOP_POS + 4)
`define TILE_HDR_NPIX_POS (`TILE_HDR_TOP_POS + 5)
`define TILE_HDR_PASS_ID_POS (`TILE_HDR_NPIX_POS + `TILE_HDR_NPIX_W)
`define TILE_HDR_END (`TILE_HDR_PASS_ID_POS + `TILE_HDR_PASS_ID_W)

`endif
