`timescale 1ns / 1ps

// AGU (Address Generation Unit) - Central control and address generation

module agu #(
    parameter DATA_W   = 8,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8,
    parameter H_IN     = 32,
    parameter W_IN     = 32,
    parameter C_IN     = 1,
    parameter C_OUT    = 32,
    parameter K        = 5,
    parameter PAD      = 2,
    parameter ADDR_W   = 16
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,

    output reg                 act_read_en,
    output reg  [ADDR_W-1:0]   act_read_addr,
    output reg  signed [3:0]   act_read_shift,
    output reg  [TILE_W-1:0]   act_mask,

    output reg                 wgt_read_en,
    output reg  [ADDR_W-1:0]   wgt_read_addr,

    output reg                 valid_in,
    output reg                 clear_psum,

    output reg                 data_ready,

    output reg                 out_we,
    output reg  [ADDR_W-1:0]   out_addr,
    output reg  [2:0]          out_row_idx,

    output reg                 bank_sel,

    output reg                 done
);

    localparam H_OUT = H_IN;
    localparam W_OUT = W_IN;
    
    localparam N_TILE_C = (C_OUT + TILE_C - 1) / TILE_C;
    localparam N_TILE_W = (W_OUT + TILE_W - 1) / TILE_W;
    
    localparam BRAM_LATENCY = 2;
    
    // State Machine
    localparam S_IDLE        = 4'd0;
    localparam S_INIT        = 4'd1;
    localparam S_COMPUTE     = 4'd2;
    localparam S_WAIT_PIPE   = 4'd3;
    localparam S_DATA_READY  = 4'd4;
    localparam S_DRAIN       = 4'd5;
    localparam S_CLEAR       = 4'd6;
    localparam S_NEXT_TILE   = 4'd7;
    localparam S_DONE        = 4'd8;
    
    reg [3:0] state;
    
    reg [9:0] cnt_h0;
    reg [9:0] cnt_base_c;
    reg [9:0] cnt_base_w;
    reg [9:0] cnt_ci;
    reg [3:0] cnt_hk;
    reg [3:0] cnt_wk;

    reg [3:0] pipe_cnt;
    reg [3:0] drain_cnt;
    
    wire signed [10:0] hk_signed = $signed({1'b0, cnt_hk}) - PAD;
    wire signed [10:0] wk_signed = $signed({1'b0, cnt_wk}) - PAD;
    wire signed [10:0] h_act = $signed({1'b0, cnt_h0}) + hk_signed;
    wire signed [10:0] w_act = $signed({1'b0, cnt_base_w}) + wk_signed;

    wire h_valid = (h_act >= 0) && (h_act < H_IN);
    wire w_start_valid = (w_act >= 0);
    wire w_end_valid = (w_act + TILE_W - 1 < W_IN);

    wire signed [10:0] w_act_clamped = (w_act < 0) ? 0 : 
                                       (w_act >= W_IN) ? (W_IN - TILE_W) : w_act;

    wire signed [3:0] pad_shift = (w_act < 0) ? w_act[3:0] : 4'sd0;

    wire [ADDR_W-1:0] act_byte_addr = (h_valid) ? 
        (cnt_ci * H_IN * W_IN + h_act * W_IN + w_act_clamped) : 0;

    wire [TILE_W-1:0] gen_mask;
    genvar mi;
    generate
        for (mi = 0; mi < TILE_W; mi = mi + 1) begin : gen_mask_bits
            wire signed [10:0] w_pos = w_act + mi;
            assign gen_mask[mi] = h_valid && (w_pos >= 0) && (w_pos < W_IN);
        end
    endgenerate

    wire [ADDR_W-1:0] wgt_word_addr = 
        (cnt_base_c / TILE_C) * (C_IN * K * K) + 
        cnt_ci * (K * K) + 
        cnt_hk * K + 
        cnt_wk;

    reg [ADDR_W-1:0] out_base_addr;
    
    // Edge Detection for Start
    reg start_d;
    wire start_rising = start && !start_d;
    
    always @(posedge clk) begin
        if (!rst_n) start_d <= 0;
        else     start_d <= start;
    end

    // Main State Machine
    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            cnt_h0        <= 0;
            cnt_base_c    <= 0;
            cnt_base_w    <= 0;
            cnt_ci        <= 0;
            cnt_hk        <= 0;
            cnt_wk        <= 0;
            pipe_cnt      <= 0;
            drain_cnt     <= 0;
            act_read_en   <= 0;
            act_read_addr <= 0;
            act_read_shift <= 0;
            act_mask      <= 0;
            wgt_read_en   <= 0;
            wgt_read_addr <= 0;
            clear_psum    <= 0;
            data_ready    <= 0;
            out_we        <= 0;
            out_addr      <= 0;
            out_row_idx   <= 0;
            out_base_addr <= 0;
            bank_sel      <= 0;
            done          <= 0;
        end else begin
            clear_psum <= 0;
            data_ready <= 0;
            out_we     <= 0;
            
            case (state)
                S_IDLE: begin
                    if (start_rising) begin
                        state      <= S_INIT;
                        cnt_h0     <= 0;
                        cnt_base_c <= 0;
                        cnt_base_w <= 0;
                        done       <= 0;
                    end
                end
                
                S_INIT: begin
                    cnt_ci  <= 0;
                    cnt_hk  <= 0;
                    cnt_wk  <= 0;
                    clear_psum <= 1;
                    state <= S_COMPUTE;
                end
                
                S_COMPUTE: begin
                    act_read_en   <= 1;
                    act_read_addr <= act_byte_addr;
                    act_read_shift <= pad_shift;
                    act_mask      <= gen_mask;
                    
                    wgt_read_en   <= 1;
                    wgt_read_addr <= wgt_word_addr;
                    
                    if (cnt_wk < K - 1) begin
                        cnt_wk <= cnt_wk + 1;
                    end else begin
                        cnt_wk <= 0;
                        if (cnt_hk < K - 1) begin
                            cnt_hk <= cnt_hk + 1;
                        end else begin
                            cnt_hk <= 0;
                            if (cnt_ci < C_IN - 1) begin
                                cnt_ci <= cnt_ci + 1;
                            end else begin
                                state <= S_WAIT_PIPE;
                                pipe_cnt <= BRAM_LATENCY + 1;
                            end
                        end
                    end
                end
                
                S_WAIT_PIPE: begin
                    act_read_en <= 0;
                    wgt_read_en <= 0;
                    
                    if (pipe_cnt > 0) begin
                        pipe_cnt <= pipe_cnt - 1;
                    end else begin
                        state <= S_DATA_READY;
                    end
                end
                
                S_DATA_READY: begin
                    data_ready <= 1;
                    drain_cnt <= TILE_C + 1;
                    out_base_addr <= cnt_base_c * (H_OUT * W_OUT) + cnt_h0 * W_OUT + cnt_base_w;
                    out_addr <= cnt_base_c * (H_OUT * W_OUT) + cnt_h0 * W_OUT + cnt_base_w;
                    state <= S_DRAIN;
                end
                
                S_DRAIN: begin
                    if (drain_cnt > 0) begin
                        drain_cnt <= drain_cnt - 1;
                    end else begin
                        state <= S_CLEAR;
                    end
                end
                
                S_CLEAR: begin
                    clear_psum <= 1;
                    state <= S_NEXT_TILE;
                end
                
                S_NEXT_TILE: begin
                    if (cnt_base_w + TILE_W < W_OUT) begin
                        cnt_base_w <= cnt_base_w + TILE_W;
                        state <= S_INIT;
                    end else begin
                        cnt_base_w <= 0;
                        if (cnt_base_c + TILE_C < C_OUT) begin
                            cnt_base_c <= cnt_base_c + TILE_C;
                            state <= S_INIT;
                        end else begin
                            cnt_base_c <= 0;
                            if (cnt_h0 < H_OUT - 1) begin
                                cnt_h0 <= cnt_h0 + 1;
                                state <= S_INIT;
                            end else begin
                                state <= S_DONE;
                            end
                        end
                    end
                end
                
                S_DONE: begin
                    done <= 1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
    
    // Valid_in Generation
    reg [1:0] valid_pipe;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            valid_pipe <= 0;
            valid_in <= 0;
        end else begin
            valid_pipe[0] <= (state == S_COMPUTE);
            valid_pipe[1] <= valid_pipe[0];
            valid_in <= valid_pipe[1];
        end
    end

endmodule
