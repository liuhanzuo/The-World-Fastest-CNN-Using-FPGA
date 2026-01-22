`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pe_array
// Description: 8x8 Output-Stationary Processing Element Array
//              Each PE performs MAC: psum += act * wgt
// 
// Architecture:
//   - 8 rows (one per output channel tile)
//   - 8 columns (one per output width tile)
//   - Broadcast activation across rows (same act_vec to all channels)
//   - Broadcast weight across columns (same wgt for each channel to all width positions)
//////////////////////////////////////////////////////////////////////////////////

module pe_array #(
    parameter DATA_W   = 8,              // Activation/Weight data width
    parameter PSUM_W   = 24,             // Partial sum width
    parameter TILE_C   = 8,              // Output channel tile size
    parameter TILE_W   = 8               // Output width tile size
)(
    input  wire                              clk,
    input  wire                              resetn,  // 低电平复位
    
    // Control signals (from AGU)
    input  wire                              valid_in,     // MAC enable
    input  wire                              clear_psum,   // Clear accumulators
    
    // Data inputs
    input  wire [TILE_W*DATA_W-1:0]          act_vec,      // 8 activations (broadcast to all rows)
    input  wire [TILE_C*DATA_W-1:0]          wgt_vec,      // 8 weights (one per output channel)
    
    // Partial sum outputs (flattened: [row][col])
    output wire [TILE_C*TILE_W*PSUM_W-1:0]   psum_flat
);

    // Internal psum storage: psum[row][col]
    reg signed [PSUM_W-1:0] psum [0:TILE_C-1][0:TILE_W-1];
    
    // Generate PE array
    genvar row, col;
    generate
        for (row = 0; row < TILE_C; row = row + 1) begin : gen_row
            for (col = 0; col < TILE_W; col = col + 1) begin : gen_col
                
                // Extract individual activation and weight
                wire signed [DATA_W-1:0] act_val = $signed(act_vec[col*DATA_W +: DATA_W]);
                wire signed [DATA_W-1:0] wgt_val = $signed(wgt_vec[row*DATA_W +: DATA_W]);
                
                // MAC operation
                wire signed [2*DATA_W-1:0] product = act_val * wgt_val;
                
                always @(posedge clk) begin
                    if (!resetn) begin
                        psum[row][col] <= 0;
                    end else if (clear_psum) begin
                        psum[row][col] <= 0;
                    end else if (valid_in) begin
                        psum[row][col] <= psum[row][col] + product;
                    end
                end
                
                // Connect to flat output
                assign psum_flat[(row*TILE_W + col)*PSUM_W +: PSUM_W] = psum[row][col];
            end
        end
    endgenerate

endmodule
