`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: act_buffer_if
// Description: Activation Buffer Interface - 连接到外部全局BRAM的数据处理模块
//
// 功能：
//   - 接收外部BRAM读取的3个word数据（已经有1拍延迟）
//   - 执行字节对齐和stride采样
//   - 应用shift和mask
//
// 延迟说明：
//   - 外部BRAM（cnn_top）读取有 1 拍延迟
//   - 本模块再添加 1 拍延迟来处理数据
//   - 总延迟 = 2 拍，与 AGU 时序匹配
//////////////////////////////////////////////////////////////////////////////////

module act_buffer_if #(
    parameter DATA_W       = 8,
    parameter TILE_W       = 8,
    parameter STRIDE       = 1,
    parameter WORD_W       = DATA_W * TILE_W,     // 64 bits output
    parameter ADDR_W       = 16
)(
    input  wire                clk,
    input  wire                resetn,

    // AGU控制信号
    input  wire                read_en,
    input  wire [ADDR_W-1:0]   read_base_addr,
    input  wire signed [3:0]   read_shift,
    input  wire [TILE_W-1:0]   act_mask,
    
    // 输出激活向量
    output reg  [WORD_W-1:0]   act_vector,
    
    // 外部BRAM数据输入（3个连续word，已有1拍延迟）
    input  wire [WORD_W-1:0]   bram_read_data_0,
    input  wire [WORD_W-1:0]   bram_read_data_1,
    input  wire [WORD_W-1:0]   bram_read_data_2
);

    // ============================================================
    // 地址计算
    // ============================================================
    wire [2:0] byte_offset = read_base_addr[2:0];

    // ============================================================
    // Pipeline Registers - 延迟控制信号 2 拍以对齐数据
    // Stage 1: 与外部 BRAM 读取同步
    // Stage 2: 与接收到的 BRAM 数据同步
    // ============================================================
    reg [2:0]        offset_d1, offset_d2;
    reg signed [3:0] shift_d1, shift_d2;
    reg [TILE_W-1:0] mask_d1, mask_d2;

    always @(posedge clk) begin
        if (!resetn) begin
            offset_d1   <= 0;
            offset_d2   <= 0;
            shift_d1    <= 0;
            shift_d2    <= 0;
            mask_d1     <= 0;
            mask_d2     <= 0;
        end else begin
            // Stage 1
            offset_d1   <= byte_offset;
            shift_d1    <= read_shift;
            mask_d1     <= act_mask;
            // Stage 2
            offset_d2   <= offset_d1;
            shift_d2    <= shift_d1;
            mask_d2     <= mask_d1;
        end
    end

    // ============================================================
    // 数据延迟寄存器 - 只需 1 拍来与控制信号对齐
    // 外部 BRAM 已经有 1 拍延迟，这里再加 1 拍 = 总共 2 拍
    // ============================================================
    reg [WORD_W-1:0] word_0_d1, word_1_d1, word_2_d1;
    
    always @(posedge clk) begin
        // 只需 1 拍延迟，因为外部 BRAM 已经有 1 拍延迟
        word_0_d1 <= bram_read_data_0;
        word_1_d1 <= bram_read_data_1;
        word_2_d1 <= bram_read_data_2;
    end
    
    // 组合24字节 (192位) 的数据
    wire [191:0] combined_data = {word_2_d1, word_1_d1, word_0_d1};

    // ============================================================
    // 字节对齐 - 根据byte_offset选择起始位置，提取16字节
    // ============================================================
    reg [127:0] aligned_16bytes;
    always @(*) begin
        case (offset_d2)
            3'd0: aligned_16bytes = combined_data[127:0];
            3'd1: aligned_16bytes = combined_data[135:8];
            3'd2: aligned_16bytes = combined_data[143:16];
            3'd3: aligned_16bytes = combined_data[151:24];
            3'd4: aligned_16bytes = combined_data[159:32];
            3'd5: aligned_16bytes = combined_data[167:40];
            3'd6: aligned_16bytes = combined_data[175:48];
            3'd7: aligned_16bytes = combined_data[183:56];
            default: aligned_16bytes = combined_data[127:0];
        endcase
    end
    
    // ============================================================
    // 将16字节拆分为字节数组，方便stride选择
    // ============================================================
    wire [7:0] byte_arr [0:15];
    genvar bi;
    generate
        for (bi = 0; bi < 16; bi = bi + 1) begin : gen_bytes
            assign byte_arr[bi] = aligned_16bytes[bi*8 +: 8];
        end
    endgenerate
    
    // ============================================================
    // Stride Selection
    // ============================================================
    reg [WORD_W-1:0] strided_data;
    always @(*) begin
        if (STRIDE == 1) begin
            strided_data = aligned_16bytes[63:0];
        end else begin
            strided_data = {
                byte_arr[14], byte_arr[12], byte_arr[10], byte_arr[8],
                byte_arr[6], byte_arr[4], byte_arr[2], byte_arr[0]
            };
        end
    end
    
    // ============================================================
    // Apply Shift for Padding
    // ============================================================
    reg [WORD_W-1:0] act_shifted;
    always @(*) begin
        case (shift_d2)
            -4'sd7: act_shifted = {strided_data[7:0], 56'd0};
            -4'sd6: act_shifted = {strided_data[15:0], 48'd0};
            -4'sd5: act_shifted = {strided_data[23:0], 40'd0};
            -4'sd4: act_shifted = {strided_data[31:0], 32'd0};
            -4'sd3: act_shifted = {strided_data[39:0], 24'd0};
            -4'sd2: act_shifted = {strided_data[47:0], 16'd0};
            -4'sd1: act_shifted = {strided_data[55:0], 8'd0};
            4'sd0:  act_shifted = strided_data;
            4'sd1:  act_shifted = {8'd0, strided_data[63:8]};
            4'sd2:  act_shifted = {16'd0, strided_data[63:16]};
            4'sd3:  act_shifted = {24'd0, strided_data[63:24]};
            4'sd4:  act_shifted = {32'd0, strided_data[63:32]};
            4'sd5:  act_shifted = {40'd0, strided_data[63:40]};
            4'sd6:  act_shifted = {48'd0, strided_data[63:48]};
            4'sd7:  act_shifted = {56'd0, strided_data[63:56]};
            default: act_shifted = strided_data;
        endcase
    end

    // ============================================================
    // Apply Mask and Output
    // ============================================================
    integer i;
    always @(*) begin
        if (STRIDE == 1) begin
            for (i = 0; i < TILE_W; i = i + 1) begin
                if (mask_d2[i])
                    act_vector[i*DATA_W +: DATA_W] = act_shifted[i*DATA_W +: DATA_W];
                else
                    act_vector[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
            end
        end else begin
            if (shift_d2 > 0) begin
                for (i = 0; i < TILE_W; i = i + 1) begin
                    if (i < shift_d2) begin
                        act_vector[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
                    end else begin
                        if (mask_d2[i])
                            act_vector[i*DATA_W +: DATA_W] = strided_data[(i - shift_d2) * DATA_W +: DATA_W];
                        else
                            act_vector[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
                    end
                end
            end else begin
                for (i = 0; i < TILE_W; i = i + 1) begin
                    if (mask_d2[i])
                        act_vector[i*DATA_W +: DATA_W] = strided_data[i*DATA_W +: DATA_W];
                    else
                        act_vector[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
                end
            end
        end
    end

endmodule