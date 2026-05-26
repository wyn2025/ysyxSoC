// define this macro to enable fast behavior simulation
// for flash by skipping SPI transfers
//`define FAST_FLASH

module spi_top_apb #(
  parameter flash_addr_start = 32'h30000000,
  parameter flash_addr_end   = 32'h3fffffff,
  parameter spi_ss_num       = 8
) (
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

  output                  spi_sck,
  output [spi_ss_num-1:0] spi_ss,
  output                  spi_mosi,
  input                   spi_miso,
  output                  spi_irq_out
);

`ifdef FAST_FLASH

wire [31:0] data;
parameter invalid_cmd = 8'h0;
flash_cmd flash_cmd_i(
  .clock(clock),
  .valid(in_psel && !in_penable),
  .cmd(in_pwrite ? invalid_cmd : 8'h03),
  .addr({8'b0, in_paddr[23:2], 2'b0}),
  .data(data)
);
assign spi_sck    = 1'b0;
assign spi_ss     = 8'b0;
assign spi_mosi   = 1'b1;
assign spi_irq_out= 1'b0;
assign in_pslverr = 1'b0;
assign in_pready  = in_penable && in_psel && !in_pwrite;
assign in_prdata  = data[31:0];

`else

  localparam  ST_IDLE = 0, 
              ST_CMD = 1, 
              ST_ADDR = 2, 
              ST_DATA = 3, 
              ST_DONE = 4;

  //XIP控制器
  wire is_flash_req;
  wire xip_enable ;
  wire reg_enable ;
  // SPI 控制器
  wire        reg_ready;
  wire [31:0] reg_rdata;
  wire        reg_err;
  wire        reg_sck;
  wire        reg_mosi;
  wire [spi_ss_num-1:0] reg_ss;
  // XIP 模式下的 SPI 信号
  wire xip_active ;
  wire xip_mosi_out ;
  wire xip_ss_out   ; // Active Low (0为选中)
  wire xip_sck_out  ; // 简化的 SPI Mode 0 时钟
 
  // 辅助信号
  wire xip_start_cond ;
  wire [2:0] state_next ;
  wire is_st_idle ;
  wire is_st_cmd  ;
  wire is_st_addr ;
  wire is_st_data ;
  wire is_st_done ;

  wire [31 : 0] shifter_next;
  wire [31 : 0] shifter_idle;
  wire [31 : 0] shifter_cmd;
  wire [31 : 0] shifter_addr;
  wire [31 : 0] shifter_data;
  wire [31:0] xip_rdata_swapped;

  //计数
  wire [5 : 0] cmd_bit_cnt_next;
  wire [5 : 0] addr_bit_cnt_next;
  wire [5 : 0] data_bit_cnt_next;
  wire [5 : 0] cnt_next;

  // XIP 控制器 (简易状态机)
  reg [2:0]  xip_state;
  reg [5:0]  xip_bit_cnt;
  reg [31:0] xip_data_shifter;
  reg        xip_ready_reg;

  reg spi_miso_latched;

  // 地址空间解码，判断当前请求是否落在 Flash 映射区域
  assign is_flash_req = (in_paddr >= flash_addr_start) && (in_paddr <= flash_addr_end);
  // XIP 仅支持读操作，如果是写操作则视为非法或忽略
  assign xip_enable = in_psel && is_flash_req && !in_pwrite;
  // 普通寄存器访问：片选有效且地址不在Flash区域
  assign reg_enable = in_psel && !is_flash_req;

  // XIP 模式下的 SPI 信号
  assign xip_active = (xip_state != ST_IDLE);
  assign xip_mosi_out = xip_active ? xip_data_shifter[31] : 1'b0;
  assign xip_ss_out   = !xip_active; // Active Low (0为选中)
  assign xip_sck_out  = xip_active ? ~clock : 1'b0; // 简化的 SPI Mode 0 时钟

  // 总线与引脚多路复用 (Mux),根据当前是 XIP 模式还是 寄存器模式，选择输出信号
  // APB 回读信号 Mux
  assign in_prdata  = is_flash_req ? xip_rdata_swapped : reg_rdata;
  assign in_pready  = is_flash_req ? xip_ready_reg    : reg_ready;
  assign in_pslverr = is_flash_req ? 1'b0             : reg_err; // 忽略XIP写错误
  // SPI 物理引脚 Mux,如果正在进行 XIP 传输，则由 XIP 逻辑控制引脚
  assign spi_sck  = is_flash_req ? xip_sck_out  : reg_sck;
  assign spi_mosi = is_flash_req ? xip_mosi_out : reg_mosi;
  // CS 处理：XIP只控制 bit 0，寄存器模式控制所有
  assign spi_ss   = is_flash_req ? { {(spi_ss_num-1){1'b1}}, xip_ss_out } : reg_ss;
  // 提取公共的启动条件
  assign xip_start_cond = (xip_state == ST_IDLE) && xip_enable && in_penable;

  //状态控制
  assign is_st_cmd  = ((xip_state == ST_IDLE) & xip_start_cond) | 
                      ((xip_state == ST_CMD) & ~(xip_bit_cnt == 0)) ;
  assign is_st_addr = ((xip_state == ST_CMD) & (xip_bit_cnt == 0)) |
                      ((xip_state == ST_ADDR) & ~(xip_bit_cnt == 0))  ;
  assign is_st_data = ((xip_state == ST_ADDR) & (xip_bit_cnt == 0)) |
                      ((xip_state == ST_DATA) & ~(xip_bit_cnt == 0))  ;
  assign is_st_done = ((xip_state == ST_DATA) & (xip_bit_cnt == 0)) |
                      ((xip_state == ST_DONE) & in_penable)  ;
            
  assign state_next = is_st_cmd  ? ST_CMD  :
                      is_st_addr ? ST_ADDR :
                      is_st_data ? ST_DATA :
                      is_st_done ? ST_DONE : ST_IDLE;

  // 位计数器控制
  assign cmd_bit_cnt_next  = (xip_bit_cnt == 0) ? 23 : xip_bit_cnt - 1; // CMD 阶段从 7 递减到 0
  assign addr_bit_cnt_next = (xip_bit_cnt == 0) ? 31 : xip_bit_cnt - 1; // ADDR 阶段从 23 递减到 0
  assign data_bit_cnt_next = xip_bit_cnt - 1;
  assign cnt_next = (xip_state == ST_IDLE) ? 'd7 :
                    (xip_state == ST_CMD)  ? cmd_bit_cnt_next  :
                    (xip_state == ST_ADDR) ? addr_bit_cnt_next :
                    (xip_state == ST_DATA) ? data_bit_cnt_next : xip_bit_cnt;

  // 移位寄存器
  assign shifter_idle = {24'h030000, 8'h00}; // CMD 0x03 + 8-bit padding
  assign shifter_cmd  = (xip_bit_cnt == 0) ? {in_paddr[23:0], 8'h00} : {xip_data_shifter[30:0], 1'b0};
  assign shifter_addr = {xip_data_shifter[30:0], 1'b0}; // 地址发送过程中持续移位
  assign shifter_data = {xip_data_shifter[30:0], spi_miso_latched}; // 数据阶段持续移位并接收 MISO
  assign shifter_next = ((xip_state == ST_IDLE) & xip_start_cond) ? shifter_idle :
                        (xip_state == ST_CMD)  ? shifter_cmd  :
                        (xip_state == ST_ADDR) ? shifter_addr :
                        (xip_state == ST_DATA) ? shifter_data : xip_data_shifter; // DONE 状态保持当前值

  // 处理字节序问题：将 Big-Endian (网络字节序/SPI序) 转换为 Little-Endian                      
  assign xip_rdata_swapped = {
      xip_data_shifter[7:0],    // 接收到的第1个字节 (低地址) -> 放到 LSB
      xip_data_shifter[15:8],   // 接收到的第2个字节
      xip_data_shifter[23:16],  // 接收到的第3个字节
      xip_data_shifter[31:24]   // 接收到的第4个字节 (高地址) -> 放到 MSB
  };

  //当访问 Flash 地址时，自动生成 SPI 读时序 (Command 0x03)
  // 1. 状态机跳转逻辑 (控制 xip_state)
  always @(posedge clock or posedge reset) begin
    if (reset)
      xip_state <= ST_IDLE;
    else
      xip_state <= state_next;
end

// 2. 位计数器逻辑 (控制 xip_bit_cnt)
always @(posedge clock or posedge reset) begin
  if (reset)
    xip_bit_cnt <= 0;
  else
    xip_bit_cnt <= cnt_next;
end

// 3. 移位寄存器/数据路径 (控制 xip_data_shifter)
always @(posedge clock or posedge reset) begin
  if (reset)
    xip_data_shifter <= 0;
  else 
    xip_data_shifter <= shifter_next;
end

// 4. 握手信号逻辑 (控制 xip_ready_reg)
always @(posedge clock or posedge reset) begin
  if (reset) 
    xip_ready_reg <= 1'b0;
  else if (xip_state == ST_DONE)
      xip_ready_reg <= 1'b1;
  else if (xip_state == ST_IDLE)
      xip_ready_reg <= 1'b0;
end

// 1. 在系统时钟下降沿锁存 MISO
  // 此时 SCK = ~0 = 1 (上升沿)，是 SPI Mode 0 协议规定的数据采样时刻
  always @(negedge clock) begin
    if (reset)
      spi_miso_latched <= 1'b0;
    else
      spi_miso_latched <= spi_miso;
  end

  spi_top u0_spi_top (
    .wb_clk_i(clock),
    .wb_rst_i(reset),
    .wb_adr_i(in_paddr[4:0]),
    .wb_dat_i(in_pwdata),
    .wb_dat_o(reg_rdata),
    .wb_sel_i(in_pstrb),
    .wb_we_i (in_pwrite),
    // 只有当不是访问Flash时，才激活寄存器控制器
    .wb_stb_i(reg_enable), 
    .wb_cyc_i(in_penable && reg_enable),
    .wb_ack_o(reg_ready),
    .wb_err_o(reg_err),
    .wb_int_o(spi_irq_out),
    .ss_pad_o(reg_ss),
    .sclk_pad_o(reg_sck),
    .mosi_pad_o(reg_mosi),
    .miso_pad_i(spi_miso)
  );

`endif // FAST_FLASH

endmodule
