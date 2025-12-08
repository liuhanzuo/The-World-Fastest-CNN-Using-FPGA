module pe #(
    parameter DATA_W = 8,
    parameter WGT_W  = 8,
    parameter PSUM_W = 32
)(
    input  wire clk,
    input  wire rst,

    input  wire [DATA_W-1:0] act_in,
    input  wire [WGT_W-1:0]  wgt_in,
    input  wire              valid_in,
    input  wire              clear,

    output reg [PSUM_W-1:0]  psum_out
);

    wire signed [DATA_W-1:0] act_s = act_in;
    wire signed [WGT_W-1:0]  wgt_s = wgt_in;
    wire signed [DATA_W+WGT_W-1:0] mul = act_s * wgt_s;

    always @(posedge clk) begin
        if (rst)
            psum_out <= 0;
        else if (clear)
            psum_out <= 0;
        else if (valid_in)
            psum_out <= psum_out + mul;
    end
endmodule
