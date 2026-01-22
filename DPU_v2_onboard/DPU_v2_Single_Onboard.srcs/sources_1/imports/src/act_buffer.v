`timescale 1ns / 1ps

// Activation Buffer with Ping-Pong BRAM and Byte-Aligned Gearbox

module act_buffer #(
    parameter DATA_W       = 8,
    parameter TILE_W       = 8,
    parameter WORD_W       = DATA_W * TILE_W,
    parameter ADDR_W       = 16,
    parameter BRAM_DEPTH   = 8192
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire                bank_sel,          // 0: read bank0, write bank1

    input  wire                read_en,
    input  wire [ADDR_W-1:0]   read_base_addr,    // Byte address
    input  wire signed [3:0]   read_shift,        // negative = left pad, positive = right shift
    input  wire [TILE_W-1:0]   act_mask,          // 1 = valid, 0 = zero
    output reg  [WORD_W-1:0]   act_vector,

    input  wire [7:0]          write_we,          // Byte enable
    input  wire [ADDR_W-1:0]   write_addr,
    input  wire [WORD_W-1:0]   write_data,
    input  wire                write_bank_sel,    // 0: write to bank0, 1: write to bank1
    output reg  [WORD_W-1:0]   ext_rd_data
);
    
    wire [2:0]        byte_offset    = read_base_addr[2:0];
    wire [ADDR_W-4:0] low_word_addr  = read_base_addr[ADDR_W-1:3];
    wire [ADDR_W-4:0] high_word_addr = low_word_addr + 1'b1;
    wire [ADDR_W-4:0] write_word_addr = write_addr[ADDR_W-1:3];

    // Pipeline Registers
    reg [2:0]        offset_d1, offset_d2;
    reg signed [3:0] shift_d1, shift_d2;
    reg [TILE_W-1:0] mask_d1, mask_d2;
    reg              valid_d1, valid_d2;
    reg              bank_sel_d1, bank_sel_d2;

    always @(posedge clk) begin
        if (!rst_n) begin
            offset_d1   <= 0;
            offset_d2   <= 0;
            shift_d1    <= 0;
            shift_d2    <= 0;
            mask_d1     <= 0;
            mask_d2     <= 0;
            valid_d1    <= 0;
            valid_d2    <= 0;
            bank_sel_d1 <= 0;
            bank_sel_d2 <= 0;
        end else begin
            offset_d1   <= byte_offset;
            shift_d1    <= read_shift;
            mask_d1     <= act_mask;
            valid_d1    <= read_en;
            bank_sel_d1 <= bank_sel;

            offset_d2   <= offset_d1;
            shift_d2    <= shift_d1;
            mask_d2     <= mask_d1;
            valid_d2    <= valid_d1;
            bank_sel_d2 <= bank_sel_d1;
        end
    end

    // BRAM Instantiation
    (* ram_style = "block" *) reg [WORD_W-1:0] bram0 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) reg [WORD_W-1:0] bram1 [0:BRAM_DEPTH-1];
    
    // Initialize for simulation
    integer init_i;
    initial begin
        for (init_i = 0; init_i < BRAM_DEPTH; init_i = init_i + 1) begin
            bram0[init_i] = {WORD_W{1'b0}};
            bram1[init_i] = {WORD_W{1'b0}};
        end
    end

    
    reg [WORD_W-1:0] bram0_low_r1, bram0_low_r2;
    reg [WORD_W-1:0] bram0_high_r1, bram0_high_r2;
    reg [WORD_W-1:0] bram1_low_r1, bram1_low_r2;
    reg [WORD_W-1:0] bram1_high_r1, bram1_high_r2;
    
    reg [WORD_W-1:0] bram0_ext_out, bram1_ext_out;

    integer i0;
    always @(posedge clk) begin
        if (read_en) begin
            bram0_low_r1  <= bram0[low_word_addr];
            bram0_high_r1 <= bram0[high_word_addr];
        end
        bram0_low_r2  <= bram0_low_r1;
        bram0_high_r2 <= bram0_high_r1;
        
        if (write_bank_sel == 1'b0) begin
            for (i0 = 0; i0 < 8; i0 = i0 + 1) begin
                if (write_we[i0])
                     bram0[write_word_addr][i0*8 +: 8] <= write_data[i0*8 +: 8];
            end
            bram0_ext_out <= bram0[write_word_addr];
        end
    end
    
    integer i1;
    always @(posedge clk) begin
        if (read_en) begin
            bram1_low_r1  <= bram1[low_word_addr];
            bram1_high_r1 <= bram1[high_word_addr];
        end
        bram1_low_r2  <= bram1_low_r1;
        bram1_high_r2 <= bram1_high_r1;
        
        if (write_bank_sel == 1'b1) begin
             for (i1 = 0; i1 < 8; i1 = i1 + 1) begin
                if (write_we[i1])
                     bram1[write_word_addr][i1*8 +: 8] <= write_data[i1*8 +: 8];
            end
            bram1_ext_out <= bram1[write_word_addr];
        end
    end

    reg write_bank_sel_d1;
    always @(posedge clk) write_bank_sel_d1 <= write_bank_sel;
    always @(*) ext_rd_data = (write_bank_sel_d1) ? bram1_ext_out : bram0_ext_out;

    // Bank Selection and Gearbox
    wire [WORD_W-1:0] low_word  = (bank_sel_d2 == 1'b0) ? bram0_low_r2  : bram1_low_r2;
    wire [WORD_W-1:0] high_word = (bank_sel_d2 == 1'b0) ? bram0_high_r2 : bram1_high_r2;
    
    wire [127:0] combined_data = {high_word, low_word};
    
    reg [WORD_W-1:0] act_aligned;
    always @(*) begin
        case (offset_d2)
            3'd0: act_aligned = combined_data[63:0];
            3'd1: act_aligned = combined_data[71:8];
            3'd2: act_aligned = combined_data[79:16];
            3'd3: act_aligned = combined_data[87:24];
            3'd4: act_aligned = combined_data[95:32];
            3'd5: act_aligned = combined_data[103:40];
            3'd6: act_aligned = combined_data[111:48];
            3'd7: act_aligned = combined_data[119:56];
            default: act_aligned = combined_data[63:0];
        endcase
    end
    
    // Apply Shift for Padding
    reg [WORD_W-1:0] act_shifted;
    always @(*) begin
        case (shift_d2)
            -4'sd7: act_shifted = {act_aligned[7:0], 56'd0};
            -4'sd6: act_shifted = {act_aligned[15:0], 48'd0};
            -4'sd5: act_shifted = {act_aligned[23:0], 40'd0};
            -4'sd4: act_shifted = {act_aligned[31:0], 32'd0};
            -4'sd3: act_shifted = {act_aligned[39:0], 24'd0};
            -4'sd2: act_shifted = {act_aligned[47:0], 16'd0};
            -4'sd1: act_shifted = {act_aligned[55:0], 8'd0};
            4'sd0:  act_shifted = act_aligned;
            4'sd1:  act_shifted = {8'd0, act_aligned[63:8]};
            4'sd2:  act_shifted = {16'd0, act_aligned[63:16]};
            4'sd3:  act_shifted = {24'd0, act_aligned[63:24]};
            4'sd4:  act_shifted = {32'd0, act_aligned[63:32]};
            4'sd5:  act_shifted = {40'd0, act_aligned[63:40]};
            4'sd6:  act_shifted = {48'd0, act_aligned[63:48]};
            4'sd7:  act_shifted = {56'd0, act_aligned[63:56]};
            default: act_shifted = act_aligned;
        endcase
    end

    // Apply Mask and Output
    integer i;
    always @(*) begin
        for (i = 0; i < TILE_W; i = i + 1) begin
            if (mask_d2[i])
                act_vector[i*DATA_W +: DATA_W] = act_shifted[i*DATA_W +: DATA_W];
            else
                act_vector[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
        end
    end

endmodule
