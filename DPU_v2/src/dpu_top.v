`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: dpu_top
// Description: Top-level DPU Module with External BRAM Interface
//              支持连接到外部共享BRAM的Ping-Pong架构
//
// 修改说明：
//   - 移除内部act_buffer中的BRAM
//   - 通过外部接口连接到全局共享BRAM
//   - 保留内部权重缓冲（每层独立的权重）
//////////////////////////////////////////////////////////////////////////////////

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
    parameter STRIDE   = 1,
    parameter ADDR_W   = 16,
    parameter SHIFT    = 8,
    parameter RELU_EN  = 1,
    // 计算输出尺寸
    localparam H_OUT   = (H_IN + 2*PAD - K) / STRIDE + 1,
    localparam W_OUT   = (W_IN + 2*PAD - K) / STRIDE + 1
)(
    input  wire                clk,
    input  wire                resetn,
    input  wire                start,
    
    // ============================================================
    // 外部BRAM读接口（连接到全局共享BRAM）
    // ============================================================
    output wire                ext_act_read_en,
    output wire [ADDR_W-1:0]   ext_act_read_addr,
    input  wire [TILE_W*DATA_W-1:0] ext_act_read_data_0,  // word 0
    input  wire [TILE_W*DATA_W-1:0] ext_act_read_data_1,  // word 1
    input  wire [TILE_W*DATA_W-1:0] ext_act_read_data_2,  // word 2
    
    // ============================================================
    // 外部BRAM写接口
    // ============================================================
    output wire                ext_act_write_en,
    output wire [ADDR_W-1:0]   ext_act_write_addr,
    output wire [TILE_W*DATA_W-1:0] ext_act_write_data,
    output wire [TILE_W-1:0]   ext_act_write_mask,
    
    // ============================================================
    // 权重加载接口（内部权重缓冲）
    // ============================================================
    input  wire                ext_wgt_we,
    input  wire [ADDR_W-1:0]   ext_wgt_addr,
    input  wire [TILE_C*DATA_W-1:0] ext_wgt_data,
    
    // 状态
    output wire                done
);

    // ============================================================
    // AGU信号
    // ============================================================
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

    // ============================================================
    // 外部BRAM读接口连接
    // ============================================================
    assign ext_act_read_en   = agu_act_read_en;
    assign ext_act_read_addr = agu_act_read_addr;

    // ============================================================
    // Writeback Logic - 写入外部BRAM
    // ============================================================
    wire [ADDR_W-1:0] drain_write_addr = agu_out_addr + drain_row_idx * (H_OUT * W_OUT);
    
    // 生成写mask
    wire [2:0] write_byte_offset = drain_write_addr[2:0];
    wire [TILE_W-1:0] drain_mask;
    
    generate
        if (W_OUT >= TILE_W) begin : gen_full_mask
            assign drain_mask = {TILE_W{1'b1}};
        end else begin : gen_partial_mask
            assign drain_mask = (write_byte_offset == 0) ? {{(TILE_W-W_OUT){1'b0}}, {W_OUT{1'b1}}} :
                               (write_byte_offset == 4) ? {{W_OUT{1'b1}}, {(TILE_W-W_OUT){1'b0}}} :
                               {TILE_W{1'b0}};
        end
    endgenerate
    
    // 生成移位后的drain数据
    wire [TILE_W*DATA_W-1:0] drain_data_shifted;
    generate
        if (W_OUT >= TILE_W) begin : gen_no_shift
            assign drain_data_shifted = drain_data;
        end else begin : gen_shift
            assign drain_data_shifted = (write_byte_offset == 0) ? drain_data :
                                       (write_byte_offset == 4) ? {drain_data[W_OUT*DATA_W-1:0], {(TILE_W-W_OUT)*DATA_W{1'b0}}} :
                                       drain_data;
        end
    endgenerate
    
    // 外部写接口
    assign ext_act_write_en   = drain_valid;
    assign ext_act_write_addr = drain_write_addr;
    assign ext_act_write_data = drain_data_shifted;
    assign ext_act_write_mask = drain_mask;

    // ============================================================
    // AGU Instance
    // ============================================================
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
        .STRIDE(STRIDE),
        .ADDR_W(ADDR_W)
    ) u_agu (
        .clk(clk),
        .resetn(resetn),
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

    // ============================================================
    // Activation Buffer Interface（连接外部BRAM）
    // ============================================================
    act_buffer_if #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .STRIDE(STRIDE),
        .ADDR_W(ADDR_W)
    ) u_act_buffer_if (
        .clk(clk),
        .resetn(resetn),
        .read_en(agu_act_read_en),
        .read_base_addr(agu_act_read_addr),
        .read_shift(agu_act_read_shift),
        .act_mask(agu_act_mask),
        .act_vector(act_vector),
        // 连接外部BRAM数据
        .bram_read_data_0(ext_act_read_data_0),
        .bram_read_data_1(ext_act_read_data_1),
        .bram_read_data_2(ext_act_read_data_2)
    );

    // ============================================================
    // Weight Buffer Instance（内部BRAM，每层独立）
    // ============================================================
    wgt_buffer #(
        .DATA_W(DATA_W),
        .TILE_C(TILE_C),
        .ADDR_W(ADDR_W)
    ) u_wgt_buffer (
        .clk(clk),
        .resetn(resetn),
        .read_en(agu_wgt_read_en),
        .read_addr(agu_wgt_read_addr),
        .wgt_vector(wgt_vector),
        .write_en(ext_wgt_we),
        .write_addr(ext_wgt_addr),
        .write_data(ext_wgt_data)
    );

    // ============================================================
    // PE Array Instance
    // ============================================================
    pe_array #(
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W)
    ) u_pe_array (
        .clk(clk),
        .resetn(resetn),
        .valid_in(agu_valid_in),
        .clear_psum(agu_clear_psum),
        .act_vec(act_vector),
        .wgt_vec(wgt_vector),
        .psum_flat(psum_flat)
    );

    // ============================================================
    // Drainer Instance
    // ============================================================
    drainer #(
        .DATA_W(DATA_W),
        .PSUM_W(PSUM_W),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .SHIFT(SHIFT),
        .RELU_EN(RELU_EN)
    ) u_drainer (
        .clk(clk),
        .resetn(resetn),
        .data_ready(agu_data_ready),
        .psum_flat(psum_flat),
        .drain_valid(drain_valid),
        .drain_row_idx(drain_row_idx),
        .drain_data(drain_data)
    );

endmodule
