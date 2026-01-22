`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: drainer
// Description: PE Drainer with Quantization and Writeback
//
// Function:
//   1. Latch partial sums when data_ready asserts
//   2. Quantize 24-bit psum to 8-bit output (right shift + saturate)
//   3. Output 8 values per cycle (one row at a time)
//   4. Generate writeback address for activation buffer
//
// Timing:
//   - data_ready: latches all 8x8 psums
//   - drain_valid: asserts for TILE_C cycles after data_ready
//   - drain_row_idx: 0 to TILE_C-1, indicates which row is being output
//////////////////////////////////////////////////////////////////////////////////

module drainer #(
    parameter DATA_W   = 8,
    parameter PSUM_W   = 24,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8,
    parameter SHIFT    = 8,             // Quantization shift amount
    parameter RELU_EN  = 1              // Enable ReLU activation (1=enabled, 0=disabled)
)(
    input  wire                              clk,
    input  wire                              resetn,  // 低电平复位
    
    // Control signals (from AGU)
    input  wire                              data_ready,     // Latch psums
    
    // Partial sums from PE array
    input  wire [TILE_C*TILE_W*PSUM_W-1:0]   psum_flat,
    
    // Drain outputs
    output reg                               drain_valid,
    output reg  [2:0]                        drain_row_idx,
    output wire [TILE_W*DATA_W-1:0]          drain_data
);

    // ============================================================
    // Psum Latch
    // ============================================================
    reg [PSUM_W-1:0] psum_latch [0:TILE_C-1][0:TILE_W-1];
    
    integer i, j;
    always @(posedge clk) begin
        if (!resetn) begin
            for (i = 0; i < TILE_C; i = i + 1)
                for (j = 0; j < TILE_W; j = j + 1)
                    psum_latch[i][j] <= 0;
        end else if (data_ready) begin
            for (i = 0; i < TILE_C; i = i + 1)
                for (j = 0; j < TILE_W; j = j + 1)
                    psum_latch[i][j] <= psum_flat[(i*TILE_W + j)*PSUM_W +: PSUM_W];
        end
    end

    // ============================================================
    // Drain State Machine
    // ============================================================
    reg [3:0] drain_cnt;
    reg       latch_done;  // One cycle delay after latching
    
    always @(posedge clk) begin
        if (!resetn) begin
            drain_cnt     <= 0;
            drain_valid   <= 0;
            drain_row_idx <= 0;
            latch_done    <= 0;
        end else begin
            latch_done <= data_ready;  // One cycle delay
            
            if (latch_done) begin
                // Start drain one cycle after latching
                drain_cnt     <= TILE_C - 1;
                drain_valid   <= 1;
                drain_row_idx <= 0;
            end else if (drain_valid) begin
                if (drain_cnt > 0) begin
                    drain_cnt     <= drain_cnt - 1;
                    drain_row_idx <= drain_row_idx + 1;
                end else begin
                    drain_valid <= 0;
                end
            end
        end
    end

    // ============================================================
    // Quantization (Shift + ReLU + Saturate)
    // ============================================================
    genvar col;
    generate
        for (col = 0; col < TILE_W; col = col + 1) begin : gen_quant
            wire signed [PSUM_W-1:0] psum_val = $signed(psum_latch[drain_row_idx][col]);
            wire signed [PSUM_W-1:0] shifted  = psum_val >>> SHIFT;
            
            // Apply ReLU if enabled, then saturate to signed 8-bit range [-128, 127]
            reg [DATA_W-1:0] saturated;
            always @(*) begin
                if (RELU_EN && shifted < 0) begin
                    // ReLU: clamp negative values to 0
                    saturated = 8'd0;
                end else if (shifted > 127) begin
                    saturated = 8'd127;
                end else if (shifted < -128) begin
                    saturated = 8'h80;  // -128
                end else begin
                    saturated = shifted[DATA_W-1:0];
                end
            end
            
            assign drain_data[col*DATA_W +: DATA_W] = saturated;
        end
    endgenerate

endmodule
