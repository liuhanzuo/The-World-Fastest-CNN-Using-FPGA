`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: agu_pooling
// Description: Address Generation Unit for Pooling Layer
//              将 Pooling 视为特殊的卷积操作进行地址生成
//
// 与卷积 AGU 的区别：
//   - 不需要权重地址生成（Average Pooling 权重固定为 1）
//   - 不需要输出通道循环（池化不改变通道数）
//   - Kernel 大小和 Stride 通常相同（无重叠）
//
// 地址生成策略：
//   - 与卷积 AGU 相同，AGU 计算输出点对应的输入基地址
//   - act_buffer 根据 stride 选择返回的数据
//////////////////////////////////////////////////////////////////////////////////

module agu_pooling #(
    parameter DATA_W   = 8,
    parameter TILE_W   = 8,
    parameter H_IN     = 32,              // 输入特征图高度
    parameter W_IN     = 32,              // 输入特征图宽度
    parameter C_IN     = 32,              // 输入通道数（= 输出通道数）
    parameter POOL_K   = 2,               // Pooling kernel 大小
    parameter POOL_S   = 2,               // Pooling stride（通常等于 POOL_K）
    parameter ADDR_W   = 16
)(
    input  wire                clk,
    input  wire                resetn,  // 低电平复位
    input  wire                start,
    
    // Activation Buffer Interface
    output reg                 act_read_en,
    output reg  [ADDR_W-1:0]   act_read_addr,
    output reg  signed [3:0]   act_read_shift,
    output reg  [TILE_W-1:0]   act_mask,
    
    // PE Pooling Interface
    output reg                 valid_in,
    output reg                 clear_psum,
    
    // Drainer Interface  
    output reg                 data_ready,
    
    // Output Writeback Interface
    output reg                 out_we,
    output reg  [ADDR_W-1:0]   out_addr,
    
    // Status
    output reg                 done
);

    // ============================================================
    // Derived Parameters
    // ============================================================
    localparam H_OUT = (H_IN - POOL_K) / POOL_S + 1;
    localparam W_OUT = (W_IN - POOL_K) / POOL_S + 1;
    
    localparam N_TILE_W = (W_OUT + TILE_W - 1) / TILE_W;
    
    localparam BRAM_LATENCY = 2;
    
    // ============================================================
    // State Machine
    // ============================================================
    localparam S_IDLE        = 4'd0;
    localparam S_INIT        = 4'd1;
    localparam S_COMPUTE     = 4'd2;
    localparam S_WAIT_PIPE   = 4'd3;
    localparam S_DATA_READY  = 4'd4;
    localparam S_DRAIN       = 4'd5;
    localparam S_CLEAR       = 4'd6;
    localparam S_NEXT_TILE   = 4'd7;
    localparam S_DONE        = 4'd8;
    
    reg [3:0] state;
    
    // ============================================================
    // Loop Counters
    // ============================================================
    reg [9:0] cnt_h0;        // 输出行索引 (0 to H_OUT-1)
    reg [9:0] cnt_ci;        // 输入通道（= 输出通道）
    reg [9:0] cnt_base_w;    // 输出宽度基地址（输出坐标系）
    reg [3:0] cnt_hk;        // Kernel 行 (0 to POOL_K-1)
    reg [3:0] cnt_wk;        // Kernel 列 (0 to POOL_K-1)
    
    reg [3:0] pipe_cnt;
    reg [3:0] drain_cnt;
    
    // ============================================================
    // Address Calculation
    // ============================================================
    // 输入行位置 = 输出行 * POOL_S + kernel 行偏移
    wire [10:0] h_act = cnt_h0 * POOL_S + cnt_hk;
    
    // 第一个输出点对应的输入列位置
    // 输入位置 = 输出位置 * POOL_S + kernel 列偏移
    wire signed [10:0] w_act_first = $signed({1'b0, cnt_base_w}) * POOL_S + $signed({1'b0, cnt_wk});
    
    // 检查边界（池化通常没有 padding，所以始终有效）
    wire h_valid = (h_act < H_IN);
    
    // 读取起始位置
    wire signed [10:0] w_read_start;
    generate
        if (POOL_S == 1) begin : read_start_stride1
            assign w_read_start = (w_act_first < 0) ? 0 : 
                                  (w_act_first >= W_IN) ? (W_IN - 1) : w_act_first;
        end else begin : read_start_stride_gt1
            // stride>1 时，保持奇偶性以实现正确的 stride 采样
            wire should_clamp_left = w_act_first < 0;
            wire should_clamp_right = w_act_first >= W_IN;
            wire preserve_odd = w_act_first[0];
            
            wire signed [10:0] w_clamped_left = preserve_odd ? 11'sd1 : 11'sd0;
            wire signed [10:0] w_clamped_right = preserve_odd ? ((W_IN - 2 >= 0) ? (W_IN - 2) : (W_IN - 1)) : (W_IN - 1);
            
            assign w_read_start = should_clamp_left ? w_clamped_left :
                                  should_clamp_right ? w_clamped_right :
                                  w_act_first;
        end
    endgenerate

    // Shift 计算
    wire signed [3:0] pad_shift;
    generate
        if (POOL_S == 1) begin : shift_stride1
            assign pad_shift = (w_act_first < 0) ? w_act_first[3:0] : 4'sd0;
        end else begin : shift_stride_gt1
            wire signed [10:0] w_diff = w_read_start - w_act_first;
            wire signed [10:0] w_offset = w_diff / POOL_S;
            assign pad_shift = (w_offset > 7) ? 4'sd7 :
                               (w_offset < -8) ? -4'sd8 :
                               w_offset[3:0];
        end
    endgenerate
    
    // Activation 字节地址
    wire [ADDR_W-1:0] act_byte_addr = (h_valid) ? 
        (cnt_ci * H_IN * W_IN + h_act * W_IN + w_read_start) : 0;
    
    // 生成有效数据 mask
    wire [TILE_W-1:0] gen_mask;
    genvar mi;
    generate
        for (mi = 0; mi < TILE_W; mi = mi + 1) begin : gen_mask_bits
            // 第 mi 个输出点对应的实际输入列位置
            wire signed [10:0] w_pos = w_act_first + mi * POOL_S;
            // 第 mi 个输出点的输出列坐标
            wire [9:0] w_out_pos = cnt_base_w + mi;
            // mask 条件：输入有效 且 输出在范围内
            assign gen_mask[mi] = h_valid && 
                                  (w_pos >= 0) && (w_pos < W_IN) &&
                                  (w_out_pos < W_OUT);
        end
    endgenerate
    
    // ============================================================
    // Main State Machine
    // ============================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            cnt_h0        <= 0;
            cnt_ci        <= 0;
            cnt_base_w    <= 0;
            cnt_hk        <= 0;
            cnt_wk        <= 0;
            pipe_cnt      <= 0;
            drain_cnt     <= 0;
            act_read_en   <= 0;
            act_read_addr <= 0;
            act_read_shift <= 0;
            act_mask      <= 0;
            valid_in      <= 0;
            clear_psum    <= 0;
            data_ready    <= 0;
            out_we        <= 0;
            out_addr      <= 0;
            done          <= 0;
        end else begin
            clear_psum <= 0;
            data_ready <= 0;
            out_we     <= 0;
            
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state      <= S_INIT;
                        cnt_h0     <= 0;
                        cnt_ci     <= 0;
                        cnt_base_w <= 0;
                        done       <= 0;
                    end
                end
                
                S_INIT: begin
                    cnt_hk  <= 0;
                    cnt_wk  <= 0;
                    clear_psum <= 1;
                    state <= S_COMPUTE;
                end
                
                S_COMPUTE: begin
                    act_read_en   <= 1;
                    act_read_addr <= act_byte_addr;
                    act_read_shift <= pad_shift;
                    act_mask      <= gen_mask;
                    
                    // Loop control: 遍历 kernel 的每个位置
                    if (cnt_wk < POOL_K - 1) begin
                        cnt_wk <= cnt_wk + 1;
                    end else begin
                        cnt_wk <= 0;
                        if (cnt_hk < POOL_K - 1) begin
                            cnt_hk <= cnt_hk + 1;
                        end else begin
                            // 完成一个 kernel，进入流水线等待
                            state <= S_WAIT_PIPE;
                            pipe_cnt <= BRAM_LATENCY + 1;
                        end
                    end
                end
                
                S_WAIT_PIPE: begin
                    act_read_en <= 0;
                    
                    if (pipe_cnt > 0) begin
                        pipe_cnt <= pipe_cnt - 1;
                    end else begin
                        valid_in <= 0;
                        state <= S_DATA_READY;
                    end
                end
                
                S_DATA_READY: begin
                    data_ready <= 1;
                    drain_cnt <= TILE_W + 1;  // 只需要 drain TILE_W 个结果
                    out_addr <= cnt_ci * (H_OUT * W_OUT) + cnt_h0 * W_OUT + cnt_base_w;
                    state <= S_DRAIN;
                end
                
                S_DRAIN: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= S_CLEAR;
                    end
                end
                
                S_CLEAR: begin
                    clear_psum <= 1;
                    state <= S_NEXT_TILE;
                end
                
                S_NEXT_TILE: begin
                    // 先遍历宽度 tile
                    if (cnt_base_w + TILE_W < W_OUT) begin
                        cnt_base_w <= cnt_base_w + TILE_W;
                        state <= S_INIT;
                    end else begin
                        cnt_base_w <= 0;
                        // 再遍历行
                        if (cnt_h0 < H_OUT - 1) begin
                            cnt_h0 <= cnt_h0 + 1;
                            state <= S_INIT;
                        end else begin
                            cnt_h0 <= 0;
                            // 最后遍历通道
                            if (cnt_ci < C_IN - 1) begin
                                cnt_ci <= cnt_ci + 1;
                                state <= S_INIT;
                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    // ============================================================
    // Valid_in Generation - 流水线延迟处理
    // ============================================================
    reg [1:0] valid_pipe;
    
    always @(posedge clk) begin
        if (!resetn) begin
            valid_pipe <= 0;
            valid_in <= 0;
        end else begin
            valid_pipe[0] <= (state == S_COMPUTE);
            valid_pipe[1] <= valid_pipe[0];
            valid_in <= valid_pipe[1];
        end
    end

endmodule
