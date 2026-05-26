module sdram(
  input           clk,
  input           cke,
  input [1 : 0]   cs,
  input           ras,
  input           cas,
  input           we,
  input [12 : 0]  a,
  input [1 : 0]   ba,
  input [3 : 0]   dqm,
  inout [63 : 0]  dq
);

sdram_bit_extension sdram_bit_extension_u1(
  .clk(clk),
  .cke(cke),
  .cs(cs[1]),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm),
  .dq(dq[63 :32])
);

sdram_bit_extension sdram_bit_extension_u2(
  .clk(clk),
  .cke(cke),
  .cs(cs[0]),
  .ras(ras),
  .cas(cas),
  .we(we),
  .a(a),
  .ba(ba),
  .dqm(dqm),
  .dq(dq[31 :0])
);

endmodule