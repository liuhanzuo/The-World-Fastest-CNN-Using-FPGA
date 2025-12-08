module pe_array #(
    parameter N       = 8,
    parameter DATA_W  = 8,
    parameter WGT_W   = 8,
    parameter PSUM_W  = 32
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire [N*N*DATA_W-1:0]   act_tile_flat, // 8¡Á8 activations = 512 bits
    input  wire [WGT_W-1:0]        wgt_scalar,    // one kernel weight per cycle

    input  wire                    valid_in,
    input  wire                    clear_psum,

    output wire [N*N*PSUM_W-1:0]   psum_flat
);

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : ROW
            for (j = 0; j < N; j = j + 1) begin : COL

                localparam IDX = i*N + j;

                wire [DATA_W-1:0] act_ij =
                    act_tile_flat[IDX*DATA_W +: DATA_W];

                wire [PSUM_W-1:0] psum_o;

                pe #(
                    .DATA_W(DATA_W),
                    .WGT_W (WGT_W),
                    .PSUM_W(PSUM_W)
                ) u_pe (
                    .clk      (clk),
                    .rst      (rst),
                    .act_in   (act_ij),
                    .wgt_in   (wgt_scalar),
                    .valid_in (valid_in),
                    .clear    (clear_psum),
                    .psum_out (psum_o)
                );

                assign psum_flat[IDX*PSUM_W +: PSUM_W] = psum_o;
            end
        end
    endgenerate

endmodule
