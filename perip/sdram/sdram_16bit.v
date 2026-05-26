module sdram_16bit(
  input        clk,
  input        cke,
  input        cs,
  input        ras,
  input        cas,
  input        we,
  input [12:0] a,
  input [ 1:0] ba,
  // 写操作时，将某个 DQM 信号拉高，对应字节的数据输入将被忽略，不会写入存储阵列；保持另一个 DQM 为低的字节则正常写入。这样就实现了单字节粒度的写控制。
  input [ 1:0] dqm,
  inout [15:0] dq

);
localparam  CMD_NOP                 = 3'b111,
            CMD_ACTIVE              = 3'b011,
            CMD_READ                = 3'b101,
            CMD_WRITE               = 3'b100,
            CMD_BURST_TERMINATE     = 3'b110,
            CMD_PRECHARGE           = 3'b010,
            CMD_AUTO_REFRESH        = 3'b001,
            CMD_LOAD_MODE_REGISTER  = 3'b000;


//  assign dq = 16'bz;
  wire          clk_rel;

  wire [3 : 0]  bank_en_n ;

  wire [15 : 0] data_r_n ;
  wire          read_finish_one  ;
  wire          finish_one  ;

  wire [2 : 0]  burst_len ;
  wire          burst_type ;
  wire [2 : 0]  cas_latency ;
  wire [1 : 0]  op_mode ;
  wire          write_burst_mode ;

  wire          write_read_stop ;
  wire          is_cmd_w_r ;

  reg          is_reading ;
  reg         is_writing ;

  reg [2 : 0]   cmd_w ;

  reg [1 : 0]   read_latency_cnt ;
  reg [3 : 0]   bank_w_en;
  reg [3 : 0]   bank_r_en;
  reg [3 : 0]   bank_ac_en ;

  reg [11 : 0]  mode_reg ;

  reg [12 : 0] addr_col ;
  reg [12 : 0] addr_row ;

  reg [8 : 0]   burst_cnt ;
//  reg [8 : 0]   burst_len_r ;
  reg [8 : 0]   burst_len_real ;

  reg [1 : 0]  dqm_r ;
  reg [15 : 0] dq_r ;

  assign clk_rel = clk & cke  ;

  assign bank_en_n = {(ba==3) , (ba==2) , (ba==1) , (ba==0)} ;
  assign data_r_n =  bank_r_en[0] ? sdram_bank_0.data_r :
                     bank_r_en[1] ? sdram_bank_1.data_r :
                     bank_r_en[2] ? sdram_bank_2.data_r :
                     bank_r_en[3] ? sdram_bank_3.data_r : 16'bz ;
  assign dq = is_reading ? data_r_n : 16'bz ;

  assign burst_len = mode_reg[2:0] ;
  assign burst_type = mode_reg[3] ;
  assign cas_latency = mode_reg[6:4] ;
  assign op_mode = mode_reg[8:7] ;
  assign write_burst_mode = mode_reg[9] ;

  assign write_read_stop = (cmd_w == CMD_BURST_TERMINATE) | is_cmd_w_r |
                      (burst_cnt == burst_len_real) ;
  assign is_cmd_w_r = (cmd_w == CMD_WRITE) || (cmd_w == CMD_READ) ;

  assign finish_one = read_finish_one | is_writing  ;
  assign read_finish_one = (read_latency_cnt == (cas_latency[1 : 0] - 1)) ;

  assign cmd_w = cs ? 3'b111 : {ras,cas,we} ;

  always @(*) begin
    case(burst_len)
      3'b000: burst_len_real = 1 - 1 ;
      3'b001: burst_len_real = 2 - 1;
      3'b010: burst_len_real = 4 - 1;
      3'b011: burst_len_real = 8 - 1;
      3'b111: burst_len_real = 511 - a[8 : 0] ;
      default: burst_len_real = 0 ;
    endcase
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_ACTIVE)
      addr_row <= a ;
    else
      addr_row <= addr_row ;
  end

  always @(posedge clk_rel) begin
    if(is_cmd_w_r)
      addr_col <= a ;
    else if(finish_one)
      addr_col <= addr_col + 'd1 ;
    else
      addr_col <= addr_col ;
  end

  always @(posedge clk_rel) begin
      dqm_r <= dqm ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_READ)
      bank_r_en <= bank_en_n ;
    else
      bank_r_en <= bank_r_en ;
  end

  always @(posedge clk_rel) begin
    if(is_cmd_w_r)
      burst_cnt <= 0 ;
    else if(finish_one)
      burst_cnt <= burst_cnt + 1 ;
    else if(is_reading)
      burst_cnt <= burst_cnt ;
    else
      burst_cnt <= 'd0 ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_WRITE)
      bank_w_en <= bank_en_n ;
    else if(write_read_stop)
       bank_w_en <= 0 ;
    else if(is_writing)
      bank_w_en <= bank_w_en ;
    else
      bank_w_en <= 0 ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_ACTIVE)
      bank_ac_en <= bank_en_n ;
    else
      bank_ac_en <= bank_ac_en ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_LOAD_MODE_REGISTER)
      mode_reg <= a[11:0] ;
    else
      mode_reg <= mode_reg ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_READ)
      is_reading <= 1 ;
    else if((write_read_stop) && read_finish_one)
      is_reading <= 0 ;
    else
      is_reading <= is_reading ;
  end

  always @(posedge clk_rel) begin
    if(cmd_w == CMD_WRITE)
      is_writing <= 1 ;
    else if(write_read_stop)
      is_writing <= 0 ;
    else
      is_writing <= is_writing ;
  end

  always @(posedge clk_rel) begin
      dq_r <= dq ;
  end

  always @(posedge clk_rel) begin
    if(read_finish_one)
      read_latency_cnt <= 0 ;
    else if(is_reading)
      read_latency_cnt <= read_latency_cnt + 1 ;
    else
      read_latency_cnt <= 0 ;
  end

sdram_bank sdram_bank_0(
    .clk       (clk_rel),
    .en_w        (bank_w_en[0]),
    .en_ac       (bank_ac_en[0]),
    .row_addr  (addr_row),
    .col_addr  (addr_col),
    .data_w    (dq_r),
    .dqm       (dqm_r),

    .data_r    ()
);
sdram_bank sdram_bank_1(
    .clk       (clk_rel),
    .en_w        (bank_w_en[1]),
    .en_ac       (bank_ac_en[1]),
    .row_addr  (addr_row),
    .col_addr  (addr_col),
    .data_w    (dq_r),
    .dqm       (dqm_r),

    .data_r    ()
);
sdram_bank sdram_bank_2(
    .clk       (clk_rel),
    .en_w        (bank_w_en[2]),
    .en_ac       (bank_ac_en[2]),
    .row_addr  (addr_row),
    .col_addr  (addr_col),
    .data_w    (dq_r),
    .dqm       (dqm_r),

    .data_r    ()
);
sdram_bank sdram_bank_3(
    .clk       (clk_rel),
    .en_w        (bank_w_en[3]),
    .en_ac       (bank_ac_en[3]),
    .row_addr  (addr_row),
    .col_addr  (addr_col),
    .data_w    (dq_r),
    .dqm       (dqm_r),

    .data_r    ()
);
endmodule
