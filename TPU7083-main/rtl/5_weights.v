`ifndef __WEIGHT_RING__
`define __WEIGHT_RING__

`include "00_params.vh"
`include "00_variantes.vh"

/* Anneau de poids ④ et cache de poids ⑤ (spec/07_poids.md).
 *
 * ④ présente aux multiplieurs, au cycle g de chaque fenêtre, le groupe g des poids de la passe en cours.
 * Ses positions avancent d'un cran à chaque cycle de wgt_rot, de la dernière vers la position 0,
 * et la position 0 est la prise des multiplieurs, câblée sans porte.
 * Autant de crans que la passe a de groupes ramènent le groupe 0 sur la prise pour la fenêtre suivante.
 *
 * POURQUOI UN CACHE EN CHAÎNE, DÉVERSÉ PENDANT LA DERNIÈRE FENÊTRE.
 * ⑤ reçoit pendant la passe p les poids de p + 1 et doit les faire entrer dans ④ sans faire attendre les
 * MAC.
 * Pendant les G cycles de la dernière fenêtre de p, ceux de wgt_xfer, chaque cran lit sur la prise le
 * groupe g de p et écrit derrière lui, dans la dernière position, le groupe g de p + 1 sorti de la tête
 * de la chaîne.
 * Le groupe remplacé vient d'être lu : aucun cycle n'est perdu, et la fenêtre suivante voit p + 1 dès son
 * premier cycle (spec/07_poids.md sections 3.4 et 4.3).
 * Un groupe par cycle demande une chaîne qui avance d'un cran par cycle, d'où le maître-esclave.
 * Le cache à trous se déverserait en 6 G cycles et ferait attendre les MAC 40 cycles à chaque passe qui
 * charge ses poids, à G = 8.
 * G registres chargés en parallèle demanderaient un mux par bit de ④ et une écriture adressée, le
 * tableau adressé que l'architecture exclut.
 *
 * CE QUE TIENT ⑤.
 * Exactement G_MAX groupes : G_MAX − 1 dans la chaîne, et le dernier dans le chargeur, où il reste jusqu'au
 * déversement.
 * Le premier mot d'un groupe pousse dans la chaîne le groupe que le chargeur vient de compléter, au front
 * même où ce mot entre dans le chargeur.
 * L'affectation non bloquante donne à la chaîne l'ancienne valeur du chargeur, ce que fait le
 * maître-esclave dans la version structurelle.
 *
 * LE SEUL MUX DE ④ en G uniforme est à l'entrée de la dernière position, sur le chemin de rotation et non
 * sur celui des MAC.
 *
 * VARIANTE G1, G1 non nul et différent de G, contrat 5 amendé de
 * rtl/contrats.md, sur la structure de la section 4.4 de la
 * Lot 7 des accords (rtl/bancs.md),
 * que la spécification écrit aux sections 3.2 et 4.4 de
 * spec/07_poids.md.
 * Une passe au pas 1 applique G_S1 = G1 groupes et une passe au pas 2 en applique G (trou 21 de
 * verif/lectures.md).
 * ④ et ⑤ gardent la structure du G uniforme sur G_MAX = max(G, G1) positions, G_LOW = min(G, G1).
 * ⑤ lit sur i_wgt_stride1, au premier mot d'une passe, le G_LOAD des poids qu'il reçoit, et le tient jusqu'à
 * sa libération.
 * Après ses G_LOAD × GROUP_WORDS mots, sa chaîne garde G_MAX − G_LOAD positions périmées en tête.
 * Elle avance alors d'autant de crans, un par cycle, sans mot et sans que ④ ne prenne rien, sa dernière
 * position reprenant le chargeur.
 * C'est l'alignement, après lequel c_q porte le groupe q, et wgt_cache_full ne monte qu'à son terme.
 * ④ lit sur i_ring_stride1 le G_RING de la passe qu'il sert.
 * P_0 à P_(G_RING − 1) tournent aux cycles de wgt_rot, et les positions hautes, P_(G_RING) à P_(G_MAX − 1),
 * ne bougent qu'aux manœuvres de transfert, wgt_pre ou wgt_xfer.
 * Une manœuvre fait entrer la tête de ⑤ en P_(G_MAX − 1), descendre les positions hautes d'un cran et avancer
 * la chaîne.
 * Un transfert compte G_MAX manœuvres.
 * Les wgt_pre du pré-transfert remplissent les positions hautes pendant que P_0 à P_(G_RING − 1) tournent
 * encore pour la passe p, puis les G_RING wgt_xfer de sa dernière fenêtre font descendre tout l'anneau
 * derrière les groupes que lisent les MAC.
 * À la fenêtre suivante, P_q porte le groupe q de p + 1, et les groupes poussés au-delà des G_LOAD de la
 * passe chargée sont sans usage.
 * Le seul mux2 ajouté, de fermeture, est à l'entrée de P_(G_LOW − 1) : il prend P_0 hors wgt_xfer quand
 * G_RING vaut G_LOW, et la position du dessus sinon.
 * L'entrée de P_(G_MAX − 1) garde le mux2 du G uniforme, la tête de ⑤ à chaque manœuvre et P_0 sinon.
 * Les positions hautes ont leur propre validation, wgt_rot quand G_RING vaut G_MAX et une manœuvre sinon,
 * que la version structurelle fait par une branche à part des arbres de phase.
 *
 * LECTURES, retenues par levier technique du 15/10/2026 (trou 24 de
 * verif/lectures.md et section des lectures du
 * dépôt de travail non publié) :
 * - trou 24 lu au plus tôt, ⑤ s'aligne de lui-même dès son dernier mot de poids, et wgt_cache_full, qui ne
 *   monte qu'après l'alignement, ouvre au séquenceur le pré-transfert comme le déversement seul ;
 * - ⑤ redevient libre au front de sa dernière manœuvre de transfert, la G-ième en G uniforme, la G_MAX-ième
 *   en variante G1, donc au plus tard à W0(p + 1) (levier technique 3) ;
 * - seule une passe qui charge ses poids a un pré-transfert, ce que décide le séquenceur (levier technique 2) ;
 * - la règle couvre G1 < G, G_MAX valant alors G, et ce sont alors les passes au pas 1 qui ont des positions
 *   hautes.
 *
 * Les instants suivent les lectures retenues des trous
 * (dépôt de travail non publié, section des trous).
 * ⑤ redevient libre au cycle qui suit le G-ième cycle consécutif de wgt_xfer en G uniforme, sa G_MAX-ième
 * manœuvre en variante G1 (trou 8).
 * o_wgt_cache_full, tiré d'un registre, ne voit un mot écrit au front du cycle t qu'à partir du cycle
 * t + 1 (trou 19), et du cycle t + 1 + G_MAX − G_LOAD en variante G1, alignement fait.
 *
 * CE QUE LE CONTRAT D'USAGE LAISSE AUX BANCS.
 * Le module ne juge pas son stimulus, et le banc rtl/test/test_5_weights.v
 * fait échouer tout cas qui enfreint :
 * - wgt_pre et wgt_xfer jamais au même cycle, wgt_xfer seulement avec wgt_rot ;
 * - un mot de poids seulement sous wgt_cache_ready, qui vaut 0 pendant l'alignement
 *   (spec/07_poids.md section 5), une manœuvre
 *   seulement ⑤ plein ;
 * - wgt_pre seulement si G_RING < G_MAX, au plus G_MAX − G_RING par transfert, tous avant son premier
 *   wgt_xfer, donc wgt_pre à 0 hors variante G1 ;
 * - G_MAX manœuvres par transfert, les G wgt_xfer consécutifs hors variante G1 (contrat 5 d'origine).
 *
 * TRANCHES ET DRAPEAUX, coupes de pipeline du 28/10/2026.
 * Sous DIFF_SLICE = 1 hors variante G1, REP vaut K et le mux d'entrée de la dernière position se coupe en REP
 * tranches, une par filtre, chacune choisie par sa feuille de i_wgt_xsel, copie de wgt_xfer quand wgt_rot est haut.
 * r_at_group et r_full sont tirés du compte suivant, un cycle plus tôt, si bien que la poussée d'un groupe dans
 * la chaîne et wgt_cache_full ne lisent qu'une bascule chacun.
 *
 * Seuls les compteurs, leurs drapeaux r_at_group et r_full, et G_LOAD ont un reset : compteurs de mots et de
 * déversement en G uniforme, compteur de mots, compte d'alignement, compte des manœuvres et G_LOAD en variante G1.
 * ④ est rempli par le déversement seul qui suit VIDE, et ⑤ est réécrit avant tout usage
 * (spec/12_controle.md section 4.6).
 * Un reset pendant un alignement ou un pré-transfert vide donc ⑤, et les groupes déjà poussés dans les
 * positions hautes restent sans usage jusqu'au déversement seul qui suit (propriété P5 des bancs du RTL (rtl/bancs.md)).
 * Les constantes comparées au compteur de mots sont ramenées à CNT_W bits : sans ce cast, Verilator
 * relève un élargissement dès que CNT_W compte moins de bits que W, sur 563 des 1 280 jeux balayés le
 * 13/10/2026, aucun des trois jeux du plan.
 * Celles des comptes d'alignement et de manœuvres le sont de même à XFER_W bits.
 * Les registres sont des bascules, leur réalisation en tlatch maître-esclave relève de la version
 * structurelle. */

module weight_ring #(parameter C           = `TILE_C,
                     parameter K           = `TILE_K,
                     parameter G           = `TILE_G,
                     parameter G1          = `TILE_G1,
                     parameter BW          = `TILE_BW,
                     parameter W           = `TILE_W,
                     parameter G_S1        = groups_stride1(G, G1),
                     parameter G_MAX       = groups_max(G, G1),
                     parameter G_LOW       = groups_low(G, G1),
                     parameter GROUP_BITS  = 9 * C * K * BW,
                     parameter GROUP_WORDS = (GROUP_BITS + W - 1) / W,
                     parameter WGT_WORDS   = G_MAX * GROUP_WORDS,
                     parameter CNT_W       = $clog2(WGT_WORDS + 1),
                     parameter XFER_W      = $clog2(G_MAX + 1),
                     parameter REP         = (`TILE_DIFF_SLICE != 0 && G1 == 0) ? K : 1)
                    (input                   i_clk,
                     input                   i_rst_n,
                     input  [W-1:0]          i_wgt_cache_data,
                     input                   i_wgt_cache_valid,
                     input                   i_wgt_xfer,
                     input                   i_wgt_rot,
                     input  [REP-1:0]        i_wgt_xsel,
                     output                  o_wgt_cache_full,
                     output                  o_wgt_cache_ready,
                     output [GROUP_BITS-1:0] o_wgt_head,
                     input                   i_wgt_stride1,
                     input                   i_wgt_pre,
                     input                   i_ring_stride1);

    `include "00_groups.vh"

    localparam SLICE_BITS = GROUP_BITS / REP;

    reg  [GROUP_WORDS*W-1:0]        r_loader;
    reg  [(G_MAX-1)*GROUP_BITS-1:0] r_chain;
    reg  [CNT_W-1:0]                r_word_count;
    reg                             r_at_group;
    wire                            w_release;
    wire [CNT_W-1:0]                w_count_next   = w_release ? {CNT_W{1'b0}}
                                                   : (i_wgt_cache_valid ? r_word_count + 1'b1 : r_word_count);
    wire [G_MAX-1:0]                w_at_group_next;
    wire [GROUP_BITS-1:0]           w_loader_group = r_loader[GROUP_BITS-1:0];
    wire [GROUP_BITS-1:0]           w_chain_head   = r_chain[GROUP_BITS-1:0];
    wire                            w_group_push   = i_wgt_cache_valid && r_at_group;
    wire                            w_chain_shift;

    genvar slice_idx;

    /* r_at_group vaut au cycle près r_word_count == m GROUP_WORDS pour un m de 1 à G_MAX - 1 : le compte
     * suivant le calcule un cycle plus tôt, et la poussée du groupe complet ne lit plus qu'une bascule. */
    assign w_at_group_next[0] = 1'b0;

    genvar cpt_group;
    generate
        for (cpt_group = 1; cpt_group < G_MAX; cpt_group = cpt_group + 1)
            begin : group_complete
                assign w_at_group_next[cpt_group] = w_count_next == CNT_W'(cpt_group * GROUP_WORDS);
            end
    endgenerate

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_word_count <= {CNT_W{1'b0}};
        else if (w_release)
            r_word_count <= {CNT_W{1'b0}};
        else if (i_wgt_cache_valid)
            r_word_count <= r_word_count + 1'b1;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_at_group <= 1'b0;
        else if (w_release || i_wgt_cache_valid)
            r_at_group <= |w_at_group_next;

    always @(posedge i_clk)
        if (i_wgt_cache_valid)
            r_loader <= {i_wgt_cache_data, r_loader[GROUP_WORDS*W-1:W]};

    always @(posedge i_clk)
        if (w_chain_shift)
            r_chain <= {w_loader_group, r_chain[(G_MAX-1)*GROUP_BITS-1:GROUP_BITS]};

    generate
        if (G_LOW < G_MAX)
            begin : g_variant_g1
                reg  [G_MAX*GROUP_BITS-1:0]           r_ring;
                reg  [XFER_W-1:0]                     r_align_count;
                reg  [XFER_W-1:0]                     r_move_count;
                reg                                   r_load_s1;
                wire                                  w_load_low;
                wire                                  w_ring_low;
                wire [CNT_W-1:0]                      w_load_words;
                wire [XFER_W-1:0]                     w_align_target;
                wire                                  w_loaded;
                wire                                  w_aligned;
                wire                                  w_align_step;
                wire                                  w_move;
                wire                                  w_high_shift;
                wire [GROUP_BITS-1:0]                 w_ring_head;
                wire [GROUP_BITS-1:0]                 w_ring_entry;
                wire [(G_MAX-G_LOW+1)*GROUP_BITS-1:0] w_high_fed;
                wire [GROUP_BITS-1:0]                 w_close_entry;

                /* G_LOAD et G_RING valent G_S1 au pas 1 et G au pas 2, et l'une de ces deux valeurs est G_LOW :
                 * seul ce cas demande un alignement de ⑤, ou ferme ④ sous ses positions hautes. */
                assign w_load_low     = (r_load_s1 ? G_S1 : G) == G_LOW;
                assign w_ring_low     = (i_ring_stride1 ? G_S1 : G) == G_LOW;
                assign w_load_words   = w_load_low ? CNT_W'(G_LOW * GROUP_WORDS) : CNT_W'(WGT_WORDS);
                assign w_align_target = w_load_low ? XFER_W'(G_MAX - G_LOW) : {XFER_W{1'b0}};
                assign w_loaded       = r_word_count >= w_load_words;
                assign w_aligned      = r_align_count == w_align_target;
                assign w_align_step   = w_loaded && !w_aligned;
                assign w_move         = i_wgt_pre || i_wgt_xfer;
                assign w_high_shift   = (i_wgt_rot && !w_ring_low) || w_move;
                assign w_ring_head    = r_ring[GROUP_BITS-1:0];
                assign w_ring_entry   = w_move ? w_chain_head : w_ring_head;

                /* w_high_fed empile l'entrée de P_(G_MAX − 1) sur P_(G_LOW) à P_(G_MAX − 1) : un cran les décale
                 * d'un groupe, et P_(G_LOW), la plus basse, alimente le mux2 de fermeture. */
                assign w_high_fed     = {w_ring_entry, r_ring[G_MAX*GROUP_BITS-1:G_LOW*GROUP_BITS]};
                assign w_close_entry  = (w_ring_low && !i_wgt_xfer) ? w_ring_head : w_high_fed[GROUP_BITS-1:0];

                assign w_chain_shift  = w_group_push || w_align_step || w_move;
                assign w_release      = w_move && r_move_count == XFER_W'(G_MAX - 1);

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_load_s1 <= 1'b0;
                    else if (i_wgt_cache_valid && r_word_count == {CNT_W{1'b0}})
                        r_load_s1 <= i_wgt_stride1;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_align_count <= {XFER_W{1'b0}};
                    else if (w_release)
                        r_align_count <= {XFER_W{1'b0}};
                    else if (w_align_step)
                        r_align_count <= r_align_count + 1'b1;

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_move_count <= {XFER_W{1'b0}};
                    else if (w_release)
                        r_move_count <= {XFER_W{1'b0}};
                    else if (w_move)
                        r_move_count <= r_move_count + 1'b1;

                always @(posedge i_clk)
                    begin
                        if (i_wgt_rot)
                            r_ring[G_LOW*GROUP_BITS-1:0] <= {w_close_entry, r_ring[G_LOW*GROUP_BITS-1:GROUP_BITS]};
                        if (w_high_shift)
                            r_ring[G_MAX*GROUP_BITS-1:G_LOW*GROUP_BITS]
                                <= w_high_fed[(G_MAX-G_LOW+1)*GROUP_BITS-1:GROUP_BITS];
                    end

                assign o_wgt_cache_full  = w_loaded && w_aligned;
                assign o_wgt_cache_ready = !w_loaded;
                assign o_wgt_head        = w_ring_head;

                /* REP vaut 1 en variante G1, dont le mux d'entrée de P_(G_MAX − 1) reste sur w_move. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_xsel_ignored = ^i_wgt_xsel;
                /* verilator lint_on UNUSEDSIGNAL */
            end
        else
            begin : g_uniform
                reg  [G*GROUP_BITS-1:0] r_ring;
                reg  [XFER_W-1:0]       r_xfer_count;
                reg                     r_full;
                wire [GROUP_BITS-1:0]   w_ring_head  = r_ring[GROUP_BITS-1:0];
                wire [GROUP_BITS-1:0]   w_ring_entry;

                /* La tranche s porte les poids du filtre s (disposition de rtl/6_mac.v lignes 939 et 952) : sa
                 * feuille de i_wgt_xsel choisit son entrée, libre quand i_wgt_rot est bas. */
                for (slice_idx = 0; slice_idx < REP; slice_idx = slice_idx + 1)
                    begin : g_slice
                        assign w_ring_entry[slice_idx*SLICE_BITS +: SLICE_BITS]
                            = i_wgt_xsel[slice_idx] ? w_chain_head[slice_idx*SLICE_BITS +: SLICE_BITS]
                                                    : w_ring_head[slice_idx*SLICE_BITS +: SLICE_BITS];
                    end

                assign w_chain_shift = w_group_push || i_wgt_xfer;
                assign w_release     = i_wgt_xfer && (r_xfer_count + 1'b1 == G);

                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_xfer_count <= {XFER_W{1'b0}};
                    else if (i_wgt_xfer && !w_release)
                        r_xfer_count <= r_xfer_count + 1'b1;
                    else
                        r_xfer_count <= {XFER_W{1'b0}};

                always @(posedge i_clk)
                    if (i_wgt_rot)
                        r_ring <= {w_ring_entry, r_ring[G*GROUP_BITS-1:GROUP_BITS]};

                /* r_full vaut au cycle près r_word_count >= WGT_WORDS, plein dès que le compte atteint ou dépasse le
                 * nombre de mots du bloc (correctif des compteurs du 28/10/2026, 61fedaa3) : tiré à chaque front du
                 * compte suivant, il se lève aussi d'un compte posé au-delà de WGT_WORDS, sans écriture ni
                 * libération. */
                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        r_full <= 1'b0;
                    else
                        r_full <= w_count_next >= CNT_W'(WGT_WORDS);

                assign o_wgt_cache_full  = r_full;
                assign o_wgt_cache_ready = !r_full;
                assign o_wgt_head        = w_ring_head;

                /* En G uniforme, le contrat 5 amendé ignore i_wgt_stride1, i_wgt_pre et i_ring_stride1 : ni
                 * G_LOAD, ni pré-transfert, ni positions hautes. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_g1_ignored = ^{i_wgt_stride1, i_wgt_pre, i_ring_stride1};
                /* verilator lint_on UNUSEDSIGNAL */
            end
    endgenerate

endmodule

`endif
