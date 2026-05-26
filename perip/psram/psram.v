module psram(
  input sck,
  input ce_n,
  inout [3:0] dio
);

// 状态机定义
    localparam STATE_CMD  = 3'd0;
    localparam STATE_ADDR = 3'd1;
    localparam STATE_WAIT = 3'd2;
    localparam STATE_DATA = 3'd3;

    localparam MODE_QSPI = 1'd0;
    localparam MODE_QPI = 1'd1;

    localparam ADDR_BITS = 24;       // 地址位宽
    localparam MEM_DEPTH = 4 * 1024 * 1024;      // 仿真存储深度
    localparam REAL_ADDR_WIDTH = (MEM_DEPTH > 1) ? $clog2(MEM_DEPTH) : 1;;  // 实际地址位宽
 
    // 下一个状态
    wire [2 : 0]  next_state;
    wire is_cmd;
    wire is_addr;
    wire is_wait;
    wire is_data;

    wire is_write; // 写操作标志

    wire mode_is_qspi;
    wire mode_is_qpi;
    wire cmd_valid; // 命令有效标志

    // 下一个状态相关的信号
    wire [7:0] cmd_next;
    wire [23:0] addr_next;
    wire [7:0] data_in_next;
    wire out_en_next;
    wire [5:0] cnt_next;
    wire [5:0] bit_cnt_next;
    wire [5:0] cnt_cmd_next;
    wire [5:0] cnt_addr_next;
    wire [5:0] cnt_wait_next;
    wire [5:0] cnt_data_next;
    //输出
    wire [3:0] dio_out_buf_next;

    // 内部存储阵列
    reg [7:0] mem [0:MEM_DEPTH-1];
    // 当前状态寄存器
    reg [2:0] current_state;
    // 模式寄存器（0：QSPI，1：QPI）
    reg mode;
    // 内部寄存器
    reg [7:0]  cmd_reg;
    reg [23:0] addr_reg;
    reg [7:0]  data_in_reg;  // 接收到的写入数据
    reg        out_en;       // 输出使能
    // 计数器
    reg [5:0]  bit_cnt;      // 用于记录当前阶段传输了多少个bit/clock
    // 三态门控制
    // 当 out_en 有效时，将 data_out_reg 的高4位或低4位输出
    // 输出在下降沿更新，一次输出4bit
    reg [3:0] dio_out_buf;
    
    assign dio = out_en ? dio_out_buf : 4'bz;
    //下一个状态
    assign is_cmd = ce_n | ((current_state == STATE_CMD) & ~is_addr);
    assign is_addr = cmd_valid | ((current_state == STATE_ADDR) & (bit_cnt < 5));
    assign is_wait = ((current_state == STATE_ADDR) & (bit_cnt == 5) & (cmd_reg == 8'hEB)) |
                    ((current_state == STATE_WAIT) & (bit_cnt < 5));
    assign is_data = (current_state == STATE_WAIT) & (bit_cnt == 5) |
                    ((current_state == STATE_ADDR) & (bit_cnt == 5) & (cmd_reg == 8'h38)) |
                      (current_state == STATE_DATA);
    assign next_state = is_cmd  ? STATE_CMD  :
                        is_addr ? STATE_ADDR :
                        is_wait ? STATE_WAIT :
                        is_data ? STATE_DATA : STATE_CMD;

    assign is_write = current_state == STATE_DATA && cmd_reg == 8'h38 && bit_cnt == 1; // 写操作在数据阶段且命令为0x38时有效，且每接收完一个Byte（bit_cnt==1）进行写入

    assign cmd_valid = ((mode == MODE_QSPI)&&(current_state == STATE_CMD) && (bit_cnt == 7)) || ((mode == MODE_QPI)&&(current_state == STATE_CMD) && (bit_cnt == 1)); // 命令在命令阶段接收完8bit时有效
    assign mode_is_qspi = (cmd_next == 8'hF5) && cmd_valid; // 0xF5为QSPI模式命令
    assign mode_is_qpi = (cmd_next == 8'h35) && cmd_valid; // 0x35为QPI模式命令

    //命令
    assign cmd_next = current_state == STATE_CMD ? 
                        (({cmd_reg[6:0], dio[0]} & {8{(mode==MODE_QSPI)}}) | 
                        ({cmd_reg[3:0], dio} & {8{(mode==MODE_QPI)}})) :
                        cmd_reg;
    //地址
    assign addr_next = (current_state == STATE_ADDR) ? {addr_reg[19:0], dio} : // 地址寄存器左移4位并接入新输入
                      ((current_state == STATE_DATA) && (bit_cnt == 1)) ? addr_reg + 1 : // 数据阶段每传完一个Byte地址自增
                      addr_reg;
    //数据输入
    assign data_in_next = (current_state == STATE_DATA && cmd_reg == 8'h38) ? // 写命令数据阶段
                        ((bit_cnt == 0) ? {dio, data_in_reg[3:0]} : // 接收高4位
                        (bit_cnt == 1) ? {data_in_reg[7:4], dio} : // 接收低4位
                        data_in_reg) :
                        data_in_reg;
    //输出使能
    assign out_en_next = (current_state == STATE_DATA) && (cmd_reg == 8'hEB);

    //位计数器
    assign cnt_cmd_next =  (mode == MODE_QPI) ? 
                            ((bit_cnt == 1) ? 0 : bit_cnt + 1): // 命令阶段每接收4bit计数器加1，满2次（8bit）后重置
                            (bit_cnt == 7) ? 0 : bit_cnt + 1; // 命令阶段每接收1bit计数器加1，满8bit后重置
    assign cnt_addr_next = (bit_cnt == 5) ? 0 : bit_cnt + 1; // 地址阶段每接收4bit计数器加1，满6次（24bit）后重置
    assign cnt_wait_next = (bit_cnt == 5) ? 0 : bit_cnt + 1; // 等待阶段每个时钟周期计数器加1，满
    assign cnt_data_next = {5'b0, ~bit_cnt[0]}; 
    assign cnt_next = (current_state == STATE_CMD) ? cnt_cmd_next :
                            (current_state == STATE_ADDR) ? cnt_addr_next :
                            (current_state == STATE_WAIT) ? cnt_wait_next :
                            (current_state == STATE_DATA) ? cnt_data_next :
                            0;
    //输出
    assign dio_out_buf_next = (current_state == STATE_DATA && cmd_reg == 8'hEB) ?
                        (({4{(bit_cnt == 0)}} & mem[addr_reg[REAL_ADDR_WIDTH-1:0]][7:4])| 
                        ({4{(bit_cnt == 1)}} & mem[addr_reg[REAL_ADDR_WIDTH-1:0]][3:0]))
                      : 4'dz; //TODO

    // 主逻辑：SCK 上升沿采样输入 (Sample Input)
    always @(posedge sck or posedge ce_n) begin
        if(ce_n)
            current_state <= STATE_CMD; // 片选无效时回到命令状态
        else
            current_state <= next_state;
    end
    always @(posedge sck) begin
        if(ce_n) 
            mode <= MODE_QSPI; // 片选无效时默认QSPI模式
        else if(mode_is_qpi) // 在命令阶段接收完8bit命令后确定模式
            mode <= MODE_QPI; // 0xEB为QPI模式命令，其他为QSPI模式
        else if(mode_is_qspi)
            mode <= MODE_QSPI;
        else
            mode <= mode; // 其他情况保持当前模式
    end
    always @(posedge sck) begin
        if(ce_n) 
            cmd_reg <= 0;
        else 
            cmd_reg <= cmd_next;
    end
    always @(posedge sck) begin
        if(ce_n) 
            addr_reg <= 0;
        else 
            addr_reg <= addr_next;
    end
    always @(posedge sck) begin
        if(ce_n) 
            data_in_reg <= 0;
        else 
            data_in_reg <= data_in_next;
    end
    always @(posedge sck) begin
        if(is_write) // 写命令数据阶段每接收完一个Byte写入内存
            mem[addr_reg[REAL_ADDR_WIDTH-1:0]] <= data_in_next;
    end
    always @(posedge sck or posedge ce_n) begin
        if(ce_n) 
            bit_cnt <= 0;
        else 
            bit_cnt <= cnt_next;
    end
    always @(negedge sck) begin
        if(ce_n) 
            out_en <= 0;
        else 
            out_en <= out_en_next;
    end
    always @(negedge sck) begin
        if(ce_n) 
            dio_out_buf <= 4'b0;
        else 
            dio_out_buf <= dio_out_buf_next;
    end    

    export "DPI-C" function read_psram_data;
    function byte unsigned read_psram_data(input int addr);
        // 这里可以加边界检查
        if (addr >= 0 && addr <= MEM_DEPTH)
            return mem[addr];
        else
            return 8'hEF; // 错误码
    endfunction
endmodule
