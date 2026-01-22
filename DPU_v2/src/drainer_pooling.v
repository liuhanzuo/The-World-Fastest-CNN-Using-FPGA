`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: drainer_pooling
// Description: Drainer for Pooling Layer
//              将 PE Pooling 的输出转换为适合写入 buffer 的格式
//
// 与卷积 Drainer 的区别：
//   - 只有 TILE_W 个输出（不是 TILE_C x TILE_W）
//   - 不需要逐行 drain（直接输出所有结果）
//////////////////////////////////////////////////////////////////////////////////

module drainer_pooling #(
    parameter DATA_W   = 8,              // 输入数据位宽
    parameter PSUM_W   = 24,             // 部分和位宽
    parameter OUT_W    = 8,              // 输出数据位宽
    parameter TILE_W   = 8,              // 输出宽度 tile 大小
    parameter SHIFT    = 0,              // 输出移位量（用于量化）
    parameter RELU_EN  = 0               // ReLU 使能
)(
    input  wire                              clk,
    input  wire                              resetn,  // 低电平复位
    
    // Control
    input  wire                              data_ready,   // 数据准备好信号
    
    // Data Input from PE Pooling
    input  wire [TILE_W*PSUM_W-1:0]          pool_in,
    
    // Output
    output reg                               drain_valid,
    output wire [TILE_W*OUT_W-1:0]           drain_data
);

    // ============================================================
    // 状态机
    // ============================================================
    localparam S_IDLE   = 2'd0;
    localparam S_DRAIN  = 2'd1;
    localparam S_DONE   = 2'd2;
    
    reg [1:0] state;
    reg [TILE_W*PSUM_W-1:0] pool_reg;
    
    always @(posedge clk) begin
        if (!resetn) begin
            state       <= S_IDLE;
            drain_valid <= 0;
            pool_reg    <= 0;
        end else begin
            drain_valid <= 0;
            
            case (state)
                S_IDLE: begin
                    if (data_ready) begin
                        pool_reg <= pool_in;
                        state <= S_DRAIN;
                    end
                end
                
                S_DRAIN: begin
                    drain_valid <= 1;
                    state <= S_DONE;
                end
                
                S_DONE: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    // ============================================================
    // 输出量化和 ReLU
    // ============================================================
    genvar i;
    generate
        for (i = 0; i < TILE_W; i = i + 1) begin : gen_output
            wire signed [PSUM_W-1:0] psum_val = $signed(pool_reg[i*PSUM_W +: PSUM_W]);
            
            // 移位量化
            wire signed [PSUM_W-1:0] shifted_val = psum_val >>> SHIFT;
            
            // 饱和到输出位宽
            wire signed [OUT_W-1:0] saturated_val;
            localparam signed [PSUM_W-1:0] MAX_VAL = (1 << (OUT_W-1)) - 1;
            localparam signed [PSUM_W-1:0] MIN_VAL = -(1 << (OUT_W-1));
            
            assign saturated_val = (shifted_val > MAX_VAL) ? MAX_VAL[OUT_W-1:0] :
                                   (shifted_val < MIN_VAL) ? MIN_VAL[OUT_W-1:0] :
                                   shifted_val[OUT_W-1:0];
            
            // ReLU
            wire signed [OUT_W-1:0] relu_val;
            if (RELU_EN) begin : with_relu
                assign relu_val = (saturated_val < 0) ? {OUT_W{1'b0}} : saturated_val;
            end else begin : no_relu
                assign relu_val = saturated_val;
            end
            
            assign drain_data[i*OUT_W +: OUT_W] = relu_val;
        end
    endgenerate

endmodule
