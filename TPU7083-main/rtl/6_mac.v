`ifndef __MAC_ARRAY__
`define __MAC_ARRAY__

`include "00_params.vh"
`include "6a_mul_s4xu4.v"

/* Multiplieurs, arbres d'addition et registres de pipeline des MAC : contrat 6 de
 * rtl/contrats.md, amendé par la variante V4 de
 * rtl/contrats.md puis par le contrat D.3 de
 * rtl/contrats.md, d'après
 * spec/08_mac.md sections 2 à 4.
 *
 * CE QUE FAIT LE BLOC. À chaque cycle, 9 C K multiplieurs u BA × s BW et K arbres d'addition rendent
 * la somme des 9 C produits de chaque filtre. Le bloc ne s'arrête jamais et n'a ni reset ni signal de
 * validité : sa latence est fixe, STAGES cycles, et le contrôleur cale dessus le calendrier de l'anneau
 * ⑥ (08_mac.md sections 2 et 4). Hors fenêtre, les registres prennent ce qui se présente et ⑥ ne s'en
 * sert pas.
 *
 * PRISES FIXES. Le multiplieur (k, idx, i) lit la voie i de la prise idx de la fenêtre et le poids du
 * filtre k qui lui fait face, à des positions de câblage, sans porte de sélection (08_mac.md
 * section 3.1). Le terme n = idx C + i est ainsi le n-ième champ de la fenêtre, et son poids le
 * n-ième champ du bloc du filtre k dans i_wgt_head. Chaque bit de la fenêtre attaque K multiplieurs.
 *
 * LES COPIES. i_win_data porte COPIES copies de la fenêtre, la copie c en [c × 9 C BA +: 9 C BA], et le
 * filtre k lit la copie ⌊k × COPIES / K⌋, choix écrit une fois, avant l'arbre, pour ses deux branches.
 * COPIES vient de WIN_COPIES sous ② capturée au front, une copie de window_reg par tranche de filtres
 * (contrat 4), et viendrait de REG_COPIES sous le registre d'opérandes, que la garde refuse tant qu'il
 * n'est pas écrit. À COPIES = 1, chaque filtre lit i_win_data comme avant.
 *
 * DEUX ARBRES. TREE = 0 garde l'arbre binaire de la structure écrite sous le multiplieur de référence.
 * TREE = 1 est la réduction 3:2 de Wallace sous le multiplieur de Baugh-Wooley dont les produits
 * partiels sont versés dans l'arbre, MODEL = 2 (bw_fused), suivie de l'additionneur final que nomme
 * FINAL, à propagation (0) ou de Brent-Kung à nœuds inverseurs (3), une instance de mac_csa par
 * filtre. param_check refuse toute autre valeur tant que sa branche n'est pas écrite.
 * Corrigé le 27/10/2026 (tâche 2 du plan A10) : MODEL = 3 a aussi sa branche sous TREE = 1, le multiplieur S4xU4 de
 * Yann Guidon en portes, mul_s4xu4 de 6a_mul_s4xu4.v, une instance par terme, dont le produit signé de 8 bits entre
 * dans l'arbre, p_0 à p_6 dans les colonnes 0 à 6 et ¬p_7 dans la colonne 7, avec la constante −128 × N_TERMS modulo
 * 2^TREE_W : la matrice de bw_ripple, seul le multiplieur changeant. param_check refuse les valeurs sans branche.
 *
 * LES DEUX PIÈGES DE SIGNE (piege.md, dépôt de travail non publié, pièges 1 et 2).
 * Un produit dont un opérande est non signé devient non signé, sans un mot du compilateur : le poids
 * 4'hF y vaut 15 au lieu de -1. L'activation, non signée, s'étend donc d'un bit à zéro sous $signed,
 * et le poids passe lui-même sous $signed. Le produit, signé, se calcule sur les BA + BW bits de son
 * champ, où il tient exactement (spec/02_arithmetique.md
 * section 4.1).
 * Le signe d'un fil se perd aussi dans le fil non signé qui le reçoit. Aucun bus de l'arbre ne compte
 * donc sur son type : chaque extension recopie le bit de poids fort, écrite en toutes lettres.
 * L'anneau ⑥, qui consomme o_mac_sum, doit le lire signé.
 *
 * L'ARBRE BINAIRE. Au niveau l, les termes du niveau l − 1 se prennent par paires dans l'ordre de n et
 * sortent sur BA + BW + l bits. Le dernier terme d'un niveau impair passe seul, étendu d'un bit
 * (08_mac.md section 3.2.2). Un nœud du niveau l somme au plus 2^l produits, que ces largeurs tiennent :
 * aucun débordement (02_arithmetique.md section 4.2).
 *
 * SES COUPES. Un registre suit chaque niveau d'une coupe non nulle, CUT_A, CUT_B puis CUT_C, et un
 * dernier la racine : les entrées du cycle t sortent pendant le cycle t + STAGES, STAGES − 1 coupes
 * écrites en tête que tient la garde. Une coupe nulle ne pose aucun registre, d'où la garde
 * CUT_X != 0 de chaque terme, sans laquelle le niveau 0, les produits, en prendrait un. Ces coupes ne
 * portent que l'arbre binaire, donc le seul défaut de 00_params.vh : les accords de la liste posent
 * l'arbre de Wallace sans coupe du jeu, MAC_TREE = 1 et MAC_CUT_A = 0.
 * Corrigé le 26/10/2026 (tâche 1 du plan A8) : elles portent aussi l'arbre 3:2, où chacune compte en
 * niveaux de réduction (SES ÉTAGES plus bas), les accords de la liste gardant l'arbre de Wallace sans
 * coupe du jeu.
 * C'est l'additionneur complet à retenue en une porte a21o, décision J5 d'architecture du 10/10/2026, qui
 * fait tenir l'arbre de 9 niveaux en trois étages. La configuration de calage, K = 2, le coupait après
 * les niveaux 2 et 6 : 5,10, 5,20 et 5,25 ns au coin lent, sous les 5,98 ns d'un cycle à 150 MHz,
 * pour 2 390 bascules. Celui de convgen, retenue en deux portes, demandait six étages et 4 950
 * bascules (08_mac.md sections 3.3, 3.4 et 6).
 * Le défaut coupe après le niveau 1 (CUT_A = 1, CUT_B = 6), à cause du changement de rangée serré,
 * G = max(2 M + 2, 3 M) = 6 à M = 2 : ② y est transparente au cycle même où l'esclave de ③ s'ouvre, et
 * l'activation n'atteint les multiplieurs qu'après cet esclave, le mux2 et le and2 du haut puis ②,
 * 1,525 ns après le front au lieu de 0,581 ns. latency.tree_registers rend alors les coupes [1, 6], en
 * étages de 5,795, 5,806 et 5,254 ns à K = 8, et [2, 6] hors de ce régime, en 5,678, 5,200 et 5,254 ns.
 * La coupe en 2 épargnerait 6 912 bascules à K = 8 (16 472 contre 9 560), environ 0,34 mm² à 48,99 µm²
 * la bascule, mais ne tient pas le budget de l'étage 1, 5,979 ns moins 0,1 ns de marge, au régime
 * serré. Le retard vient du chemin des données, que la commande de ② ne change pas : la registrer
 * ôte win_load de ce chemin sans rendre la coupe en 2 possible (tuner/latency.py de
 * accordeur au commit 37ea1ed0, point
 * 6_mac.v:55 de la revue du RTL d'af5ab629).
 *
 * LA TROISIÈME COUPE. Quand CUT_C n'est pas nul, un registre suit aussi le niveau CUT_C, entre CUT_B
 * et la racine, et les entrées du cycle t sortent pendant le cycle t + 4 : L_MAC = 4. Sa raison : dès
 * C ≥ 57, les 9 C ≥ 513 produits demandent 10 niveaux, et aucun pipeline à trois étages ne les tient
 * dans les 5,979 ns qu'un étage tient à 150 MHz. Sa dernière coupe devrait suivre le niveau 7 au moins,
 * l'étage parti du niveau 6 mettant 6,081 ns jusqu'au niveau 10 et celui du niveau 7, 5,474 ns. La
 * coupe d'avant devrait suivre le niveau 3 au moins, l'étage parti du niveau 2 mettant 6,027 ns jusqu'au
 * niveau 7 et celui du niveau 3, 5,420 ns. Or l'étage 1 n'atteint pas le niveau 3, qui sort à 5,924 ns
 * des poids, plus le décalage de la fenêtre, quand le premier étage ne tient que 5,879 ns, le budget
 * moins une marge de 0,1 ns. Le modèle de latence de l'accordeur, latency.tree_registers, rend donc les
 * coupes [1, 6, 9] aux accords à C = 64, en étages de 5,795, 5,806, 5,254 et 4,261 ns à K = 8 au
 * changement de rangée serré (tuner/latency.py et tuner/data/tree_segments.json de
 * accordeur au commit 8f53fda). La variante V4 du
 * plan d'origine ne l'écrivait que si un accord retenait C ≥ 57, levier technique du 12/10/2026
 * (dépôt de travail non publié, ligne 7245 au commit 5bcb0b8) : dépôt de travail non publié la remplace, la liste des accords
 * en portant trois à C = 64.
 *
 * LA RÉDUCTION 3:2 (08_mac.md section 3.2.1, partial_products, fused_columns et wallace de
 * tuner/arith/mult.py et trees.py de accordeur).
 * Chaque terme verse ses BA × BW produits partiels de Baugh-Wooley dans TREE_W colonnes : a_j ∧ w_i dans
 * la colonne i + j pour i de 0 à BW − 2, ¬(a_j ∧ w_(BW − 1)) dans la colonne BW − 1 + j, puis un bit à 1
 * entre dans chaque colonne où la constante (−(2^BA − 1) × 2^(BW − 1) × N_TERMS) modulo 2^TREE_W, soit
 * −120 × 9 C au u4 × s4, a un 1. Une colonne range ses bits terme après terme, les and2 par i croissant
 * puis le nand2, la constante en dernier. À chaque niveau, une colonne de hauteur h prend ⌊h / 3⌋
 * additionneurs complets, puis un demi-additionneur si le reste vaut 2, et le bit restant passe : la
 * colonne du niveau suivant reçoit d'abord les retenues de sa voisine de droite, puis ses sommes, puis
 * ce bit, et une retenue au-delà de la colonne TREE_W − 1 tombe. La réduction s'arrête à deux bits au
 * plus par colonne, que l'additionneur final somme modulo 2^TREE_W.
 * Les hauteurs de chaque niveau, calculées une fois dans CSA_TABLE, bornent toutes les boucles de la
 * réduction, et L_CSA, FA_COUNT et HA_COUNT en sortent par les mêmes fonctions (réponse à I2 de la
 * relecture RTL des suites) : test/model/tests/test_csa_counts.py les compare à mac_trees.json
 * de l'accordeur et compte les blocs g_fa et g_ha que Verilator élabore.
 * Chaque bit d'un niveau est un fil d'un tableau, pas un bit d'un bus plat : un bus large écrit bit par
 * bit réveille sous Icarus tous ses lecteurs à chaque écriture, un coût quadratique.
 *
 * SES ÉTAGES. Sans coupe du jeu (CUT_A = CUT_B = CUT_C = 0, « la garde le tient », corrigé le 26/10/2026 :
 * les coupes du jeu sont admises, voir plus bas), STAGES − 1 registres
 * suivent les niveaux de réduction ⌈k × L_CSA / STAGES⌉, k de 1 à STAGES − 1, chacun sur tous les bits
 * de ses colonnes, puis le registre de sortie suit l'additionneur final, le seul à STAGES = 1
 * : les entrées du cycle t sortent pendant le cycle t + STAGES. L_CSA vaut 7 au moins
 * (C = 1) et STAGES 4 au plus, si bien que ces niveaux sont distincts et précèdent le dernier. La pose
 * au grain des portes reste à la netlist.
 * Corrigé le 27/10/2026 (tâche 2 du plan A10) : sous MODEL = 3, L_CSA vaut 5 au moins (C = 1). Ces niveaux restent
 * distincts et sous L_CSA, qui dépasse toujours STAGES.
 * Avec des coupes du jeu (tâche 1 du plan A8, 26/10/2026), un registre suit le niveau de réduction de chaque
 * coupe non nulle, CUT_A, CUT_B puis CUT_C, sur tous les bits de ses colonnes, et le registre de sortie
 * l'additionneur final, d'où la même latence. À C = 48, L_CSA = 17 : à L_MAC = 4 sous ② au front, STAGES = 3,
 * les coupes nominales tombent après les niveaux 6 et 12, et les coupes du jeu (8, 13) registrent 284 puis
 * 51 bits au lieu de 619 et 69. La règle des coupes du jeu, non nulles en tête, strictement croissantes, de 1
 * à L_CSA − 1, au nombre de STAGES − 1, est la règle CSA_SET_CUTS de param_check, que mac_csa tient aussi
 * lui-même, le rejeu de rtl/pnr/pnr_bloc.py synthétisant ce fichier sans param_check.
 *
 * L'ADDITIONNEUR FINAL (08_mac.md section 3.3, add et _prefix de tuner/arith/adders.py), retenue sortante
 * abandonnée. FINAL = 0 : demi-additionneur au bit 0, additionneurs complets a21o au-delà. FINAL = 3 :
 * préfixe de Brent-Kung, g = x ∧ y et p = x ⊕ y, (g, p) ∘ (g', p') = (g ∨ p ∧ g', p ∧ p') sur les
 * couples de pairs, chaque nœud en cellule à un étage selon la polarité de ses entrées :
 * a21oi et nand2 sur des entrées directes, qui rendent des sorties inversées, o21ai et nor2 sur des
 * entrées inversées, qui rendent des sorties directes, un opérande d'une autre polarité inversé, puis
 * s_0 = p_0 et s_i = p_i ⊕ G_(i − 1), en xnor sur une retenue inversée. FINAL = 5 : aucun additionneur,
 * les deux rangées de la réduction sont registrées telles quelles, o_sum portant la rangée x en [TREE_W-1:0] et la
 * rangée y au-dessus (ROWS = 2), et l'additionneur de ⑥ les ajoute par une rangée de 3:2 (Hoang et al. 2010,
 * branche d'étude rtl-mac300-somme). mac_array pose alors TREE_W = ACC, pour que la constante de Baugh-Wooley et les
 * retenues se calculent modulo 2^ACC, ce qui rend la somme des rangées juste sans extension de signe.
 *
 * LA SORTIE. Quand TREE_W < ACC, la somme s'étend par le signe jusqu'à ACC bits, par câblage : la
 * spécification étend ainsi 17 bits utiles à 19. Sinon elle garde ses ACC bits bas et replie modulo
 * 2^ACC, comme _wrap d'AsicSim (02_arithmetique.md section 4.3).
 */

/* La réduction 3:2 d'un filtre, son additionneur final et ses étages : la branche TREE ≠ 0 de mac_array (contrat D.3 de
 * rtl/contrats.md), qui en pose une instance par filtre. i_act porte les
 * 9 C activations de la copie que lit le filtre, i_wgt ses 9 C poids, terme n = idx C + i, et o_sum la somme sur TREE_W
 * bits, STAGES cycles après ses entrées. Un module par filtre plutôt qu'un bloc generate : Verilator y met un tiers de
 * temps de moins, 10,6 s au lieu de 16,2 s pour le lint à C = 8 et K = 5 (mesure locale du 19/10/2026), Icarus autant. */

module mac_csa #(parameter C       = `TILE_C,
                 parameter BA      = `TILE_BA,
                 parameter BW      = `TILE_BW,
                 parameter CUT_A   = `TILE_MAC_CUT_A,
                 parameter CUT_B   = `TILE_MAC_CUT_B,
                 parameter CUT_C   = `TILE_MAC_CUT_C,
                 parameter TREE    = `TILE_MAC_TREE,
                 parameter MODEL   = `TILE_MAC_MODEL,
                 parameter FINAL   = `TILE_FINAL_ADDER,
                 parameter STAGES  = `TILE_L_MAC - ((`TILE_WIN_LOAD != 0) ? 1 : 0),
                 parameter N_TERMS = 9 * C,
                 parameter TREE_W  = BA + BW + $clog2(N_TERMS),
                 parameter ROWS    = (FINAL == 5) ? 2 : 1)
                (input                    i_clk,
                 input  [9*C*BA-1:0]      i_act,
                 input  [9*C*BW-1:0]      i_wgt,
                 output [ROWS*TREE_W-1:0] o_sum);

    /* Produits partiels d'un terme dans la colonne col : les and2 a_j ∧ w_i, i + j = col, i de csa_and_first(col)
     * à BW − 2, puis le nand2 de la rangée de signe quand col − (BW − 1) est un j de 0 à BA − 1. */
    function integer csa_and_first(input integer col);
        csa_and_first = (col > BA - 1) ? col - (BA - 1) : 0;
    endfunction

    function integer csa_and_count(input integer col);
        integer last;
        begin
            last          = (col < BW - 2) ? col : BW - 2;
            csa_and_count = (last >= csa_and_first(col)) ? last - csa_and_first(col) + 1 : 0;
        end
    endfunction

    /* Sous MODEL = 3, un bit par colonne de 0 à BA + BW − 1, celui du produit de mul_s4xu4 (tâche 2 du plan A10). */
    function integer csa_term_bits(input integer col);
        if (MODEL == 3)
            csa_term_bits = (col < BA + BW) ? 1 : 0;
        else
            csa_term_bits = csa_and_count(col) + ((col >= BW - 1 && col < BW - 1 + BA) ? 1 : 0);
    endfunction

    /* Bit col de la constante de Baugh-Wooley du filtre, (−(2^BA − 1) × 2^(BW − 1) × N_TERMS) mod 2^TREE_W, et sous
     * MODEL = 3, (−2^(BA + BW − 1) × N_TERMS) mod 2^TREE_W, soit −128 × N_TERMS, qui compense ¬p_7. */
    function integer csa_constant_bit(input integer col);
        integer modulus;
        integer magnitude;
        begin
            modulus          = 1 << TREE_W;
            magnitude        = (((MODEL == 3) ? 1 << (BA + BW - 1) : ((1 << BA) - 1) * (1 << (BW - 1))) * N_TERMS)
                               % modulus;
            csa_constant_bit = (((modulus - magnitude) % modulus) >> col) & 1;
        end
    endfunction

    function integer csa_start_height(input integer col);
        csa_start_height = (MODEL == 2 || MODEL == 3) ? N_TERMS * csa_term_bits(col) + csa_constant_bit(col) : 0;
    endfunction

    /* Réduction de Wallace d'une colonne de hauteur height : ⌊height / 3⌋ additionneurs complets, puis un
     * demi-additionneur si le reste vaut 2. */
    function integer csa_fa_rule(input integer height);
        csa_fa_rule = height / 3;
    endfunction

    function integer csa_ha_rule(input integer height);
        csa_ha_rule = (height % 3 == 2) ? 1 : 0;
    endfunction

    /* Hauteurs des TREE_W colonnes, HEIGHT_W bits chacune : la plus haute, au départ, compte au plus les
     * BA × BW × N_TERMS produits partiels et la constante. */
    localparam HEIGHT_W = $clog2(BA * BW * N_TERMS + 2);

    function [TREE_W*HEIGHT_W-1:0] csa_step(input [TREE_W*HEIGHT_W-1:0] heights);
        integer col;
        integer height;
        integer carries;
        begin
            carries = 0;
            for (col = 0; col < TREE_W; col = col + 1)
                begin
                    height = 32'(heights[col*HEIGHT_W +: HEIGHT_W]);
                    csa_step[col*HEIGHT_W +: HEIGHT_W] =
                        HEIGHT_W'(height - 2 * csa_fa_rule(height) - csa_ha_rule(height) + carries);
                    carries = csa_fa_rule(height) + csa_ha_rule(height);
                end
        end
    endfunction

    function [TREE_W*HEIGHT_W-1:0] csa_start(input integer cols);
        integer col;
        begin
            csa_start = {(TREE_W*HEIGHT_W){1'b0}};
            for (col = 0; col < cols; col = col + 1)
                csa_start[col*HEIGHT_W +: HEIGHT_W] = HEIGHT_W'(csa_start_height(col));
        end
    endfunction

    function integer csa_tallest(input [TREE_W*HEIGHT_W-1:0] heights);
        integer col;
        begin
            csa_tallest = 0;
            for (col = 0; col < TREE_W; col = col + 1)
                if (32'(heights[col*HEIGHT_W +: HEIGHT_W]) > csa_tallest)
                    csa_tallest = 32'(heights[col*HEIGHT_W +: HEIGHT_W]);
        end
    endfunction

    /* Niveaux de réduction jusqu'à target bits au plus par colonne. */
    function integer csa_levels_to(input integer target);
        reg [TREE_W*HEIGHT_W-1:0] heights;
        begin
            csa_levels_to = 0;
            heights       = csa_start(TREE_W);
            while (csa_tallest(heights) > target)
                begin
                    heights       = csa_step(heights);
                    csa_levels_to = csa_levels_to + 1;
                end
        end
    endfunction

    localparam L_CSA = (TREE == 0) ? 0 : csa_levels_to(2);

    /* Hauteurs de chaque colonne au départ puis après chaque niveau, levels + 1 rangées de TREE_W colonnes. */
    function [(L_CSA+1)*TREE_W*HEIGHT_W-1:0] csa_table(input integer levels);
        reg [TREE_W*HEIGHT_W-1:0] heights;
        integer depth;
        begin
            heights = csa_start(TREE_W);
            for (depth = 0; depth <= levels; depth = depth + 1)
                begin
                    csa_table[depth*TREE_W*HEIGHT_W +: TREE_W*HEIGHT_W] = heights;
                    heights = csa_step(heights);
                end
        end
    endfunction

    localparam [(L_CSA+1)*TREE_W*HEIGHT_W-1:0] CSA_TABLE = csa_table(L_CSA);

    function integer csa_height(input integer depth, input integer col);
        csa_height = 32'(CSA_TABLE[(depth*TREE_W + col)*HEIGHT_W +: HEIGHT_W]);
    endfunction

    /* Bits des colonnes de 0 à col − 1 au niveau depth : la place de la colonne col dans son tableau. */
    function integer csa_offset(input integer depth, input integer col);
        integer lower;
        begin
            csa_offset = 0;
            for (lower = 0; lower < col; lower = lower + 1)
                csa_offset = csa_offset + csa_height(depth, lower);
        end
    endfunction

    /* Additionneurs complets, demi-additionneurs et bits passés de la colonne col au niveau depth, de 1 à L_CSA,
     * puis les retenues qu'elle reçoit de la colonne col − 1. */
    function integer csa_fa(input integer depth, input integer col);
        csa_fa = csa_fa_rule(csa_height(depth - 1, col));
    endfunction

    function integer csa_ha(input integer depth, input integer col);
        csa_ha = csa_ha_rule(csa_height(depth - 1, col));
    endfunction

    function integer csa_pass(input integer depth, input integer col);
        csa_pass = csa_height(depth - 1, col) - 3 * csa_fa(depth, col) - 2 * csa_ha(depth, col);
    endfunction

    function integer csa_carries_in(input integer depth, input integer col);
        csa_carries_in = (col == 0) ? 0 : csa_fa(depth, col - 1) + csa_ha(depth, col - 1);
    endfunction

    function integer csa_fa_total(input integer levels);
        integer depth;
        integer col;
        begin
            csa_fa_total = 0;
            for (depth = 1; depth <= levels; depth = depth + 1)
                for (col = 0; col < TREE_W; col = col + 1)
                    csa_fa_total = csa_fa_total + csa_fa(depth, col);
        end
    endfunction

    function integer csa_ha_total(input integer levels);
        integer depth;
        integer col;
        begin
            csa_ha_total = 0;
            for (depth = 1; depth <= levels; depth = depth + 1)
                for (col = 0; col < TREE_W; col = col + 1)
                    csa_ha_total = csa_ha_total + csa_ha(depth, col);
        end
    endfunction

    /* FA_COUNT et HA_COUNT, additionneurs complets et demi-additionneurs d'un filtre, ne servent qu'à
     * test/probe_csa.v, qui les lit par référence hiérarchique avec L_CSA : exception du lint bornée à leurs
     * deux lignes. */
    /* verilator lint_off UNUSEDPARAM */
    localparam FA_COUNT = csa_fa_total(L_CSA);
    localparam HA_COUNT = csa_ha_total(L_CSA);
    /* verilator lint_on UNUSEDPARAM */

    /* Coupes du jeu, CUT_A, CUT_B puis CUT_C (tâche 1 du plan A8, 26/10/2026) : non nulles en tête, strictement croissantes,
     * de 1 à L_CSA − 1, au nombre de STAGES − 1, ou toutes nulles. La garde est propre au module, le rejeu de
     * rtl/pnr/pnr_bloc.py synthétisant ce fichier sans param_check : hors de cette règle, l'élaboration s'arrête sur le
     * message de la règle CSA_SET_CUTS de param_check. Un $error d'élaboration à une seule chaîne, Icarus 13 n'admettant
     * pas d'argument de plus et l'outil de synthèse générique perdant le texte d'un $fatal. */
    localparam CUT_COUNT = ((CUT_A != 0) ? 1 : 0) + ((CUT_B != 0) ? 1 : 0) + ((CUT_C != 0) ? 1 : 0);
    localparam CUT_LAST  = (CUT_C != 0) ? CUT_C : (CUT_B != 0) ? CUT_B : CUT_A;
    localparam CUTS_OK   = CUT_COUNT == 0
                           || (CUT_A >= 1 && (CUT_C == 0 || CUT_B != 0) && (CUT_B == 0 || CUT_B > CUT_A)
                               && (CUT_C == 0 || CUT_C > CUT_B) && CUT_LAST < L_CSA && CUT_COUNT + 1 == STAGES);

    generate
        if (!CUTS_OK)
            begin : g_cuts_refused
                $error("ECHEC parametres : coupes de l'arbre 3:2 hors regle, non nulles en tete, strictement croissantes, de 1 a L_CSA - 1, au nombre de STAGES - 1");
            end
    endgenerate

    /* Registres de la réduction : après le niveau de chaque coupe du jeu non nulle, ou, les trois nulles, après les
     * niveaux nominaux ⌈k × L_CSA / STAGES⌉, k de 1 à STAGES − 1. La garde CUT_X != 0 de chaque terme ôte le registre du
     * niveau 0, les produits, à une coupe nulle. */
    function integer csa_cut(input integer depth);
        integer stage;
        begin
            csa_cut = 0;
            if (CUT_COUNT != 0)
                csa_cut = ((CUT_A != 0 && depth == CUT_A) || (CUT_B != 0 && depth == CUT_B)
                           || (CUT_C != 0 && depth == CUT_C)) ? 1 : 0;
            else
                for (stage = 1; stage < STAGES; stage = stage + 1)
                    if (depth == (stage * L_CSA + STAGES - 1) / STAGES)
                        csa_cut = 1;
        end
    endfunction

    function integer csa_cut_count(input integer levels);
        integer depth;
        begin
            csa_cut_count = 0;
            for (depth = 0; depth <= levels; depth = depth + 1)
                csa_cut_count = csa_cut_count + csa_cut(depth);
        end
    endfunction

    /* La réduction se déroule en pas : le pas 0 porte les produits partiels, chaque pas suivant un niveau de
     * réduction, ou, juste après un niveau de coupe, les registres de ce niveau. Rend 2 × niveau + 1 pour un pas de
     * registres, 2 × niveau pour un pas de réduction. */
    function integer csa_step_kind(input integer step_index);
        integer passed;
        integer depth;
        integer registers;
        begin
            depth     = 0;
            registers = 0;
            for (passed = 1; passed <= step_index; passed = passed + 1)
                if (registers == 0 && csa_cut(depth) != 0)
                    registers = 1;
                else
                    begin
                        depth     = depth + 1;
                        registers = 0;
                    end
            csa_step_kind = 2 * depth + registers;
        end
    endfunction

    /* Préfixe de Brent-Kung sur TREE_W bits, pairs de tuner/arith/adders.py : BK_UP niveaux de montée, d = 1, 2,
     * 4 et ainsi de suite tant que d < TREE_W, puis BK_UP − 1 niveaux de descente, d de 2^(BK_UP − 2) à 1. */
    localparam BK_UP     = $clog2(TREE_W);
    localparam BK_LEVELS = 2 * BK_UP - 1;

    function integer bk_span(input integer depth);
        bk_span = (depth <= BK_UP) ? 1 << (depth - 1) : 1 << (2 * BK_UP - 1 - depth);
    endfunction

    /* Le nœud node prend (G, P)[node] ∘ (G, P)[node − d] au niveau depth : node = 2 d − 1, 4 d − 1 et au-delà de
     * 2 d en 2 d à la montée, node = 3 d − 1, 5 d − 1 et au-delà à la descente. */
    function integer bk_target(input integer depth, input integer node);
        if (depth <= BK_UP)
            bk_target = ((node + 1) % (2 * bk_span(depth)) == 0) ? 1 : 0;
        else
            bk_target = ((node + 1) % (2 * bk_span(depth)) == bk_span(depth) && node + 1 > bk_span(depth)) ? 1 : 0;
    endfunction

    /* Polarité du nœud node après depth niveaux : chaque cellule à un étage l'inverse. */
    function integer bk_direct(input integer depth, input integer node);
        integer passed;
        begin
            bk_direct = 1;
            for (passed = 1; passed <= depth; passed = passed + 1)
                if (bk_target(passed, node) != 0)
                    bk_direct = 1 - bk_direct;
        end
    endfunction

    /* Le dernier pas, celui du niveau L_CSA, après les STAGES − 1 pas de registres. */
    localparam LAST = L_CSA + csa_cut_count(L_CSA);

    /* Le calendrier se calcule une fois, en tables de tête, avant toute expansion des generate, et les generate n'en
     * lisent que des tranches. L'outil de synthèse générique recopie la table des noms du module à chaque appel de
     * fonction constante, et résout en temps quadratique un localparam ou un fil de bloc englobant lu par des milliers
     * de blocs internes : appelées dans les generate, ces fonctions et ces localparam portaient l'élaboration à une
     * heure à C = 48, contre 40 s ainsi (profil du 21/10/2026, dépôt de travail non publié).
     * Les fonctions restent, pour ces tables et pour test/probe_csa.v. Entrées de 32 bits. */
    localparam TW1 = TREE_W + 1;

    /* Place de la colonne col au niveau depth, col de 0 à TREE_W, la dernière valant les bits du niveau. */
    function [(L_CSA+1)*TW1*32-1:0] csa_offset_table(input integer levels);
        integer depth;
        integer col;
        begin
            csa_offset_table = 0;
            for (depth = 0; depth <= levels; depth = depth + 1)
                for (col = 0; col <= TREE_W; col = col + 1)
                    csa_offset_table[(depth*TW1 + col)*32 +: 32] = csa_offset(depth, col);
        end
    endfunction

    /* Au niveau depth de 1 à L_CSA et à la colonne col : additionneurs complets, demi-additionneurs, bits passés,
     * retenues reçues de la colonne col − 1. */
    function [(L_CSA+1)*TREE_W*128-1:0] csa_adder_table(input integer levels);
        integer depth;
        integer col;
        begin
            csa_adder_table = 0;
            for (depth = 1; depth <= levels; depth = depth + 1)
                for (col = 0; col < TREE_W; col = col + 1)
                    csa_adder_table[(depth*TREE_W + col)*128 +: 128] =
                        {32'(csa_carries_in(depth, col)), 32'(csa_pass(depth, col)), 32'(csa_ha(depth, col)),
                         32'(csa_fa(depth, col))};
        end
    endfunction

    /* Colonne col du pas 0 : bits d'un terme, and2 d'un terme, premier i des and2, bit de la constante. */
    function [TREE_W*128-1:0] csa_column_table(input integer cols);
        integer col;
        begin
            csa_column_table = 0;
            for (col = 0; col < cols; col = col + 1)
                csa_column_table[col*128 +: 128] =
                    {32'(csa_constant_bit(col)), 32'(csa_and_first(col)), 32'(csa_and_count(col)),
                     32'(csa_term_bits(col))};
        end
    endfunction

    /* Genre de chaque pas, 2 × niveau + 1 pour un pas de registres, puis sa base dans w_bits_all, somme des bits des
     * pas précédents, la dernière entrée valant le total. */
    function [(LAST+1)*32-1:0] csa_step_table(input integer steps);
        integer step_index;
        begin
            csa_step_table = 0;
            for (step_index = 0; step_index <= steps; step_index = step_index + 1)
                csa_step_table[step_index*32 +: 32] = csa_step_kind(step_index);
        end
    endfunction

    function [(LAST+2)*32-1:0] csa_base_table(input integer steps);
        integer step_index;
        integer sum;
        begin
            csa_base_table = 0;
            sum            = 0;
            for (step_index = 0; step_index <= steps; step_index = step_index + 1)
                begin
                    csa_base_table[step_index*32 +: 32] = sum;
                    sum = sum + csa_offset(csa_step_kind(step_index) / 2, TREE_W);
                end
            csa_base_table[(steps+1)*32 +: 32] = sum;
        end
    endfunction

    /* Préfixe de Brent-Kung : nœud du niveau depth au bit node, polarités des deux entrées égales, entrée directe,
     * puis polarité du dernier niveau, et l'écart de chaque niveau. */
    function [(BK_LEVELS+1)*TREE_W*4-1:0] bk_node_table(input integer levels);
        integer depth;
        integer node;
        begin
            bk_node_table = 0;
            for (depth = 1; depth <= levels; depth = depth + 1)
                for (node = 0; node < TREE_W; node = node + 1)
                    if (bk_target(depth, node) != 0)
                        bk_node_table[(depth*TREE_W + node)*4 +: 3] =
                            {bk_direct(depth - 1, node) != 0,
                             bk_direct(depth - 1, node - bk_span(depth)) == bk_direct(depth - 1, node), 1'b1};
            for (node = 0; node < TREE_W; node = node + 1)
                bk_node_table[node*4 + 3] = bk_direct(levels, node) != 0;
        end
    endfunction

    function [(BK_LEVELS+1)*32-1:0] bk_span_table(input integer levels);
        integer depth;
        begin
            bk_span_table = 0;
            for (depth = 1; depth <= levels; depth = depth + 1)
                bk_span_table[depth*32 +: 32] = bk_span(depth);
        end
    endfunction

    localparam [(L_CSA+1)*TW1*32-1:0]       OFF_TABLE  = csa_offset_table(L_CSA);
    localparam [(L_CSA+1)*TREE_W*128-1:0]   ADD_TABLE  = csa_adder_table(L_CSA);
    localparam [TREE_W*128-1:0]             COL_TABLE  = csa_column_table(TREE_W);
    localparam [(LAST+1)*32-1:0]            STEP_TABLE = csa_step_table(LAST);
    localparam [(LAST+2)*32-1:0]            BASE_TABLE = csa_base_table(LAST);
    /* Les tables du préfixe ne se lisent que sous FINAL = 3 : exception du lint bornée à leurs deux lignes. */
    /* verilator lint_off UNUSEDPARAM */
    localparam [(BK_LEVELS+1)*TREE_W*4-1:0] BK_TABLE   = bk_node_table(BK_LEVELS);
    localparam [(BK_LEVELS+1)*32-1:0]       SPAN_TABLE = bk_span_table(BK_LEVELS);
    /* verilator lint_on UNUSEDPARAM */
    localparam ALL_BITS = BASE_TABLE[(LAST+1)*32 +: 32];
    localparam LAST_AT  = BASE_TABLE[LAST*32 +: 32];

    /* Les bits de chaque pas, à la base de ce pas : un seul tableau du module plutôt qu'un tableau par bloc de pas,
     * qu'un bloc interne lirait dans son bloc englobant. Un tableau de fils plutôt qu'un vecteur, dont Icarus résout
     * les milliers de pilotes d'un bit en temps quadratique, découpé en fils par split_var, sans quoi Verilator le
     * convertit en un temps triple (mac_array à C = 16, 21/10/2026 : Icarus 161 s de CPU en vecteur, 23 s en tableau,
     * 14 s au commit af5ab629, Verilator 66 s sans split_var, 23 s avec, 19 s au commit af5ab629). */
    wire w_bits_all [0:ALL_BITS-1] /*verilator split_var*/;

    wire [TREE_W-1:0] w_row_x;
    wire [TREE_W-1:0] w_row_y;
    wire [ROWS*TREE_W-1:0] w_sum;
    reg  [ROWS*TREE_W-1:0] r_sum;

    genvar level;
    genvar step;
    genvar column;
    genvar slot;
    genvar adder;

    /* Lectures des tables par les genvar, sans localparam par bloc : Verilator en élabore chacun, un tiers du temps de
     * lint à C = 8 (mesure locale du 19/10/2026). Propres à ce fichier, retirées à sa fin. */
    `define CSA_OFF(d, c)    OFF_TABLE[((d)*TW1 + (c))*32 +: 32]
    `define CSA_ADD(d, c, k) ADD_TABLE[((d)*TREE_W + (c))*128 + (k)*32 +: 32]
    `define CSA_COL(c, k)    COL_TABLE[(c)*128 + (k)*32 +: 32]
    `define CSA_LEVEL(s)     (STEP_TABLE[(s)*32 +: 32] / 2)
    `define CSA_REG(s)       (STEP_TABLE[(s)*32 +: 32] % 2)
    `define CSA_AT(s)        BASE_TABLE[(s)*32 +: 32]
    `define CSA_HEIGHT(d, c) CSA_TABLE[((d)*TREE_W + (c))*HEIGHT_W +: HEIGHT_W]
    `define CSA_PER(c)       `CSA_COL(c, 0)
    `define CSA_ANDS(c)      `CSA_COL(c, 1)
    `define CSA_FIRST(c)     `CSA_COL(c, 2)
    `define CSA_ONE(c)       `CSA_COL(c, 3)
    `define CSA_FULL(s, c)   `CSA_ADD(`CSA_LEVEL(s), c, 0)
    `define CSA_HALF(s, c)   `CSA_ADD(`CSA_LEVEL(s), c, 1)
    `define CSA_PASS(s, c)   `CSA_ADD(`CSA_LEVEL(s), c, 2)
    `define CSA_IN(s, c)     (`CSA_AT((s) - 1) + `CSA_OFF(`CSA_LEVEL(s) - 1, c))
    `define CSA_OUT(s, c)    (`CSA_AT(s) + `CSA_OFF(`CSA_LEVEL(s), c) + `CSA_ADD(`CSA_LEVEL(s), c, 3))
    `define CSA_NEXT(s, c)   (`CSA_AT(s) + `CSA_OFF(`CSA_LEVEL(s), (c) + 1))
    `define CSA_BK_NODE(l, n) BK_TABLE[((l)*TREE_W + (n))*4]
    `define CSA_BK_SAME(l, n) BK_TABLE[((l)*TREE_W + (n))*4 + 1]
    `define CSA_BK_AOI(l, n)  BK_TABLE[((l)*TREE_W + (n))*4 + 2]
    `define CSA_BK_LAST(n)    BK_TABLE[(n)*4 + 3]

    generate
        for (step = 0; step <= LAST; step = step + 1)
            begin : g_csa_step
                if (step == 0)
                    begin : g_columns
                        for (column = 0; column < TREE_W; column = column + 1)
                            begin : g_column
                                for (slot = 0; slot < ((MODEL == 3) ? 0 : N_TERMS * `CSA_PER(column)); slot = slot + 1)
                                    begin : g_bit
                                        /* Le bit slot % PER du terme slot / PER : and2 a_j ∧ w_i,
                                         * i = FIRST + slot % PER, ou nand2 de la rangée de signe,
                                         * i = BW − 1, un and2 inversé, j = column − i. */
                                        assign w_bits_all[`CSA_OFF(0, column) + slot] =
                                            (i_act[(slot / `CSA_PER(column))*BA + column
                                                   - ((slot % `CSA_PER(column) < `CSA_ANDS(column))
                                                      ? `CSA_FIRST(column) + slot % `CSA_PER(column) : BW - 1)]
                                             & i_wgt[(slot / `CSA_PER(column))*BW
                                                     + ((slot % `CSA_PER(column) < `CSA_ANDS(column))
                                                        ? `CSA_FIRST(column) + slot % `CSA_PER(column) : BW - 1)])
                                            ^ ((slot % `CSA_PER(column) < `CSA_ANDS(column)) ? 1'b0 : 1'b1);
                                    end

                                if (`CSA_ONE(column) != 0)
                                    begin : g_one
                                        assign w_bits_all[`CSA_OFF(0, column) + N_TERMS * `CSA_PER(column)] = 1'b1;
                                    end
                            end

                        /* MODEL = 3 (tâche 2 du plan A10) : un multiplieur S4xU4 par terme, poids sur i_s, activation sur
                         * i_u. Le bit column de son produit entre au rang slot de la colonne column, terme après terme
                         * comme sous MODEL = 2, inversé à la colonne BA + BW − 1, le bit de signe, que la constante
                         * −2^(BA + BW − 1) × N_TERMS compense. */
                        if (MODEL == 3)
                            begin : g_s4xu4
                                for (slot = 0; slot < N_TERMS; slot = slot + 1)
                                    begin : g_term
                                        wire [BA+BW-1:0] w_p;

                                        mul_s4xu4 u_mul (.i_s(i_wgt[slot*BW +: BW]), .i_u(i_act[slot*BA +: BA]), .o_p(w_p));

                                        for (column = 0; column < BA + BW; column = column + 1)
                                            begin : g_bit
                                                assign w_bits_all[`CSA_OFF(0, column) + slot] =
                                                    w_p[column] ^ ((column == BA + BW - 1) ? 1'b1 : 1'b0);
                                            end
                                    end
                            end
                    end
                else if (`CSA_REG(step) != 0)
                    begin : g_register
                        for (slot = 0; slot < `CSA_OFF(`CSA_LEVEL(step), TREE_W); slot = slot + 1)
                            begin : g_bit
                                reg r_bit;

                                always @(posedge i_clk)
                                    r_bit <= w_bits_all[`CSA_AT(step - 1) + slot];

                                assign w_bits_all[`CSA_AT(step) + slot] = r_bit;
                            end
                    end
                else
                    begin : g_adders
                        for (column = 0; column < TREE_W; column = column + 1)
                            begin : g_column
                                if (column + 1 < TREE_W)
                                    begin : g_inner
                                        for (adder = 0; adder < `CSA_FULL(step, column); adder = adder + 1)
                                            begin : g_fa
                                                wire w_a  = w_bits_all[`CSA_IN(step, column) + 3*adder];
                                                wire w_b  = w_bits_all[`CSA_IN(step, column) + 3*adder + 1];
                                                wire w_c  = w_bits_all[`CSA_IN(step, column) + 3*adder + 2];
                                                wire w_ab = w_a ^ w_b;

                                                assign w_bits_all[`CSA_OUT(step, column) + adder]  = w_ab ^ w_c;
                                                assign w_bits_all[`CSA_NEXT(step, column) + adder] = (w_ab & w_c) | (w_a & w_b);
                                            end

                                        for (adder = 0; adder < `CSA_HALF(step, column); adder = adder + 1)
                                            begin : g_ha
                                                wire w_a = w_bits_all[`CSA_IN(step, column) + 3*`CSA_FULL(step, column)];
                                                wire w_b = w_bits_all[`CSA_IN(step, column) + 3*`CSA_FULL(step, column) + 1];

                                                assign w_bits_all[`CSA_OUT(step, column) + `CSA_FULL(step, column)]  = w_a ^ w_b;
                                                assign w_bits_all[`CSA_NEXT(step, column) + `CSA_FULL(step, column)] = w_a & w_b;
                                            end
                                    end
                                else
                                    begin : g_top
                                        /* La colonne TREE_W − 1 : ses retenues tombent, la somme
                                         * étant prise modulo 2^TREE_W. Une branche par colonne
                                         * plutôt qu'un bloc par retenue, pour le temps
                                         * d'élaboration. */
                                        for (adder = 0; adder < `CSA_FULL(step, column); adder = adder + 1)
                                            begin : g_fa
                                                wire w_a = w_bits_all[`CSA_IN(step, column) + 3*adder];
                                                wire w_b = w_bits_all[`CSA_IN(step, column) + 3*adder + 1];
                                                wire w_c = w_bits_all[`CSA_IN(step, column) + 3*adder + 2];

                                                assign w_bits_all[`CSA_OUT(step, column) + adder] = w_a ^ w_b ^ w_c;
                                            end

                                        for (adder = 0; adder < `CSA_HALF(step, column); adder = adder + 1)
                                            begin : g_ha
                                                wire w_a = w_bits_all[`CSA_IN(step, column) + 3*`CSA_FULL(step, column)];
                                                wire w_b = w_bits_all[`CSA_IN(step, column) + 3*`CSA_FULL(step, column) + 1];

                                                assign w_bits_all[`CSA_OUT(step, column) + `CSA_FULL(step, column)] = w_a ^ w_b;
                                            end
                                    end

                                for (adder = 0; adder < `CSA_PASS(step, column); adder = adder + 1)
                                    begin : g_pass
                                        assign w_bits_all[`CSA_OUT(step, column) + `CSA_FULL(step, column)
                                                          + `CSA_HALF(step, column) + adder] =
                                            w_bits_all[`CSA_IN(step, column) + 3*`CSA_FULL(step, column)
                                                       + 2*`CSA_HALF(step, column) + adder];
                                    end
                            end
                    end
            end

        for (column = 0; column < TREE_W; column = column + 1)
            begin : g_rows
                if (`CSA_HEIGHT(L_CSA, column) > 0)
                    begin : g_x
                        assign w_row_x[column] = w_bits_all[LAST_AT + `CSA_OFF(L_CSA, column)];
                    end
                else
                    begin : g_x_zero
                        assign w_row_x[column] = 1'b0;
                    end

                if (`CSA_HEIGHT(L_CSA, column) > 1)
                    begin : g_y
                        assign w_row_y[column] = w_bits_all[LAST_AT + `CSA_OFF(L_CSA, column) + 1];
                    end
                else
                    begin : g_y_zero
                        assign w_row_y[column] = 1'b0;
                    end
            end

        if (FINAL == 0)
            begin : g_ripple
                wire [TREE_W-2:0] w_carry;

                assign w_sum[0]   = w_row_x[0] ^ w_row_y[0];
                assign w_carry[0] = w_row_x[0] & w_row_y[0];

                for (slot = 1; slot < TREE_W; slot = slot + 1)
                    begin : g_digit
                        wire w_xy = w_row_x[slot] ^ w_row_y[slot];

                        assign w_sum[slot] = w_xy ^ w_carry[slot-1];
                        if (slot + 1 < TREE_W)
                            begin : g_carry
                                assign w_carry[slot] = (w_xy & w_carry[slot-1]) | (w_row_x[slot] & w_row_y[slot]);
                            end
                    end
            end
        else if (FINAL == 3)
            begin : g_bk_inv
                for (level = 0; level <= BK_LEVELS; level = level + 1)
                    begin : g_prefix
                        wire [TREE_W-1:0] w_g;
                        wire [TREE_W-1:0] w_p;

                        if (level == 0)
                            begin : g_start
                                assign w_g = w_row_x & w_row_y;
                                assign w_p = w_row_x ^ w_row_y;
                            end
                        else
                            begin : g_nodes
                                wire [TREE_W-1:0] w_g_in = g_prefix[level-1].w_g;
                                wire [TREE_W-1:0] w_p_in = g_prefix[level-1].w_p;

                                for (slot = 0; slot < TREE_W; slot = slot + 1)
                                    begin : g_slot
                                        if (`CSA_BK_NODE(level, slot) != 0)
                                            begin : g_node
                                                localparam PARTNER = slot - SPAN_TABLE[level*32 +: 32];

                                                wire w_gj;
                                                wire w_pj;

                                                if (`CSA_BK_SAME(level, slot) != 0)
                                                    begin : g_same
                                                        assign w_gj = w_g_in[PARTNER];
                                                        assign w_pj = w_p_in[PARTNER];
                                                    end
                                                else
                                                    begin : g_flip
                                                        assign w_gj = ~w_g_in[PARTNER];
                                                        assign w_pj = ~w_p_in[PARTNER];
                                                    end

                                                if (`CSA_BK_AOI(level, slot) != 0)
                                                    begin : g_aoi
                                                        assign w_g[slot] = ~((w_p_in[slot] & w_gj) | w_g_in[slot]);
                                                        assign w_p[slot] = ~(w_p_in[slot] & w_pj);
                                                    end
                                                else
                                                    begin : g_oai
                                                        assign w_g[slot] = ~((w_p_in[slot] | w_gj) & w_g_in[slot]);
                                                        assign w_p[slot] = ~(w_p_in[slot] | w_pj);
                                                    end
                                            end
                                        else
                                            begin : g_keep
                                                assign w_g[slot] = w_g_in[slot];
                                                assign w_p[slot] = w_p_in[slot];
                                            end
                                    end
                            end
                    end

                /* Nœuds morts, que l'accordeur élague (Netlist.prune) : le P du dernier niveau et le G du bit
                 * de poids fort, qu'aucune somme ne lit. Exception du lint bornée à ce fil. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire [TREE_W:0] w_pruned = {g_prefix[BK_LEVELS].w_p, g_prefix[BK_LEVELS].w_g[TREE_W-1]};
                /* verilator lint_on UNUSEDSIGNAL */

                assign w_sum[0] = g_prefix[0].w_p[0];

                for (slot = 1; slot < TREE_W; slot = slot + 1)
                    begin : g_digit
                        if (`CSA_BK_LAST(slot - 1) != 0)
                            begin : g_xor
                                assign w_sum[slot] = g_prefix[0].w_p[slot] ^ g_prefix[BK_LEVELS].w_g[slot-1];
                            end
                        else
                            begin : g_xnor
                                assign w_sum[slot] = ~(g_prefix[0].w_p[slot] ^ g_prefix[BK_LEVELS].w_g[slot-1]);
                            end
                    end
            end
        else if (FINAL == 5)
            begin : g_carry_save
                assign w_sum = {w_row_y, w_row_x};
            end
    endgenerate

    always @(posedge i_clk)
        r_sum <= w_sum;

    assign o_sum = r_sum;

endmodule

module mac_array #(parameter C       = `TILE_C,
                   parameter K       = `TILE_K,
                   parameter BA      = `TILE_BA,
                   parameter BW      = `TILE_BW,
                   parameter ACC     = `TILE_ACC,
                   parameter CUT_A   = `TILE_MAC_CUT_A,
                   parameter CUT_B   = `TILE_MAC_CUT_B,
                   parameter CUT_C   = `TILE_MAC_CUT_C,
                   parameter TREE    = `TILE_MAC_TREE,
                   parameter MODEL   = `TILE_MAC_MODEL,
                   parameter FINAL   = `TILE_FINAL_ADDER,
                   parameter STAGES  = `TILE_L_MAC - ((`TILE_WIN_LOAD != 0) ? 1 : 0),
                   parameter COPIES  = `TILE_REG_COPIES,
                   parameter N_TERMS = 9 * C,
                   parameter LEVELS  = $clog2(N_TERMS),
                   parameter TREE_W  = BA + BW + LEVELS,
                   parameter ROWS    = (FINAL == 5) ? 2 : 1)
                  (input                         i_clk,
                   input  [COPIES*9*C*BA-1:0]    i_win_data,
                   input  [K*9*C*BW-1:0]         i_wgt_head,
                   output [ROWS*K*ACC-1:0]       o_mac_sum);

    /* Sous FINAL = 5, mac_csa réduit sur ACC colonnes et rend ses deux rangées, la rangée r du filtre k sortant en
     * [(r × K + k) × ACC +: ACC] : la rangée x garde la place de la somme. */
    localparam CSA_W  = (ROWS == 2) ? ACC : TREE_W;
    localparam ROOT_W = ROWS * CSA_W;

    /* ⌈N_TERMS / 2^depth⌉ : chaque niveau prend le précédent par paires. */
    function integer level_terms(input integer depth);
        integer halving;
        begin
            level_terms = N_TERMS;
            for (halving = 0; halving < depth; halving = halving + 1)
                level_terms = (level_terms + 1) / 2;
        end
    endfunction

    function integer level_width(input integer depth);
        level_width = BA + BW + depth;
    endfunction

    genvar filter;
    genvar tap;
    genvar lane;
    genvar level;
    genvar term;

    generate
        for (filter = 0; filter < K; filter = filter + 1)
            begin : g_filter
                wire [9*C*BA-1:0] w_win = i_win_data[(filter*COPIES/K)*9*C*BA +: 9*C*BA];
                wire [ROOT_W-1:0] w_root;
                wire [ACC-1:0]    w_mac_sum;

                if (TREE == 0)
                    begin : g_binary
                        wire [N_TERMS*level_width(0)-1:0] w_products;

                        for (level = 0; level <= LEVELS; level = level + 1)
                            begin : g_level
                                wire [level_terms(level)*level_width(level)-1:0] w_terms;
                                wire [level_terms(level)*level_width(level)-1:0] w_out;

                                if ((CUT_A != 0 && level == CUT_A) || (CUT_B != 0 && level == CUT_B)
                                    || (CUT_C != 0 && level == CUT_C) || level == LEVELS)
                                    begin : g_register
                                        reg [level_terms(level)*level_width(level)-1:0] r_terms;

                                        always @(posedge i_clk)
                                            r_terms <= w_terms;

                                        assign w_out = r_terms;
                                    end
                                else
                                    begin : g_direct
                                        assign w_out = w_terms;
                                    end

                                if (level == 0)
                                    begin : g_leaves
                                        assign w_terms = w_products;
                                    end
                                else
                                    begin : g_adders
                                        wire [level_terms(level-1)*level_width(level-1)-1:0] w_in = g_level[level-1].w_out;

                                        for (term = 0; term < level_terms(level); term = term + 1)
                                            begin : g_term
                                                wire [level_width(level-1)-1:0] w_left =
                                                    w_in[2*term*level_width(level-1) +: level_width(level-1)];
                                                wire [level_width(level)-1:0]   w_left_ext = {w_left[level_width(level-1)-1], w_left};

                                                if (2*term + 1 < level_terms(level-1))
                                                    begin : g_pair
                                                        wire [level_width(level-1)-1:0] w_right =
                                                            w_in[(2*term + 1)*level_width(level-1) +: level_width(level-1)];
                                                        wire [level_width(level)-1:0]   w_right_ext =
                                                            {w_right[level_width(level-1)-1], w_right};

                                                        assign w_terms[term*level_width(level) +: level_width(level)] =
                                                            w_left_ext + w_right_ext;
                                                    end
                                                else
                                                    begin : g_odd
                                                        assign w_terms[term*level_width(level) +: level_width(level)] = w_left_ext;
                                                    end
                                            end
                                    end
                            end

                        for (tap = 0; tap < 9; tap = tap + 1)
                            begin : g_tap
                                for (lane = 0; lane < C; lane = lane + 1)
                                    begin : g_lane
                                        wire [BA-1:0] w_act = w_win[(tap*C + lane)*BA +: BA];
                                        wire [BW-1:0] w_wgt = i_wgt_head[((filter*9 + tap)*C + lane)*BW +: BW];

                                        assign w_products[(tap*C + lane)*level_width(0) +: level_width(0)] =
                                            $signed({1'b0, w_act}) * $signed(w_wgt);
                                    end
                            end

                        assign w_root = g_level[LEVELS].w_out;
                    end
                else
                    begin : g_csa
                        mac_csa #(.C(C), .BA(BA), .BW(BW), .CUT_A(CUT_A), .CUT_B(CUT_B), .CUT_C(CUT_C), .TREE(TREE),
                                  .MODEL(MODEL), .FINAL(FINAL), .STAGES(STAGES), .TREE_W(CSA_W)) u_csa (
                            .i_clk(i_clk), .i_act(w_win), .i_wgt(i_wgt_head[filter*9*C*BW +: 9*C*BW]), .o_sum(w_root));
                    end

                if (ROWS == 2)
                    begin : g_rows
                        assign w_mac_sum                         = w_root[ACC-1:0];
                        assign o_mac_sum[(K + filter)*ACC +: ACC] = w_root[ACC +: ACC];
                    end
                else if (TREE_W < ACC)
                    begin : g_extend
                        assign w_mac_sum = {{(ACC - TREE_W){w_root[TREE_W-1]}}, w_root};
                    end
                else
                    begin : g_reduce
                        /* Les bits au-delà d'ACC tombent exprès, c'est le repli du contrat. Quand TREE_W > ACC,
                         * au jeu LMAC4 par exemple (C = 57, TREE_W = 18, ACC = 17), personne ne les lit, d'où
                         * l'exception du lint, bornée à ce fil. */
                        /* verilator lint_off UNUSEDSIGNAL */
                        wire [TREE_W-1:0] w_folded = w_root;
                        /* verilator lint_on UNUSEDSIGNAL */

                        assign w_mac_sum = w_folded[ACC-1:0];
                    end

                assign o_mac_sum[filter*ACC +: ACC] = w_mac_sum;
            end
    endgenerate

endmodule

/* Fin des lectures des tables de mac_csa, propres à ce fichier. */
`undef CSA_OFF
`undef CSA_ADD
`undef CSA_COL
`undef CSA_LEVEL
`undef CSA_REG
`undef CSA_AT
`undef CSA_HEIGHT
`undef CSA_PER
`undef CSA_ANDS
`undef CSA_FIRST
`undef CSA_ONE
`undef CSA_FULL
`undef CSA_HALF
`undef CSA_PASS
`undef CSA_IN
`undef CSA_OUT
`undef CSA_NEXT
`undef CSA_BK_NODE
`undef CSA_BK_SAME
`undef CSA_BK_AOI
`undef CSA_BK_LAST

`endif
