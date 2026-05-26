module bitrev (
  input  sck,
  input  ss,
  input  mosi,
  output miso
);

//网表型
  wire [7:0] shift_reg_tx_w;
// 内部寄存器
    reg [2:0] bit_cnt;      // 位计数器 (0-7)
    reg [7:0] shift_reg_rx; // 接收移位寄存器
    reg [7:0] shift_reg_tx; // 发送移位寄存器

/*****************组合逻辑*******************/
    assign shift_reg_tx_w = {
                    shift_reg_rx[0], // 原第0位 -> 现第7位
                    shift_reg_rx[1], // 原第1位 -> 现第6位
                    shift_reg_rx[2], // 原第2位 -> 现第5位 
                    shift_reg_rx[3], 
                    shift_reg_rx[4], 
                    shift_reg_rx[5], 
                    shift_reg_rx[6], // 原第6位 -> 现第1位
                    shift_reg_rx[7]  // 原第7位 -> 现第0位
                };
    //输出控制
    assign miso = (ss) ? 1'b1 : shift_reg_tx[7];

/*****************时序逻辑*******************/
// 接收逻辑 (SPI Mode 0: 上升沿采样)
    always @(posedge sck or posedge ss) begin
        if (ss)
            bit_cnt <= 3'd0;
        else
            bit_cnt <= bit_cnt + 1'b1;
    end
    always @(posedge sck or posedge ss) begin
        if (ss) begin
            shift_reg_rx <= 8'd0;
        end else
            // 移位进入 MOSI 数据 (假设高位在前 MSB First)
            shift_reg_rx <= {shift_reg_rx[6:0], mosi};
    end

// 发送逻辑 (SPI Mode 0: 下降沿驱动)
    always @(negedge sck or posedge ss) begin
        if (ss)
          shift_reg_tx <= 8'd0;
        else if (bit_cnt == 3'd0)
          shift_reg_tx <= shift_reg_tx_w;
        else
          shift_reg_tx <= {shift_reg_tx[6:0], 1'b0};
    end

endmodule
