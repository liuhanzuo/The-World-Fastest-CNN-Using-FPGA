// ================================================================
// pe_array_with_bram.v
// Top-level array wrapper:
//  - Assume act_vec / wgt_vec have been fetched by external buffer/BRAM according to current
//    (Ci, hk, wk, base_c, base_w):
//
//    act_vec[w] = I[Ci, h0+hk, base_w + w]        (w=0..TILE_W-1)
//    wgt_vec[c] = K[Ci, hk, wk, base_c + c]      (c=0..TILE_C-1)
//
//  - Pass act_vec / wgt_vec to pe_array module
// ================================================================
module pe_array_with_bram #(
    parameter TILE_C = 8,
    parameter TILE_W = 8,
    parameter DATA_W = 8,
    parameter WGT_W  = 8,
    parameter PSUM_W = 32
)(
    input  wire                             clk,
    input  wire                             rst,

    // 来自 Activation Buffer / BRAM 的 8 个 activation
    input  wire [TILE_W*DATA_W-1:0]        act_vec,

    // 来自 Weight Buffer / BRAM 的 8 个 weight
    input  wire [TILE_C*WGT_W-1:0]         wgt_vec,

    input  wire                             valid_in,
    input  wire                             clear_psum,

    output wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat
);

    // Register inputs to align timing with BRAM outputs
    reg  [TILE_W*DATA_W-1:0] act_vec_r;
    reg  [TILE_C*WGT_W-1:0]  wgt_vec_r;
    reg                      valid_in_r;
    reg                      clear_psum_r;

    always @(posedge clk) begin
        if (rst) begin
            act_vec_r    <= 0;
            wgt_vec_r    <= 0;
            valid_in_r   <= 0;
            clear_psum_r <= 0;
        end else begin
            act_vec_r    <= act_vec;
            wgt_vec_r    <= wgt_vec;
            valid_in_r   <= valid_in;
            clear_psum_r <= clear_psum;
        end
    end
    pe_array #(
        .TILE_C (TILE_C),
        .TILE_W (TILE_W),
        .DATA_W (DATA_W),
        .WGT_W  (WGT_W),
        .PSUM_W (PSUM_W)
    ) u_array (
        .clk       (clk),
        .rst       (rst),
        .act_vec   (act_vec),
        .wgt_vec   (wgt_vec),
        .valid_in  (valid_in),
        .clear_psum(clear_psum),
        .psum_flat (psum_flat)
    );

endmodule
