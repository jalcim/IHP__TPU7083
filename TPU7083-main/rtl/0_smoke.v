`ifndef __SMOKE__
`define __SMOKE__

`include "00_params.vh"

/* Module du banc trivial : additionne C à chaque cycle. Il ne sert qu'à éprouver
 * la chaîne des paramètres, des vecteurs et de CTest. */

module smoke #(parameter C     = `TILE_C,
               parameter SUM_W = 16)
              (input              i_clk,
               input              i_rst_n,
               output [SUM_W-1:0] o_sum);

    wire [SUM_W-1:0] w_step = C[SUM_W-1:0];
    reg  [SUM_W-1:0] r_sum;

    always @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n)
            r_sum <= {SUM_W{1'b0}};
        else
            r_sum <= r_sum + w_step;

    assign o_sum = r_sum;

endmodule

`endif
