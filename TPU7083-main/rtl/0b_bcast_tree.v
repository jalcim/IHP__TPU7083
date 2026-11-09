`ifndef __BCAST_TREE__
`define __BCAST_TREE__

/* Arbre de diffusion en registres répliqués : une activation anticipée de DEPTH cycles à la racine arrive à son
 * cycle sur LEAVES feuilles, chaque registre en pilotant au plus FANOUT du niveau suivant.
 * Les registres portent keep, pour que la synthèse ne fusionne pas des répliques égales.
 * Le keep se pose aussi sur chaque bloc always : Yosys ne donne à une bascule que les attributs de son bloc
 * (passes/proc/proc_dff.cc), et opt_merge ne garde deux cellules égales que si toutes deux portent keep
 * (passes/opt/opt_merge.cc), le keep d'un fil n'y comptant pas.
 * À DEPTH = 0, les feuilles sont des fils, sans terme de remise : leur valeur pendant la remise est celle de la
 * racine, registre déjà remis chez la source. */

module bcast_tree #(parameter WIDTH       = 1,
                    parameter DEPTH       = 0,
                    parameter LEAVES      = 1,
                    parameter FANOUT      = 4,
                    parameter RESET_VALUE = 0)
                   (input                     i_clk,
                    input                     i_rst_n,
                    input  [WIDTH-1:0]        i_root,
                    output [LEAVES*WIDTH-1:0] o_leaf);

    function integer level_nodes(input integer level);
        integer span;
        integer step;
        begin
            span = 1;
            for (step = level; step < DEPTH; step = step + 1)
                span = span * FANOUT;
            level_nodes = (LEAVES + span - 1) / span;
        end
    endfunction

    function integer level_offset(input integer level);
        integer step;
        begin
            level_offset = 0;
            for (step = 1; step < level; step = step + 1)
                level_offset = level_offset + level_nodes(step);
        end
    endfunction

    genvar level;
    genvar node;

    generate
        if (DEPTH == 0)
            begin : g_wires
                assign o_leaf = {LEAVES{i_root}};

                /* Sans registre, l'horloge et la remise ne servent pas. */
                /* verilator lint_off UNUSEDSIGNAL */
                wire w_clock_ignored = ^{i_clk, i_rst_n};
                /* verilator lint_on UNUSEDSIGNAL */
            end
        else
            begin : g_levels
                (* keep *) reg [level_offset(DEPTH + 1)*WIDTH-1:0] r_node;

                for (level = 1; level <= DEPTH; level = level + 1)
                    begin : g_level
                        for (node = 0; node < level_nodes(level); node = node + 1)
                            begin : g_node
                                if (level == 1)
                                    begin : g_from_root
                                        (* keep *) always @(posedge i_clk or negedge i_rst_n)
                                            if (!i_rst_n)
                                                r_node[node*WIDTH +: WIDTH] <= {WIDTH{RESET_VALUE != 0}};
                                            else
                                                r_node[node*WIDTH +: WIDTH] <= i_root;
                                    end
                                else
                                    begin : g_from_parent
                                        (* keep *) always @(posedge i_clk or negedge i_rst_n)
                                            if (!i_rst_n)
                                                r_node[(level_offset(level) + node)*WIDTH +: WIDTH]
                                                    <= {WIDTH{RESET_VALUE != 0}};
                                            else
                                                r_node[(level_offset(level) + node)*WIDTH +: WIDTH]
                                                    <= r_node[(level_offset(level - 1) + node / FANOUT)*WIDTH +: WIDTH];
                                    end
                            end
                    end

                assign o_leaf = r_node[level_offset(DEPTH + 1)*WIDTH-1:level_offset(DEPTH)*WIDTH];
            end
    endgenerate

endmodule

`endif
