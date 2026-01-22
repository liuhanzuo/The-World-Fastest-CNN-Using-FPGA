`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: fc_layer_ext
// Description: 全连接层 - 使用外部BRAM接口
//              从外部BRAM读取输入数据，使用内部权重缓冲
//
// 计算: output[i] = sum(input[j] * weight[i][j]) >> SHIFT
//////////////////////////////////////////////////////////////////////////////////

module fc_layer_ext #(
    parameter DATA_W   = 8,
    parameter ADDR_W   = 16,
    parameter IN_SIZE  = 128,
    parameter OUT_SIZE = 10,
    parameter SHIFT    = 6
)(
    input  wire                clk,
    input  wire                resetn,
    input  wire                start,
    
    // 外部BRAM单字节读接口（读取输入数据）
    output reg                 bram_read_en,
    output reg  [ADDR_W-1:0]   bram_read_addr,
    input  wire [DATA_W-1:0]   bram_read_data,
    
    // 权重加载接口（内部权重缓冲）
    input  wire                wgt_we,
    input  wire [ADDR_W-1:0]   wgt_addr,
    input  wire [DATA_W-1:0]   wgt_data,
    
    // 输出
    output reg  [3:0]          pred_class,
    output reg signed [DATA_W-1:0] pred_score,
    output reg                 done
);

    // ============================================================
    // 权重缓冲（内部BRAM）
    // 大小: OUT_SIZE * IN_SIZE = 10 * 128 = 1280
    // ============================================================
    localparam WGT_DEPTH = OUT_SIZE * IN_SIZE;
    (* ram_style = "block" *) reg signed [DATA_W-1:0] wgt_buf [0:WGT_DEPTH-1];
    
    // 权重写入
    always @(posedge clk) begin
        if (wgt_we) begin
            wgt_buf[wgt_addr] <= wgt_data;
        end
    end
    
    // ============================================================
    // 状态机
    // ============================================================
    localparam S_IDLE  = 3'd0;
    localparam S_LOAD  = 3'd1;
    localparam S_WAIT  = 3'd2;
    localparam S_MAC   = 3'd3;
    localparam S_STORE = 3'd4;
    localparam S_NEXT  = 3'd5;
    localparam S_FIND  = 3'd6;
    localparam S_DONE  = 3'd7;
    
    reg [2:0] state;
    reg [15:0] cnt_out;           // 输出神经元计数
    reg [15:0] cnt_in;            // 输入神经元计数
    reg [3:0] wait_cnt;
    
    // MAC累加器
    reg signed [DATA_W+DATA_W+$clog2(IN_SIZE)-1:0] acc;
    
    // 输出结果缓冲
    reg signed [DATA_W-1:0] out_buf [0:OUT_SIZE-1];
    
    // 读取的数据和权重
    reg signed [DATA_W-1:0] in_val;
    reg signed [DATA_W-1:0] wgt_val;
    wire [ADDR_W-1:0] wgt_read_addr = cnt_out * IN_SIZE + cnt_in;
    
    // 最大值查找
    reg [3:0] max_idx;
    reg signed [DATA_W-1:0] max_val;
    
    // ============================================================
    // 主状态机
    // ============================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            done <= 0;
            bram_read_en <= 0;
            cnt_out <= 0;
            cnt_in <= 0;
            acc <= 0;
            pred_class <= 0;
            pred_score <= 0;
        end else begin
            // 默认
            bram_read_en <= 0;
            done <= 0;
            
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_LOAD;
                        cnt_out <= 0;
                        cnt_in <= 0;
                        acc <= 0;
                    end
                end
                
                S_LOAD: begin
                    // 发起读请求（读取输入数据）
                    bram_read_en <= 1;
                    bram_read_addr <= cnt_in;  // 输入数据地址
                    wait_cnt <= 0;
                    state <= S_WAIT;
                end
                
                S_WAIT: begin
                    // 等待BRAM读延迟
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt >= 1) begin
                        in_val <= bram_read_data;
                        wgt_val <= wgt_buf[wgt_read_addr];
                        state <= S_MAC;
                    end
                end
                
                S_MAC: begin
                    // 执行MAC操作
                    acc <= acc + $signed(in_val) * $signed(wgt_val);
                    
                    if (cnt_in >= IN_SIZE - 1) begin
                        state <= S_STORE;
                    end else begin
                        cnt_in <= cnt_in + 1;
                        state <= S_LOAD;
                    end
                end
                
                S_STORE: begin
                    // 存储当前输出神经元结果
                    // 应用移位和饱和
                    if ((acc >>> SHIFT) > 127)
                        out_buf[cnt_out] <= 127;
                    else if ((acc >>> SHIFT) < -128)
                        out_buf[cnt_out] <= -128;
                    else
                        out_buf[cnt_out] <= acc[SHIFT +: DATA_W];
                    
                    state <= S_NEXT;
                end
                
                S_NEXT: begin
                    // 移动到下一个输出神经元
                    cnt_in <= 0;
                    acc <= 0;
                    
                    if (cnt_out >= OUT_SIZE - 1) begin
                        // 全部计算完成，开始查找最大值
                        cnt_out <= 0;
                        max_idx <= 0;
                        max_val <= {1'b1, {(DATA_W-1){1'b0}}};  // 最小值
                        state <= S_FIND;
                    end else begin
                        cnt_out <= cnt_out + 1;
                        state <= S_LOAD;
                    end
                end
                
                S_FIND: begin
                    // 查找最大值（argmax）
                    if ($signed(out_buf[cnt_out]) > $signed(max_val)) begin
                        max_val <= out_buf[cnt_out];
                        max_idx <= cnt_out[3:0];
                    end
                    
                    if (cnt_out >= OUT_SIZE - 1) begin
                        pred_class <= max_idx;
                        pred_score <= max_val;
                        state <= S_DONE;
                    end else begin
                        cnt_out <= cnt_out + 1;
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
