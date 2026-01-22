`timescale 1ns / 1ps

// PE Array - 8x8 Output-Stationary Processing Element Array

module pe_array #(
    parameter DATA_W   = 8,
    parameter PSUM_W   = 24,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8
)(
    input  wire                              clk,
    input  wire                              rst_n,

    input  wire                              valid_in,
    input  wire                              clear_psum,

    input  wire [TILE_W*DATA_W-1:0]          act_vec,
    input  wire [TILE_C*DATA_W-1:0]          wgt_vec,

    output wire [TILE_C*TILE_W*PSUM_W-1:0]   psum_flat
);

    // Internal psum storage
    reg signed [PSUM_W-1:0] psum [0:TILE_C-1][0:TILE_W-1];
    
    // Generate PE array
    genvar row, col;
    generate
        for (row = 0; row < TILE_C; row = row + 1) begin : gen_row
            for (col = 0; col < TILE_W; col = col + 1) begin : gen_col
                
                wire signed [DATA_W-1:0] act_val = $signed(act_vec[col*DATA_W +: DATA_W]);
                wire signed [DATA_W-1:0] wgt_val = $signed(wgt_vec[row*DATA_W +: DATA_W]);
                
                wire signed [2*DATA_W-1:0] product = act_val * wgt_val;
                
                always @(posedge clk) begin
                    if (!rst_n) begin
                        psum[row][col] <= 0;
                    end else if (clear_psum) begin
                        psum[row][col] <= 0;
                    end else if (valid_in) begin
                        psum[row][col] <= psum[row][col] + product;
                    end
                end
                
                assign psum_flat[(row*TILE_W + col)*PSUM_W +: PSUM_W] = psum[row][col];
            end
        end
    endgenerate

endmodule
