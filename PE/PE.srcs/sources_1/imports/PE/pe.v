// ================================================================
// pe.v
// Single PE: responsible for accumulating one output position (Co, w0)
// Each clock cycle:
//   If clear=1    -> psum is cleared
//   else if valid=1 -> psum += act_in * wgt_in
// ================================================================
module pe #(
    parameter DATA_W = 8,
    parameter WGT_W  = 8,
    parameter PSUM_W = 32
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [DATA_W-1:0]      act_in,     
    input  wire [WGT_W-1:0]       wgt_in,     
    input  wire                   valid_in,   // valid signal
    input  wire                   clear,      // clear psum or not

    output reg  [PSUM_W-1:0]      psum_out    
);

    // 有符号乘法
    wire signed [DATA_W-1:0]      act_s = act_in;
    wire signed [WGT_W-1:0]       wgt_s = wgt_in;
    wire signed [DATA_W+WGT_W-1:0] mul  = act_s * wgt_s;

    wire signed [PSUM_W-1:0] mul_ext =
        {{(PSUM_W-(DATA_W+WGT_W)){mul[DATA_W+WGT_W-1]}}, mul};

    always @(posedge clk) begin
        if (rst) begin
            psum_out <= {PSUM_W{1'b0}};
        end else if (clear) begin
            psum_out <= {PSUM_W{1'b0}};
        end else if (valid_in) begin
            psum_out <= psum_out + mul_ext;
        end
        // valid_in=0 and clear=0 -> hold value
    end

endmodule
