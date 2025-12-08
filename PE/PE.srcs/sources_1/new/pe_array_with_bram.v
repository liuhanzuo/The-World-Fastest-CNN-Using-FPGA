module pe_array_with_bram #(
    parameter N        = 8,
    parameter DATA_W   = 8,
    parameter WGT_W    = 8,
    parameter PSUM_W   = 32,
    parameter ACT_W    = N*N*DATA_W  // = 512
)(
    input wire                     clk,
    input wire                     rst,

    input wire [ACT_W-1:0]         act_flat,     // 512 bits from BRAM
    input wire [WGT_W-1:0]         wgt_scalar,   // 1 weight per cycle

    input wire                     valid_in,
    input wire                     clear_psum,

    output wire [N*N*PSUM_W-1:0]   psum_out
);

    pe_array #(
        .N(N),
        .DATA_W(DATA_W),
        .WGT_W(WGT_W),
        .PSUM_W(PSUM_W)
    ) array (
        .clk(clk),
        .rst(rst),
        .act_tile_flat(act_flat),
        .wgt_scalar(wgt_scalar),
        .valid_in(valid_in),
        .clear_psum(clear_psum),
        .psum_flat(psum_out)
    );

endmodule
