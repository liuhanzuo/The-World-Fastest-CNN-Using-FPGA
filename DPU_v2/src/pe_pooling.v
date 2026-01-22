`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pe_pooling
// Description: Pooling PE Array，支持 Average Pooling 和 Max Pooling
//              将 Pooling 视为特殊的卷积操作：
//              - Average Pooling: 权重为 1/k², 累加后除以 k²
//              - Max Pooling: 选择 kernel 范围内的最大值
//
// Architecture:
//   - 只有 TILE_W 列（池化不改变通道数，每个输出位置独立处理）
//   - 每列 PE 处理一个输出位置
//   - AGU 提供的地址生成逻辑与卷积相同（只是没有通道维度的循环）
//
// 与卷积 PE 的区别：
//   - 不需要权重输入（Average Pooling 权重固定为 1，最后统一除以 k²）
//   - Max Pooling 使用比较而非乘加
//   - 只有 TILE_W 个 PE（不是 TILE_C x TILE_W）
//////////////////////////////////////////////////////////////////////////////////

module pe_pooling #(
    parameter DATA_W   = 8,              // 输入数据位宽
    parameter PSUM_W   = 24,             // 部分和位宽（用于累加）
    parameter TILE_W   = 8,              // 输出宽度 tile 大小
    parameter POOL_K   = 2,              // Pooling kernel 大小（默认 2x2）
    parameter POOL_MODE = 0              // 0: Average Pooling, 1: Max Pooling
)(
    input  wire                              clk,
    input  wire                              resetn,  // 低电平复位
    
    // Control signals (from AGU)
    input  wire                              valid_in,     // 数据有效
    input  wire                              clear_psum,   // 清除累加器
    input  wire [TILE_W-1:0]                 mask,         // 有效数据 mask
    
    // Data inputs
    input  wire [TILE_W*DATA_W-1:0]          act_vec,      // 8 个输入激活值
    
    // Pooling outputs (只有 TILE_W 个输出)
    output wire [TILE_W*PSUM_W-1:0]          pool_out
);

    // ============================================================
    // 计算 k² 用于 Average Pooling 的除法
    // ============================================================
    localparam POOL_K_SQ = POOL_K * POOL_K;
    
    // 计算 log2(POOL_K_SQ) 用于移位除法（当 k² 是 2 的幂时）
    // 对于 2x2 pooling: k² = 4, shift = 2
    // 对于 3x3 pooling: k² = 9, 需要真除法
    // 对于 4x4 pooling: k² = 16, shift = 4
    function integer clog2;
        input integer value;
        integer i;
        begin
            clog2 = 0;
            for (i = value - 1; i > 0; i = i >> 1)
                clog2 = clog2 + 1;
        end
    endfunction
    
    localparam SHIFT_AMT = clog2(POOL_K_SQ);
    localparam IS_POWER_OF_2 = (POOL_K_SQ == (1 << SHIFT_AMT));
    
    // ============================================================
    // PE Array Generation
    // ============================================================
    genvar col;
    generate
        for (col = 0; col < TILE_W; col = col + 1) begin : gen_pool_pe
            
            // 提取当前列的输入值
            wire signed [DATA_W-1:0] act_val = $signed(act_vec[col*DATA_W +: DATA_W]);
            wire valid_data = valid_in & mask[col];
            
            if (POOL_MODE == 0) begin : avg_pool
                // ============================================================
                // Average Pooling: 累加所有值，输出时除以 k²
                // ============================================================
                reg signed [PSUM_W-1:0] sum_acc;
                
                always @(posedge clk) begin
                    if (!resetn) begin
                        sum_acc <= 0;
                    end else if (clear_psum) begin
                        sum_acc <= 0;
                    end else if (valid_data) begin
                        // 累加输入值（权重视为 1）
                        sum_acc <= sum_acc + {{(PSUM_W-DATA_W){act_val[DATA_W-1]}}, act_val};
                    end
                end
                
                // 输出：除以 k²
                // 如果 k² 是 2 的幂，使用移位；否则使用除法
                wire signed [PSUM_W-1:0] avg_result;
                if (IS_POWER_OF_2) begin : shift_div
                    assign avg_result = sum_acc >>> SHIFT_AMT;
                end else begin : real_div
                    assign avg_result = sum_acc / POOL_K_SQ;
                end
                
                assign pool_out[col*PSUM_W +: PSUM_W] = avg_result;
                
            end else begin : max_pool
                // ============================================================
                // Max Pooling: 选择 kernel 范围内的最大值
                // ============================================================
                reg signed [PSUM_W-1:0] max_val;
                reg first_valid;  // 标记是否为第一个有效数据
                
                // 扩展输入到 PSUM_W 位宽用于比较
                wire signed [PSUM_W-1:0] act_extended = {{(PSUM_W-DATA_W){act_val[DATA_W-1]}}, act_val};
                
                always @(posedge clk) begin
                    if (!resetn) begin
                        max_val <= {1'b1, {(PSUM_W-1){1'b0}}};  // 初始化为最小值
                        first_valid <= 1'b1;
                    end else if (clear_psum) begin
                        max_val <= {1'b1, {(PSUM_W-1){1'b0}}};  // 重置为最小值
                        first_valid <= 1'b1;
                    end else if (valid_data) begin
                        if (first_valid) begin
                            // 第一个有效数据直接赋值
                            max_val <= act_extended;
                            first_valid <= 1'b0;
                        end else if (act_extended > max_val) begin
                            // 比较并更新最大值
                            max_val <= act_extended;
                        end
                    end
                end
                
                assign pool_out[col*PSUM_W +: PSUM_W] = max_val;
            end
        end
    endgenerate

endmodule
