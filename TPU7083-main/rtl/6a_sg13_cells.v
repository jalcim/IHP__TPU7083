`ifndef __SG13_CELLS__
`define __SG13_CELLS__

/* Enveloppes des cellules sg13_* qu'instancie mul_s4xu4 de rtl/6a_mul_s4xu4.v vers les cellules standard
 * sg13cmos5l_*, élaborées sous la seule macro TILE_MAPPED_CELLS, que posent les scripts de synthèse (tâche 2 du plan
 * A10). Sans elle, rtl/6a_mul_s4xu4.v inclut les modèles de simulation de rtl/test/6a_sg13_cells_sim.v.
 * L'attribut keep garde chaque cellule de Yann telle qu'il l'a placée.
 * Dérivé de src/sg13_cells_sg13cmos5l.v de github.com/ygdes/S4xU4 au commit c5c0377, © 2026 Yann Guidon, licence
 * Apache-2.0 (texte dans rtl/LICENCE-S4xU4).
 * Changements :
 * - réduit aux quatorze cellules combinatoires qu'instancie mul_s4xu4 ;
 * - garde `ifndef __ICARUS__ retirée, le choix entre enveloppes et modèles passant par TILE_MAPPED_CELLS dans
 *   rtl/6a_mul_s4xu4.v ;
 * - garde d'inclusion __SG13_CELLS__ ajoutée.
 * Le corps de chaque enveloppe est celui de l'original. */

module sg13_a21o_1 (X, A1, A2, B1);
	output X;
	input A1, A2, B1;
  (* keep *) sg13cmos5l_a21o_1 ihp(.X(X), .A1(A1), .A2(A2), .B1(B1));
endmodule

module sg13_a21oi_1 (Y, A1, A2, B1);
	output Y;
	input A1, A2, B1;
  (* keep *) sg13cmos5l_a21oi_1 ihp(.Y(Y), .A1(A1), .A2(A2), .B1(B1));
endmodule

module sg13_a221oi_1 (Y, A1, A2, B1, B2, C1);
	output Y;
	input A1, A2, B1, B2, C1;
  (* keep *) sg13cmos5l_a221oi_1 ihp(.Y(Y), .A1(A1), .A2(A2), .B1(B1), .B2(B2), .C1(C1));
endmodule

module sg13_a22oi_1 (Y, A1, A2, B1, B2);
	output Y;
	input A1, A2, B1, B2;
  (* keep *) sg13cmos5l_a22oi_1 ihp(.Y(Y), .A1(A1), .A2(A2), .B1(B1), .B2(B2));
endmodule

module sg13_and2_1 (X, A, B);
	output X;
	input A, B;
  (* keep *) sg13cmos5l_and2_1 ihp(.X(X), .A(A), .B(B));
endmodule

module sg13_and3_1 (X, A, B, C);
	output X;
	input A, B, C;
  (* keep *) sg13cmos5l_and3_1 ihp(.X(X), .A(A), .B(B), .C(C));
endmodule

module sg13_inv_1 (Y, A);
	output Y;
	input A;
  (* keep *) sg13cmos5l_inv_1 ihp(.Y(Y), .A(A));
endmodule

module sg13_nand2_1 (Y, A, B);
	output Y;
	input A, B;
  (* keep *) sg13cmos5l_nand2_1 ihp(.Y(Y), .A(A), .B(B));
endmodule

module sg13_nor2_1 (Y, A, B);
	output Y;
	input A, B;
  (* keep *) sg13cmos5l_nor2_1 ihp(.Y(Y), .A(A), .B(B));
endmodule

module sg13_nor3_1 (Y, A, B, C);
	output Y;
	input A, B, C;
  (* keep *) sg13cmos5l_nor3_1 ihp(.Y(Y), .A(A), .B(B), .C(C));
endmodule

module sg13_o21ai_1 (Y, A1, A2, B1);
	output Y;
	input A1, A2, B1;
  (* keep *) sg13cmos5l_o21ai_1 ihp(.Y(Y), .A1(A1), .A2(A2), .B1(B1));
endmodule

module sg13_or2_1 (X, A, B);
	output X;
	input A, B;
  (* keep *) sg13cmos5l_or2_1 ihp(.X(X), .A(A), .B(B));
endmodule

module sg13_xnor2_1 (Y, A, B);
	output Y;
	input A, B;
  (* keep *) sg13cmos5l_xnor2_1 ihp(.Y(Y), .A(A), .B(B));
endmodule

module sg13_xor2_1 (X, A, B);
	output X;
	input A, B;
  (* keep *) sg13cmos5l_xor2_1 ihp(.X(X), .A(A), .B(B));
endmodule

`endif
