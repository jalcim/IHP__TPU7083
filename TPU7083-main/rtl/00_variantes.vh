`ifndef __VARIANTES__
`define __VARIANTES__

/* Variantes de la tuile qui n'entrent pas encore aux jeux des accords : leurs valeurs ne passent ni par
 * test/accord_sets.py ni par test/model/params.py, qui ne lisent que 00_params.vh, et une suite entière se joue sous une
 * autre valeur par la variable de cache RTL_EXTRA_DEFINES de CMakeLists.txt (-DTILE_THR_SHARE=1).
 * THR_SHARE, forme de ⑦ (rtl/8_threshold.v) : 0, la forme cardinale, K G_MAX
 * canaux comparés au cycle T + 1 puis sérialisés ; 1, le partage dans le temps, K canaux par cycle, les seuils du groupe
 * courant lus dans les banques par un et-ou décodé (levier technique du 21/10/2026, étude du partage dans le temps de ⑦). L'adoption comme
 * défaut se décide après la synthèse de la tuile réunie, et le paramètre rejoint alors 00_params.vh.
 * Écart à cette règle, nommé par le plan des coupes de pipeline du 28/10/2026 : DIFF_DEPTH et DIFF_SLICE prennent leur
 * défaut avant la synthèse de la tuile réunie, la tuile restant égale au cycle près à celle sans arbre ni tranche
 * (jumeau DIFF0 de test/cmake/18_diffusions.cmake). La synthèse de la tuile les révise. */
`ifndef TILE_THR_SHARE
 `define TILE_THR_SHARE 0
`endif
/* DIFF_DEPTH, profondeur des arbres de diffusion des activations : 3, celle que le relevé des distances du P&R
 * p2c-A tire pour acc_win, de u_seq à la plus lointaine tranche de ⑥, bornée à L_MAC - 1 (plan des coupes du
 * 28/10/2026). */
`ifndef TILE_DIFF_DEPTH
 `define TILE_DIFF_DEPTH 3
`endif
/* DIFF_SLICE, consommateurs des diffusions en tranches, à une ICG par tranche : 1. */
`ifndef TILE_DIFF_SLICE
 `define TILE_DIFF_SLICE 1
`endif
/* WIN_COPIES, copies de ② par filtre, 1 sans copie. */
`ifndef TILE_WIN_COPIES
 `define TILE_WIN_COPIES 1
`endif
/* THR_CUT : 0, comparaisons au cycle T + 1 sur le registre de maintien ; 1, comparaisons au cycle T de acc_done et
 * registre r_crossed avant le compteur de bits, thr_xfer avancé d'un cycle, sortie inchangée, forme cardinale seule
 * (section D du plan des coupes du 28/10/2026), adoption comme défaut après la STA puis le P&R. */
`ifndef TILE_THR_CUT
 `define TILE_THR_CUT 0
`endif

`endif
