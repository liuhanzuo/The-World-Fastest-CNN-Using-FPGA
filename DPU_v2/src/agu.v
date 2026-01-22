`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: agu (Address Generation Unit)
// Description: Central control unit for DPU scheduling and address generation
//              支持可配置的stride参数
//
// 地址生成策略（配合act_buffer）：
//   - AGU计算第一个输出点对应的输入位置作为基地址
//   - act_buffer从该基地址开始读取16个连续字节
//   - stride=1时，act_buffer返回前8个字节 [0,1,2,3,4,5,6,7]
//   - stride=2时，act_buffer返回 [0,2,4,6,8,10,12,14]
//
// 示例（stride=2, TILE_W=8）：
//   输出点 [0,1,2,3,4,5,6,7] 对应输入位置 [0,2,4,6,8,10,12,14]
//   AGU传入基地址 = 0
//   act_buffer读取位置[0..15]，返回[0,2,4,6,8,10,12,14]
//////////////////////////////////////////////////////////////////////////////////

module agu #(
    parameter DATA_W   = 8,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8,
    parameter H_IN     = 32,
    parameter W_IN     = 32,
    parameter C_IN     = 1,
    parameter C_OUT    = 32,
    parameter K        = 5,
    parameter PAD      = 2,
    parameter STRIDE   = 1,
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
    
    // Weight Buffer Interface
    output reg                 wgt_read_en,
    output reg  [ADDR_W-1:0]   wgt_read_addr,
    
    // PE Array Interface
    output reg                 valid_in,
    output reg                 clear_psum,
    
    // Drainer Interface
    output reg                 data_ready,
    
    // Output Writeback Interface
    output reg                 out_we,
    output reg  [ADDR_W-1:0]   out_addr,
    output reg  [2:0]          out_row_idx,
    
    // Bank Selection
    output reg                 bank_sel,
    
    // Status
    output reg                 done
);

    // ============================================================
    // Derived Parameters
    // ============================================================
    localparam H_OUT = (H_IN + 2*PAD - K) / STRIDE + 1;
    localparam W_OUT = (W_IN + 2*PAD - K) / STRIDE + 1;
    
    localparam N_TILE_C = (C_OUT + TILE_C - 1) / TILE_C;
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
    reg [9:0] cnt_h0;        // Output row index (0 to H_OUT-1)
    reg [9:0] cnt_base_c;    // Base output channel
    reg [9:0] cnt_base_w;    // Base output width (输出坐标系)
    reg [9:0] cnt_ci;        // Input channel
    reg [3:0] cnt_hk;        // Kernel row (0 to K-1)
    reg [3:0] cnt_wk;        // Kernel col (0 to K-1)
    
    reg [3:0] pipe_cnt;
    reg [3:0] drain_cnt;
    
    // ============================================================
    // Address Calculation
    // ============================================================
    // Kernel偏移（考虑padding）
    wire signed [10:0] hk_signed = $signed({1'b0, cnt_hk}) - PAD;
    wire signed [10:0] wk_signed = $signed({1'b0, cnt_wk}) - PAD;
    
    // 输入行位置 = 输出行 * STRIDE + kernel行偏移
    wire signed [10:0] h_act = $signed({1'b0, cnt_h0}) * STRIDE + hk_signed;
    
    // 第一个输出点对应的输入列位置
    // 输入位置 = 输出位置 * STRIDE + kernel列偏移
    wire signed [10:0] w_act_first = $signed({1'b0, cnt_base_w}) * STRIDE + wk_signed;
    
    // Check bounds for h
    wire h_valid = (h_act >= 0) && (h_act < H_IN); 
    
    // 读取起始位置计算
    // 对于stride=1：当w_act_first<0时，从0开始读，通过shift处理padding
    // 对于stride>1：需要保持w_act_first的奇偶性，以确保采样对齐
    wire signed [10:0] w_read_start;
    generate
        if (STRIDE == 1) begin : read_start_stride1
            // stride=1时，使用0作为起始位置（shift会处理padding）
            assign w_read_start = (w_act_first < 0) ? 0 : 
                                  (w_act_first >= W_IN) ? (W_IN - 1) : w_act_first;
        end else begin : read_start_stride_gt1
            // stride>1时，保持奇偶性以实现正确的stride采样
            // 奇数负数 → clamp到1（保持奇偶性）
            // 偶数负数 → clamp到0
            wire should_clamp_left = w_act_first < 0;
            wire should_clamp_right = w_act_first >= W_IN;
            wire preserve_odd = w_act_first[0];  // 奇偶性
            
            wire signed [10:0] w_clamped_left = preserve_odd ? 11'sd1 : 11'sd0;
            wire signed [10:0] w_clamped_right = preserve_odd ? ((W_IN - 2 >= 0) ? (W_IN - 2) : (W_IN - 1)) : (W_IN - 1);
            
            assign w_read_start = should_clamp_left ? w_clamped_left :
                                  should_clamp_right ? w_clamped_right :
                                  w_act_first;
        end
    endgenerate

    // ============================================================
    // Padding Shift / Sampling Offset Calculation
    // 对于stride=1: shift = w_act_first (负数表示左移数据)
    // 对于stride>1: shift = (w_read_start - w_act_first) / STRIDE
    //               这是采样数据和输出点之间的偏移量
    //               例如：w_act_first=-1, w_read_start=1, stride=2
    //                     offset = (1 - (-1)) / 2 = 1
    //                     表示采样数据的第一个元素对应输出点1
    // ============================================================
    wire signed [3:0] pad_shift;
    generate
        if (STRIDE == 1) begin : shift_stride1
            // stride=1: shift = w_act_first (负数表示左移数据)
            assign pad_shift = (w_act_first < 0) ? w_act_first[3:0] : 4'sd0;
        end else begin : shift_stride_gt1
            // stride>1: 计算采样偏移量
            // offset = (w_read_start - w_act_first) / STRIDE
            wire signed [10:0] w_diff = w_read_start - w_act_first;
            wire signed [10:0] w_offset = w_diff / STRIDE;
            // 限制偏移量在[-8, 7]范围内（4位有符号数）
            assign pad_shift = (w_offset > 7) ? 4'sd7 :
                               (w_offset < -8) ? -4'sd8 :
                               w_offset[3:0];
        end
    endgenerate    
    // Byte address for activation - 传入第一个输出点对应的输入位置
    // act_buffer会从此位置读取连续16字节，然后根据stride选择
    wire [ADDR_W-1:0] act_byte_addr = (h_valid) ? 
        (cnt_ci * H_IN * W_IN + h_act * W_IN + w_read_start) : 0;
    
    // Generate padding mask
    // mask需要同时满足：
    // 1. 输入位置在有效范围内 (h_valid && w_pos >= 0 && w_pos < W_IN)
    // 2. 输出位置在有效范围内 (cnt_base_w + mi < W_OUT)
    wire [TILE_W-1:0] gen_mask;
    genvar mi;
    generate
        for (mi = 0; mi < TILE_W; mi = mi + 1) begin : gen_mask_bits
            // 第mi个输出点对应的实际输入列位置
            wire signed [10:0] w_pos = w_act_first + mi * STRIDE;
            // 第mi个输出点的输出列坐标
            wire [9:0] w_out_pos = cnt_base_w + mi;
            // mask条件：输入有效 且 输出在范围内
            assign gen_mask[mi] = h_valid && 
                                  (w_pos >= 0) && (w_pos < W_IN) &&
                                  (w_out_pos < W_OUT);
        end
    endgenerate
    
    // Weight address - 权重地址计算保持不变
    wire [ADDR_W-1:0] wgt_word_addr = 
        (cnt_base_c / TILE_C) * (C_IN * K * K) + 
        cnt_ci * (K * K) + 
        cnt_hk * K + 
        cnt_wk;
    
    reg [ADDR_W-1:0] out_base_addr;
    
    // ============================================================
    // Main State Machine
    // ============================================================
    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            cnt_h0        <= 0;
            cnt_base_c    <= 0;
            cnt_base_w    <= 0;
            cnt_ci        <= 0;
            cnt_hk        <= 0;
            cnt_wk        <= 0;
            pipe_cnt      <= 0;
            drain_cnt     <= 0;
            act_read_en   <= 0;
            act_read_addr <= 0;
            act_read_shift <= 0;
            act_mask      <= 0;
            wgt_read_en   <= 0;
            wgt_read_addr <= 0;
            valid_in      <= 0;
            clear_psum    <= 0;
            data_ready    <= 0;
            out_we        <= 0;
            out_addr      <= 0;
            out_row_idx   <= 0;
            out_base_addr <= 0;
            bank_sel      <= 0;
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
                        cnt_base_c <= 0;
                        cnt_base_w <= 0;
                        done       <= 0;
                    end
                end
                
                S_INIT: begin
                    cnt_ci  <= 0;
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
                    
                    wgt_read_en   <= 1;
                    wgt_read_addr <= wgt_word_addr;
                    
                    // Loop control
                    if (cnt_wk < K - 1) begin
                        cnt_wk <= cnt_wk + 1;
                    end else begin
                        cnt_wk <= 0;
                        if (cnt_hk < K - 1) begin
                            cnt_hk <= cnt_hk + 1;
                        end else begin
                            cnt_hk <= 0;
                            if (cnt_ci < C_IN - 1) begin
                                cnt_ci <= cnt_ci + 1;
                            end else begin
                                state <= S_WAIT_PIPE;
                                pipe_cnt <= BRAM_LATENCY + 1;
                            end
                        end
                    end
                end
                
                S_WAIT_PIPE: begin
                    act_read_en <= 0;
                    wgt_read_en <= 0;
                    
                    if (pipe_cnt > 0) begin
                        pipe_cnt <= pipe_cnt - 1;
                    end else begin
                        valid_in <= 0;
                        state <= S_DATA_READY;
                    end
                end
                
                S_DATA_READY: begin
                    data_ready <= 1;
                    drain_cnt <= TILE_C + 1;
                    out_base_addr <= cnt_base_c * (H_OUT * W_OUT) + cnt_h0 * W_OUT + cnt_base_w;
                    out_addr <= cnt_base_c * (H_OUT * W_OUT) + cnt_h0 * W_OUT + cnt_base_w;
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
                    if (cnt_base_w + TILE_W < W_OUT) begin
                        cnt_base_w <= cnt_base_w + TILE_W;
                        state <= S_INIT;
                    end else begin
                        cnt_base_w <= 0;
                        if (cnt_base_c + TILE_C < C_OUT) begin
                            cnt_base_c <= cnt_base_c + TILE_C;
                            state <= S_INIT;
                        end else begin
                            cnt_base_c <= 0;
                            if (cnt_h0 < H_OUT - 1) begin
                                cnt_h0 <= cnt_h0 + 1;
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
