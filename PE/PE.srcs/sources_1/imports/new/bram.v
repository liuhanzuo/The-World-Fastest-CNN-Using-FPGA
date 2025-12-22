`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 11:09:16
// Design Name: 
// Module Name: bram
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


module bram(
    input wire clk,
    input wire [15:0] addr,
    output wire [63:0] dout
    );
    blk_mem_gen_act bram1(
        .clka(clk),
        .ena(1'b1),
        .wea(1'b0),
        .addra(addr),
        .douta(dout)
    );
endmodule
