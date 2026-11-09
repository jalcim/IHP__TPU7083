`ifndef __THRESHOLD_UNIT__
`define __THRESHOLD_UNIT__

`include "00_params.vh"
`include "00_variantes.vh"

/* Seuillage ⑦ : cache de seuils, banques câblées, registre de maintien, comparateurs cardinaux et
 * sérialiseur des niveaux (spec/10_seuillage.md sections 2 à 5).
 *
 * LE CACHE ET LES BANQUES. Le cache est une chaîne de THR_WORDS cases de W bits, le compte d'un bloc au
 * G_MAX. Chaque mot écrit entre dans la dernière case et pousse les autres d'un cran, si bien qu'après les
 * ⌈K G_BLK T THR_W / W⌉ mots d'un bloc, G_BLK étant le G de son pas, la case n porte le mot n, case n en
 * [n W +: W] du vecteur des seuils. Chaque bit de banque est câblé sur le bit du cache qui le porte au
 * repos, et la seule impulsion i_thr_xfer les verse tous ensemble : aucun mux, aucune adresse
 * (section 3.3). Sous REP = G_MAX, i_thr_xfer arrive par une feuille par groupe, toutes au même cycle.
 * En variante G1, les banques des canaux K G_LOW et au-delà n'y prennent qu'un bloc au
 * G_MAX. Les bits du dernier mot au-delà de THR_BITS sont du bourrage, qu'aucune banque ne lit
 * (trou 18). Le compteur de mots revient à 0 au front de i_thr_xfer, si bien que le cache accepte le
 * premier mot du bloc suivant dès le cycle qui suit (trou 10).
 *
 * LA VARIANTE G1 (contrat 8 amendé de rtl/contrats.md).
 * Quand G1 n'est ni 0 ni G, une passe au pas 1 a G_S1 groupes et une passe au pas 2 en a G, et G_LOW, le plus
 * petit des deux, tombe sous G_MAX.
 * Un registre tient G_BLK, lu sur i_thr_stride1 au premier mot d'un bloc, compteur à 0, jusqu'au thr_xfer, et
 * o_thr_cache_full monte quand le compteur atteint ⌈K G_BLK T THR_W / W⌉.
 * Un bloc au G_LOW compte LOW_WORDS = ⌈K G_LOW T THR_W / W⌉ mots, que les banques des canaux 0 à
 * K G_LOW - 1 lisent dans les cases 0 à LOW_WORDS - 1.
 * Entré par la dernière case comme les autres, il finirait dans les cases hautes.
 * La case LOW_WORDS - 1 prend donc i_thr_cache_data par un mux2 de W bits quand le bloc est au G_LOW, choix
 * lu dès son premier mot sur i_thr_stride1, et la case du dessus sinon, les autres cases gardant la chaîne.
 * Ce mux2 n'existe que si LOW_WORDS < THR_WORDS.
 * C'est l'écart E13, levier technique 5 du 15/10/2026 : W mux2, environ 0,008 mm² à 456 bits.
 * Un bourrage du bloc par le lien ajouterait des mots et retarderait full, donc l'échéance du trou 19, ce qui
 * peut faire attendre les MAC.
 * Au front de i_thr_xfer, les banques des canaux 0 à K G_LOW - 1 prennent toujours les bits bas du cache, et
 * celles au-delà seulement pour un bloc au G_MAX, par leur seule validation d'écriture : un bloc au G_LOW leur
 * laisse les seuils du bloc d'avant.
 * Un registre tient G_PIX, lu sur i_done_stride1 au cycle de i_acc_done, et seuls les étages 0 à G_PIX - 1 du
 * sérialiseur de G_MAX étages reçoivent un bit de validité à 1.
 * Hors variante G1, G_LOW vaut G_MAX, le RTL est celui de G uniforme, et i_thr_stride1 et i_done_stride1 sont
 * ignorés.
 * G_LOW et les comptes d'un bloc se calculent par fonctions constantes, une largeur dérivée n'étant jamais un
 * localparam.
 *
 * LE CARDINAL PLUTÔT QUE L'INDICE. Le niveau d'un canal est le nombre de seuils que franchit sa somme,
 * comme _requant d'AsicSim. L'indice du plus haut seuil franchi rend la même valeur sur une banque
 * croissante, et une valeur fausse dès qu'elle cesse de l'être. Le module ne vérifie pas la croissance des
 * seuils qu'il reçoit, il ne doit donc pas en dépendre
 * (spec/02_arithmetique.md section 4.6).
 * Le compte ajoute chaque comparaison élargie à BA bits plutôt que de la tester : un comparateur inconnu,
 * sur une banque qu'aucun i_thr_xfer n'a chargée, rend le niveau inconnu en simulation au lieu d'un compte
 * défini qui masquerait la cause. La logique synthétisée est la même.
 *
 * L'EXTENSION PAR LE SIGNE. Un seuil rangé sur THR_W bits, plus étroit que l'accumulateur, se compare sur
 * CMP_W = max(ACC, THR_W) bits après extension par le signe, jamais par des zéros. Un seuil négatif
 * deviendrait sinon un grand positif et le niveau tomberait à tort : à la tuile par défaut, -1 rangé 3FFF
 * sur 14 bits se lirait 16 383 (spec/02_arithmetique.md section 4.5).
 * L'extension réplique le bit de signe CMP_W - THR_W + 1 fois devant les THR_W - 1 bits bas, et de même
 * pour l'accumulateur. La copie de plus que l'écart tient la réplication à un bit au moins quand CMP_W vaut
 * THR_W, là où une réplication de CMP_W - THR_W bits serait de largeur nulle, illégale même dans une branche
 * jamais prise. THR_W ≥ 2 et ACC ≥ 2, que vérifie param_check, gardent les bits bas non vides.
 * Affecter un $signed à un fil plus large étendrait aussi par le signe, mais Verilator le signale
 * (WIDTHEXPAND), et la tuile n'admet pas d'exception de lint pour cela (levier technique du 13/10/2026).
 *
 * LE TEMPS. Le registre de maintien prend i_acc_word au front du cycle T de i_acc_done, les comparateurs
 * évaluent pendant T + 1, le sérialiseur se charge au front de T + 1 : les niveaux du pixel sortent aux
 * cycles T + 2 à T + G_PIX + 1, K par cycle, l'étage g portant les canaux K g à K g + K - 1, G_PIX valant G
 * hors variante G1. Un i_thr_xfer au cycle d'un i_acc_done fait voir ensemble aux comparateurs les nouveaux
 * seuils et le nouveau pixel, le premier qui en a besoin
 * (spec/10_seuillage.md section 4.2).
 *
 * LA COLLISION. Un rechargement du sérialiseur écrase les étages qui n'ont pas encore sorti leurs niveaux. Le
 * séquenceur l'exclut en espaçant les pixels de G_PASS cycles au moins, mais une passe à G_PASS plus petit qui suit
 * une passe à G_PASS plus grand sans l'écart de la règle E20 (amendement A4 de rtl/contrats.md) le ferait sans
 * bruit. En variante G1, o_lvl_collide le signale au cycle du rechargement, r_load avec un étage 1 à G_MAX - 1
 * encore valide, l'étage 0 sortant ce cycle même, et 9_link_out.v le verse dans out_collide, que lit ÉTAT (point
 * 8_threshold.v:286 de la revue du RTL d'af5ab629). Hors d'elle, tous les pixels ont G étages et arrivent G cycles au
 * moins l'un après l'autre : o_lvl_collide vaut 0, sans cellule, là où la même expression en garderait deux à la
 * synthèse.
 *
 * LE PARTAGE DANS LE TEMPS, THR_SHARE = 1 (00_variantes.vh, levier technique du 21/10/2026). Le sérialiseur
 * n'émet que K niveaux par cycle : K voies de T comparateurs suffisent, au lieu de K G_MAX. r_hold se décale de K ACC
 * bits à chaque cycle après i_acc_done, si bien que la voie k lit au cycle T + 1 + g le canal K g + k, et un compte de
 * groupe choisit dans les banques, par un et-ou décodé, les T seuils de ce canal. Un registre de K BA bits tient les
 * niveaux, qui sortent aux mêmes cycles T + 2 à T + G_PIX + 1, r_stage_valid et o_lvl_collide gardés. Le stockage des
 * banques ne change pas, seule leur lecture. Elles se lisent jusqu'à T + G_PIX au lieu de T + 1 : le thr_xfer suivant
 * tombe avec l'acc_done du premier pixel d'une passe, que l'espacement des pixels et la borne E20 mettent au plus tôt à
 * ce cycle, et ne verse les banques qu'au front qui le clôt.
 *
 * LA COUPE, THR_CUT = 1 (00_variantes.vh, coupes de pipeline du 28/10/2026). Les comparateurs lisent i_acc_word au
 * cycle T de i_acc_done, et r_crossed, chargé à chaque cycle sans validation, tient leurs LANES T bits au cycle T + 1,
 * où le compteur de bits les lit : r_hold disparaît, le compteur de bits, le mux de chargement et r_stage gardent leur
 * cycle, et les niveaux sortent aux mêmes cycles. Les banques doivent porter les seuils de la passe dès T : le
 * séquenceur émet i_thr_xfer un cycle plus tôt (THR_XFER_LEAD), et le compteur du cache ne revient à 0 qu'au cycle
 * suivant, sur r_xfer_late, si bien que le cache se libère au même cycle. Un i_thr_xfer au cycle d'un i_acc_done laisse
 * ce pixel comparer sur les anciennes banques. W0 est le premier mot d'une passe qui seuille, T le cycle de i_acc_done
 * d'un pixel :
 *   événement                          THR_CUT = 0                       THR_CUT = 1
 *   i_thr_xfer                         W0 + L_MAC + G_PASS               W0 + L_MAC + G_PASS - 1
 *   banques neuves visibles            dès W0 + L_MAC + G_PASS + 1       dès W0 + L_MAC + G_PASS
 *   comparaisons du pixel              T + 1, sur r_hold                 T, sur i_acc_word
 *   r_stage chargé                     front de fin de T + 1             inchangé
 *   o_lvl_out et o_lvl_valid           T + 2 à T + G_PIX + 1             inchangés
 *   o_thr_cache_full à 0, cache libre  W0 + L_MAC + G_PASS + 1           inchangé, par r_xfer_late
 *   réservation du séquenceur          W0 + 1 à W0 + L_MAC + G_PASS      inchangée
 *   o_pass_done                        W_last + L_MAC + 2 G_PASS + 1     inchangé
 *   sortie vide en ERREUR              E + L_MAC + 2 G_PASS + 1          inchangée
 * THR_SHARE = 1 lit les banques jusqu'à T + G_PIX : la coupe ne vaut que sous la forme cardinale, et param_check
 * refuse le couple.
 *
 * LE RESET. Seuls le compteur du cache, les bits de validité du sérialiseur, le retard de i_acc_done et, sous
 * THR_CUT = 1, celui de i_thr_xfer en ont un, asynchrone à l'assertion comme tout le cœur. Le cache, les banques, le
 * maintien, r_crossed et les étages du sérialiseur sont toujours réécrits avant usage (spec/10_seuillage.md
 * section 4.3).
 * Les registres de G_BLK et de G_PIX n'en ont pas non plus.
 * G_PIX est réécrit à chaque i_acc_done avant d'être lu, et o_thr_cache_full compare le compteur aux comptes
 * des deux pas, tous deux non nuls, si bien qu'il vaut 0 pendant le reset quel que soit G_BLK.
 *
 * Les registres de données sont des bascules. Leur réalisation en tlatch maître-esclave relève de la
 * version structurelle (rtl/00_conception.md section 2). */

module threshold_unit #(parameter K         = `TILE_K,
                        parameter G         = `TILE_G,
                        parameter G1        = `TILE_G1,
                        parameter T         = `TILE_T,
                        parameter BA        = `TILE_BA,
                        parameter ACC       = `TILE_ACC,
                        parameter THR_W     = `TILE_THR_W,
                        parameter W         = `TILE_W,
                        parameter THR_SHARE = `TILE_THR_SHARE,
                        parameter THR_CUT   = `TILE_THR_CUT,
                        parameter G_S1      = groups_stride1(G, G1),
                        parameter G_MAX     = groups_max(G, G1),
                        parameter THR_BITS  = K * G_MAX * T * THR_W,
                        parameter THR_WORDS = (THR_BITS + W - 1) / W,
                        parameter CNT_W     = $clog2(THR_WORDS + 1),
                        parameter CMP_W     = (ACC > THR_W) ? ACC : THR_W,
                        parameter LANES     = (THR_SHARE != 0) ? K : K * G_MAX,
                        parameter REP       = (`TILE_DIFF_SLICE != 0 && G1 == 0 && THR_SHARE == 0) ? G_MAX : 1)
                       (input                    i_clk,
                        input                    i_rst_n,
                        input  [K*G_MAX*ACC-1:0] i_acc_word,
                        input                    i_acc_done,
                        input  [W-1:0]           i_thr_cache_data,
                        input                    i_thr_cache_valid,
                        input  [REP-1:0]         i_thr_xfer,
                        output                   o_thr_cache_full,
                        output                   o_thr_cache_ready,
                        output [K*BA-1:0]        o_lvl_out,
                        output                   o_lvl_valid,
                        input                    i_thr_stride1,
                        input                    i_done_stride1,
                        output                   o_lvl_collide);

    `include "00_groups.vh"

    reg  [THR_WORDS*W-1:0]  r_cache;
    reg  [CNT_W-1:0]        r_count;
    reg  [THR_BITS-1:0]     r_bank;
    reg                     r_load;
    reg  [G_MAX-1:0]        r_stage_valid;
    /* Les voies de comparaison, LANES = K G_MAX en forme cardinale, K en partage dans le temps : l'accumulateur et les
     * T seuils de chaque voie, ses T comparaisons, celles que lit le compteur de bits, puis son niveau. */
    wire [LANES*ACC-1:0]     w_lane_acc;
    wire [LANES*T*THR_W-1:0] w_lane_theta;
    wire [LANES*T-1:0]       w_crossed_all;
    wire [LANES*T-1:0]       w_count_in;
    wire [LANES*BA-1:0]      w_level;
    wire [G_MAX-1:0]        w_load_valid;
    wire                    w_cache_free;

    function automatic [BA-1:0] crossed_count(input [T-1:0] crossed);
        integer rank_index;
        begin
            crossed_count = {BA{1'b0}};
            for (rank_index = 0; rank_index < T; rank_index = rank_index + 1)
                crossed_count = crossed_count + BA'(crossed[rank_index]);
        end
    endfunction

    /* Les bits et les mots d'un bloc de seuils de groups groupes, G_LOW venant de groups_low (00_groups.vh). */
    /* Ou des G_MAX blocs de T seuils d'un canal, dont un seul passe le décodage du groupe. */
    function automatic [T*THR_W-1:0] or_groups(input [G_MAX*T*THR_W-1:0] terms);
        integer group_index;
        begin
            or_groups = {(T*THR_W){1'b0}};
            for (group_index = 0; group_index < G_MAX; group_index = group_index + 1)
                or_groups = or_groups | terms[group_index*T*THR_W +: T*THR_W];
        end
    endfunction

    function integer block_bits(input integer groups);
        block_bits = K * groups * T * THR_W;
    endfunction

    function integer block_words(input integer groups);
        block_words = (block_bits(groups) + W - 1) / W;
    endfunction

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_count <= {CNT_W{1'b0}};
        else if (w_cache_free)
            r_count <= {CNT_W{1'b0}};
        else if (i_thr_cache_valid)
            r_count <= r_count + 1;

    assign o_thr_cache_ready = !o_thr_cache_full;

    genvar cache_word;
    genvar stage;

    localparam BANK_W = THR_BITS / REP;

    genvar bank_slice;

    generate
        if (groups_low(G, G1) < G_MAX)
            begin : g_g1
                reg                    r_blk_stride1;
                reg                    r_pix_stride1;
                wire [THR_WORDS*W-1:0] w_cache_next;
                /* Compteur à 0 : le prochain mot écrit est le premier d'un bloc. */
                wire                   w_first_word = (r_count == {CNT_W{1'b0}});

                always @(posedge i_clk)
                    if (i_thr_cache_valid && w_first_word)
                        r_blk_stride1 <= i_thr_stride1;

                /* Le mux2 d'entrée et son choix n'existent que si LOW_WORDS < THR_WORDS. Le pas du premier mot
                 * se lit à l'entrée même, avant que le registre de G_BLK le tienne. */
                for (cache_word = 0; cache_word < THR_WORDS - 1; cache_word = cache_word + 1)
                    begin : g_cache_word
                        if (cache_word == block_words(groups_low(G, G1)) - 1)
                            begin : g_low_entry
                                wire w_entry_stride1 = w_first_word ? i_thr_stride1 : r_blk_stride1;
                                wire w_entry_low     = (w_entry_stride1 == (G_S1 < G));

                                assign w_cache_next[cache_word*W +: W] =
                                    w_entry_low ? i_thr_cache_data : r_cache[(cache_word + 1)*W +: W];
                            end
                        else
                            begin : g_shift
                                assign w_cache_next[cache_word*W +: W] = r_cache[(cache_word + 1)*W +: W];
                            end
                    end

                assign w_cache_next[(THR_WORDS - 1)*W +: W] = i_thr_cache_data;

                always @(posedge i_clk)
                    if (i_thr_cache_valid)
                        r_cache <= w_cache_next;

                assign o_thr_cache_full = r_blk_stride1 ? (r_count >= CNT_W'(block_words(G_S1)))
                                                        : (r_count >= CNT_W'(block_words(G)));

                /* Banques des canaux 0 à K G_LOW - 1 à chaque transfert, celles au-delà pour un bloc au G_MAX
                 * seul, G_BLK valant G_MAX au pas 1 quand G_S1 > G et au pas 2 sinon. */
                always @(posedge i_clk)
                    if (i_thr_xfer[0])
                        begin
                            r_bank[block_bits(groups_low(G, G1))-1:0] <= r_cache[block_bits(groups_low(G, G1))-1:0];
                            if (r_blk_stride1 == (G_S1 > G))
                                r_bank[THR_BITS-1:block_bits(groups_low(G, G1))]
                                    <= r_cache[THR_BITS-1:block_bits(groups_low(G, G1))];
                        end

                always @(posedge i_clk)
                    if (i_acc_done)
                        r_pix_stride1 <= i_done_stride1;

                for (stage = 0; stage < G_MAX; stage = stage + 1)
                    begin : g_stage
                        assign w_load_valid[stage] = r_pix_stride1 ? (stage < G_S1) : (stage < G);
                    end

                assign o_lvl_collide = r_load & |r_stage_valid[G_MAX-1:1];
            end
        else
            begin : g_uniform
                integer word;

                always @(posedge i_clk)
                    if (i_thr_cache_valid)
                        begin
                            for (word = 0; word < THR_WORDS - 1; word = word + 1)
                                r_cache[word*W +: W] <= r_cache[(word + 1)*W +: W];
                            r_cache[(THR_WORDS - 1)*W +: W] <= i_thr_cache_data;
                        end

                assign o_thr_cache_full = (r_count >= THR_WORDS[CNT_W-1:0]);

                /* Sous REP = G_MAX, la feuille g de l'arbre de thr_xfer charge la banque du groupe g, au même
                 * cycle que les autres : les banques restent versées ensemble. */
                for (bank_slice = 0; bank_slice < REP; bank_slice = bank_slice + 1)
                    begin : g_bank
                        always @(posedge i_clk)
                            if (i_thr_xfer[bank_slice])
                                r_bank[bank_slice*BANK_W +: BANK_W] <= r_cache[bank_slice*BANK_W +: BANK_W];
                    end

                assign w_load_valid  = {G_MAX{1'b1}};
                assign o_lvl_collide = 1'b0;

                /* Hors variante G1, blocs et pixels sont tous au G de la tuile : les deux pas, que le contrat 8
                 * amendé dit ignorés, ne sont lus que par ce fil, exception de lint. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_strides_ignored = ^{i_thr_stride1, i_done_stride1};
                /* verilator lint_on UNUSEDSIGNAL */
            end
    endgenerate

    genvar channel;
    genvar rank;
    genvar share_filter;
    genvar share_group;

    generate
        if (THR_SHARE == 0)
            begin : g_cardinal
                reg [K*G_MAX*BA-1:0] r_stage;

                assign w_lane_theta = r_bank;

                if (THR_CUT == 0)
                    begin : g_hold
                        reg [K*G_MAX*ACC-1:0] r_hold;

                        assign w_lane_acc   = r_hold;
                        assign w_count_in   = w_crossed_all;
                        assign w_cache_free = i_thr_xfer[0];

                        always @(posedge i_clk)
                            if (i_acc_done)
                                r_hold <= i_acc_word;
                    end
                else
                    begin : g_cut
                        /* Comparaisons du cycle T de acc_done, lues par le compteur de bits au cycle T + 1, seul cycle
                         * où r_load charge r_stage : aucune validation. */
                        reg [LANES*T-1:0] r_crossed;
                        reg               r_xfer_late;

                        assign w_lane_acc   = i_acc_word;
                        assign w_count_in   = r_crossed;
                        assign w_cache_free = r_xfer_late;

                        always @(posedge i_clk)
                            r_crossed <= w_crossed_all;

                        always @(posedge i_clk or negedge i_rst_n)
                            if (!i_rst_n)
                                r_xfer_late <= 1'b0;
                            else
                                r_xfer_late <= i_thr_xfer[0];
                    end

                always @(posedge i_clk)
                    if (r_load)
                        r_stage <= w_level;
                    else
                        r_stage <= r_stage >> (K * BA);

                assign o_lvl_out   = r_stage[0 +: K*BA];
            end
        else
            begin : g_shared
                reg [K*G_MAX*ACC-1:0]   r_hold;
                /* Groupe que lisent les voies, 0 au cycle T + 1, tenu au dernier groupe hors pixel. */
                reg [$clog2(G_MAX)-1:0] r_group;
                reg [K*BA-1:0]          r_lvl;

                assign w_count_in   = w_crossed_all;
                assign w_cache_free = i_thr_xfer[0];

                always @(posedge i_clk)
                    if (i_acc_done)
                        r_hold <= i_acc_word;
                    else
                        r_hold <= r_hold >> (K * ACC);

                always @(posedge i_clk)
                    if (i_acc_done)
                        r_group <= {$clog2(G_MAX){1'b0}};
                    else if (r_group != $clog2(G_MAX)'(G_MAX - 1))
                        r_group <= r_group + 1'b1;

                assign w_lane_acc = r_hold[0 +: K*ACC];

                for (share_filter = 0; share_filter < K; share_filter = share_filter + 1)
                    begin : g_filter
                        wire [G_MAX*T*THR_W-1:0] w_terms;

                        for (share_group = 0; share_group < G_MAX; share_group = share_group + 1)
                            begin : g_group
                                assign w_terms[share_group*T*THR_W +: T*THR_W] =
                                    r_bank[(K*share_group + share_filter)*T*THR_W +: T*THR_W]
                                    & {(T*THR_W){r_group == $clog2(G_MAX)'(share_group)}};
                            end

                        assign w_lane_theta[share_filter*T*THR_W +: T*THR_W] = or_groups(w_terms);
                    end

                always @(posedge i_clk)
                    r_lvl <= w_level;

                assign o_lvl_out = r_lvl;
            end

        for (channel = 0; channel < LANES; channel = channel + 1)
            begin : g_channel
                wire [T-1:0]            w_crossed;
                wire [ACC-1:0]          w_acc_raw = w_lane_acc[channel*ACC +: ACC];
                wire signed [CMP_W-1:0] w_acc     = {{(CMP_W - ACC + 1){w_acc_raw[ACC-1]}}, w_acc_raw[ACC-2:0]};

                for (rank = 0; rank < T; rank = rank + 1)
                    begin : g_rank
                        wire [THR_W-1:0]        w_theta_raw = w_lane_theta[(T*channel + rank)*THR_W +: THR_W];
                        wire signed [CMP_W-1:0] w_theta     = {{(CMP_W - THR_W + 1){w_theta_raw[THR_W-1]}},
                                                                w_theta_raw[THR_W-2:0]};

                        assign w_crossed[rank] = (w_acc >= w_theta);
                    end

                assign w_crossed_all[channel*T +: T] = w_crossed;
                assign w_level[channel*BA +: BA]     = crossed_count(w_count_in[channel*T +: T]);
            end
    endgenerate

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_load <= 1'b0;
        else
            r_load <= i_acc_done;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_stage_valid <= {G_MAX{1'b0}};
        else if (r_load)
            r_stage_valid <= w_load_valid;
        else
            r_stage_valid <= r_stage_valid >> 1;

    assign o_lvl_valid = r_stage_valid[0];

endmodule

`endif
