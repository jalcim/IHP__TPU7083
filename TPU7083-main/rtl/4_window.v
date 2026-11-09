`ifndef __WINDOW_REG__
`define __WINDOW_REG__

`include "00_params.vh"
`include "00_variantes.vh"

/* Copie de ② par filtre, WIN_COPIES > 1 (contrat 4 et section C de rtl/contrats.md, spec/06_fenetre.md section 8).
 *
 * POURQUOI UNE COPIE PAR FILTRE. Une ② unique attaque les K filtres de ⑥ : le fil long, de ses sorties aux
 * multiplieurs, a toute la logique de l'étage 1 des MAC derrière lui. Chaque filtre lit sa copie, posée près de lui,
 * et le fil long passe aux sources de ②, prises de ① et ligne ③, qui n'ont devant la copie qu'une AO22 au plus.
 *
 * SANS ÉTAGE DE PLUS. La copie capture au même front que ② au front (WIN_LOAD = 1, contrat D.1), celui qui clôt le
 * cycle W du win_load, et sa sortie vaut ses cases à tout cycle : les MAC voient la même fenêtre aux mêmes cycles,
 * L_MAC et le calendrier ne changent pas.
 *
 * COMMANDES ANTICIPÉES D'UN CYCLE. Le choix du haut et l'ouverture viennent de u_seq, loin de la plupart des copies.
 * Chaque copie les prend en registre au front d'avant, r_pick_stage, r_pick_line et r_open, si bien que ce fil long
 * a un cycle entier devant une bascule et que le haut ne passe plus que par une AO22 sur registres. top_sel et
 * top_zero valent au cycle W − 1 ceux du win_load, et i_win_open_early, o_win_open_early du séquenceur, annonce
 * o_win_open d'un cycle. Il peut retomber un cycle tard : la copie capture encore à W + 1, où sources et haut égalent
 * ceux de W, aucun col_shift ne tombant au cycle d'un win_load (en-tête de rtl/10b_sequencer.v, ② OUVERTE PAR
 * AVANCE).
 *
 * KEEP_HIERARCHY. Les K copies ont mêmes entrées, même horloge et même activation : un flot qui aplatit avant
 * d'optimiser les réunirait par opt_merge en une seule, et le fil long reviendrait. L'attribut garde chaque copie.
 *
 * AUCUN RESET, comme les cases de window_reg : r_open vaut x avant le premier front, et rien ne lit une copie avant
 * le premier win_load. */

(* keep_hierarchy *)
module window_copy #(parameter C       = `TILE_C,
                     parameter BA      = `TILE_BA,
                     parameter COL_FMT = `TILE_COL_FMT,
                     parameter PIX_W   = C * BA,
                     parameter COL_W   = (COL_FMT == 2) ? 2 * PIX_W : 3 * PIX_W)
                    (input                i_clk,
                     input  [3*COL_W-1:0] i_fifo_tap,
                     input  [3*PIX_W-1:0] i_line_out,
                     input                i_top_sel,
                     input                i_top_zero,
                     input                i_win_open_early,
                     output [9*PIX_W-1:0] o_win_data);

    wire [3*PIX_W-1:0] w_top_row;
    wire [3*PIX_W-1:0] w_a_row;
    wire [3*PIX_W-1:0] w_b_row;
    wire [9*PIX_W-1:0] w_next;
    reg                r_pick_line;
    reg                r_open;
    reg  [9*PIX_W-1:0] r_copy_cells;

    genvar col;

    always @(posedge i_clk)
        r_open <= i_win_open_early;

    generate
        /* En (fh, aligned), l'étage n'a pas d'emplacement C : le haut est la ligne ③ ou zéro, top_sel ignoré. */
        if (COL_FMT == 2)
            begin : g_aligned
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_top_sel_ignored = i_top_sel;
                /* verilator lint_on UNUSEDSIGNAL */

                always @(posedge i_clk)
                    r_pick_line <= ~i_top_zero;

                for (col = 0; col < 3; col = col + 1)
                    begin : g_top
                        assign w_top_row[col*PIX_W +: PIX_W] = i_line_out[col*PIX_W +: PIX_W] & {PIX_W{r_pick_line}};
                    end
            end
        else
            begin : g_stage_top
                reg r_pick_stage;

                always @(posedge i_clk)
                    begin
                        r_pick_stage <= i_top_sel & ~i_top_zero;
                        r_pick_line  <= ~i_top_sel & ~i_top_zero;
                    end

                for (col = 0; col < 3; col = col + 1)
                    begin : g_top
                        assign w_top_row[col*PIX_W +: PIX_W] =
                            (i_fifo_tap[col*COL_W + 2*PIX_W +: PIX_W] & {PIX_W{r_pick_stage}})
                            | (i_line_out[col*PIX_W +: PIX_W] & {PIX_W{r_pick_line}});
                    end
            end

        for (col = 0; col < 3; col = col + 1)
            begin : g_column
                assign w_a_row[col*PIX_W +: PIX_W] = i_fifo_tap[col*COL_W +: PIX_W];
                assign w_b_row[col*PIX_W +: PIX_W] = i_fifo_tap[col*COL_W + PIX_W +: PIX_W];
            end
    endgenerate

    assign w_next = {w_b_row, w_a_row, w_top_row};

    always @(posedge i_clk)
        if (r_open)
            r_copy_cells <= w_next;

    assign o_win_data = r_copy_cells;

endmodule

/* Registre de fenêtre ② et choix du haut (spec/06_fenetre.md sections 2 à 5,
 * spec/05_memoire_ligne.md section 3.4).
 *
 * POURQUOI UNE COPIE. ② tient devant les multiplieurs une fenêtre 3 × 3 de C canaux pendant les G cycles où les
 * G groupes de poids de l'anneau ④ défilent devant elle. Pendant ce temps, les prises de ① et la ligne ③ avancent
 * déjà vers la fenêtre suivante : ② découple les deux chemins. La fenêtre ne se décale pas elle-même, elle recopie
 * les prises de ①, qui ont avancé de s colonnes. Ses sources sont donc fixes, sans aucun mux de chargement par
 * colonne, et seul le haut choisit (spec/06_fenetre.md section 3).
 *
 * SOURCES DES CASES. La colonne c vient de l'étage c + 1 de ①, la colonne 0 étant la plus ancienne. La rangée
 * physique 1 vient des emplacements A, la rangée 2 des B, la rangée 0, le haut, de C, de line_out ou de zéro.
 * Le choix du haut tient en 3 PIX_W mux2 et 3 PIX_W and2 : C à la première rangée d'une passe à halo haut réel
 * (top_sel), zéro à la première rangée d'une passe au bord et de chaque carte d'un lot (top_zero), la ligne ③
 * sinon (spec/05_memoire_ligne.md section 4.2). Sans lui, la ligne du haut
 * d'une passe devrait d'abord amorcer ③, et les MAC attendraient.
 *
 * FORMAT (fh, aligned), COL_FMT = 2, contrat 4 amendé de
 * rtl/contrats.md. Chaque colonne arrive en une seule unité AB, sans
 * C, et les étages de ① n'ont que A et B, COL_W valant 2 PIX_W
 * (verif/lectures.md trou 23). Le haut est donc la ligne ③, ou zéro
 * sous top_zero : ni emplacement C ni mux2, seuls les 3 PIX_W and2 restent sur le chargement, et top_sel est ignoré.
 *
 * ORIENTATION DU NOYAU. La rangée physique 0 porte la ligne d'image y − 1 au pas 1 et 2y − 1 au pas 2, la
 * rangée 1 (A) y et 2y + 1, la rangée 2 (B) y + 1 et 2y. Au pas 2, A et B font donc face aux lignes de noyau
 * ky = 2 et ky = 1. La tuile ne sait rien de cette permutation, portée par les poids : l'anneau ④ présente à la
 * prise (r, kx) le poids que le FPGA y a rangé, et le FPGA exporte les noyaux du pas 2 avec leurs lignes ky = 1
 * et ky = 2 échangées. Les colonnes ne permutent pas, kx = c aux deux pas
 * (spec/06_fenetre.md section 3).
 *
 * ② OUVERTE. i_win_open, o_win_open du séquenceur, est haut au cycle W de chaque win_load et bas de W + 1 à
 * W + G_PASS − 1, tant que les MAC tiennent la fenêtre. Ailleurs il est haut aussi : ② recharge et se montre
 * transparente sans que ⑥ lise de somme. Registré, il ôte le cône de win_load de l'étage 1 des MAC et des validations
 * des cases (point 4_window.v:258 de la revue du RTL d'af5ab629). Un banc de bloc peut le tenir haut au seul cycle W.
 *
 * CHARGEMENT TRANSPARENT, WIN_LOAD = 0, et WIN_LOAD = 2, où le registre d'opérandes suit ② restée transparente
 * (contrats D.1 et D.2 de rtl/contrats.md). Au cycle W + g, le premier
 * étage des MAC multiplie la fenêtre capturée au cycle W par le groupe g de ④
 * (spec/08_mac.md section 4) : le groupe 0 passe au cycle
 * même du win_load (spec/12_controle.md section 4.2). o_win_data vaut donc
 * w_next aux cycles où ② est ouverte, celui du win_load compris, et les cases ensuite. Vue un cycle plus tard, la
 * nouvelle fenêtre laisserait le groupe 0 multiplier l'ancienne. Ce qui le permet : ① et ③ sont stables pendant ce cycle, aucun col_shift n'y
 * tombe (spec/05_memoire_ligne.md section 5). Ce que cela coûte : les mux2
 * et and2 du haut sont sur l'étage 1 des MAC au cycle de win_load, contrat 4 corrigé de
 * rtl/contrats.md. Il périme le « hors chemin des MAC » de
 * spec/05_memoire_ligne.md section 3.4 et de
 * spec/06_fenetre.md section 6. En bascules, la transparence passe par un
 * mux2 de sortie, sa réalisation en tlatch relève de la version structurelle
 * (rtl/00_conception.md section 2).
 *
 * CAPTURE AU FRONT, WIN_LOAD = 1, contrat D.1 de rtl/contrats.md. Les
 * cases prennent w_next au front qui clôt le cycle W du win_load, comme sous la transparence, et o_win_data vaut les
 * cases à tout cycle, sans mux2 de sortie : les MAC voient la fenêtre de W + 1 à W + G_PASS, le front qui clôt
 * W + G_PASS, où ② peut déjà être ouverte, ne la remplaçant qu'après sa dernière lecture. Elles y
 * multiplient le groupe g de ④ au cycle W + 1 + g, la rotation de ④ suivant d'un cycle (contrat D.4). Le choix du haut et le maître de ②
 * travaillent alors dans le cycle du win_load, hors de l'étage 1 des MAC, et l'étage de ② compte dans L_MAC
 * (spec/06_fenetre.md section 3.1, branche spec-suites).
 *
 * COPIES PAR FILTRE, WIN_COPIES > 1, contrat 4. WIN_COPIES copies window_copy remplacent le corps de ②, capturées au
 * même front, la copie c en o_win_data[c*9*PIX_W +: 9*PIX_W], i_win_open ignoré. param_check ne les admet qu'au
 * front, de 1 à K. À WIN_COPIES = 1, i_win_open_early est ignoré et le corps reste celui d'une ② unique.
 *
 * AUCUN RESET. Avant le premier win_load les cases sont indéfinies, et rien ne les consomme : sans fenêtre, les
 * registres des MAC prennent ce qui se présente et ⑥ ne l'utilise pas
 * (spec/08_mac.md section 4). */

module window_reg #(parameter C          = `TILE_C,
                    parameter BA         = `TILE_BA,
                    parameter COL_FMT    = `TILE_COL_FMT,
                    parameter WIN_LOAD   = `TILE_WIN_LOAD,
                    parameter WIN_COPIES = `TILE_WIN_COPIES,
                    parameter PIX_W      = C * BA,
                    parameter COL_W      = (COL_FMT == 2) ? 2 * PIX_W : 3 * PIX_W)
                   (input                           i_clk,
                    input  [3*COL_W-1:0]            i_fifo_tap,
                    input  [3*PIX_W-1:0]            i_line_out,
                    input                           i_top_sel,
                    input                           i_top_zero,
                    input                           i_win_open,
                    input                           i_win_open_early,
                    output [WIN_COPIES*9*PIX_W-1:0] o_win_data);

    genvar column;
    genvar copy;

    generate
        if (WIN_COPIES > 1 && WIN_LOAD == 1)
            begin : g_copies
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_win_open_ignored = i_win_open;
                /* verilator lint_on UNUSEDSIGNAL */

                for (copy = 0; copy < WIN_COPIES; copy = copy + 1)
                    begin : g_copy
                        window_copy #(.C(C), .BA(BA), .COL_FMT(COL_FMT)) u_copy (
                            .i_clk(i_clk), .i_fifo_tap(i_fifo_tap), .i_line_out(i_line_out), .i_top_sel(i_top_sel),
                            .i_top_zero(i_top_zero), .i_win_open_early(i_win_open_early),
                            .o_win_data(o_win_data[copy*9*PIX_W +: 9*PIX_W]));
                    end
            end
        else
            begin : g_single
                wire [3*PIX_W-1:0] w_row_top;
                wire [3*PIX_W-1:0] w_row_a;
                wire [3*PIX_W-1:0] w_row_b;
                wire [9*PIX_W-1:0] w_next;
                reg  [9*PIX_W-1:0] r_cells;

                /* verilator lint_off UNUSEDSIGNAL */
                wire w_win_open_early_ignored = i_win_open_early;
                /* verilator lint_on UNUSEDSIGNAL */

                for (column = 0; column < 3; column = column + 1)
                    begin : g_column
                        wire [COL_W-1:0] w_stage = i_fifo_tap[column*COL_W +: COL_W];
                        wire [PIX_W-1:0] w_line  = i_line_out[column*PIX_W +: PIX_W];

                        if (COL_FMT == 2)
                            begin : g_line_top
                                assign w_row_top[column*PIX_W +: PIX_W] = w_line & {PIX_W{~i_top_zero}};
                            end
                        else
                            begin : g_top_mux
                                wire [PIX_W-1:0] w_top_pick = i_top_sel ? w_stage[2*PIX_W +: PIX_W] : w_line;

                                assign w_row_top[column*PIX_W +: PIX_W] = w_top_pick & {PIX_W{~i_top_zero}};
                            end

                        assign w_row_a[column*PIX_W +: PIX_W] = w_stage[0 +: PIX_W];
                        assign w_row_b[column*PIX_W +: PIX_W] = w_stage[PIX_W +: PIX_W];
                    end

                /* En (fh, aligned), l'étage n'a pas d'emplacement C : top_sel n'a rien à choisir, il est ignoré. */
                if (COL_FMT == 2)
                    begin : g_aligned
                        /* verilator lint_off UNUSEDSIGNAL */
                        wire w_top_sel_ignored = i_top_sel;
                        /* verilator lint_on UNUSEDSIGNAL */
                    end

                assign w_next = {w_row_b, w_row_a, w_row_top};

                always @(posedge i_clk)
                    if (i_win_open)
                        r_cells <= w_next;

                if (WIN_LOAD == 1)
                    begin : g_front
                        assign o_win_data = r_cells;
                    end
                else
                    begin : g_transparent
                        assign o_win_data = i_win_open ? w_next : r_cells;
                    end
            end
    endgenerate

endmodule

`endif
