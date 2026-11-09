`ifndef __SG13_CELLS_SIM__
`define __SG13_CELLS_SIM__

/* Modèles de simulation des cellules sg13_* qu'instancie mul_s4xu4 de rtl/6a_mul_s4xu4.v, élaborés quand la macro
 * TILE_MAPPED_CELLS n'est pas posée (tâche 2 du plan A10).
 * Dérivé de test/sg13_cells_sim.v de github.com/ygdes/S4xU4 au commit c5c0377, © 2026 Yann Guidon, licence Apache-2.0
 * (texte dans rtl/LICENCE-S4xU4).
 * Changements :
 * - réduit aux quatorze cellules combinatoires qu'instancie mul_s4xu4, les bascules et leurs primitives UDP retirées ;
 * - directives `timescale et `celldefine retirées, le dépôt n'en portant aucune ;
 * - garde d'inclusion __SG13_CELLS_SIM__ ajoutée.
 * Le corps de chaque cellule est celui de l'original, primitive pour primitive. */

module sg13_a21o_1 (X, A1, A2, B1);
	output X;
	input A1, A2, B1;
	wire int_fwire_0;
	and (int_fwire_0, A1, A2);
	or (X, int_fwire_0, B1);
endmodule

module sg13_a21oi_1 (Y, A1, A2, B1);
	output Y;
	input A1, A2, B1;
	wire int_fwire_0, int_fwire_1;
	and (int_fwire_0, A1, A2);
	or (int_fwire_1, int_fwire_0, B1);
	not (Y, int_fwire_1);
endmodule

module sg13_a221oi_1 (Y, A1, A2, B1, B2, C1);
	output Y;
	input A1, A2, B1, B2, C1;
	wire int_fwire_0, int_fwire_1, int_fwire_2;
	and (int_fwire_0, B1, B2);
	and (int_fwire_1, A1, A2);
	or (int_fwire_2, int_fwire_1, int_fwire_0, C1);
	not (Y, int_fwire_2);
endmodule

module sg13_a22oi_1 (Y, A1, A2, B1, B2);
	output Y;
	input A1, A2, B1, B2;
	wire int_fwire_0, int_fwire_1, int_fwire_2;
	and (int_fwire_0, B1, B2);
	and (int_fwire_1, A1, A2);
	or (int_fwire_2, int_fwire_1, int_fwire_0);
	not (Y, int_fwire_2);
endmodule

module sg13_and2_1 (X, A, B);
	output X;
	input A, B;
	and (X, A, B);
endmodule

module sg13_and3_1 (X, A, B, C);
	output X;
	input A, B, C;
	and (X, A, B, C);
endmodule

module sg13_inv_1 (Y, A);
	output Y;
	input A;
	not (Y, A);
endmodule

module sg13_nand2_1 (Y, A, B);
	output Y;
	input A, B;
	wire int_fwire_0;
	and (int_fwire_0, A, B);
	not (Y, int_fwire_0);
endmodule

module sg13_nor2_1 (Y, A, B);
	output Y;
	input A, B;
	wire int_fwire_0;
	or (int_fwire_0, A, B);
	not (Y, int_fwire_0);
endmodule

module sg13_nor3_1 (Y, A, B, C);
	output Y;
	input A, B, C;
	wire int_fwire_0;
	or (int_fwire_0, A, B, C);
	not (Y, int_fwire_0);
endmodule

module sg13_o21ai_1 (Y, A1, A2, B1);
	output Y;
	input A1, A2, B1;
	wire int_fwire_0, int_fwire_1;
	or (int_fwire_0, A1, A2);
	and (int_fwire_1, int_fwire_0, B1);
	not (Y, int_fwire_1);
endmodule

module sg13_or2_1 (X, A, B);
	output X;
	input A, B;
	or (X, A, B);
endmodule

module sg13_xnor2_1 (Y, A, B);
	output Y;
	input A, B;
	wire int_fwire_0;
	xor (int_fwire_0, A, B);
	not (Y, int_fwire_0);
endmodule

module sg13_xor2_1 (X, A, B);
	output X;
	input A, B;
	xor (X, A, B);
endmodule

`endif
