`ifndef __LINE_MEM__
`define __LINE_MEM__

`include "00_params.vh"

/* Ligne ③ : l'emplacement A de chaque colonne qui quitte l'étage 1 de ① y entre à chaque col_shift, et en ressort
 * par trois prises fixes, T2, T1 et T0, comme haut de la fenêtre de la rangée suivante, aux deux pas
 * (spec/05_memoire_ligne.md sections 3.3 et 3.5).
 *
 * POURQUOI DES SEGMENTS CONTOURNABLES. Une valeur entrée au col_shift q atteint T0 au col_shift q + longueur − 1 :
 * les prises ne présentent le haut des trois colonnes de la fenêtre que si la ligne mesure exactement hdr_ncols
 * cases, et hdr_ncols change d'une passe à l'autre. Les L − 3 cases au-delà des prises forment donc des segments de
 * 1, 2, 4, …, 2^(J−1) cases, J le plus grand entier tel que 2^J − 1 ≤ L − 3, puis un dernier de R_SEG cases, chacun
 * contourné par un mux2 par bit : toute longueur de 3 à L s'obtient à la case près, sans colonne morte. Le FPGA ne
 * pourrait remplacer ces mux que par des colonnes mortes, qui feraient attendre les MAC (même fichier, section 8,
 * point 1).
 *
 * Ordre de la chaîne depuis i_line_in : les puissances de deux par taille croissante, puis le reste en dernier, même
 * plus court que 2^(J−1), soit 1, 2, 4 puis 3 cases à L = 13, puis T2, T1 et T0. Lecture du contrat 3 acceptée le 13/10/2026.
 *
 * Décodage, avec n = i_line_len − 3 : si le dernier segment existe et que n > 2^J − 1, il est pris et les
 * puissances de deux décodent n − R_SEG en binaire, sinon elles décodent n. Le nombre décodé est inférieur à 2^J
 * dans les deux cas, ses J bits bas suffisent.
 *
 * Seules les cases prises avancent : un segment contourné garde son contenu, qui ne ressort qu'après un changement
 * de longueur, au début d'une passe dont la première rangée ne lit pas ③ (même fichier, section 4.3). Ce contenu
 * ancien est indifférent, le modèle le tient pour x tant qu'il n'est pas réécrit (levier technique du 13/10/2026).
 * Pas de reset, le contenu étant réécrit avant d'être lu (spec/14_verification.md
 * section 4.2). Les cases sont des bascules, leur réalisation en tlatch maître-esclave, une phase par cycle, relève
 * de la version structurelle (rtl/00_conception.md section 2). */

module line_mem #(parameter C     = `TILE_C,
                  parameter BA    = `TILE_BA,
                  parameter L     = `TILE_L,
                  parameter LEN_W = `TILE_HDR_NCOLS_W,
                  parameter PIX_W = C * BA)
                 (input                i_clk,
                  input  [PIX_W-1:0]   i_line_in,
                  input                i_col_shift,
                  input  [LEN_W-1:0]   i_line_len,
                  output [3*PIX_W-1:0] o_line_out);

    /* J, nombre de segments en puissances de deux. */
    function integer pow2_count(input integer length);
        begin
            pow2_count = 0;
            while ((2 << pow2_count) - 1 <= length - 3)
                pow2_count = pow2_count + 1;
        end
    endfunction

    /* R_SEG, nul quand les puissances de deux couvrent toutes les cases contournables. */
    function integer last_length(input integer length);
        last_length = length - 3 - ((1 << pow2_count(length)) - 1);
    endfunction

    /* Le segment de 2^k cases suit ceux de 1 à 2^(k−1) cases, et le dernier segment suit les J premiers. */
    function integer segment_start(input integer index);
        segment_start = (1 << index) - 1;
    endfunction

    /* Cases dans l'ordre de la chaîne : puissances de deux, reste, puis T2, T1 et T0 en L − 3, L − 2 et L − 1. */
    reg  [L*PIX_W-1:0]                 r_cells;
    wire [L*PIX_W-1:0]                 w_next;
    /* Nœud k : entrée du segment de 2^k cases, nœud J : entrée du dernier segment. */
    wire [(pow2_count(L)+1)*PIX_W-1:0] w_chain;
    /* Entrée de T2, hors de w_chain : écrite dans w_chain à une base calculée par fonction, elle ferait croire à
     * Verilator que tout le vecteur est réécrit, et la chaîne de mux deviendrait une boucle (UNOPTFLAT). */
    wire [PIX_W-1:0]                   w_tap_in;
    wire [LEN_W-1:0]                   w_taken_cells = i_line_len - 3;
    /* Bit k < J : segment de 2^k cases pris, bit J : dernier segment pris. */
    wire [pow2_count(L):0]             w_take;

    assign w_chain[0 +: PIX_W] = i_line_in;

    /* w_span : l'entrée du segment puis ses cases, de l'amont vers l'aval. Pris, chaque case reprend sa voisine
     * d'amont et le segment sort sa dernière case. Contourné, chaque case se garde et le segment sort son entrée. */
    genvar index;
    generate
        for (index = 0; index < pow2_count(L); index = index + 1)
            begin : g_pow2
                wire [((1 << index)+1)*PIX_W-1:0] w_span =
                    {r_cells[segment_start(index)*PIX_W +: (1 << index)*PIX_W], w_chain[index*PIX_W +: PIX_W]};

                assign w_next[segment_start(index)*PIX_W +: (1 << index)*PIX_W] =
                    w_take[index] ? w_span[0 +: (1 << index)*PIX_W] : w_span[PIX_W +: (1 << index)*PIX_W];
                assign w_chain[(index+1)*PIX_W +: PIX_W] =
                    w_take[index] ? w_span[(1 << index)*PIX_W +: PIX_W] : w_span[0 +: PIX_W];
            end

        if (last_length(L) > 0)
            begin : g_last
                wire                                w_last_taken = w_taken_cells > LEN_W'((1 << pow2_count(L)) - 1);
                wire [(last_length(L)+1)*PIX_W-1:0] w_span       =
                    {r_cells[segment_start(pow2_count(L))*PIX_W +: last_length(L)*PIX_W],
                     w_chain[pow2_count(L)*PIX_W +: PIX_W]};

                assign w_take = {w_last_taken,
                                 w_last_taken ? w_taken_cells[pow2_count(L)-1:0] - (pow2_count(L))'(last_length(L))
                                              : w_taken_cells[pow2_count(L)-1:0]};

                assign w_next[segment_start(pow2_count(L))*PIX_W +: last_length(L)*PIX_W] =
                    w_take[pow2_count(L)] ? w_span[0 +: last_length(L)*PIX_W] : w_span[PIX_W +: last_length(L)*PIX_W];
                assign w_tap_in =
                    w_take[pow2_count(L)] ? w_span[last_length(L)*PIX_W +: PIX_W] : w_span[0 +: PIX_W];
            end
        else
            begin : g_no_last
                assign w_take   = w_taken_cells[pow2_count(L):0];
                assign w_tap_in = w_chain[pow2_count(L)*PIX_W +: PIX_W];

                /* Sans dernier segment, n ≤ 2^J − 1 pour toute longueur légale : le bit J de w_take, et à L = 3 ou 4
                 * les bits de n au-dessus de J, sont toujours nuls et ne décident de rien. Ce fil les lit pour le
                 * lint, sur ces seules longueurs L = 2^J + 2. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_lint_spare = ^{w_taken_cells, w_take[pow2_count(L)]};
                /* verilator lint_on UNUSEDSIGNAL */
            end
    endgenerate

    assign w_next[(L-3)*PIX_W +: 3*PIX_W] = {r_cells[(L-3)*PIX_W +: 2*PIX_W], w_tap_in};

    always @(posedge i_clk)
        if (i_col_shift)
            r_cells <= w_next;

    assign o_line_out = {r_cells[(L-3)*PIX_W +: PIX_W], r_cells[(L-2)*PIX_W +: PIX_W], r_cells[(L-1)*PIX_W +: PIX_W]};

endmodule

`endif
