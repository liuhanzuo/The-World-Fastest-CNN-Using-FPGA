`timescale 1ns / 1ps

// DPU Top - Top-level DPU Module

module dpu_top #(
    parameter DATA_W   = 8,
    parameter PSUM_W   = 24,
    parameter TILE_C   = 8,
    parameter TILE_W   = 8,
    parameter H_IN     = 32,
    parameter W_IN     = 32,
    parameter C_IN     = 1,
    parameter C_OUT    = 32,
    parameter K        = 5,
    parameter PAD      = 2,
    parameter ADDR_W   = 16,
    parameter SHIFT    = 9,
    parameter RELU_EN  = 0
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                start,
    
    input  wire                ext_act_bank_sel,
    input  wire [7:0]          ext_act_we,
    input  wire [ADDR_W-1:0]   ext_act_addr,
    input  wire [TILE_W*DATA_W-1:0] ext_act_data,
    output wire [TILE_W*DATA_W-1:0] ext_act_rdata,
    
    input  wire [7:0]          ext_wgt_we,
    input  wire [ADDR_W-1:0]   ext_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] ext_wgt_data,
    output wire [TILE_C*DATA_W-1:0] ext_wgt_rdata,
    
    output wire                done
);

    wire                 agu_act_read_en;
    wire [ADDR_W-1:0]    agu_act_read_addr;
    wire signed [3:0]    agu_act_read_shift;
    wire [TILE_W-1:0]    agu_act_mask;
    wire                 agu_wgt_read_en;
    wire [ADDR_W-1:0]    agu_wgt_read_addr;
    wire                 agu_valid_in;
    wire                 agu_clear_psum;
    wire                 agu_data_ready;
    wire                 agu_out_we;
    wire [ADDR_W-1:0]    agu_out_addr;
    wire [2:0]           agu_out_row_idx;
    wire                 agu_bank_sel;

    wire [TILE_W*DATA_W-1:0] act_vector;
    wire [TILE_C*DATA_W-1:0] wgt_vector;

    wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat;

    wire                 drain_valid;
    wire [2:0]           drain_row_idx;
    wire [TILE_W*DATA_W-1:0] drain_data;

    wire                 act_write_en;
    wire [ADDR_W-1:0]    act_write_addr;
    wire [TILE_W*DATA_W-1:0] act_write_data;
    wire                 act_write_bank_sel;
    
    localparam H_OUT = H_IN;
    localparam W_OUT = W_IN;
    wire [ADDR_W-1:0] drain_write_addr = agu_out_addr + drain_row_idx * (H_OUT * W_OUT);
    
    wire [7:0] act_write_we = ext_act_we | {8{drain_valid}};
    assign act_write_addr = (drain_valid) ? drain_write_addr : ext_act_addr;
    assign act_write_data = (drain_valid) ? drain_data : ext_act_data;
    assign act_write_bank_sel = (drain_valid) ? ~agu_bank_sel : ext_act_bank_sel;

    // AGU Instance
    agu #(
        .DATA_W(DATA_W),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .H_IN(H_IN),
        .W_IN(W_IN),
        .C_IN(C_IN),
        .C_OUT(C_OUT),
        .K(K),
        .PAD(PAD),
        .ADDR_W(ADDR_W)
    ) u_agu (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .act_read_en(agu_act_read_en),
        .act_read_addr(agu_act_read_addr),
        .act_read_shift(agu_act_read_shift),
        .act_mask(agu_act_mask),
        .wgt_read_en(agu_wgt_read_en),
        .wgt_read_addr(agu_wgt_read_addr),
        .valid_in(agu_valid_in),
        .clear_psum(agu_clear_psum),
        .data_ready(agu_data_ready),
        .out_we(agu_out_we),
        .out_addr(agu_out_addr),
        .out_row_idx(agu_out_row_idx),
        .bank_sel(agu_bank_sel),
        .done(done)
    );

    // Activation Buffer Instance
    act_buffer #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .ADDR_W(ADDR_W)
    ) u_act_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .bank_sel(agu_bank_sel),
        .read_en(agu_act_read_en),
        .read_base_addr(agu_act_read_addr),
        .read_shift(agu_act_read_shift),
        .act_mask(agu_act_mask),
        .act_vector(act_vector),
        .write_we(act_write_we),
        .write_addr(act_write_addr),
        .write_data(act_write_data),
        .write_bank_sel(act_write_bank_sel),
        .ext_rd_data(ext_act_rdata)
    );

    // Weight Buffer Instance
    wgt_buffer #(
        .DATA_W(DATA_W),
        .TILE_C(TILE_C),
        .ADDR_W(ADDR_W)
    ) u_wgt_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .read_en(agu_wgt_read_en),
        .read_addr(agu_wgt_read_addr),
        .wgt_vector(wgt_vector),
        .write_we(ext_wgt_we),
        .write_addr(ext_wgt_addr),
        .write_data(ext_wgt_data),
        .read_data_out(ext_wgt_rdata)
    );

    // PE Array Instance
    pe_array #(
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W)
    ) u_pe_array (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(agu_valid_in),
        .clear_psum(agu_clear_psum),
        .act_vec(act_vector),
        .wgt_vec(wgt_vector),
        .psum_flat(psum_flat)
    );

    // Drainer Instance
    drainer #(
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .SHIFT(SHIFT),
        .RELU_EN(RELU_EN)
    ) u_drainer (
        .clk(clk),
        .rst_n(rst_n),
        .data_ready(agu_data_ready),
        .psum_flat(psum_flat),
        .drain_valid(drain_valid),
        .drain_row_idx(drain_row_idx),
        .drain_data(drain_data)
    );

endmodule
