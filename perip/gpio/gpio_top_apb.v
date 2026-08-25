module gpio_top_apb(
  input         clock,
  input         reset,
  // 地址总线，指定要访问的寄存器地址
  input  [31:0] in_paddr,
  // 选通信号，主机选中某个从设备时拉高
  input         in_psel,
  // 使能信号，标志传输进入第二个周期（数据阶段）
  input         in_penable,
  // 保护类型，指示访问的特权/安全属性
  input  [2:0]  in_pprot,
  // 读写控制：1 表示写，0 表示读
  input         in_pwrite,
  // 写数据总线，主机写给从机的数据
  input  [31:0] in_pwdata,
  // 写选通字节使能，指示 PWDATA 哪些字节有效, 读操作时 PSTRB 应为全 0 或被忽略
  input  [3:0]  in_pstrb,
  // 从机就绪信号，高表示传输可以完成
  output        in_pready,
  // 读数据总线，从机返回给主机的数据
  output [31:0] in_prdata,
  // 传输错误指示，高表示出错
  output        in_pslverr,

  output [15:0] gpio_out,
  input  [15:0] gpio_in,
  output [7:0]  gpio_seg_0,
  output [7:0]  gpio_seg_1,
  output [7:0]  gpio_seg_2,
  output [7:0]  gpio_seg_3,
  output [7:0]  gpio_seg_4,
  output [7:0]  gpio_seg_5,
  output [7:0]  gpio_seg_6,
  output [7:0]  gpio_seg_7
);

localparam LED_ADDR_BASE = 32'h1000_2000;
localparam DIP_ADDR_BASE = 32'h1000_2004;
localparam SEG_ADDR_BASE = 32'h1000_2008;

localparam LED_ADDR_END = LED_ADDR_BASE + 2;
localparam DIP_ADDR_END = DIP_ADDR_BASE + 2;
localparam SEG_ADDR_END = SEG_ADDR_BASE + 4;

wire [15:0] led_write_data = {((in_pwdata[15:8] & {8{in_pstrb[1]}}) 
                            | (led_reg[15:8] & {8{~in_pstrb[1]}})),
                            ((in_pwdata[7:0] & {8{in_pstrb[0]}}) | 
                            (led_reg[7:0] & {8{~in_pstrb[0]}}))}; 


wire is_led_write = in_psel && in_penable && in_pwrite && (in_paddr >= LED_ADDR_BASE && in_paddr < LED_ADDR_END);
//wire is_dip_read = in_psel && in_penable && ~in_pwrite && (in_paddr >= DIP_ADDR_BASE && in_paddr < DIP_ADDR_END);
wire is_seg_write = in_psel && in_penable && in_pwrite && (in_paddr >= SEG_ADDR_BASE && in_paddr < SEG_ADDR_END);

reg [15 : 0] led_reg;
reg [15 : 0] dip_reg;
reg [31 : 0] seg_reg; 

assign gpio_out = led_reg;
assign in_prdata = {16'b0, dip_reg};
assign in_pready = 1'b1; // 从机始终准备好完成传输
assign in_pslverr = 1'b0; // 不产生错误

assign gpio_seg_0[0] = 'b1;
assign gpio_seg_1[0] = 'b1;
assign gpio_seg_2[0] = 'b1;
assign gpio_seg_3[0] = 'b1;
assign gpio_seg_4[0] = 'b1;
assign gpio_seg_5[0] = 'b1;
assign gpio_seg_6[0] = 'b1;
assign gpio_seg_7[0] = 'b1;

/*
assign gpio_seg_0 = 'b001_10011;//4
assign gpio_seg_1 = 'b001_10010;
assign gpio_seg_2 = 'b1001_1001;
assign gpio_seg_3 = 'b0001_1001;
assign gpio_seg_4 = 'b1001_0010;
assign gpio_seg_5 = 'b0100_1001;
assign gpio_seg_6 = 'b1_1111111;
assign gpio_seg_7 = 'b1_1111111;
*/
always @(posedge clock) begin
  if (reset)
    led_reg <= 16'b0;
  else if (is_led_write)
    led_reg <= led_write_data;
  else
    led_reg <= led_reg;
end

always @(posedge clock) begin
  if(reset)
    dip_reg <= 16'b0;
  else
    dip_reg <= gpio_in;
end

always @(posedge clock)begin
  if (reset)
    seg_reg <= {32{1'b1}};
  else if (is_seg_write)
    seg_reg <= in_pwdata[31:0];
  else
    seg_reg <= seg_reg;
end

bcd7seg bcd7seg_u1(
  .b  (seg_reg[3:0]),
  .h  (gpio_seg_0[7:1])
);

bcd7seg bcd7seg_u2(
  .b  (seg_reg[7:4]),
  .h  (gpio_seg_1[7:1])
);

bcd7seg bcd7seg_u3(
  .b  (seg_reg[11:8]),
  .h  (gpio_seg_2[7:1])
);

bcd7seg bcd7seg_u4(
  .b  (seg_reg[15:12]),
  .h  (gpio_seg_3[7:1])
);

bcd7seg bcd7seg_u5(
  .b  (seg_reg[19:16]),
  .h  (gpio_seg_4[7:1])
);

bcd7seg bcd7seg_u6(
  .b  (seg_reg[23:20]),
  .h  (gpio_seg_5[7:1])
);

bcd7seg bcd7seg_u7(
  .b  (seg_reg[27:24]),
  .h  (gpio_seg_6[7:1])
);

bcd7seg bcd7seg_u8(
  .b  (seg_reg[31:28]),
  .h  (gpio_seg_7[7:1])
);

endmodule
