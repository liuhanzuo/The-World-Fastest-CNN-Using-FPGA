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

    (* use_dsp = "yes" *)
    always @(posedge clk) begin
        if (rst || clear) begin
            psum_out <= {PSUM_W{1'b0}};
        end else if (valid_in) begin
            psum_out <= psum_out + $signed(act_in) * $signed(wgt_in);
        end
    end

endmodule
