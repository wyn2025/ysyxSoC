module ps2_top_apb(
  input         clock,
  input         reset,
  input  [31:0] in_paddr,
  input         in_psel,
  input         in_penable,
  input  [2:0]  in_pprot,
  input         in_pwrite,
  input  [31:0] in_pwdata,
  input  [3:0]  in_pstrb,
  output        in_pready,
  output [31:0] in_prdata,
  output        in_pslverr,

  input         ps2_clk,
  input         ps2_data
);

	reg [2 : 0]	ps2_clk_sync;
  reg [7 : 0]	ps2_data_reg;

  reg [3 : 0] sampling_cnt ;
  reg [10 : 0] data_buffer ;
  reg [7:0]	fifo[7:0];
	reg [2:0]	w_ptr,r_ptr;
  reg       fifo_ready;

  wire is_read;
  wire is_done;
	wire sampling=ps2_clk_sync[2]&~ps2_clk_sync[1];

  assign in_pready=1'b1;
  assign in_prdata={24'b0,ps2_data_reg};
  // 协议强制要求:进入 ACCESS 阶段后,PADDR、PWRITE、PSEL、PWDATA 都必须保持稳定,直到 PREADY 有效。
  assign is_read = in_psel && in_penable && ~in_pwrite && (in_paddr==32'h1001_1000);
  assign is_done = (sampling_cnt == 4'd10) && (ps2_data) && (^data_buffer[9:1]) && (~data_buffer[0]) && sampling;

  always @(posedge clock)begin
	  ps2_clk_sync<={ps2_clk_sync[1:0],ps2_clk};
  end

  always @(posedge clock)begin
    if(reset)begin
      ps2_data_reg<=8'b0;
    end
    else if(fifo_ready)begin
      ps2_data_reg <= fifo[r_ptr];
    end
    else begin
      ps2_data_reg <= 8'b0;
    end
  end

  always @(posedge clock)begin
    if(reset)begin
      data_buffer <= 11'b0;
    end
    else if(sampling)begin
      data_buffer[sampling_cnt] <= ps2_data;
    end
  end

  always @(posedge clock)begin
    if(reset)begin
      sampling_cnt <= 4'b0;
    end
    else if(sampling)begin
      if(sampling_cnt == 4'd10)begin
        sampling_cnt <= 4'b0;
      end
      else
      sampling_cnt <= sampling_cnt + 'b1;
    end
  end

  always @(posedge clock) begin
    if(reset)
    begin
      w_ptr <= 3'b0;
      r_ptr <= 3'b0;
    end
    else if(is_done)begin
      w_ptr <= w_ptr + 3'b1;
    end
    else if((is_read) & fifo_ready)begin
      r_ptr <= r_ptr + 3'b1;
    end
  end

  always @(posedge clock) begin
    if(reset)
    begin
      fifo_ready <= 1'b0;
    end
    else if(w_ptr == r_ptr)begin
      fifo_ready <= 1'b0;
    end
    else begin
      fifo_ready <= 1'b1;
    end
  end

  always @(posedge clock) begin
    if(is_done)begin
      fifo[w_ptr] <= data_buffer[8:1];
    end
  end

endmodule
