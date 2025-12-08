// ================================================================
// pe_array.v
// 8×8 PE array:
//  - Row Direction：TILE_C(Output Channels parallel)
//  - Column Direction：TILE_W(Output Width parallel)
//
// Each clock cycle:
//   Input act_vec[0..TILE_W-1]   -> 8 activations
//   Input wgt_vec[0..TILE_C-1]   -> 8 weights
//   Corresponding PE(Co_idx, w_idx) does: psum[Co_idx,w_idx] += act_vec[w_idx]*wgt_vec[Co_idx]
// ================================================================
module pe_array #(
    parameter TILE_C = 8,      
    parameter TILE_W = 8,      
    parameter DATA_W = 8,
    parameter WGT_W  = 8,
    parameter PSUM_W = 32
)(
    input  wire                             clk,
    input  wire                             rst,

    // 8 activations for output width direction: act_vec[w0]
    input  wire [TILE_W*DATA_W-1:0]        act_vec,

    // 8 weights for output channel direction: wgt_vec[Co]
    input  wire [TILE_C*WGT_W-1:0]         wgt_vec,

    input  wire                             valid_in,
    input  wire                             clear_psum,

    // 8x8 partial sums flattened: psum_flat[Co0,w0]
    output wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat
);

    genvar c, w;
    generate
        for (c = 0; c < TILE_C; c = c + 1) begin : ROW
            for (w = 0; w < TILE_W; w = w + 1) begin : COL

                wire [DATA_W-1:0] act_ij =
                    act_vec[w*DATA_W +: DATA_W];

                wire [WGT_W-1:0]  wgt_ij =
                    wgt_vec[c*WGT_W +: WGT_W];

                wire [PSUM_W-1:0] psum_ij;

                pe #(
                    .DATA_W(DATA_W),
                    .WGT_W (WGT_W),
                    .PSUM_W(PSUM_W)
                ) u_pe (
                    .clk      (clk),
                    .rst      (rst),
                    .act_in   (act_ij),
                    .wgt_in   (wgt_ij),
                    .valid_in (valid_in),
                    .clear    (clear_psum),
                    .psum_out (psum_ij)
                );

                localparam integer IDX = c*TILE_W + w;
                assign psum_flat[IDX*PSUM_W +: PSUM_W] = psum_ij;
            end
        end
    endgenerate

endmodule
