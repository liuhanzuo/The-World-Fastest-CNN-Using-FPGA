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
//   Weight buffer with +1 extra output register stage to align with act_buffer_lat2.
//   blk_mem_gen_wgt itself has configured read latency (e.g., 2 cycles). This module
//   adds one more pipeline cycle on top of that.
// 
//////////////////////////////////////////////////////////////////////////////////

module wgt_buf #(
    parameter DATA_W    = 8,
    parameter TILE_SIZE = 8,
    parameter BUS_W     = DATA_W * TILE_SIZE // 64 bits
)(
    input  wire             clk,
    input  wire [12:0]      addr,      // Address for 64-bit words
    input  wire             en,
    output reg  [BUS_W-1:0] wgt_vector // Registered output
);

    wire [BUS_W-1:0] wgt_vector_raw;

    blk_mem_gen_wgt weight_buffer (
        .clka  (clk),
        .addra (addr),
        .ena   (en),
        .douta (wgt_vector_raw)
    );

    // +1 pipeline stage to align with act_buffer_lat2's effective output latency
    always @(posedge clk) begin
        if (en) begin
            wgt_vector <= wgt_vector_raw;
        end
        // else: hold last value (recommended for clean timing)
    end

endmodule
