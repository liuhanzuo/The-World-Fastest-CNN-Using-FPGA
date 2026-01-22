`timescale 1ns / 1ps

// Drainer - PE Drainer with Quantization and Writeback

module drainer #(
    parameter DATA_W   = 8,
    parameter PSUM_W   = 24,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8,
    parameter SHIFT    = 9,             // Quantization shift amount
    parameter RELU_EN  = 0              // 1=enabled, 0=disabled
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              data_ready,

    input  wire [TILE_C*TILE_W*PSUM_W-1:0]   psum_flat,

    output reg                               drain_valid,
    output reg  [2:0]                        drain_row_idx,
    output wire [TILE_W*DATA_W-1:0]          drain_data
);

    // Psum Latch
    reg [PSUM_W-1:0] psum_latch [0:TILE_C-1][0:TILE_W-1];
    
    integer i, j;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < TILE_C; i = i + 1)
                for (j = 0; j < TILE_W; j = j + 1)
                    psum_latch[i][j] <= 0;
        end else if (data_ready) begin
            for (i = 0; i < TILE_C; i = i + 1)
                for (j = 0; j < TILE_W; j = j + 1)
                    psum_latch[i][j] <= psum_flat[(i*TILE_W + j)*PSUM_W +: PSUM_W];
        end
    end

    // Drain State Machine
    reg [3:0] drain_cnt;
    reg       latch_done;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            drain_cnt     <= 0;
            drain_valid   <= 0;
            drain_row_idx <= 0;
            latch_done    <= 0;
        end else begin
            latch_done <= data_ready;
            
            if (latch_done) begin
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

    // Quantization (Shift + ReLU + Saturate)
    genvar col;
    generate
        for (col = 0; col < TILE_W; col = col + 1) begin : gen_quant
            wire signed [PSUM_W-1:0] psum_val = $signed(psum_latch[drain_row_idx][col]);
            wire signed [PSUM_W-1:0] shifted  = psum_val >>> SHIFT;
            
            // Apply ReLU if enabled, then saturate to signed 8-bit range [-127, 127]
            reg [DATA_W-1:0] saturated;
            always @(*) begin
                if (RELU_EN && shifted < 0) begin
                    saturated = 8'd0;
                end else if (shifted > 127) begin
                    saturated = 8'd127;
                end else if (shifted < -127) begin
                    saturated = 8'h81;  // -127!
                end else begin
                    saturated = shifted[DATA_W-1:0];
                end
            end
            
            assign drain_data[col*DATA_W +: DATA_W] = saturated;
        end
    endgenerate

endmodule
