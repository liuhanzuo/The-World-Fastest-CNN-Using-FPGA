`timescale 1ns / 1ps
// ================================================================
// pe_drainer.v
// Drains the psum results from PE array, buffers them, and outputs
// rows of activations to the activation buffer.
// ================================================================
module pe_drainer #(
    parameter TILE_C = 8,
    parameter TILE_W = 8,
    parameter PSUM_W = 32,
    parameter ACT_W  = 8
)(
    input  wire                             clk,
    input  wire                             rst,

    // From AGU
    input  wire                             data_ready,  // Pulse to latch psums from PE array
    input  wire [3:0]                       out_row_idx, // Selects which row (channel) to output

    // Quantization parameters
    input  wire [3:0]                       q_act,
    input  wire [3:0]                       q_wgt,
    input  wire [3:0]                       q_out,

    // From PE Array
    input  wire [TILE_C*TILE_W*PSUM_W-1:0]  psum_flat,

    // To ACT Buffer
    output wire [TILE_W*ACT_W-1:0]          drain_out_data
);

    // Internal storage for psums
    // Stores the entire TILE_C x TILE_W block of partial sums
    reg [TILE_C*TILE_W*PSUM_W-1:0] psum_store;

    // Latch psums when data_ready is high
    always @(posedge clk) begin
        if (rst) begin
            psum_store <= 0;
        end else if (data_ready) begin
            psum_store <= psum_flat;
        end
    end

    // Select the row based on out_row_idx
    // psum_flat is organized as Row 0 (w0..w7), Row 1 (w0..w7), ...
    // We slice psum_store based on out_row_idx
    wire [TILE_W*PSUM_W-1:0] row_psums;
    
    // Variable part select: [base +: width]
    // base = out_row_idx * (TILE_W * PSUM_W)
    assign row_psums = psum_store[out_row_idx * (TILE_W*PSUM_W) +: (TILE_W*PSUM_W)];

    // Calculate shift amount: shift = q_act + q_wgt - q_out
    // If shift > 0, right shift (floor). If shift < 0, left shift.
    wire signed [5:0] shift_amt = {2'b0, q_act} + {2'b0, q_wgt} - {2'b0, q_out};

    // Quantize and pack the row
    genvar w;
    generate
        for (w = 0; w < TILE_W; w = w + 1) begin : PACK
            wire signed [PSUM_W-1:0] psum_val;
            assign psum_val = row_psums[w*PSUM_W +: PSUM_W];
            
            reg signed [PSUM_W-1:0] psum_shifted;
            
            always @(*) begin
                if (shift_amt >= 0)
                    psum_shifted = psum_val >>> shift_amt;
                else
                    psum_shifted = psum_val <<< (-shift_amt);
            end
            
            // Simple saturation logic (int32 -> int8)
            // Clip to [-128, 127]
            reg [ACT_W-1:0] act_val;
            
            always @(*) begin
                if (psum_shifted > 127)
                    act_val = 8'd127;
                else if (psum_shifted < -128)
                    act_val = 8'h80; // -128
                else
                    act_val = psum_shifted[ACT_W-1:0];
            end
            
            assign drain_out_data[w*ACT_W +: ACT_W] = act_val;
        end
    endgenerate

endmodule
