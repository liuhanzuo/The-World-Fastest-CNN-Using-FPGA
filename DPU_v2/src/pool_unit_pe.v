`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pool_unit_pe
// Description: PE Array Style Pooling Unit
//              Supports:
//              - Max Pooling 2x2 (POOL_TYPE=0)
//              - Global Average Pooling (POOL_TYPE=1)
//////////////////////////////////////////////////////////////////////////////////

module pool_unit_pe #(
    parameter DATA_W    = 8,
    parameter ADDR_W    = 16,
    parameter TILE_W    = 8,              // Data Bus Width (bytes)
    parameter C_IN      = 32,
    parameter H_IN      = 32,
    parameter W_IN      = 32,
    parameter POOL_TYPE = 0               // 0=MaxPool 2x2, 1=AvgPool (Global)
)(
    input  wire                clk,
    input  wire                resetn,
    input  wire                start,
    
    // External BRAM Bulk Read Interface
    output wire                bram_read_en,
    output wire [ADDR_W-1:0]   bram_read_addr,
    input  wire [TILE_W*DATA_W-1:0] bram_read_data,
    
    // External BRAM Bulk Write Interface
    output wire                bram_write_en,
    output wire [ADDR_W-1:0]   bram_write_addr,
    output wire [TILE_W*DATA_W-1:0] bram_write_data,
    output wire [TILE_W-1:0]   bram_write_mask,
    
    output wire                done
);

    generate
    if (POOL_TYPE == 0) begin : gen_maxpool
        // ============================================================
        // Max Pooling 2x2 Implementation
        // ============================================================
        
        // Parameters
        localparam H_OUT = H_IN / 2;
        localparam W_OUT = W_IN / 2;
        localparam READS_PER_ROW = (W_IN + TILE_W - 1) / TILE_W;
        localparam WRITES_PER_ROW = (W_OUT + TILE_W - 1) / TILE_W;
        
        // State Machine
        localparam S_IDLE       = 4'd0;
        localparam S_READ_R0    = 4'd1;
        localparam S_WAIT_R0    = 4'd2;
        localparam S_READ_R1    = 4'd3;
        localparam S_WAIT_R1    = 4'd4;
        localparam S_COMPUTE    = 4'd5;
        localparam S_WRITE      = 4'd6;
        localparam S_NEXT_ROW   = 4'd7;
        localparam S_NEXT_CH    = 4'd8;
        localparam S_DONE       = 4'd9;
        
        reg [3:0] state;
        reg [15:0] cnt_c;
        reg [15:0] cnt_h_out;
        reg [15:0] cnt_w_read;
        reg [15:0] cnt_w_write;
        reg [1:0]  wait_cnt;
        reg done_reg;
        
        // Output Regs
        reg mp_read_en;
        reg [ADDR_W-1:0] mp_read_addr;
        reg mp_write_en;
        reg [ADDR_W-1:0] mp_write_addr;
        reg [TILE_W*DATA_W-1:0] mp_write_data;
        reg [TILE_W-1:0] mp_write_mask;
        
        // Assign to ports
        assign bram_read_en = mp_read_en;
        assign bram_read_addr = mp_read_addr;
        assign bram_write_en = mp_write_en;
        assign bram_write_addr = mp_write_addr;
        assign bram_write_data = mp_write_data;
        assign bram_write_mask = mp_write_mask;
        assign done = done_reg;
        
        // Buffers
        reg [TILE_W*DATA_W-1:0] row0_buf [0:3];
        reg [TILE_W*DATA_W-1:0] row1_buf [0:3];
        reg [DATA_W-1:0] out_buf [0:W_OUT-1];
        
        // Addresses
        wire [ADDR_W-1:0] read_addr_r0 = cnt_c * (H_IN * W_IN) + (cnt_h_out * 2) * W_IN + cnt_w_read * TILE_W;
        wire [ADDR_W-1:0] read_addr_r1 = cnt_c * (H_IN * W_IN) + (cnt_h_out * 2 + 1) * W_IN + cnt_w_read * TILE_W;
        wire [ADDR_W-1:0] write_addr_base = cnt_c * (H_OUT * W_OUT) + cnt_h_out * W_OUT + cnt_w_write * TILE_W;
        
        // Max Function
        function signed [DATA_W-1:0] max4;
            input signed [DATA_W-1:0] a, b, c, d;
            reg signed [DATA_W-1:0] max_ab, max_cd;
            begin
                max_ab = ((a) > (b)) ? a : b;
                max_cd = ((c) > (d)) ? c : d;
                max4 = ((max_ab) > (max_cd)) ? max_ab : max_cd;
            end
        endfunction
        
        integer i;
        reg signed [DATA_W-1:0] v00, v01, v10, v11;
        
        always @(posedge clk) begin
            if (!resetn) begin
                state <= S_IDLE;
                done_reg <= 0;
                mp_read_en <= 0;
                mp_write_en <= 0;
                mp_write_mask <= 0;
                cnt_c <= 0;
                cnt_h_out <= 0;
                cnt_w_read <= 0;
                cnt_w_write <= 0;
                wait_cnt <= 0;
            end else begin
                mp_read_en <= 0;
                mp_write_en <= 0;
                done_reg <= 0;
                
                case (state)
                    S_IDLE: begin
                        if (start) begin
                            state <= S_READ_R0;
                            cnt_c <= 0;
                            cnt_h_out <= 0;
                            cnt_w_read <= 0;
                            cnt_w_write <= 0;
                        end
                    end
                    
                    S_READ_R0: begin
                        mp_read_en <= 1;
                        mp_read_addr <= read_addr_r0;
                        wait_cnt <= 0;
                        state <= S_WAIT_R0;
                    end
                    
                    S_WAIT_R0: begin
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 1) begin
                            row0_buf[cnt_w_read] <= bram_read_data;
                            if (cnt_w_read >= READS_PER_ROW - 1) begin
                                cnt_w_read <= 0;
                                state <= S_READ_R1;
                            end else begin
                                cnt_w_read <= cnt_w_read + 1;
                                state <= S_READ_R0;
                            end
                        end
                    end
                    
                    S_READ_R1: begin
                        mp_read_en <= 1;
                        mp_read_addr <= read_addr_r1;
                        wait_cnt <= 0;
                        state <= S_WAIT_R1;
                    end
                    
                    S_WAIT_R1: begin
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 1) begin
                            row1_buf[cnt_w_read] <= bram_read_data;
                            if (cnt_w_read >= READS_PER_ROW - 1) begin
                                cnt_w_read <= 0;
                                state <= S_COMPUTE;
                            end else begin
                                cnt_w_read <= cnt_w_read + 1;
                                state <= S_READ_R1;
                            end
                        end
                    end
                    
                    S_COMPUTE: begin
                        for (i = 0; i < W_OUT; i = i + 1) begin
                            v00 = (row0_buf[(2*i) / TILE_W][((2*i) % TILE_W) * DATA_W +: DATA_W]);
                            v01 = (row0_buf[(2*i+1) / TILE_W][((2*i+1) % TILE_W) * DATA_W +: DATA_W]);
                            v10 = (row1_buf[(2*i) / TILE_W][((2*i) % TILE_W) * DATA_W +: DATA_W]);
                            v11 = (row1_buf[(2*i+1) / TILE_W][((2*i+1) % TILE_W) * DATA_W +: DATA_W]);
                            out_buf[i] <= max4(v00, v01, v10, v11);
                        end
                        cnt_w_write <= 0;
                        state <= S_WRITE;
                    end
                    
                    S_WRITE: begin
                        mp_write_en <= 1;
                        mp_write_addr <= write_addr_base;
                        for (i = 0; i < TILE_W; i = i + 1) begin
                            if (cnt_w_write * TILE_W + i < W_OUT) begin
                                mp_write_data[i*DATA_W +: DATA_W] <= out_buf[cnt_w_write * TILE_W + i];
                                mp_write_mask[i] <= 1'b1;
                            end else begin
                                mp_write_data[i*DATA_W +: DATA_W] <= 8'd0;
                                mp_write_mask[i] <= 1'b0;
                            end
                        end
                        if (cnt_w_write >= WRITES_PER_ROW - 1) begin
                            state <= S_NEXT_ROW;
                        end else begin
                            cnt_w_write <= cnt_w_write + 1;
                        end
                    end
                    
                    S_NEXT_ROW: begin
                        cnt_w_read <= 0;
                        cnt_w_write <= 0;
                        if (cnt_h_out >= H_OUT - 1) begin
                            cnt_h_out <= 0;
                            state <= S_NEXT_CH;
                        end else begin
                            cnt_h_out <= cnt_h_out + 1;
                            state <= S_READ_R0;
                        end
                    end
                    
                    S_NEXT_CH: begin
                        if (cnt_c >= C_IN - 1) begin
                            state <= S_DONE;
                        end else begin
                            cnt_c <= cnt_c + 1;
                            state <= S_READ_R0;
                        end
                    end
                    
                    S_DONE: begin
                        done_reg <= 1;
                        state <= S_IDLE;
                    end
                endcase
            end
        end

    end else begin : gen_avgpool
        // ============================================================
        // Global Average Pooling Implementation
        // Assumes H_IN=4, W_IN=4, TILE_W=8
        // Logic: Read 2 words (16 bytes) per channel, sum, shift, write 1 byte
        // ============================================================
        
        localparam S_IDLE       = 4'd0;
        localparam S_READ_W0    = 4'd1; // Read rows 0,1
        localparam S_WAIT_W0    = 4'd2;
        localparam S_READ_W1    = 4'd3; // Read rows 2,3
        localparam S_WAIT_W1    = 4'd4;
        localparam S_COMPUTE    = 4'd5;
        localparam S_WRITE      = 4'd6;
        localparam S_NEXT_CH    = 4'd7;
        localparam S_DONE       = 4'd8;
        
        reg [3:0] state;
        reg [15:0] cnt_c;
        reg [1:0]  wait_cnt;
        reg done_reg;
        
        reg signed [19:0] accumulator;
        reg [TILE_W*DATA_W-1:0] word0_reg, word1_reg;
        
        // Output Regs
        reg ap_read_en;
        reg [ADDR_W-1:0] ap_read_addr;
        reg ap_write_en;
        reg [ADDR_W-1:0] ap_write_addr;
        reg [TILE_W*DATA_W-1:0] ap_write_data;
        reg [TILE_W-1:0] ap_write_mask;
        
        // Assign to ports
        assign bram_read_en = ap_read_en;
        assign bram_read_addr = ap_read_addr;
        assign bram_write_en = ap_write_en;
        assign bram_write_addr = ap_write_addr;
        assign bram_write_data = ap_write_data;
        assign bram_write_mask = ap_write_mask;
        assign done = done_reg;
        
        // Address calculation
        // Input Size per Channel = 4*4 = 16 bytes.
        // Word 0: Bytes 0-7 (Row 0: 0-3, Row 1: 4-7)
        // Word 1: Bytes 8-15 (Row 2: 0-3, Row 3: 4-7)
        wire [ADDR_W-1:0] read_base = cnt_c * 16;
        
        // Write Address
        // Ch0->0, Ch1->1 ... Ch7->7 (All in Word 0)
        wire [ADDR_W-1:0] write_base_word = cnt_c & ~7; // Clear lower 3 bits
        wire [2:0]        write_offset    = cnt_c[2:0];
        
        integer k;
        
        always @(posedge clk) begin
            if (!resetn) begin
                state <= S_IDLE;
                done_reg <= 0;
                ap_read_en <= 0;
                ap_write_en <= 0;
                ap_write_mask <= 0;
                cnt_c <= 0;
                wait_cnt <= 0;
                accumulator <= 0;
            end else begin
                ap_read_en <= 0;
                ap_write_en <= 0;
                done_reg <= 0;
                
                case (state)
                    S_IDLE: begin
                        if (start) begin
                            cnt_c <= 0;
                            state <= S_READ_W0;
                        end
                    end
                    
                    S_READ_W0: begin
                        ap_read_en <= 1;
                        ap_read_addr <= read_base;
                        wait_cnt <= 0;
                        state <= S_WAIT_W0;
                    end
                    
                    S_WAIT_W0: begin
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 1) begin
                            word0_reg <= bram_read_data;
                            state <= S_READ_W1;
                        end
                    end
                    
                    S_READ_W1: begin
                        ap_read_en <= 1;
                        ap_read_addr <= read_base + 8;
                        wait_cnt <= 0;
                        state <= S_WAIT_W1;
                    end
                    
                    S_WAIT_W1: begin
                        wait_cnt <= wait_cnt + 1;
                        if (wait_cnt >= 1) begin
                            word1_reg <= bram_read_data;
                            state <= S_COMPUTE;
                        end
                    end
                    
                    S_COMPUTE: begin
                        accumulator = 0;
                        // Sum 16 bytes (Assuming TILE_W=8, byte layout is simple)
                        // Word 0 contains first 8 bytes
                        for (k = 0; k < 8; k = k + 1) begin
                            accumulator = accumulator + (word0_reg[k*8 +: 8]);
                        end
                        // Word 1 contains next 8 bytes
                        for (k = 0; k < 8; k = k + 1) begin
                            accumulator = accumulator + (word1_reg[k*8 +: 8]);
                        end
                        
                        state <= S_WRITE;
                    end
                    
                    S_WRITE: begin
                        ap_write_en <= 1;
                        ap_write_addr <= write_base_word;
                        
                        // Prepare data and mask based on channel offset
                        ap_write_data <= 0;
                        ap_write_mask <= 0;
                        
                        // Division by 16 (Shift right 4)
                        ap_write_data[write_offset*8 +: 8] <= accumulator[11:4];
                        ap_write_mask[write_offset] <= 1'b1;
                        
                        state <= S_NEXT_CH;
                    end
                    
                    S_NEXT_CH: begin
                        if (cnt_c >= C_IN - 1) begin
                            state <= S_DONE;
                        end else begin
                            cnt_c <= cnt_c + 1;
                            state <= S_READ_W0;
                        end
                    end
                    
                    S_DONE: begin
                        done_reg <= 1;
                        state <= S_IDLE;
                    end
                endcase
            end
        end
    end
    endgenerate

endmodule
