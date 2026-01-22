`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: cnn_top
// Description: 完整CNN网络顶层模块 - 使用全局共享BRAM和Ping-Pong机制
//
// Network Architecture:
//   Input (1x32x32) 
//     -> Conv1 (32x32x32, K=5, pad=2, stride=1)
//     -> Pool1 (32x16x16, MaxPool 2x2)
//     -> Conv2 (64x16x16, K=3, pad=1, stride=1)
//     -> Conv3 (64x8x8,   K=3, pad=1, stride=2)
//     -> Conv4 (128x4x4,  K=3, pad=1, stride=2)
//     -> AvgPool (128x1x1)
//     -> FC (10)
//     -> Output (class 0-9)
//
// BRAM架构：
//   - 使用全局共享的Ping-Pong双Buffer
//   - Bank0和Bank1交替作为输入和输出
//   - 每层执行时从一个Bank读取，写入到另一个Bank
//   - 最大容量：32KB per bank（32x32x32=32768字节）
//
// Ping-Pong切换方式：
//   Conv1:   读Bank0(输入图像) -> 写Bank1
//   Pool1:   读Bank1 -> 写Bank0
//   Conv2:   读Bank0 -> 写Bank1
//   Conv3:   读Bank1 -> 写Bank0
//   Conv4:   读Bank0 -> 写Bank1
//   AvgPool: 读Bank1 -> 写Bank0
//   FC:      读Bank0 -> 输出
//////////////////////////////////////////////////////////////////////////////////

module cnn_top #(
    parameter DATA_W = 8,
    parameter ADDR_W = 16,
    parameter TILE_W = 8,
    parameter TILE_C = 8
)(
    input  wire                clk,
    input  wire                resetn,
    input  wire                start,
    
    // 输入图像加载接口
    input  wire                img_we,
    input  wire [ADDR_W-1:0]   img_addr,
    input  wire [DATA_W-1:0]   img_data,
    
    // Conv1权重加载
    input  wire                conv1_wgt_we,
    input  wire [ADDR_W-1:0]   conv1_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] conv1_wgt_data,
    
    // Conv2权重加载
    input  wire                conv2_wgt_we,
    input  wire [ADDR_W-1:0]   conv2_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] conv2_wgt_data,
    
    // Conv3权重加载
    input  wire                conv3_wgt_we,
    input  wire [ADDR_W-1:0]   conv3_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] conv3_wgt_data,
    
    // Conv4权重加载
    input  wire                conv4_wgt_we,
    input  wire [ADDR_W-1:0]   conv4_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] conv4_wgt_data,
    
    // FC权重加载
    input  wire                fc_wgt_we,
    input  wire [ADDR_W-1:0]   fc_wgt_addr,
    input  wire [DATA_W-1:0]   fc_wgt_data,
    
    // 输出
    output wire [3:0]          pred_class,
    output wire signed [DATA_W-1:0] pred_score,
    output wire                done
);

    // ============================================================
    // 层参数定义
    // ============================================================
    // Conv1: 1x32x32 -> 32x32x32
    localparam CONV1_C_IN  = 1,   CONV1_C_OUT = 32;
    localparam CONV1_H_IN  = 32,  CONV1_W_IN  = 32;
    localparam CONV1_K     = 5,   CONV1_PAD   = 2,  CONV1_STRIDE = 1;
    localparam CONV1_SHIFT = 9;
    
    // Pool1: 32x32x32 -> 32x16x16
    localparam POOL1_C = 32, POOL1_H_IN = 32, POOL1_W_IN = 32;
    
    // Conv2: 32x16x16 -> 64x16x16
    localparam CONV2_C_IN  = 32,  CONV2_C_OUT = 64;
    localparam CONV2_H_IN  = 16,  CONV2_W_IN  = 16;
    localparam CONV2_K     = 3,   CONV2_PAD   = 1,  CONV2_STRIDE = 1;
    localparam CONV2_SHIFT = 8;
    
    // Conv3: 64x16x16 -> 64x8x8
    localparam CONV3_C_IN  = 64,  CONV3_C_OUT = 64;
    localparam CONV3_H_IN  = 16,  CONV3_W_IN  = 16;
    localparam CONV3_K     = 3,   CONV3_PAD   = 1,  CONV3_STRIDE = 2;
    localparam CONV3_SHIFT = 8;
    
    // Conv4: 64x8x8 -> 128x4x4
    localparam CONV4_C_IN  = 64,  CONV4_C_OUT = 128;
    localparam CONV4_H_IN  = 8,   CONV4_W_IN  = 8;
    localparam CONV4_K     = 3,   CONV4_PAD   = 1,  CONV4_STRIDE = 2;
    localparam CONV4_SHIFT = 8;
    
    // AvgPool: 128x4x4 -> 128x1x1
    localparam AVGPOOL_C = 128, AVGPOOL_H = 4, AVGPOOL_W = 4;
    
    // FC: 128 -> 10
    localparam FC_IN = 128, FC_OUT = 10, FC_SHIFT = 6;
    
    // ============================================================
    // 状态机
    // ============================================================
    localparam S_IDLE    = 4'd0;
    localparam S_CONV1   = 4'd1;
    localparam S_POOL1   = 4'd2;
    localparam S_CONV2   = 4'd3;
    localparam S_CONV3   = 4'd4;
    localparam S_CONV4   = 4'd5;
    localparam S_AVGPOOL = 4'd6;
    localparam S_FC      = 4'd7;
    localparam S_DONE    = 4'd8;
    
    reg [3:0] state;
    reg layer_start;
    
    // 层完成信号
    wire conv1_done, pool1_done, conv2_done, conv3_done, conv4_done;
    wire avgpool_done, fc_done;
    
    // ============================================================
    // Ping-Pong Bank选择
    // ============================================================
    // current_read_bank: 当前层读取的bank
    // 写入bank = ~current_read_bank
    reg current_read_bank;
    
    // ============================================================
    // 全局共享BRAM - Ping-Pong双Buffer
    // ============================================================
    localparam BRAM_DEPTH = 4096;  // 4096 words * 8 bytes = 32KB per bank
    
    (* ram_style = "block" *) reg [TILE_W*DATA_W-1:0] bram_bank0 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) reg [TILE_W*DATA_W-1:0] bram_bank1 [0:BRAM_DEPTH-1];
    
    // 初始化
    integer init_i;
    initial begin
        for (init_i = 0; init_i < BRAM_DEPTH; init_i = init_i + 1) begin
            bram_bank0[init_i] = 0;
            bram_bank1[init_i] = 0;
        end
    end
    
    // ============================================================
    // BRAM读接口信号（多路复用）
    // ============================================================
    reg                         bram_read_en;
    reg  [ADDR_W-1:0]          bram_read_addr_0, bram_read_addr_1, bram_read_addr_2;
    wire [TILE_W*DATA_W-1:0]   bram_read_data_0, bram_read_data_1, bram_read_data_2;
    
    // BRAM写接口信号（多路复用）
    reg                         bram_write_en;
    reg  [ADDR_W-1:0]          bram_write_addr;
    reg  [TILE_W*DATA_W-1:0]   bram_write_data;
    reg  [TILE_W-1:0]          bram_write_mask;
    
    // 单字节读写接口（用于池化层等）
    reg                         bram_byte_read_en;
    reg  [ADDR_W-1:0]          bram_byte_read_addr;
    wire [DATA_W-1:0]          bram_byte_read_data;
    
    reg                         bram_byte_write_en;
    reg  [ADDR_W-1:0]          bram_byte_write_addr;
    reg  [DATA_W-1:0]          bram_byte_write_data;
    
    // ============================================================
    // BRAM读逻辑 - 读取3个连续word
    // ============================================================
    wire [ADDR_W-4:0] read_word_addr_0 = bram_read_addr_0[ADDR_W-1:3];
    wire [ADDR_W-4:0] read_word_addr_1 = bram_read_addr_1[ADDR_W-1:3];
    wire [ADDR_W-4:0] read_word_addr_2 = bram_read_addr_2[ADDR_W-1:3];
    
    // Bank0 读取寄存器
    reg [TILE_W*DATA_W-1:0] bank0_rd0, bank0_rd1, bank0_rd2;
    always @(posedge clk) begin
        if (bram_read_en) begin
            bank0_rd0 <= bram_bank0[read_word_addr_0];
            bank0_rd1 <= bram_bank0[read_word_addr_1];
            bank0_rd2 <= bram_bank0[read_word_addr_2];
        end
    end
    
    // Bank1 读取寄存器
    reg [TILE_W*DATA_W-1:0] bank1_rd0, bank1_rd1, bank1_rd2;
    always @(posedge clk) begin
        if (bram_read_en) begin
            bank1_rd0 <= bram_bank1[read_word_addr_0];
            bank1_rd1 <= bram_bank1[read_word_addr_1];
            bank1_rd2 <= bram_bank1[read_word_addr_2];
        end
    end
    
    // Bank选择（延迟匹配）
    reg current_read_bank_d;
    always @(posedge clk) begin
        current_read_bank_d <= current_read_bank;
    end
    
    assign bram_read_data_0 = current_read_bank_d ? bank1_rd0 : bank0_rd0;
    assign bram_read_data_1 = current_read_bank_d ? bank1_rd1 : bank0_rd1;
    assign bram_read_data_2 = current_read_bank_d ? bank1_rd2 : bank0_rd2;
    
    // ============================================================
    // BRAM写逻辑（写入到另一个bank）
    // ============================================================
    wire [ADDR_W-4:0] write_word_addr = bram_write_addr[ADDR_W-1:3];
    wire write_to_bank1 = ~current_read_bank;  // 写入到读取bank的对面
    
    integer wi;
    always @(posedge clk) begin
        if (bram_write_en) begin
            if (write_to_bank1) begin
                for (wi = 0; wi < TILE_W; wi = wi + 1) begin
                    if (bram_write_mask[wi])
                        bram_bank1[write_word_addr][wi*DATA_W +: DATA_W] <= bram_write_data[wi*DATA_W +: DATA_W];
                end
            end else begin
                for (wi = 0; wi < TILE_W; wi = wi + 1) begin
                    if (bram_write_mask[wi])
                        bram_bank0[write_word_addr][wi*DATA_W +: DATA_W] <= bram_write_data[wi*DATA_W +: DATA_W];
                end
            end
        end
    end
    
    // ============================================================
    // 单字节读逻辑
    // ============================================================
    wire [ADDR_W-4:0] byte_read_word_addr = bram_byte_read_addr[ADDR_W-1:3];
    wire [2:0] byte_read_offset = bram_byte_read_addr[2:0];
    
    reg [TILE_W*DATA_W-1:0] byte_read_word_reg;
    reg [2:0] byte_read_offset_d;
    
    always @(posedge clk) begin
        byte_read_offset_d <= byte_read_offset;
        if (bram_byte_read_en) begin
            byte_read_word_reg <= current_read_bank ? bram_bank1[byte_read_word_addr] : bram_bank0[byte_read_word_addr];
        end
    end
    
    assign bram_byte_read_data = byte_read_word_reg[byte_read_offset_d*DATA_W +: DATA_W];
    
    // ============================================================
    // 单字节写逻辑
    // ============================================================
    wire [ADDR_W-4:0] byte_write_word_addr = bram_byte_write_addr[ADDR_W-1:3];
    wire [2:0] byte_write_offset = bram_byte_write_addr[2:0];
    
    always @(posedge clk) begin
        if (bram_byte_write_en) begin
            if (write_to_bank1)
                bram_bank1[byte_write_word_addr][byte_write_offset*DATA_W +: DATA_W] <= bram_byte_write_data;
            else
                bram_bank0[byte_write_word_addr][byte_write_offset*DATA_W +: DATA_W] <= bram_byte_write_data;
        end
    end
    
    // ============================================================
    // 外部图像加载逻辑（写入Bank0）
    // ============================================================
    reg [TILE_W*DATA_W-1:0] img_pack_reg;
    reg [2:0] img_pack_cnt;
    reg img_pack_valid;
    reg [ADDR_W-1:0] img_pack_addr;
    
    always @(posedge clk) begin
        if (!resetn) begin
            img_pack_reg <= 0;
            img_pack_cnt <= 0;
            img_pack_valid <= 0;
            img_pack_addr <= 0;
        end else begin
            img_pack_valid <= 0;
            if (img_we) begin
                img_pack_reg[img_pack_cnt*8 +: 8] <= img_data;
                if (img_pack_cnt == 7) begin
                    img_pack_valid <= 1;
                    img_pack_addr <= img_addr >> 3;
                    img_pack_cnt <= 0;
                end else begin
                    img_pack_cnt <= img_pack_cnt + 1;
                end
            end
        end
    end
    
    // 图像加载直接写入Bank0（初始化阶段）
    wire [ADDR_W-4:0] img_write_word_addr = img_pack_addr;
    always @(posedge clk) begin
        if (img_pack_valid) begin
            bram_bank0[img_write_word_addr] <= img_pack_reg;
        end
    end
    
    // ============================================================
    // 主控状态机
    // ============================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            layer_start <= 0;
            current_read_bank <= 0;  // 初始读Bank0
        end else begin
            layer_start <= 0;
            
            case (state)
                S_IDLE: begin
                    current_read_bank <= 0;  // Conv1读Bank0
                    if (start) begin
                        state <= S_CONV1;
                        layer_start <= 1;
                    end
                end
                
                S_CONV1: begin
                    if (conv1_done) begin
                        current_read_bank <= 1;  // Pool1读Bank1
                        state <= S_POOL1;
                        layer_start <= 1;
                    end
                end
                
                S_POOL1: begin
                    if (pool1_done) begin
                        current_read_bank <= 0;  // Conv2读Bank0
                        state <= S_CONV2;
                        layer_start <= 1;
                    end
                end
                
                S_CONV2: begin
                    if (conv2_done) begin
                        current_read_bank <= 1;  // Conv3读Bank1
                        state <= S_CONV3;
                        layer_start <= 1;
                    end
                end
                
                S_CONV3: begin
                    if (conv3_done) begin
                        current_read_bank <= 0;  // Conv4读Bank0
                        state <= S_CONV4;
                        layer_start <= 1;
                    end
                end
                
                S_CONV4: begin
                    if (conv4_done) begin
                        current_read_bank <= 1;  // AvgPool读Bank1
                        state <= S_AVGPOOL;
                        layer_start <= 1;
                    end
                end
                
                S_AVGPOOL: begin
                    if (avgpool_done) begin
                        current_read_bank <= 0;  // FC读Bank0
                        state <= S_FC;
                        layer_start <= 1;
                    end
                end
                
                S_FC: begin
                    if (fc_done) begin
                        state <= S_DONE;
                    end
                end
                
                S_DONE: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    assign done = (state == S_DONE);

    // ============================================================
    // 各层DPU信号定义
    // ============================================================
    // Conv1 信号
    wire        conv1_act_read_en;
    wire [ADDR_W-1:0] conv1_act_read_addr;
    wire        conv1_out_we;
    wire [ADDR_W-1:0] conv1_out_addr;
    wire [TILE_W*DATA_W-1:0] conv1_out_data;
    wire [TILE_W-1:0] conv1_out_mask;
    
    // Pool1 信号（使用批量接口）
    wire        pool1_read_en;
    wire [ADDR_W-1:0] pool1_read_addr;
    wire        pool1_write_en;
    wire [ADDR_W-1:0] pool1_write_addr;
    wire [TILE_W*DATA_W-1:0] pool1_write_data;
    wire [TILE_W-1:0] pool1_write_mask;
    
    // Conv2 信号
    wire        conv2_act_read_en;
    wire [ADDR_W-1:0] conv2_act_read_addr;
    wire        conv2_out_we;
    wire [ADDR_W-1:0] conv2_out_addr;
    wire [TILE_W*DATA_W-1:0] conv2_out_data;
    wire [TILE_W-1:0] conv2_out_mask;
    
    // Conv3 信号
    wire        conv3_act_read_en;
    wire [ADDR_W-1:0] conv3_act_read_addr;
    wire        conv3_out_we;
    wire [ADDR_W-1:0] conv3_out_addr;
    wire [TILE_W*DATA_W-1:0] conv3_out_data;
    wire [TILE_W-1:0] conv3_out_mask;
    
    // Conv4 信号
    wire        conv4_act_read_en;
    wire [ADDR_W-1:0] conv4_act_read_addr;
    wire        conv4_out_we;
    wire [ADDR_W-1:0] conv4_out_addr;
    wire [TILE_W*DATA_W-1:0] conv4_out_data;
    wire [TILE_W-1:0] conv4_out_mask;
    
    // AvgPool 信号
    wire        avgpool_read_en;
    wire [ADDR_W-1:0] avgpool_read_addr;
    wire        avgpool_write_en;
    wire [ADDR_W-1:0] avgpool_write_addr;
    wire [TILE_W*DATA_W-1:0] avgpool_write_data;
    wire [TILE_W-1:0] avgpool_write_mask;
    
    // FC 信号
    wire        fc_byte_read_en;
    wire [ADDR_W-1:0] fc_byte_read_addr;
    
    // ============================================================
    // BRAM接口多路复用
    // ============================================================
    always @(*) begin
        // 默认值
        bram_read_en = 0;
        bram_read_addr_0 = 0;
        bram_read_addr_1 = 0;
        bram_read_addr_2 = 0;
        bram_write_en = 0;
        bram_write_addr = 0;
        bram_write_data = 0;
        bram_write_mask = 0;
        bram_byte_read_en = 0;
        bram_byte_read_addr = 0;
        bram_byte_write_en = 0;
        bram_byte_write_addr = 0;
        bram_byte_write_data = 0;
        
        case (state)
            S_CONV1: begin
                bram_read_en = conv1_act_read_en;
                bram_read_addr_0 = conv1_act_read_addr;
                bram_read_addr_1 = conv1_act_read_addr + 8;
                bram_read_addr_2 = conv1_act_read_addr + 16;
                bram_write_en = conv1_out_we;
                bram_write_addr = conv1_out_addr;
                bram_write_data = conv1_out_data;
                bram_write_mask = conv1_out_mask;
            end
            
            S_POOL1: begin
                // 使用批量读写接口（PE风格的Pool）
                bram_read_en = pool1_read_en;
                bram_read_addr_0 = pool1_read_addr;
                bram_read_addr_1 = pool1_read_addr + 8;
                bram_read_addr_2 = pool1_read_addr + 16;
                bram_write_en = pool1_write_en;
                bram_write_addr = pool1_write_addr;
                bram_write_data = pool1_write_data;
                bram_write_mask = pool1_write_mask;
            end
            
            S_CONV2: begin
                bram_read_en = conv2_act_read_en;
                bram_read_addr_0 = conv2_act_read_addr;
                bram_read_addr_1 = conv2_act_read_addr + 8;
                bram_read_addr_2 = conv2_act_read_addr + 16;
                bram_write_en = conv2_out_we;
                bram_write_addr = conv2_out_addr;
                bram_write_data = conv2_out_data;
                bram_write_mask = conv2_out_mask;
            end
            
            S_CONV3: begin
                bram_read_en = conv3_act_read_en;
                bram_read_addr_0 = conv3_act_read_addr;
                bram_read_addr_1 = conv3_act_read_addr + 8;
                bram_read_addr_2 = conv3_act_read_addr + 16;
                bram_write_en = conv3_out_we;
                bram_write_addr = conv3_out_addr;
                bram_write_data = conv3_out_data;
                bram_write_mask = conv3_out_mask;
            end
            
            S_CONV4: begin
                bram_read_en = conv4_act_read_en;
                bram_read_addr_0 = conv4_act_read_addr;
                bram_read_addr_1 = conv4_act_read_addr + 8;
                bram_read_addr_2 = conv4_act_read_addr + 16;
                bram_write_en = conv4_out_we;
                bram_write_addr = conv4_out_addr;
                bram_write_data = conv4_out_data;
                bram_write_mask = conv4_out_mask;
            end
            
            S_AVGPOOL: begin
                bram_read_en = avgpool_read_en;
                bram_read_addr_0 = avgpool_read_addr;
                bram_read_addr_1 = avgpool_read_addr + 8;
                bram_read_addr_2 = avgpool_read_addr + 16;
                bram_write_en = avgpool_write_en;
                bram_write_addr = avgpool_write_addr;
                bram_write_data = avgpool_write_data;
                bram_write_mask = avgpool_write_mask;
            end
            
            S_FC: begin
                bram_byte_read_en = fc_byte_read_en;
                bram_byte_read_addr = fc_byte_read_addr;
            end
        endcase
    end

    // ============================================================
    // Conv1 DPU Instance（使用外部BRAM）
    // ============================================================
    dpu_top #(
        .DATA_W(DATA_W),
        .H_IN(CONV1_H_IN), .W_IN(CONV1_W_IN),
        .C_IN(CONV1_C_IN), .C_OUT(CONV1_C_OUT),
        .K(CONV1_K), .PAD(CONV1_PAD), .STRIDE(CONV1_STRIDE),
        .SHIFT(CONV1_SHIFT), .RELU_EN(1)
    ) u_conv1 (
        .clk(clk), .resetn(resetn),
        .start(state == S_CONV1 && layer_start),
        // 外部BRAM读接口
        .ext_act_read_en(conv1_act_read_en),
        .ext_act_read_addr(conv1_act_read_addr),
        .ext_act_read_data_0(bram_read_data_0),
        .ext_act_read_data_1(bram_read_data_1),
        .ext_act_read_data_2(bram_read_data_2),
        // 外部BRAM写接口
        .ext_act_write_en(conv1_out_we),
        .ext_act_write_addr(conv1_out_addr),
        .ext_act_write_data(conv1_out_data),
        .ext_act_write_mask(conv1_out_mask),
        // 权重加载
        .ext_wgt_we(conv1_wgt_we),
        .ext_wgt_addr(conv1_wgt_addr),
        .ext_wgt_data(conv1_wgt_data),
        .done(conv1_done)
    );
    
    // ============================================================
    // Pool1 Instance（MaxPool 2x2 - PE风格并行实现）
    // ============================================================
    pool_unit_pe #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .C_IN(POOL1_C),
        .H_IN(POOL1_H_IN),
        .W_IN(POOL1_W_IN),
        .POOL_TYPE(0)  // 0=MaxPool
    ) u_pool1 (
        .clk(clk), .resetn(resetn),
        .start(state == S_POOL1 && layer_start),
        // 批量读接口
        .bram_read_en(pool1_read_en),
        .bram_read_addr(pool1_read_addr),
        .bram_read_data(bram_read_data_0),
        // 批量写接口
        .bram_write_en(pool1_write_en),
        .bram_write_addr(pool1_write_addr),
        .bram_write_data(pool1_write_data),
        .bram_write_mask(pool1_write_mask),
        .done(pool1_done)
    );
    
    // ============================================================
    // Conv2 DPU Instance
    // ============================================================
    dpu_top #(
        .DATA_W(DATA_W),
        .H_IN(CONV2_H_IN), .W_IN(CONV2_W_IN),
        .C_IN(CONV2_C_IN), .C_OUT(CONV2_C_OUT),
        .K(CONV2_K), .PAD(CONV2_PAD), .STRIDE(CONV2_STRIDE),
        .SHIFT(CONV2_SHIFT), .RELU_EN(1)
    ) u_conv2 (
        .clk(clk), .resetn(resetn),
        .start(state == S_CONV2 && layer_start),
        .ext_act_read_en(conv2_act_read_en),
        .ext_act_read_addr(conv2_act_read_addr),
        .ext_act_read_data_0(bram_read_data_0),
        .ext_act_read_data_1(bram_read_data_1),
        .ext_act_read_data_2(bram_read_data_2),
        .ext_act_write_en(conv2_out_we),
        .ext_act_write_addr(conv2_out_addr),
        .ext_act_write_data(conv2_out_data),
        .ext_act_write_mask(conv2_out_mask),
        .ext_wgt_we(conv2_wgt_we),
        .ext_wgt_addr(conv2_wgt_addr),
        .ext_wgt_data(conv2_wgt_data),
        .done(conv2_done)
    );
    
    // ============================================================
    // Conv3 DPU Instance
    // ============================================================
    dpu_top #(
        .DATA_W(DATA_W),
        .H_IN(CONV3_H_IN), .W_IN(CONV3_W_IN),
        .C_IN(CONV3_C_IN), .C_OUT(CONV3_C_OUT),
        .K(CONV3_K), .PAD(CONV3_PAD), .STRIDE(CONV3_STRIDE),
        .SHIFT(CONV3_SHIFT), .RELU_EN(1)
    ) u_conv3 (
        .clk(clk), .resetn(resetn),
        .start(state == S_CONV3 && layer_start),
        .ext_act_read_en(conv3_act_read_en),
        .ext_act_read_addr(conv3_act_read_addr),
        .ext_act_read_data_0(bram_read_data_0),
        .ext_act_read_data_1(bram_read_data_1),
        .ext_act_read_data_2(bram_read_data_2),
        .ext_act_write_en(conv3_out_we),
        .ext_act_write_addr(conv3_out_addr),
        .ext_act_write_data(conv3_out_data),
        .ext_act_write_mask(conv3_out_mask),
        .ext_wgt_we(conv3_wgt_we),
        .ext_wgt_addr(conv3_wgt_addr),
        .ext_wgt_data(conv3_wgt_data),
        .done(conv3_done)
    );
    
    // ============================================================
    // Conv4 DPU Instance
    // ============================================================
    dpu_top #(
        .DATA_W(DATA_W),
        .H_IN(CONV4_H_IN), .W_IN(CONV4_W_IN),
        .C_IN(CONV4_C_IN), .C_OUT(CONV4_C_OUT),
        .K(CONV4_K), .PAD(CONV4_PAD), .STRIDE(CONV4_STRIDE),
        .SHIFT(CONV4_SHIFT), .RELU_EN(1)
    ) u_conv4 (
        .clk(clk), .resetn(resetn),
        .start(state == S_CONV4 && layer_start),
        .ext_act_read_en(conv4_act_read_en),
        .ext_act_read_addr(conv4_act_read_addr),
        .ext_act_read_data_0(bram_read_data_0),
        .ext_act_read_data_1(bram_read_data_1),
        .ext_act_read_data_2(bram_read_data_2),
        .ext_act_write_en(conv4_out_we),
        .ext_act_write_addr(conv4_out_addr),
        .ext_act_write_data(conv4_out_data),
        .ext_act_write_mask(conv4_out_mask),
        .ext_wgt_we(conv4_wgt_we),
        .ext_wgt_addr(conv4_wgt_addr),
        .ext_wgt_data(conv4_wgt_data),
        .done(conv4_done)
    );
    
    // ============================================================
    // AvgPool Instance
    // ============================================================
    pool_unit_pe #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .C_IN(AVGPOOL_C),
        .H_IN(AVGPOOL_H),
        .W_IN(AVGPOOL_W),
        .POOL_TYPE(1)  // 1=AvgPool
    ) u_avgpool (
        .clk(clk), .resetn(resetn),
        .start(state == S_AVGPOOL && layer_start),
        .bram_read_en(avgpool_read_en),
        .bram_read_addr(avgpool_read_addr),
        .bram_read_data(bram_read_data_0),
        .bram_write_en(avgpool_write_en),
        .bram_write_addr(avgpool_write_addr),
        .bram_write_data(avgpool_write_data),
        .bram_write_mask(avgpool_write_mask),
        .done(avgpool_done)
    );
    
    // ============================================================
    // FC Layer Instance
    // ============================================================
    fc_layer_ext #(
        .DATA_W(DATA_W),
        .IN_SIZE(FC_IN),
        .OUT_SIZE(FC_OUT),
        .SHIFT(FC_SHIFT)
    ) u_fc (
        .clk(clk), .resetn(resetn),
        .start(state == S_FC && layer_start),
        // 从BRAM读取输入
        .bram_read_en(fc_byte_read_en),
        .bram_read_addr(fc_byte_read_addr),
        .bram_read_data(bram_byte_read_data),
        // 权重加载
        .wgt_we(fc_wgt_we),
        .wgt_addr(fc_wgt_addr),
        .wgt_data(fc_wgt_data),
        // 输出
        .pred_class(pred_class),
        .pred_score(pred_score),
        .done(fc_done)
    );

endmodule
