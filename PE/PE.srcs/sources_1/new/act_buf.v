`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/08 19:56:11
// Design Name: 
// Module Name: act_buf
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


module act_buffer_lat2 #(
    parameter DATA_W       = 8,
    parameter TILE_W       = 8,
    parameter WORD_W       = DATA_W * TILE_W, // 64 bits
    parameter ADDR_W       = 13
)(
    input  wire                clk,
    input  wire                rst,

    // --- Control ---
    input  wire                bank_sel,   

    // --- AGU Read Interface ---
    input  wire                read_en,
    input  wire [ADDR_W-1:0]   read_base_addr, 
    output reg  [WORD_W-1:0]   act_vector,

    // --- Write Interface ---
    input  wire                write_en,
    input  wire [ADDR_W-1:0]   write_addr, 
    input  wire [WORD_W-1:0]   write_data
);

    // ============================================================
    // 1. Address Decoding & Word Change Detection (Stage 0)
    // ============================================================
    wire [ADDR_W-1:0] end_of_window_addr = read_base_addr + 3'd7;
    wire [ADDR_W-4:0] req_word_addr      = end_of_window_addr[ADDR_W-1:3];
    wire [2:0]        req_offset    = read_base_addr[2:0];        // Byte Offset

    reg [ADDR_W-4:0]  last_req_word_addr;
    wire              word_changed_s0;

    // Detect if we need to fetch a new 64-bit word
    assign word_changed_s0 = (req_word_addr != last_req_word_addr);

    always @(posedge clk) begin
        if (rst) last_req_word_addr <= {ADDR_W-3{1'b1}};
        else if (read_en) last_req_word_addr <= req_word_addr;
    end

    // ============================================================
    // 2. Control Signal Pipelining (Matching BRAM Latency)
    // ============================================================
    // BRAM Latency = 2 cycles.
    // We latch BRAM output into 'curr_word' at the end of Cycle 2.
    // So 'curr_word' is valid in Cycle 3.
    
    reg       word_changed_s1, word_changed_s2; // Delays for Load Enable
    reg [2:0] offset_s1, offset_s2, offset_s3;  // Delays for Mux Selection

    always @(posedge clk) begin
        if (read_en) begin
            // Pipeline the "Load New Word" trigger (Depth = 2)
            word_changed_s1 <= word_changed_s0;
            word_changed_s2 <= word_changed_s1; // <--- This triggers the register update

            // Pipeline the "Shift Amount" (Depth = 3)
            // Why 3? Because 'act_vector' is comb logic AFTER 'curr_word' is updated.
            offset_s1 <= req_offset;
            offset_s2 <= offset_s1;
            offset_s3 <= offset_s2;             // <--- This controls the final Mux
        end
    end

    // ============================================================
    // 3. Ping-Pong BRAM Logic (Same as before)
    // ============================================================
    // Note: BRAM read enables must be triggered by Stage 0 signals
    wire [WORD_W-1:0] bram0_dout, bram1_dout;
    reg bram0_en, bram0_we, bram1_en, bram1_we;
    reg [ADDR_W-1:0] bram0_addr, bram1_addr;
    reg [WORD_W-1:0] bram0_din, bram1_din;

    always @(*) begin
        if (bank_sel == 1'b0) begin 
            // Read Bank 0 (AGU), Write Bank 1 (PE)
            bram0_addr = req_word_addr;     // Stage 0 Address
            bram0_en   = read_en; // Only enable if word changed!
            bram0_we   = 1'b0;
            bram0_din  = 0;

            bram1_addr = write_addr;
            bram1_en   = write_en;
            bram1_we   = write_en;
            bram1_din  = write_data;
        end else begin
            // Write Bank 0, Read Bank 1
            bram0_addr = write_addr;
            bram0_en   = write_en;
            bram0_we   = write_en;
            bram0_din  = write_data;

            bram1_addr = req_word_addr;     // Stage 0 Address
            bram1_en   = read_en;
            bram1_we   = 1'b0;
            bram1_din  = 0;
        end
    end

    blk_mem_gen_act bank0 ( .clka(clk), .ena(bram0_en), .wea(bram0_we), .addra(bram0_addr), .dina(bram0_din), .douta(bram0_dout) );
    blk_mem_gen_act bank1 ( .clka(clk), .ena(bram1_en), .wea(bram1_we), .addra(bram1_addr), .dina(bram1_din), .douta(bram1_dout) );

    wire [WORD_W-1:0] raw_bram_data = (bank_sel == 1'b0) ? bram0_dout : bram1_dout;

    // ============================================================
    // 4. Data Realignment Pipeline (The "Gearbox")
    // ============================================================
    reg [WORD_W-1:0] prev_word;
    reg [WORD_W-1:0] curr_word;

    always @(posedge clk) begin
        if (rst) begin
            prev_word <= 0;
            curr_word <= 0;
        end
        else if (read_en) begin
            // Update registers ONLY when the pipeline signals valid BRAM data
            // word_changed_s2 is high exactly when 'raw_bram_data' is valid for the new word
            if (word_changed_s2) begin
                prev_word <= curr_word;
                curr_word <= raw_bram_data;
            end
        end
    end

    // ============================================================
    // 5. Output Mux (Combinational)
    // ============================================================
    // Uses offset_s3 because the data in prev/curr corresponds to the request 3 cycles ago.
    always @(*) begin
        case (offset_s3) 
            3'd0: act_vector = curr_word; 
            3'd1: act_vector = {prev_word[63:8],   curr_word[7:0]};
            3'd2: act_vector = {prev_word[63:16],  curr_word[15:0]};
            3'd3: act_vector = {prev_word[63:24],  curr_word[23:0]};
            3'd4: act_vector = {prev_word[63:32],  curr_word[31:0]};
            3'd5: act_vector = {prev_word[63:40],  curr_word[39:0]};
            3'd6: act_vector = {prev_word[63:48],  curr_word[47:0]};
            3'd7: act_vector = {prev_word[63:56],  curr_word[55:0]};
            default: act_vector = prev_word;
        endcase
    end

endmodule