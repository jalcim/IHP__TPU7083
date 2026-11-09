`ifndef __LINK_OUT__
`define __LINK_OUT__

`include "00_params.vh"

/* Lien sortant : les niveaux de ⑦ et les octets d'écho ou d'état vers le FPGA, codés DBI, registrés au ras
 * des plots, avec l'horloge transmise (spec/11_sortie.md sections 2 à 5).
 *
 * POURQUOI AUCUN TAMPON. Les MAC n'attendent jamais (spec/00_objet.md,
 * section Règle ultime), la tuile ne gèle donc jamais sur le FPGA. READY_OUT surveille, il n'arrête rien,
 * comme READY_IN côté entrée (spec/11_sortie.md section 4.3).
 * Un tampon élastique ne ferait que retarder la perte : pendant une couche à une tranche, toutes les passes
 * émettent un mot par cycle sans trou, et le retard accumulé ne se résorbe pas avant la fin de la couche.
 * Retarder une passe décalerait en outre toute la suite par rapport au flux préparé que le FPGA rejoue cycle
 * par cycle. Un mot qui part READY_OUT bas lève donc out_overflow, collant, lu par ÉTAT, et rien d'autre.
 * OUT_BUF = 0 est la seule variante écrite, les autres n'ont pas de branche et
 * rtl/0_param_check.v les refuse avant tout cycle.
 *
 * LE DBI SE COMPTE CONTRE LES BROCHES. Chaque groupe de 8 bits, le dernier pouvant être plus court,
 * s'inverse si plus de la moitié de ses broches, données et DBI, basculeraient sans inversion
 * (spec/11_sortie.md section 4.1). Au plus 4 des 9 broches d'un groupe
 * plein basculent alors par cycle. La référence est ce que portent les broches, Q_OUT et DBI_OUT, donc le mot
 * déjà codé. Comparer au niveau reçu le cycle d'avant serait une faute silencieuse : le FPGA décode
 * Q_OUT ⊕ {8{DBI_OUT}} juste quelle que soit la décision, seule la borne des basculements tombe.
 *
 * LE NIVEAU PASSE AVANT L'ÉCHO. ⑫ n'émet l'écho et l'état que sortie vide
 * (spec/03_interfaces.md section 4.7). Si un octet tombe quand même au
 * cycle d'un niveau, le niveau passe et out_collide le rend visible. out_collide monte aussi sur i_lvl_collide, le
 * rechargement du sérialiseur de ⑦ qui écrase des niveaux pas encore sortis (point 8_threshold.v:286 de la revue
 * du RTL d'af5ab629).
 *
 * UNE MONTÉE L'EMPORTE SUR L'EFFACEMENT. flags_clr remet les deux drapeaux à zéro à son front, sauf celui
 * qui monte au même front : un EFFACE ne doit pas cacher une faute du cycle où il s'exécute (contrat 9 de
 * rtl/contrats.md, choix confirmé le 12/10/2026).
 *
 * READY_OUT arrive de la carte sans relation de phase avec clk, d'où les deux bascules du synchroniseur :
 * out_overflow juge un mot contre READY_OUT tel qu'il était deux cycles plus tôt.
 * CLK_OUT est clk inversée. Les mots changent au front montant de clk, le FPGA les capture au front montant
 * de CLK_OUT, au milieu du mot (spec/11_sortie.md section 4.4).
 * Le reset est asynchrone à l'assertion et relâché par rst_n_sync
 * (spec/03_interfaces.md section 4.11). */

module link_out #(parameter OUT_W   = `TILE_OUT_W,
                  parameter OUT_BUF = `TILE_OUT_BUF,
                  parameter DBI_N   = (OUT_W + 7) / 8)
                 (input              i_clk,
                  input              i_rst_n,
                  input  [OUT_W-1:0] i_lvl_out,
                  input              i_lvl_valid,
                  input  [7:0]       i_echo_byte,
                  input              i_echo_valid,
                  input              i_flags_clr,
                  input              i_ready_out,
                  output [OUT_W-1:0] o_q_out,
                  output [DBI_N-1:0] o_dbi_out,
                  output             o_valid_out,
                  output             o_clk_out,
                  output             o_out_overflow,
                  output             o_out_collide,
                  input              i_lvl_collide);

    reg  [OUT_W-1:0] r_q_out;
    reg  [DBI_N-1:0] r_dbi_out;
    reg              r_valid_out;
    reg              r_out_ready_meta;
    reg              r_out_ready_s;
    reg              r_out_overflow;
    reg              r_out_collide;

    wire             w_send = i_lvl_valid | i_echo_valid;
    wire [OUT_W-1:0] w_echo_word;
    wire [OUT_W-1:0] w_word = i_lvl_valid ? i_lvl_out : w_echo_word;
    wire [OUT_W-1:0] w_diff = w_word ^ r_q_out;
    wire [DBI_N-1:0] w_invert;
    wire [OUT_W-1:0] w_mask;
    wire [OUT_W-1:0] w_code = w_word ^ w_mask;

    /* Inversion du groupe group_idx, voies 8 group_idx à 8 group_idx + 7 bornées par OUT_W : plus de la
     * moitié de ses broches basculeraient sans elle. Quatre bits comptent les 9 broches d'un groupe plein. */
    function invert_group(input [OUT_W-1:0] diff, input dbi_prev, input integer group_idx);
        integer   lane_idx;
        reg [3:0] pins;
        reg [3:0] toggles;
        begin
            pins    = 4'd1;
            toggles = {3'b000, dbi_prev};
            for (lane_idx = 0; lane_idx < OUT_W; lane_idx = lane_idx + 1)
                if (lane_idx / 8 == group_idx)
                    begin
                        pins    = pins + 4'd1;
                        toggles = toggles + {3'b000, diff[lane_idx]};
                    end
            invert_group = 2 * toggles > pins;
        end
    endfunction

    genvar group;
    genvar lane;

    generate
        if (OUT_W > 8)
            begin : g_echo_padded
                assign w_echo_word = {{(OUT_W - 8){1'b0}}, i_echo_byte};
            end
        else
            begin : g_echo_exact
                assign w_echo_word = i_echo_byte;
            end

        for (group = 0; group < DBI_N; group = group + 1)
            begin : g_group
                assign w_invert[group] = invert_group(w_diff, r_dbi_out[group], group);
            end

        for (lane = 0; lane < OUT_W; lane = lane + 1)
            begin : g_lane
                assign w_mask[lane] = w_invert[lane / 8];
            end

        if (OUT_BUF == 0)
            begin : g_unbuffered
                always @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        begin
                            r_q_out     <= {OUT_W{1'b0}};
                            r_dbi_out   <= {DBI_N{1'b0}};
                            r_valid_out <= 1'b0;
                        end
                    else
                        begin
                            if (w_send)
                                begin
                                    r_q_out   <= w_code;
                                    r_dbi_out <= w_invert;
                                end
                            r_valid_out <= w_send;
                        end
            end
    endgenerate

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_out_ready_meta <= 1'b0;
                r_out_ready_s    <= 1'b0;
            end
        else
            begin
                r_out_ready_meta <= i_ready_out;
                r_out_ready_s    <= r_out_ready_meta;
            end

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            begin
                r_out_overflow <= 1'b0;
                r_out_collide  <= 1'b0;
            end
        else
            begin
                r_out_overflow <= (w_send & ~r_out_ready_s) | (r_out_overflow & ~i_flags_clr);
                r_out_collide  <= (i_lvl_valid & i_echo_valid) | i_lvl_collide | (r_out_collide & ~i_flags_clr);
            end

    assign o_q_out        = r_q_out;
    assign o_dbi_out      = r_dbi_out;
    assign o_valid_out    = r_valid_out;
    assign o_clk_out      = ~i_clk;
    assign o_out_overflow = r_out_overflow;
    assign o_out_collide  = r_out_collide;

endmodule

`endif
