`ifndef __MUL_S4XU4__
`define __MUL_S4XU4__

`ifdef TILE_MAPPED_CELLS
`include "6a_sg13_cells.v"
`else
`include "test/6a_sg13_cells_sim.v"
`endif

/* Multiplieur S4xU4 de Yann Guidon en portes, MODEL 3 de mac_csa de rtl/6_mac.v (tâche 2 du plan A10) : o_p, le
 * produit signé i_s × i_u sur 8 bits, i_s le poids signé en complément à deux, i_u l'activation non signée.
 * Le poids passe en module (cS, de 0 à 8, cS[3] valant 1 au seul poids −8) et l'activation prend le signe du poids
 * sur 5 bits (cU), puis trois rangées de produits partiels, la troisième fusionnant les rangées 2 et 3, se réduisent
 * en deux par une rangée d'additionneurs complets et un additionneur à anticipation de retenue les somme.
 * Les cellules sg13_* sont les enveloppes de rtl/6a_sg13_cells.v sous la macro TILE_MAPPED_CELLS, que posent les
 * scripts de synthèse, et les modèles de rtl/test/6a_sg13_cells_sim.v sans elle.
 * 79 cellules : les 75 portes de Yann hors bascules, plus les 4 inverseurs qui remplacent ses sorties Q_N.
 *
 * Dérivé de src/mulS4xU4.v et src/FullAdder_sg13.v de github.com/ygdes/S4xU4 au commit c5c0377, © 2026 Yann Guidon,
 * licence Apache-2.0 (texte dans rtl/LICENCE-S4xU4).
 * Changements :
 * - les huit bascules sdfrbp d'entrée retirées, avec Clk, Rst_n, Sen et Uen : i_s et i_u attaquent la logique,
 *   lS et lU n'étant plus que leurs noms ;
 * - leurs quatre sorties Q_N, lSn0, lSn3, lUn0 et lUn3, remplacées par quatre inverseurs instanciés, iqS0, iqS3, iqU0
 *   et iqU3 ;
 * - module mulS4xU4 renommé mul_s4xu4, ports S, U et P renommés i_s, i_u et o_p ;
 * - modules FullAdderSG13, FullAdderSG13negS et FullAdderSG13_x renommés full_adder_sg13, full_adder_sg13_neg_s et
 *   full_adder_sg13_x ;
 * - commentaires d'en-tête réécrits, lignes déjà mises en commentaire par l'original (P0x, P1x) retirées, garde
 *   d'inclusion __MUL_S4XU4__ et choix des cellules par TILE_MAPPED_CELLS ajoutés.
 * Les autres portes, leurs noms d'instance, leurs fils et leurs commentaires sont ceux de l'original, instance par
 * instance. */

// Just a dumb Full Adder
module full_adder_sg13 (
  input  wire d1,
  input  wire d2,
  input  wire d3,
  output wire S,
  output wire C
);
  wire t, u;

  // sum:
  sg13_xor2_1 x1 (.X(t), .A(d1), .B(d2));
  sg13_xor2_1 x2 (.X(S), .A(t ), .B(d3));

  // carry out:
  sg13_a22oi_1 a(.A1(d1), .A2(d2), .B1(t), .B2(d3), .Y(u));
  sg13_inv_1 i(.A(u), .Y(C));
endmodule

// Same but with a negated sum output
// (same speed and area)
module full_adder_sg13_neg_s (
  input  wire d1,
  input  wire d2,
  input  wire d3,
  output wire Sn,
  output wire C
);
  wire t, u;

  // sum:
  sg13_xor2_1  x1 (.X(t),  .A(d1), .B(d2));
  sg13_xnor2_1 x2 (.Y(Sn), .A(t ), .B(d3));

  // carry out:
  sg13_a22oi_1 a(.A1(d1), .A2(d2), .B1(t), .B2(d3), .Y(u));
  sg13_inv_1 i(.A(u), .Y(C));
endmodule

// same dumb Full Adder with entra temp output
module full_adder_sg13_x (
  input  wire d1,
  input  wire d2,
  input  wire d3,
  output wire S,
  output wire C,
  output wire X
);
  wire u;

  // sum:
  sg13_xor2_1 x1 (.X(X), .A(d1), .B(d2));
  sg13_xor2_1 x2 (.X(S), .A(X ), .B(d3));

  // carry out:
  sg13_a22oi_1 a(.A1(d1), .A2(d2), .B1(X), .B2(d3), .Y(u));
  sg13_inv_1 i(.A(u), .Y(C));
endmodule

module mul_s4xu4 (
  input  wire [3:0] i_s,
  input  wire [3:0] i_u,
  output wire [7:0] o_p
);

  wire [7:0] P;

  assign o_p = P;

  ////////////////////
  // The inputs, without the synchronous latches:
  ////////////////////

  // the complementary outputs of the latches become 4 inverters
  wire[3:0] lS = i_s;
  wire lSn0, // fo2
       lSn3;
  sg13_inv_1 iqS0(.A(lS[0]), .Y(lSn0));
  sg13_inv_1 iqS3(.A(lS[3]), .Y(lSn3));

  wire[3:0] lU = i_u;
  wire lUn0, // fo2
       lUn3; // fo2
  sg13_inv_1 iqU0(.A(lU[0]), .Y(lUn0));
  sg13_inv_1 iqU3(.A(lU[3]), .Y(lUn3));

  // The easy one:
  // P[0] = S[0] & U[0]
  sg13_nor2_1 no0(.A(lSn0), .B(lUn0), .Y(P[0]));


  ////////////////////
  // S4 => unsigned:
  ////////////////////

  // Complements: -x = (~x)+1 = ~(x-1)
  // This operand must not be negative
  wire[3:0] cS; // these wires will drive the 4 stages of the shif&and replicator

  // buffering the LSB
  sg13_inv_1    ivS0(.A(lSn0), .Y(cS[0]));  // fo4

  // cS[1] = lS[1]  (lS[3] and lS[0]  )
  wire lS1_t1, lS1_t2;
  sg13_nand2_1  naS1(.A(lS[3]), .B(lS[0]), .Y(lS1_t1));
  sg13_xor2_1   xoS1(.A(lS[1]), .B(lS1_t1), .X(lS1_t2));
  sg13_inv_1    ivS1(.A(lS1_t2), .Y(cS[1])); // fo5

  // cS[2] = lS[2]  (lS[3] and lS[0]  )
  wire lS2_t1, lS2_t2;
  sg13_o21ai_1  oaS2(.B1(lS[3]), .A1(lS[0]), .A2(lS[1]), .Y(lS2_t1));
  sg13_xor2_1   xoS2(.A(lS[2]),  .B(lS2_t1), .X(lS2_t2));
  sg13_inv_1    ivS2(.A(lS2_t2), .Y(cS[2])); // fo5

  // cS[3] = 1 when S=1000
  //       = lS[3] & ~(lS[2]|lS[1]|lS[0])
  wire lS3_t1;
  sg13_nor3_1 noS3(.A(lS[0]), .B(lS[1]),  .C(lS[2]), .Y(lS3_t1));
  sg13_and2_1 anS3(.A(lS[3]), .B(lS3_t1), .X(cS[3])); // fo4


  ////////////////////
  // U4 => signed 5 bits
  ////////////////////

  wire[4:0] cU; // this is a sign-extended word that drives the columns of the shif&and replicator

  // buffering
  sg13_inv_1    ivU0(.A(lUn0), .Y(cU[0]));  // fo3

  // cU[1] = lU[1] ^ ~(lS[3] & lU[0])
  wire lU1_t1, lU1_t2;
  sg13_nand2_1  naU1(.A(lS[3]), .B(lU[0]), .Y(lU1_t1));
  sg13_xor2_1   xoU1(.A(lU[1]), .B(lU1_t1), .X(lU1_t2));
  sg13_inv_1    ivU1(.A(lU1_t2), .Y(cU[1])); // fo4

  // cU[2] = lU[2] ^ ~(lS[3] & (lU[0] | lU[1]))
  wire lU2_t1, lU2_t2;
  sg13_o21ai_1  oaU2(.B1(lS[3]), .A1(lU[0]), .A2(lU[1]), .Y(lU2_t1));
  sg13_xor2_1   xoU2(.A(lU[2]),  .B(lU2_t1), .X(lU2_t2));
  sg13_inv_1    ivU2(.A(lU2_t2), .Y(cU[2])); // fo4

  // cU[3] = lU[3] ^  (lSn3 | ~(lU[0] | lU[1] | lU[2] ))
  wire lU3_t0, lU3_t1, lU3_t2;
  sg13_nor3_1 noU3(.A(lU[0]),  .B(lU[1]),   .C(lU[2]), .Y(lU3_t0));
  sg13_nor2_1 noU2(.A(lSn3),   .B(lU3_t0),  .Y(lU3_t1));
  sg13_xor2_1 xoU3(.A(lUn3),   .B(lU3_t1),  .X(lU3_t2));
  sg13_inv_1  ivU3(.A(lU3_t2), .Y(cU[3])); // fo4

  // cU[4] = lSn3 & (lUn3 | lU3_t0)
  sg13_a21oi_1  aoU4(.A1(lUn3), .A2(lU3_t0), .B1(lSn3), .Y(cU[4]));

  assign P[7]=cU[4];  // yeah, at last a 2nd bit !

  ////////////////////
  // Replicator : shift-and
  ////////////////////
  // output bits ranks 3, 4, 5, 6 are negated.

  wire [4:1] Partial0;
  sg13_and2_1    aP01(.A(cS[0]), .B(cU[1]), .X(Partial0[1]));
  sg13_and2_1    aP02(.A(cS[0]), .B(cU[2]), .X(Partial0[2]));
  sg13_nand2_1  naP03(.A(cS[0]), .B(cU[3]), .Y(Partial0[3]));
  sg13_nand2_1  naP04(.A(cS[0]), .B(cU[4]), .Y(Partial0[4]));

  wire [5:1] Partial1;
  sg13_and2_1    aP11(.A(cS[1]), .B(cU[0]), .X(Partial1[1]));
  sg13_and2_1    aP12(.A(cS[1]), .B(cU[1]), .X(Partial1[2]));
  sg13_nand2_1  naP13(.A(cS[1]), .B(cU[2]), .Y(Partial1[3]));
  sg13_nand2_1  naP14(.A(cS[1]), .B(cU[3]), .Y(Partial1[4]));
  sg13_nand2_1  naP15(.A(cS[1]), .B(cU[4]), .Y(Partial1[5]));

  wire [6:2] Partial2; // Combines 2 levels, because numbers magic and happy coincidences.
  sg13_and2_1    aP32(.A (cS[2]), .B (cU[0]),                         .X(Partial2[2]));
  sg13_a22oi_1  aoP33(.A1(cS[2]), .A2(cU[1]), .B1(cS[3]), .B2(cU[0]), .Y(Partial2[3]));
  sg13_a22oi_1  aoP34(.A1(cS[2]), .A2(cU[2]), .B1(cS[3]), .B2(cU[1]), .Y(Partial2[4]));
  sg13_a22oi_1  aoP35(.A1(cS[2]), .A2(cU[3]), .B1(cS[3]), .B2(cU[2]), .Y(Partial2[5]));
  sg13_a22oi_1  aoP36(.A1(cS[2]), .A2(cU[4]), .B1(cS[3]), .B2(cU[3]), .Y(Partial2[6]));


  ////////////////////
  // Partials compression
  ////////////////////
  // 3 partial results reduced to 2

  wire A1, A2, A3n, A4n, A5n,
           B2, B3n, B4n, B5n,
     tx1;
  full_adder_sg13       fa2(.d1(Partial0[2]), .d2(Partial1[2]), .d3(Partial2[2]),  .S(A1), .C(A2));
  full_adder_sg13_neg_s fa3(.d1(Partial0[3]), .d2(Partial1[3]), .d3(Partial2[3]), .Sn(B2), .C(A3n));
  full_adder_sg13       fa4(.d1(Partial0[4]), .d2(Partial1[4]), .d3(Partial2[4]), .S(B3n), .C(A4n));
  full_adder_sg13_x     fa5(.d1(Partial0[4]), .d2(Partial1[5]), .d3(Partial2[5]), .S(B4n), .C(A5n), .X(tx1));
  sg13_xor2_1           rx1(                                     .A(Partial2[6]), .B(tx1), .X(B5n));


  ////////////////////
  // Propagate/Generate
  ////////////////////
  wire G0, G1, G2, G3, G4,
               P2, P3, P4,     P34,
                   t3, t4, t5,
               X2, X3, X4, X5;
  // PGX: the 3 critical gates for a CLA, but some polarities
  // must be adjusted due to inverted inputs
  sg13_xor2_1  PGX2x(.A(A2),  .B(B2),  .X(X2));
  sg13_and2_1  PGX2a(.A(A2),  .B(B2),  .X(G2));
  sg13_or2_1   PGX2o(.A(A2),  .B(B2),  .X(P2));

  sg13_xor2_1  PGX3x(.A(A3n), .B(B3n), .X(X3));
  sg13_nor2_1  PGX3o(.A(A3n), .B(B3n), .Y(G3));
  sg13_nand2_1 PGX3a(.A(A3n), .B(B3n), .Y(P3));

  sg13_xor2_1  PGX4x(.A(A4n), .B(B4n), .X(X4));
  sg13_nor2_1  PGX4o(.A(A4n), .B(B4n), .Y(G4));
  sg13_nand2_1 PGX4a(.A(A4n), .B(B4n), .Y(P4));

  sg13_xor2_1  PGX5x(.A(A5n), .B(B5n), .X(X5));

  // some intermediary signals
  sg13_and2_1  int1(.A(Partial0[1]),  .B(Partial1[1]),         .X(G0));
  sg13_and3_1  int2(.A(Partial0[1]),  .B(Partial1[1]), .C(A1), .X(G1));
  sg13_and2_1  int3(.A(P3),  .B(P4),  .X(P34));

  // at last some outputs:
  sg13_xor2_1  xo1(.A(Partial0[1]),  .B(Partial1[1]),  .X(P[1]));
  sg13_xor2_1  xo2(.A(G0),           .B(A1),           .X(P[2]));
  sg13_xor2_1  xo3(.A(G1),           .B(X2),           .X(P[3]));

  // Take a breath, and carry on
  sg13_a21o_1  ao(.A1(P2), .A2(G1), .B1(G2), .X(t3));

  // more outputs
  sg13_xor2_1  xo4(.A(t3), .B(X3), .X(P[4]));

  sg13_a21oi_1  ao4(.A1(t3), .A2(P3), .B1(G3), .Y(t4));
  sg13_xnor2_1  xo5(.A(t4),   .B(X4), .Y(P[5]));

  sg13_a221oi_1 ao5(.A1(t3), .A2(P34), .B1(G3), .B2(P4), .C1(G4), .Y(t5));
  sg13_xnor2_1  xo6(.A(t5), .B(X5), .Y(P[6]));
endmodule

`endif
