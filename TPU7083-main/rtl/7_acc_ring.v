`ifndef __ACC_RING__
`define __ACC_RING__

`include "00_params.vh"
`include "00_variantes.vh"

/* Anneau d'accumulateurs ⑥ et registre de capture
 * (spec/09_accumulation.md sections 2 à 5, contrat 7 de
 * rtl/contrats.md, amendé pour la variante G1 par
 * dépôt de travail non publié).
 *
 * CE BLOC N'EXÉCUTE QUE DES PAS. La règle de saut, un saut après la fenêtre n si
 * n mod (R - 1) < P_ACC - R, et sa période R - 1 vivent dans le contrôle
 * (spec/12_controle.md section 4.2). Un échange et un saut sont
 * ici le même pas : seul le acc_win qui suit un échange fait entrer la tête dans la capture, et le
 * mot de tête d'un saut est abandonné.
 *
 * LA BOUCLE COMPTE L_E + 1 MOTS AVEC LA CAPTURE. L'anneau a L_E = P_ACC - 1 positions, la capture
 * tient le mot du pixel en cours, et la tête r_head, colonne 259 de la spécification, n'est qu'un
 * transit : sans saut, le mot d'un pixel revient dans la capture P_ACC fenêtres plus tard.
 * Un anneau de P_ACC positions ferait une boucle de P_ACC + 1 mots, et un mot oisif serait lu comme
 * somme partielle dès la deuxième tranche
 * (spec/09_accumulation.md section 7).
 *
 * LA VERSION EN BASCULES REPRODUIT LES PHASES AUX PORTS. Les colonnes à trous de la section 4.1
 * avancent par phases de classe 3, 2, 1 puis 0, une par cycle sur M_E cycles, et leur réalisation
 * relève de la version structurelle. Ici la tête et les positions 1 à L_E - 1 bougent au front du
 * cycle de acc_step, et la position 0 prend la capture au front de sa phase de classe 0,
 * ENTRY_DELAY = M_E - 1 cycles plus tard : sur un échange, c'est le cycle de acc_win, où la capture
 * tient encore le mot complet de la fenêtre précédente. Entre les deux fronts, la position 0 est le
 * trou, sa valeur déjà recopiée en position 1.
 *
 * LE PIÈGE, ET IL EST SILENCIEUX. La remise à zéro de la première tranche porte sur l'opérande de
 * l'additionneur, jamais sur la capture : remettre la capture à zéro écraserait le groupe ajouté au
 * même cycle (13_accumulate.v, dépôt de travail non publié l'explique en tête).
 * acc_first et acc_last ne sont lus qu'au cycle de acc_win, puis tenus pendant les G_PASS - 1 mises à
 * jour qui suivent, le contrôle étant libre de les changer dès le cycle suivant.
 *
 * LA VARIANTE G1, G1 NI NUL NI ÉGAL À G.
 * Une fenêtre d'une passe au pas 1 dure G_S1 = G1 cycles, une fenêtre d'une passe au pas 2 G cycles : c'est son
 * G_PASS, lu sur i_acc_stride1 au cycle de acc_win comme acc_first et acc_last, puis tenu par r_stride1.
 * L'anneau, la tête et la capture tiennent G_MAX = max(G, G_S1) cases de K ACC bits, mais une fenêtre ne fait
 * tourner que ses G_PASS premières cases.
 * La somme entre en case G_PASS - 1, par le mux2 de fermeture de la case G_LOW - 1 quand la fenêtre est au plus
 * petit G_PASS, et les cases G_PASS à G_MAX - 1 de la capture gardent alors leur valeur
 * (spec/09_accumulation.md sections 3.3 et 4.5,
 * branche spec-generale).
 * acc_done tombe G_PASS cycles après acc_win, et o_done_stride1 rend à ⑦ le pas de la fenêtre au même cycle.
 * o_acc_word porte les K G_PASS sommes de la fenêtre dans ses bits bas, et ses bits au-delà de K G_PASS ACC sont
 * sans usage : ⑦ ne lit que les K G_PASS premiers canaux, G_PASS tiré de o_done_stride1.
 * Hors variante G1, G_PASS vaut G = G_MAX à toute fenêtre, i_acc_stride1 est ignoré et o_done_stride1 vaut 0.
 *
 * La somme replie sur ACC bits, filtre par filtre, comme le modèle de référence :
 * ni saturation ni bit de garde. Seuls les deux compteurs et acc_done ont un reset : l'anneau, la
 * tête, la capture et le pas tenu sont réécrits avant tout usage, la première tranche ignorant ce qu'elle lit.
 * UPD_REST et ENTRY_DELAY ne sont pas des réglages : ce sont les constantes du contrat,
 * en paramètres pour que la largeur de leur compteur les suive.
 *
 * TRANCHES, REP = K.
 * Sous DIFF_SLICE = 1 hors variante G1, chaque commande arrive en REP = K copies, une par tranche.
 * La tranche s (REP = K) possède les bits g*K*ACC + s*ACC +: ACC de chaque mot pour g de 0 à G − 1 (r_head, r_ring[i],
 * r_capture) et le filtre s de w_sum.
 * Elle a ses propres r_upd_left, r_entry_left, r_first, r_last, w_update, w_entry_load, w_source, w_first et
 * w_operand, pilotés par l'entrée [s].
 * r_stride1 n'existe qu'à REP = 1, sous la variante G1.
 * La rotation {w_sum, w_source[WORD_W-1:K*ACC]} ne mêle pas les filtres, d'où des tranches fermées.
 * o_acc_done et o_done_stride1 viennent de la tranche 0, o_acc_word se réassemble dans l'ordre d'origine des bits.
 * REP = 1 rend le module d'origine.
 */

module acc_ring #(parameter K           = `TILE_K,
                  parameter G           = `TILE_G,
                  parameter G1          = `TILE_G1,
                  parameter ACC         = `TILE_ACC,
                  parameter P_ACC       = `TILE_P_ACC,
                  parameter M_E         = `TILE_M_E,
                  parameter G_S1        = groups_stride1(G, G1),
                  parameter G_MAX       = groups_max(G, G1),
                  parameter L_E         = P_ACC - 1,
                  parameter WORD_W      = K * G_MAX * ACC,
                  parameter UPD_REST    = G_MAX - 1,
                  parameter UPD_W       = $clog2(UPD_REST + 1),
                  parameter ENTRY_DELAY = M_E - 1,
                  parameter ENTRY_W     = $clog2(ENTRY_DELAY + 1),
                  parameter ROWS        = (`TILE_FINAL_ADDER == 5) ? 2 : 1,
                  parameter REP         = (`TILE_DIFF_SLICE != 0 && G1 == 0) ? K : 1)
                 (input               i_clk,
                  input               i_rst_n,
                  input  [ROWS*K*ACC-1:0] i_mac_sum,
                  input  [REP-1:0]    i_acc_win,
                  input  [REP-1:0]    i_acc_step,
                  input  [REP-1:0]    i_acc_first,
                  input  [REP-1:0]    i_acc_last,
                  output [WORD_W-1:0] o_acc_word,
                  output              o_acc_done,
                  input  [REP-1:0]    i_acc_stride1,
                  output              o_done_stride1);

    `include "00_groups.vh"

    localparam FILTERS = K / REP;
    localparam FIELD   = FILTERS * ACC;

    reg  [L_E*WORD_W-1:0]  r_ring;
    reg  [WORD_W-1:0]      r_head;
    reg  [WORD_W-1:0]      r_capture;
    reg  [REP-1:0]         r_first;
    reg  [REP-1:0]         r_last;
    reg  [REP*UPD_W-1:0]   r_upd_left;
    reg  [REP*ENTRY_W-1:0] r_entry_left;
    reg                    r_done;

    /* Seul r_last[0] fait r_done, o_acc_done venant de la tranche 0 : les r_last des autres tranches ne servent pas. */
    /* verilator lint_off UNUSEDSIGNAL */
    wire w_last_ignored = ^r_last;
    /* verilator lint_on UNUSEDSIGNAL */

    wire [REP-1:0]         w_update;
    wire [REP-1:0]         w_entry_load;
    wire [WORD_W-1:0]      w_source;
    wire [K*ACC-1:0]       w_operand;
    wire [K*ACC-1:0]       w_sum;
    wire [WORD_W-1:0]      w_rotate_max = {w_sum, w_source[WORD_W-1:K*ACC]};
    wire [WORD_W-1:0]      w_capture_next;
    wire [UPD_W-1:0]       w_upd_rest;

    function integer field_base(input integer group, input integer slice);
        field_base = (group * K + slice * FILTERS) * ACC;
    endfunction

    genvar filter;
    genvar slice_idx;
    genvar group_idx;
    genvar word_idx;

    /* Sous ROWS = 2 (FINAL_ADDER = 5), i_mac_sum porte les deux rangées de la réduction de chaque filtre, la rangée r du
     * filtre k en [(r × K + k) × ACC +: ACC] : une rangée de 3:2 les réduit avec l'opérande à deux mots, que
     * l'additionneur ajoute (Hoang et al. 2010). C'est de la logique, l'anneau garde un mot par somme. */
    generate
        for (filter = 0; filter < K; filter = filter + 1)
            begin : g_adder
                if (ROWS == 2)
                    begin : g_carry_save
                        wire [ACC-1:0] w_a     = w_operand[filter*ACC +: ACC];
                        wire [ACC-1:0] w_x     = i_mac_sum[filter*ACC +: ACC];
                        wire [ACC-1:0] w_y     = i_mac_sum[(K + filter)*ACC +: ACC];
                        wire [ACC-1:0] w_half  = w_a ^ w_x ^ w_y;
                        wire [ACC-2:0] w_major = (w_a[ACC-2:0] & w_x[ACC-2:0]) | (w_a[ACC-2:0] & w_y[ACC-2:0])
                                                 | (w_x[ACC-2:0] & w_y[ACC-2:0]);

                        assign w_sum[filter*ACC +: ACC] = w_half + {w_major, 1'b0};
                    end
                else
                    begin : g_two_operands
                        assign w_sum[filter*ACC +: ACC] = w_operand[filter*ACC +: ACC] + i_mac_sum[filter*ACC +: ACC];
                    end
            end
    endgenerate

    /* La case 0 de la source passe à l'additionneur et la somme entre en case G_PASS - 1 : après G_PASS mises à
     * jour, chaque case de 0 à G_PASS - 1 est revenue à sa place avec son groupe ajouté.
     * w_rotate_max ferme la rotation en case G_MAX - 1, celle de toute fenêtre hors variante G1. */
    generate
        if (G_S1 != G)
            begin : g_stride
                reg               r_stride1;
                wire              w_stride1    = i_acc_win ? i_acc_stride1 : r_stride1;
                wire              w_close_low  = (G_S1 < G) ? w_stride1 : !w_stride1;
                wire [WORD_W-1:0] w_rotate_low = {r_capture[WORD_W-1:groups_low(G, G1)*K*ACC], w_sum,
                                                  w_source[groups_low(G, G1)*K*ACC-1:K*ACC]};

                /* Le mux2 de fermeture de la case G_LOW - 1 y fait entrer la somme quand la fenêtre est au plus
                 * petit G_PASS, et les cases G_LOW à G_MAX - 1 gardent alors leur valeur. */
                assign w_capture_next = w_close_low ? w_rotate_low : w_rotate_max;
                assign w_upd_rest     = w_stride1 ? UPD_W'(G_S1 - 1) : UPD_W'(G - 1);

                always @(posedge i_clk)
                    if (i_acc_win)
                        r_stride1 <= i_acc_stride1;

                /* Le acc_win suivant vient au plus tôt au cycle de acc_done : r_stride1 y tient encore le pas de la
                 * fenêtre qui finit. */
                assign o_done_stride1 = r_stride1;
            end
        else
            begin : g_uniform
                assign w_capture_next = w_rotate_max;
                assign w_upd_rest     = UPD_REST[UPD_W-1:0];
                assign o_done_stride1 = 1'b0;

                /* Hors variante G1, G_PASS vaut G à toute fenêtre : le pas n'y choisit rien. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_stride_ignored = ^i_acc_stride1;
                /* verilator lint_on UNUSEDSIGNAL */
            end
    endgenerate

    /* Tranche s : filtres s FILTERS à (s + 1) FILTERS - 1 de chaque groupe, et ses compteurs, pilotés par l'entrée [s].
     * La rotation ne mêle pas les filtres : chaque tranche se ferme sur elle-même. */
    generate
        for (slice_idx = 0; slice_idx < REP; slice_idx = slice_idx + 1)
            begin : g_slice
                wire [UPD_W-1:0]   w_upd_left   = r_upd_left[slice_idx*UPD_W +: UPD_W];
                wire [ENTRY_W-1:0] w_entry_left = r_entry_left[slice_idx*ENTRY_W +: ENTRY_W];
                wire               w_first      = i_acc_win[slice_idx] ? i_acc_first[slice_idx] : r_first[slice_idx];

                assign w_update[slice_idx]     = i_acc_win[slice_idx] || w_upd_left != 0;
                assign w_entry_load[slice_idx] = w_entry_left == 1;
                assign w_operand[slice_idx*FIELD +: FIELD]
                    = w_first ? {FIELD{1'b0}} : w_source[slice_idx*FIELD +: FIELD];

                for (group_idx = 0; group_idx < G_MAX; group_idx = group_idx + 1)
                    begin : g_group
                        assign w_source[field_base(group_idx, slice_idx) +: FIELD]
                            = i_acc_win[slice_idx] ? r_head[field_base(group_idx, slice_idx) +: FIELD]
                                                   : r_capture[field_base(group_idx, slice_idx) +: FIELD];

                        always @(posedge i_clk)
                            begin
                                if (i_acc_step[slice_idx])
                                    r_head[field_base(group_idx, slice_idx) +: FIELD]
                                        <= r_ring[(L_E-1)*WORD_W + field_base(group_idx, slice_idx) +: FIELD];
                                if (w_update[slice_idx])
                                    r_capture[field_base(group_idx, slice_idx) +: FIELD]
                                        <= w_capture_next[field_base(group_idx, slice_idx) +: FIELD];
                            end

                        for (word_idx = 0; word_idx < L_E; word_idx = word_idx + 1)
                            begin : g_word
                                if (word_idx == 0)
                                    begin : g_entry
                                        always @(posedge i_clk)
                                            if (w_entry_load[slice_idx])
                                                r_ring[field_base(group_idx, slice_idx) +: FIELD]
                                                    <= r_capture[field_base(group_idx, slice_idx) +: FIELD];
                                    end
                                else
                                    begin : g_shift
                                        always @(posedge i_clk)
                                            if (i_acc_step[slice_idx])
                                                r_ring[word_idx*WORD_W + field_base(group_idx, slice_idx) +: FIELD]
                                                    <= r_ring[(word_idx-1)*WORD_W + field_base(group_idx, slice_idx) +: FIELD];
                                    end
                            end
                    end

                always @(posedge i_clk)
                    if (i_acc_win[slice_idx])
                        begin
                            r_first[slice_idx] <= i_acc_first[slice_idx];
                            r_last[slice_idx]  <= i_acc_last[slice_idx];
                        end

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        begin
                            r_upd_left[slice_idx*UPD_W +: UPD_W]       <= {UPD_W{1'b0}};
                            r_entry_left[slice_idx*ENTRY_W +: ENTRY_W] <= {ENTRY_W{1'b0}};
                        end
                    else
                        begin
                            if (i_acc_win[slice_idx])
                                r_upd_left[slice_idx*UPD_W +: UPD_W] <= w_upd_rest;
                            else if (w_upd_left != 0)
                                r_upd_left[slice_idx*UPD_W +: UPD_W] <= w_upd_left - 1'b1;
                            if (i_acc_step[slice_idx])
                                r_entry_left[slice_idx*ENTRY_W +: ENTRY_W] <= ENTRY_DELAY[ENTRY_W-1:0];
                            else if (w_entry_left != 0)
                                r_entry_left[slice_idx*ENTRY_W +: ENTRY_W] <= w_entry_left - 1'b1;
                        end
            end
    endgenerate

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_done <= 1'b0;
        else
            r_done <= r_last[0] && r_upd_left[UPD_W-1:0] == 1;

    assign o_acc_word = r_capture;
    assign o_acc_done = r_done;

endmodule

`endif
