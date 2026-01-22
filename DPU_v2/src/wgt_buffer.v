`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: wgt_buffer
// Description: Weight Buffer with Sequential BRAM Storage
//
// Memory Layout (per output channel group):
//   - Weights stored as: W[ci][hk][wk][co] for co in [0, TILE_C-1]
//   - Each BRAM word = TILE_C weights = 8 bytes
//   - Address = ci * (K*K) + (hk+PAD) * K + (wk+PAD)
//
// Features:
//   - 2-cycle read latency (BRAM pipeline)
//   - Sequential access pattern from AGU
//////////////////////////////////////////////////////////////////////////////////

module wgt_buffer #(
    parameter DATA_W     = 8,
    parameter TILE_C     = 8,
    parameter WORD_W     = DATA_W * TILE_C,    // 64 bits
    parameter ADDR_W     = 16,                  // Word address width
    parameter BRAM_DEPTH = 16384                // 128KB / 8 bytes = 16K words
)(
    input  wire                clk,
    input  wire                resetn,  // 低电平复位

    // --- Read Interface (from AGU) ---
    input  wire                read_en,
    input  wire [ADDR_W-1:0]   read_addr,       // Word address
    output reg  [WORD_W-1:0]   wgt_vector,      // Output weight vector

    // --- Write Interface (for initialization) ---
    input  wire                write_en,
    input  wire [ADDR_W-1:0]   write_addr,      // Word address
    input  wire [WORD_W-1:0]   write_data
);

    // ============================================================
    // BRAM Instantiation
    // ============================================================
    (* ram_style = "block" *) reg [WORD_W-1:0] bram [0:BRAM_DEPTH-1];
    
    // Initialize BRAM to 0 (for simulation)
    integer init_i;
    initial begin
        for (init_i = 0; init_i < BRAM_DEPTH; init_i = init_i + 1) begin
            bram[init_i] = {WORD_W{1'b0}};
        end
    end
    
    // Pipeline registers for 2-cycle latency (to match act_buffer)
    reg [WORD_W-1:0] data_d1, data_d2;

    // ============================================================
    // Read Logic
    // ============================================================
    always @(posedge clk) begin
        if (read_en) begin
            data_d1 <= bram[read_addr];
        end
        data_d2 <= data_d1;
    end
    
    always @(*) begin
        wgt_vector = data_d2;
    end

    // ============================================================
    // Write Logic
    // ============================================================
    always @(posedge clk) begin
        if (write_en) begin
            bram[write_addr] <= write_data;
        end
    end

endmodule
