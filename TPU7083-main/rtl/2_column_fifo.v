`ifndef __COLUMN_FIFO__
`define __COLUMN_FIFO__

`include "00_params.vh"

/* File de colonnes ①, étages 1 à D_COL − 1 de spec/05_memoire_ligne.md section 3.2.
 * L'étage D_COL est celui de l'assembleur (rtl/1b_column_asm.v) :
 * i_col_data en est le contenu, i_col_valid dit qu'il tient une colonne complète.
 * Les étages 1 à 3 sont les prises de la fenêtre suivante, l'étage 1 la colonne la plus ancienne.
 * Ils n'avancent que sur col_shift, même vides.
 * Les étages 4 à D_COL − 1 sont l'avance, qui absorbe les irrégularités du lien.
 *
 * LA CASCADE. La file est un registre à décalage : toutes les colonnes derrière une case libre avancent dans le
 * même cycle (décision d'architecture du 12/10/2026 : « la propagation dans un registre à décalage, ce qui se fait évidemment en
 * 1 cycle car de droite à gauche », reporté dans rtl/00_conception.md section 5).
 * Lue au pied de la lettre, « une colonne avance quand l'étage suivant est vide » ferait remonter une case libre
 * d'un étage par cycle, et un col_shift ne libérerait l'étage D_COL que D_COL − 4 cycles plus tard, cinq à D_COL = 9.
 * Les MAC attendraient alors sur les passes à halo haut réel au pas 2, conv4 en 720p et en 1080p, conv8 en 1080p,
 * à moins de passer à D_COL = 11, deux étages de 576 bits en plus, 0,042 mm².
 * C'est la seule lecture qui tient R1 (verif/lectures.md trou 4).
 *
 * CE QU'ELLE COÛTE. Une chaîne combinatoire de départs à travers les étages élastiques, de i_col_shift à
 * o_col_ready, une porte par étage de 4 à D_COL − 1, cinq à D_COL = 9, parcourue dans le cycle même du col_shift.
 * o_col_ready ne lit pas i_col_valid : la chaîne ne referme aucune boucle avec l'assembleur.
 * La spécification doit l'écrire à sa réécriture (même trou).
 *
 * LE POINT QUI MORD. Chaque étage n'a qu'une source fixe, l'étage qui le précède dans le flux, s + 1, et
 * i_col_data pour l'étage D_COL − 1 : aucun mux de données (spec/05_memoire_ligne.md
 * section 3.2). Un étage prend sa source ou garde son contenu, rien d'autre, et il prend aussi une source vide :
 * seule sa validité dit qu'il tient une colonne.
 *
 * À D_COL = 4, il n'y a pas d'avance : l'étage 3 prend la colonne de l'assembleur sur col_shift, o_col_ready vaut
 * i_col_shift et o_shift_ok vaut i_col_valid.
 *
 * FORMAT (fh, aligned), COL_FMT = 2 : toute colonne arrive sur 2 lignes, et chaque étage n'a que A et B sur
 * COL_W = 2 PIX_W bits (verif/lectures.md trou 22). La file ne lit de
 * ses étages que COL_W et l'emplacement A de l'étage 1 : son comportement ne change pas (contrat 2 amendé de
 * rtl/contrats.md).
 *
 * Seuls les bits de validité ont un reset, asynchrone à l'assertion : le contenu des étages est toujours réécrit
 * avant usage (spec/03_interfaces.md section 4.11). */

module column_fifo #(parameter C       = `TILE_C,
                     parameter BA      = `TILE_BA,
                     parameter D_COL   = `TILE_D_COL,
                     parameter COL_FMT = `TILE_COL_FMT,
                     parameter PIX_W   = C * BA,
                     parameter COL_W   = (COL_FMT == 2) ? 2 * PIX_W : 3 * PIX_W)
                    (input                i_clk,
                     input                i_rst_n,
                     input  [COL_W-1:0]   i_col_data,
                     input                i_col_valid,
                     input                i_col_shift,
                     output               o_col_ready,
                     output               o_tap_valid,
                     output               o_shift_ok,
                     output [3*COL_W-1:0] o_fifo_tap,
                     output [PIX_W-1:0]   o_line_in);

    reg  [D_COL-2:0]           r_valid;
    wire [(D_COL-1)*COL_W-1:0] w_stage;
    wire [(D_COL-1)*COL_W-1:0] w_source;
    wire [D_COL-2:0]           w_source_valid;
    wire [D_COL-2:0]           w_take;
    wire [D_COL-2:0]           w_leave;
    wire [D_COL-2:0]           w_load;

    /* Tranche s − 1 : la source fixe de l'étage s, l'étage s + 1, ou i_col_data pour l'étage D_COL − 1. */
    assign w_source       = {i_col_data, w_stage[(D_COL-1)*COL_W-1:COL_W]};
    assign w_source_valid = {i_col_valid, r_valid[D_COL-2:1]};

    /* L'étage s part quand l'étage s − 1 le prend, l'étage 1 vers la ligne ③ sur col_shift. */
    assign w_leave = {w_take[D_COL-3:0], i_col_shift};

    /* Le dernier étage ne prend i_col_data qu'au front où col_valid et col_ready sont hauts ensemble, comme toute
     * frontière de bloc (spec/12_controle.md section 4.5). */
    assign w_load = {w_take[D_COL-2] && i_col_valid, w_take[D_COL-3:0]};

    genvar stage;
    generate
        for (stage = 1; stage < D_COL; stage = stage + 1)
            begin : g_stage
                reg [COL_W-1:0] r_column;

                if (stage <= 3)
                    begin : g_tap
                        assign w_take[stage-1] = i_col_shift;
                    end
                else
                    begin : g_advance
                        /* « L'étage s est vide en début de cycle ou part au même front » (contrat 2), déroulé
                         * jusqu'aux prises : l'étage s prend l'étage s + 1 dès qu'un étage de 4 à s est vide,
                         * ou que les prises avancent. */
                        assign w_take[stage-1] = i_col_shift || !(&r_valid[stage-1:3]);
                    end

                always @(posedge i_clk)
                    if (w_load[stage-1])
                        r_column <= w_source[(stage-1)*COL_W +: COL_W];

                assign w_stage[(stage-1)*COL_W +: COL_W] = r_column;
            end
    endgenerate

    /* Un étage reste plein s'il ne part pas, le devient s'il prend une source pleine, et devient vide s'il part
     * sans rien recevoir. */
    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_valid <= {(D_COL-1){1'b0}};
        else
            r_valid <= (r_valid & ~w_leave) | (w_take & w_source_valid);

    assign o_col_ready = w_take[D_COL-2];
    assign o_tap_valid = &r_valid[2:0];
    /* Validité de la source de l'étage 3 : l'étage 4, ou la colonne de l'assembleur à D_COL = 4. */
    assign o_shift_ok  = w_source_valid[2];
    assign o_fifo_tap  = w_stage[3*COL_W-1:0];
    assign o_line_in   = w_stage[PIX_W-1:0];

endmodule

`endif
