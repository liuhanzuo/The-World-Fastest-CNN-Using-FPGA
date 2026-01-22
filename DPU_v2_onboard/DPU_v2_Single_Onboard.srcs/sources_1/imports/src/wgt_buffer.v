`timescale 1ns / 1ps

// Weight Buffer with Sequential BRAM Storage

module wgt_buffer #(
    parameter DATA_W     = 8,
    parameter TILE_C     = 8,
    parameter WORD_W     = DATA_W * TILE_C,
    parameter ADDR_W     = 16,
    parameter BRAM_DEPTH = 8192
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire                read_en,
    input  wire [ADDR_W-1:0]   read_addr,       // Word address
    output reg  [WORD_W-1:0]   wgt_vector,

    input  wire [7:0]          write_we,        // Byte enable
    input  wire [ADDR_W-1:0]   write_addr,      // Word address
    input  wire [WORD_W-1:0]   write_data,
    output reg  [WORD_W-1:0]   read_data_out
);

    // BRAM Instantiation
    (* ram_style = "block" *) reg [WORD_W-1:0] bram [0:BRAM_DEPTH-1];
    
    // Initialize BRAM to 0
    integer init_i;
    initial begin
        for (init_i = 0; init_i < BRAM_DEPTH; init_i = init_i + 1) begin
            bram[init_i] = {WORD_W{1'b0}};
        end
    end
    
    // Pipeline registers
    reg [WORD_W-1:0] data_d1, data_d2;

    // Read Logic
    always @(posedge clk) begin
        if (read_en) begin
            data_d1 <= bram[read_addr];
        end
        data_d2 <= data_d1;
    end
    
    always @(*) begin
        wgt_vector = data_d2;
    end

    // Write/Read Logic
    integer i;
    always @(posedge clk) begin
        for (i = 0; i < 8; i = i + 1) begin
             if (write_we[i]) begin
                 bram[write_addr][i*8 +: 8] <= write_data[i*8 +: 8];
             end
        end
        read_data_out <= bram[write_addr];
    end

endmodule
