module sdram_bank(
    input              clk     ,
    input              en_w    ,
    input              en_ac   ,
    input   [12 : 0]   row_addr    ,
    input   [12 : 0]   col_addr    ,
    input   [15 : 0]   data_w  ,
    input   [ 1 : 0]   dqm     ,

    output  [15 : 0]   data_r  
);
  localparam ROW_NUM = 8192;
  localparam COL_NUM = 512;
  localparam BRAM_NUM = ROW_NUM * COL_NUM;

  wire [15 : 0] data_w_masked ;

    reg [12 : 0]  row_addr_r ;

    reg [15 : 0]bram_bank[BRAM_NUM - 1 : 0] ;

    assign data_r = bram_bank[row_addr_r * COL_NUM + col_addr] ;

    assign data_w_masked = {(({8{~dqm[1]}} & data_w[15:8]) | 
                          {8{dqm[1]}} & bram_bank[row_addr_r * COL_NUM + col_addr][15:8]) ,
                          ({8{~dqm[0]}} & data_w[7:0]) | ({8{dqm[0]}} & bram_bank[row_addr_r * COL_NUM + col_addr][7:0])} ;

always @(posedge clk) begin
    if(en_ac)
      row_addr_r <= row_addr ;
    else
      row_addr_r <= row_addr_r ;
    end

  always @(posedge clk) begin
    if(en_w)
      bram_bank[row_addr_r * COL_NUM + col_addr] <= data_w_masked ;
  end

endmodule