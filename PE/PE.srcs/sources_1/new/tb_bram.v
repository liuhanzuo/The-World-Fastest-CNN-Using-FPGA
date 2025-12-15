`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/15 11:09:16
// Design Name: 
// Module Name: tb_bram
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


module tb_bram();
    reg clk = 0, rst = 1;
    reg [15:0] addr = 16'b0;
    wire [63:0] dout;
    integer i;
    act_buffer_lat2 act_buf(
        .clk(clk),
        .rst(rst),
        .bank_sel(1'b0),
        .read_en(1'b1),
        .read_base_addr(addr),
        .act_vector(dout)
    );
    
    always #5 clk = ~clk;
    
    initial begin
        #10 rst = 0;
        for (i = 0; i < 8; i = i + 1) begin
            #10
            @(posedge clk);
            addr = addr + 1;
        end
    end
endmodule
