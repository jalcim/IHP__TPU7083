`ifndef __COLUMN_ASM__
`define __COLUMN_ASM__

`include "00_params.vh"

/* Assembleur de colonnes : l'étage D_COL de la file ①, en trois formats de colonnes choisis par COL_FMT.
 *
 * FORMAT EN UNITÉS, COL_FMT = 0, (3l, cc).
 * L'étage D_COL tient les emplacements A et B de la colonne en cours de réception (r_ab).
 * Une unité AB s'y écrit mot par mot, chaque mot à sa position fixe, par sa seule validation :
 * aucun registre intermédiaire et aucun multiplexeur ne réaligne les données
 * (spec/03_interfaces.md section 3.5,
 * spec/05_memoire_ligne.md section 3.1).
 * Le C d'une colonne à 3 lignes vient de la tête du registre CC (r_cc0), câblée sur le champ C de col_data.
 *
 * POURQUOI UN REGISTRE CC SÉPARÉ. Une colonne à 3 lignes fait 3 PIX_W bits, 4,5 mots à C = 48 et W = 128.
 * Écrire son C avec son unité AB demanderait de réaligner les mots sur un demi-mot, 576 mux2.
 * Les C de deux colonnes voyagent donc ensemble dans une unité CC, au même format qu'une unité AB,
 * et s'écrivent à position fixe dans ce registre de deux emplacements, 768 tlatch et 0,014 mm²
 * (spec/03_interfaces.md sections 3.5 et 6).
 * Hors de l'étage, il ne bloque pas la file : il se libère dès que ses deux C sont pris, et absorbe
 * 3 mots de plus dans une rangée à 3 lignes.
 * Loger l'unité CC à la place d'une colonne de l'étage D_COL, comme le modèle de l'accordeur, porte
 * l'attente des MAC de 2 592 à 2 880 cycles sur les flux à 720p qui cassent
 * (verif/README.md section 8.4).
 *
 * LE TROU 3. L'étage prend le premier mot d'une unité AB au front même où sa colonne complète descend,
 * et le registre CC prend le premier mot d'une unité CC ou C1 au front où part le seul C qui l'occupe.
 * Lu au sens strict, un mot n'entrerait qu'au cycle suivant : une colonne de 3 mots tiendrait l'étage
 * 4 cycles, et au pas 2 les MAC attendraient 4 cycles par rangée
 * (verif/lectures.md trou 3).
 * o_ab_free et o_cc_free dépendent donc combinatoirement de i_col_ready, par w_descend.
 * Jamais l'inverse : o_col_valid ne lit que des registres, aucun chemin ne va de ready vers valid
 * (spec/12_controle.md section 4.5).
 *
 * L'UNITÉ C1. La dernière colonne d'une rangée à 3 lignes de largeur impaire envoie son C seul,
 * sur C1_WORDS mots.
 * Il va dans la tête du registre, à la même position fixe que le C d'une unité CC, et ses bits de
 * bourrage, au-delà de PIX_W, ne s'écrivent nulle part
 * (verif/lectures.md trou 18).
 *
 * FORMAT EN FLUX, COL_FMT = 1, (3l, stream), contrat de la variante V3 de
 * rtl/contrats.md.
 * Les colonnes d'une carte forment un seul flux de bits, A, B puis C pour chaque colonne, coupé en mots de W bits :
 * ni unité, ni registre CC.
 * L'aiguilleur donne avec chaque mot ses bits utiles, au-delà desquels le dernier mot d'une carte porte un bourrage,
 * jeté ici, et ses bits de colonnes à 3 lignes, comptés depuis son bit 0.
 * r_stream tient le flux reçu depuis le premier bit de la colonne de tête, sur 3 PIX_W + 2 W bits : la colonne de
 * tête et au plus 2 W bits qui la suivent, borne que tient o_word_free.
 * Une colonne fait 2 ou 3 PIX_W bits et commence donc toujours sur un multiple de PIX_W du flux.
 * Un drapeau par tranche de PIX_W bits (r_three) suffit à dire la taille de la colonne qui y commencerait : il se
 * pose à l'arrivée du premier bit de la tranche, selon que ce bit tombe sous les bits de colonnes à 3 lignes
 * de son mot.
 * Une colonne est valide au cycle qui suit l'arrivée de son dernier bit, et sa descente décale le flux de sa
 * taille : o_col_valid ne lit encore que des registres, et o_word_free lit i_col_ready.
 * La réalisation attendue, l'étage D_COL, un tampon de 2 W bits et 3 PIX_W × 3 mux2 de réalignement, relève de
 * la version structurelle : ce RTL comportemental dit le flux par décalages. La descente y est déjà un mux 3:1 à
 * constantes, le placement du mot reste un décalage variable de w_kept_bits.
 *
 * FORMAT (fh, aligned), COL_FMT = 2, contrat 1b amendé de
 * rtl/contrats.md.
 * Aucune région n'a de halo haut réel : toute colonne arrive sur 2 lignes, en une seule unité AB, et le registre CC
 * ne sert pas (verif/lectures.md trou 22).
 * L'étage D_COL tient r_ab et r_complete comme en unités, et col_data vaut r_ab sur COL_W = 2 PIX_W bits, sans C.
 * Ni registre CC, ni compte des unités C : col_valid vaut r_complete, cc_free et word_free valent 0, et cc_we, c1_we,
 * col_lines et les entrées du flux sont ignorés.
 * ab_free garde la lecture du trou 3, et un dernier mot AB écrit au front d'une descente garde r_complete à 1.
 *
 * Seuls les bits de validité ont un reset, r_complete, r_needs_c, r_cc_count et r_col_valid en unités, r_complete seul
 * en (fh, aligned), r_held en flux :
 * r_ab, r_cc0, r_cc1, r_stream et r_three sont toujours réécrits avant usage
 * (spec/03_interfaces.md section 4.11).
 * Le champ C de col_data reste donc inconnu jusqu'à la première unité CC ou C1, sans effet sur une
 * colonne à 2 lignes, que la fenêtre ne lit jamais par C.
 * Les registres sont écrits en bascules, leur réalisation en tlatch maître-esclave relève de la
 * version structurelle (rtl/00_conception.md section 2). */

module column_asm #(parameter C        = `TILE_C,
                    parameter BA       = `TILE_BA,
                    parameter W        = `TILE_W,
                    parameter COL_FMT  = `TILE_COL_FMT,
                    parameter PIX_W    = C * BA,
                    parameter COL_W    = (COL_FMT == 2) ? 2 * PIX_W : 3 * PIX_W,
                    parameter AB_WORDS = (2 * PIX_W + W - 1) / W,
                    parameter C1_WORDS = (PIX_W + W - 1) / W,
                    parameter WB_W     = $clog2(W + 1),
                    parameter STREAM_W = 3 * PIX_W + 2 * W,
                    parameter HELD_W   = $clog2(STREAM_W + 1),
                    parameter SLOTS    = (STREAM_W + PIX_W - 1) / PIX_W)
                   (input                 i_clk,
                    input                 i_rst_n,
                    input  [W-1:0]        i_in_word,
                    input  [AB_WORDS-1:0] i_ab_we,
                    input  [AB_WORDS-1:0] i_cc_we,
                    input  [C1_WORDS-1:0] i_c1_we,
                    input                 i_col_lines,
                    input                 i_col_ready,
                    output [COL_W-1:0]    o_col_data,
                    output                o_col_valid,
                    output                o_ab_free,
                    output                o_cc_free,
                    input                 i_word_we,
                    input  [WB_W-1:0]     i_word_bits,
                    input  [WB_W-1:0]     i_word_three,
                    output                o_word_free);

    genvar bit_idx;
    genvar slot_idx;

    generate
        if (COL_FMT == 1)
            begin : g_stream
                reg  [STREAM_W-1:0] r_stream;
                reg  [SLOTS-1:0]    r_three;
                reg  [HELD_W-1:0]   r_held;
                wire                w_head_three;
                wire [HELD_W-1:0]   w_head_bits;
                wire                w_go;
                wire [HELD_W-1:0]   w_drop_bits;
                wire [HELD_W-1:0]   w_kept_bits;
                wire [SLOTS-1:0]    w_three_kept;
                wire [HELD_W-1:0]   w_go_kept;
                wire                w_go_three;
                wire                w_go_next_three;
                wire [HELD_W-1:0]   w_go_next_bits;
                wire                w_stay_next_three;
                wire [HELD_W-1:0]   w_stay_next_bits;
                wire                w_free_go;
                wire                w_free_stay;
                wire [WB_W-1:0]     w_word_len;
                wire [W-1:0]        w_word_used;
                wire [STREAM_W-1:0] w_kept;
                wire [STREAM_W-1:0] w_below;
                wire [STREAM_W-1:0] w_placed;
                wire [SLOTS-1:0]    w_three_next;

                assign w_head_three = r_three[0];
                assign w_head_bits  = w_head_three ? HELD_W'(3 * PIX_W) : HELD_W'(2 * PIX_W);
                assign o_col_valid  = (r_held != {HELD_W{1'b0}}) & (r_held >= w_head_bits);
                assign w_go         = o_col_valid & i_col_ready;
                assign w_drop_bits  = w_go ? w_head_bits : {HELD_W{1'b0}};
                assign w_kept_bits  = r_held - w_drop_bits;
                assign w_three_kept = w_go ? (w_head_three ? r_three >> 3 : r_three >> 2) : r_three;

                /* word_free compte la place que libère la descente du même front (trou 3), si bien que i_col_ready,
                 * venu du séquenceur par la file ①, le gagne, puis la prise du mot dans l'aiguilleur. Il se calcule
                 * donc pour les deux issues de la descente, depuis les registres et le mot du cycle, et w_go ne fait
                 * plus que choisir entre elles : même fonction, expansion de Shannon sur w_go, sans bascule ni cycle
                 * de plus (coupe S de l'étude de réalisabilité, rapport.md, dépôt de travail non publié,
                 * section « Poignée de main du flux »). L'équivalence au RTL d'af5ab629 est prouvée par un banc,
                 * test/equiv/prove.py sous test/cmake/14_equiv_flux.cmake.
                 * Dans chaque issue, la tête qui reste : commencée, sa taille est dans son drapeau, sinon le mot du
                 * cycle la donne à son bit 0. Après une descente, la tête suivante commence à la tranche 3 ou 2,
                 * selon la taille de la colonne qui descend. */
                assign w_go_kept         = r_held - w_head_bits;
                assign w_go_three        = w_head_three ? r_three[3] : r_three[2];
                assign w_go_next_three   = (w_go_kept != {HELD_W{1'b0}}) ? w_go_three
                                                                         : (i_word_three != {WB_W{1'b0}});
                assign w_go_next_bits    = w_go_next_three ? HELD_W'(3 * PIX_W) : HELD_W'(2 * PIX_W);
                assign w_stay_next_three = (r_held != {HELD_W{1'b0}}) ? r_three[0] : (i_word_three != {WB_W{1'b0}});
                assign w_stay_next_bits  = w_stay_next_three ? HELD_W'(3 * PIX_W) : HELD_W'(2 * PIX_W);
                assign w_free_go         = ({1'b0, w_go_kept} + (HELD_W + 1)'(i_word_bits))
                                           <= ({1'b0, w_go_next_bits} + (HELD_W + 1)'(2 * W));
                assign w_free_stay       = ({1'b0, r_held} + (HELD_W + 1)'(i_word_bits))
                                           <= ({1'b0, w_stay_next_bits} + (HELD_W + 1)'(2 * W));
                assign o_word_free       = w_go ? w_free_go : w_free_stay;

                assign w_word_len   = i_word_bits;
                assign w_word_used  = i_in_word & ~({W{1'b1}} << w_word_len);
                /* La descente décale le flux de 0, 2 PIX_W ou 3 PIX_W bits, jamais d'autre chose : un mux 3:1 à
                 * constantes, et non un décaleur variable sur STREAM_W bits, que la synthèse rendait en dizaines de
                 * milliers de mux2 (revue du RTL au commit af5ab629, dépôt de travail non publié). */
                assign w_kept       = w_go ? (w_head_three ? r_stream >> (3 * PIX_W) : r_stream >> (2 * PIX_W)) : r_stream;
                assign w_below      = ~({STREAM_W{1'b1}} << w_kept_bits);
                assign w_placed     = {{(STREAM_W - W){1'b0}}, w_word_used} << w_kept_bits;

                /* Une tranche déjà tenue garde son drapeau, une tranche qui commence dans le mot du cycle prend le
                 * sien. Au-delà, le drapeau est sans objet : il sera reposé à l'arrivée du premier bit. */
                for (slot_idx = 0; slot_idx < SLOTS; slot_idx = slot_idx + 1)
                    begin : g_slot
                        wire [HELD_W-1:0] w_slot_pos = HELD_W'(slot_idx * PIX_W);

                        assign w_three_next[slot_idx] = (w_slot_pos < w_kept_bits) ? w_three_kept[slot_idx]
                                                        : ((w_slot_pos - w_kept_bits) < HELD_W'(i_word_three));
                    end

                always @(posedge i_clk)
                    begin
                        r_stream <= (w_kept & w_below) | (i_word_we ? w_placed : {STREAM_W{1'b0}});
                        r_three  <= w_three_next;
                    end

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_held <= {HELD_W{1'b0}};
                    else
                        r_held <= w_kept_bits + (i_word_we ? HELD_W'(w_word_len) : {HELD_W{1'b0}});

                assign o_col_data  = r_stream[COL_W-1:0];
                assign o_ab_free   = 1'b0;
                assign o_cc_free   = 1'b0;

                /* Le flux n'a ni unité AB, ni unité CC, ni unité C1 : leurs validations et col_lines sont ignorées. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_units_ignored = ^{i_ab_we, i_cc_we, i_c1_we, i_col_lines};
                /* verilator lint_on UNUSEDSIGNAL */
            end
        else if (COL_FMT == 2)
            begin : g_aligned
                reg  [2*PIX_W-1:0] r_ab;
                reg                r_complete;
                wire [2*PIX_W-1:0] w_word_tiled;
                wire [2*PIX_W-1:0] w_ab_write;
                wire               w_descend;

                /* Une unité AB s'écrit comme en unités : le bit b vient du bit b mod W de son mot n = b / W, choisi par
                 * la validation de ce mot. */
                for (bit_idx = 0; bit_idx < 2 * PIX_W; bit_idx = bit_idx + 1)
                    begin : g_unit_bit
                        assign w_word_tiled[bit_idx] = i_in_word[bit_idx % W];
                        assign w_ab_write[bit_idx]   = i_ab_we[bit_idx / W];

                        always @(posedge i_clk)
                            if (w_ab_write[bit_idx])
                                r_ab[bit_idx] <= w_word_tiled[bit_idx];
                    end

                assign w_descend = o_col_valid & i_col_ready;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_complete <= 1'b0;
                    else if (i_ab_we[AB_WORDS-1])
                        r_complete <= 1'b1;
                    else if (w_descend)
                        r_complete <= 1'b0;

                assign o_col_valid = r_complete;
                assign o_col_data  = r_ab;
                assign o_ab_free   = ~r_complete | w_descend;
                assign o_cc_free   = 1'b0;
                assign o_word_free = 1'b0;

                /* Ni unités CC ou C1, ni flux : leurs validations, col_lines et les entrées du flux sont ignorés. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_c_and_stream_ignored = ^{i_cc_we, i_c1_we, i_col_lines, i_word_we, i_word_bits, i_word_three};
                /* verilator lint_on UNUSEDSIGNAL */
            end
        else
            begin : g_units
                reg  [2*PIX_W-1:0] r_ab;
                reg  [PIX_W-1:0]   r_cc0;
                reg  [PIX_W-1:0]   r_cc1;
                reg  [1:0]         r_cc_count;
                reg                r_complete;
                reg                r_needs_c;
                reg                r_col_valid;
                wire [2*PIX_W-1:0] w_word_tiled;
                wire [2*PIX_W-1:0] w_ab_write;
                wire [2*PIX_W-1:0] w_cc_write;
                wire               w_descend;
                wire               w_cc_shift;
                wire               w_complete_next = i_ab_we[AB_WORDS-1] ? 1'b1 : (w_descend ? 1'b0 : r_complete);
                wire               w_needs_c_next  = i_ab_we[AB_WORDS-1] ? i_col_lines : r_needs_c;
                wire [1:0]         w_cc_count_next = i_cc_we[AB_WORDS-1] ? 2'd2
                                                   : (i_c1_we[C1_WORDS-1] ? 2'd1
                                                   : (w_cc_shift ? r_cc_count - 2'd1 : r_cc_count));

                /* Le bit b d'une unité vient du bit b mod W de son mot n = b / W, quel que soit le type de l'unité :
                 * le mot reçu, répété à chaque position de mot, sert donc de donnée à tous les bits, et la validation
                 * du mot n les choisit. Les bits de {r_cc1, r_cc0} se lisent comme ceux d'une unité, r_cc0 en bas. */
                for (bit_idx = 0; bit_idx < 2 * PIX_W; bit_idx = bit_idx + 1)
                    begin : g_unit_bit
                        assign w_word_tiled[bit_idx] = i_in_word[bit_idx % W];
                        assign w_ab_write[bit_idx]   = i_ab_we[bit_idx / W];

                        always @(posedge i_clk)
                            if (w_ab_write[bit_idx])
                                r_ab[bit_idx] <= w_word_tiled[bit_idx];

                        if (bit_idx < PIX_W)
                            begin : g_head
                                assign w_cc_write[bit_idx] = i_cc_we[bit_idx / W] | i_c1_we[bit_idx / W];

                                /* Seule la tête avance : sous w_cc_shift, r_cc0 prend r_cc1, et w_cc_shift ne
                                 * pilote plus que la broche GATE de l'ICG de la tête et cette sélection. */
                                always @(posedge i_clk)
                                    if (w_cc_write[bit_idx] | w_cc_shift)
                                        r_cc0[bit_idx] <= w_cc_write[bit_idx] ? w_word_tiled[bit_idx] : r_cc1[bit_idx];
                            end
                        else
                            begin : g_tail
                                assign w_cc_write[bit_idx] = i_cc_we[bit_idx / W];

                                always @(posedge i_clk)
                                    if (w_cc_write[bit_idx])
                                        r_cc1[bit_idx-PIX_W] <= w_word_tiled[bit_idx];
                            end
                    end

                assign w_descend  = o_col_valid & i_col_ready;
                assign w_cc_shift = w_descend & r_needs_c;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        begin
                            r_complete  <= 1'b0;
                            r_needs_c   <= 1'b0;
                            r_cc_count  <= 2'd0;
                            r_col_valid <= 1'b0;
                        end
                    else
                        begin
                            if (i_ab_we[AB_WORDS-1])
                                begin
                                    r_complete <= 1'b1;
                                    r_needs_c  <= i_col_lines;
                                end
                            else if (w_descend)
                                r_complete <= 1'b0;
                            if (i_cc_we[AB_WORDS-1])
                                r_cc_count <= 2'd2;
                            else if (i_c1_we[C1_WORDS-1])
                                r_cc_count <= 2'd1;
                            else if (w_cc_shift)
                                r_cc_count <= r_cc_count - 2'd1;
                            r_col_valid <= w_complete_next & (~w_needs_c_next | (w_cc_count_next != 2'd0));
                        end

                assign o_col_valid = r_col_valid;
                assign o_col_data  = {r_cc0, r_ab};
                assign o_ab_free   = ~r_complete | w_descend;
                assign o_cc_free   = (r_cc_count == 2'd0) | ((r_cc_count == 2'd1) & w_cc_shift);
                assign o_word_free = 1'b0;

                /* Les unités n'ont pas de flux : ses entrées sont ignorées. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_stream_ignored = ^{i_word_we, i_word_bits, i_word_three};
                /* verilator lint_on UNUSEDSIGNAL */
            end
    endgenerate

endmodule

`endif
