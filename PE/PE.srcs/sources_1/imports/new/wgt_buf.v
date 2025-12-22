`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/08 18:08:41
// Design Name: 
// Module Name: wgt_buf
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module wgt_buf #(
    parameter DATA_W = 8,
    parameter TILE_SIZE = 8,
    parameter BUS_W = DATA_W * TILE_SIZE // 64 bits
)(
    input  wire             clk,
    input  wire [12:0]      addr,      // Address for 64-bit words
    input  wire             en,
    output wire [BUS_W-1:0] wgt_vector // Output 8 weights (64 bits) at once
);

    blk_mem_gen_wgt weight_buffer(
        .clka (clk),
        .addra(addr),
        .ena(en),
        .douta(wgt_vector) 
    );

endmodule
