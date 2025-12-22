`timescale 1ns / 1ps
// ================================================================
// top.v
// Top-level module integrating AGU, Buffers, PE Array, and Drainer
// ================================================================
module top #(
    parameter H_IN        = 10,
    parameter W_IN        = 10,
    parameter C_IN        = 16,
    parameter C_OUT       = 16,
    parameter K           = 3,
    parameter TILE_C      = 8,
    parameter TILE_W      = 8,
    parameter DATA_W      = 8,
    parameter WGT_W       = 8,
    parameter PSUM_W      = 32,
    parameter ACT_ADDR_W  = 16,
    parameter WGT_ADDR_W  = 16,
    parameter OUT_ADDR_W  = 16
)(
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    
    // Quantization parameters (Input from outside or register config)
    input  wire [3:0]               q_act,
    input  wire [3:0]               q_wgt,
    input  wire [3:0]               q_out,

    output wire                     done
);

    // ============================================================
    // Internal Signals
    // ============================================================
    
    // AGU -> Buffers
    wire [ACT_ADDR_W-1:0]   act_read_base;
    wire [WGT_ADDR_W-1:0]   wgt_read_base;
    wire [OUT_ADDR_W-1:0]   out_write_base;
    wire                    out_we;
    wire [3:0]              out_row_idx;
    wire                    pingpong_sel;
    wire [TILE_W-1:0]       mask_w;

    // AGU -> PE Array / Drainer
    wire                    data_ready;
    wire                    clear_psum;
    wire                    valid_in;

    // Buffers -> PE Array
    wire [TILE_W*DATA_W-1:0] act_vec_raw;
    reg  [TILE_W*DATA_W-1:0] act_vec_masked;
    wire [TILE_C*WGT_W-1:0]  wgt_vec;

    // PE Array -> Drainer
    wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat;

    // Drainer -> ACT Buffer (Write back)
    wire [TILE_W*DATA_W-1:0] drain_out_data;

    // ============================================================
    // 1. AGU Instance
    // ============================================================
    conv_agu_cw #(
        .H_IN(H_IN), .W_IN(W_IN), .C_IN(C_IN),
        .C_OUT(C_OUT), .K(K),
        .TILE_C(TILE_C), .TILE_W(TILE_W),
        .ACT_ADDR_W(ACT_ADDR_W), .WGT_ADDR_W(WGT_ADDR_W), .OUT_ADDR_W(OUT_ADDR_W)
    ) u_agu (
        .clk(clk),
        .rst(rst),
        .start(start),
        .act_read_base(act_read_base),
        .wgt_read_base(wgt_read_base),
        .out_write_base(out_write_base),
        .out_we(out_we),
        .out_row_idx(out_row_idx),
        .data_ready(data_ready),
        .clear_psum(clear_psum),
        .valid_in(valid_in),
        .pingpong_sel(pingpong_sel),
        .mask_w(mask_w),
        .done(done)
    );

    // ============================================================
    // 2. ACT Buffer (Ping-Pong)
    // ============================================================
    // Assuming act_buffer_lat2 handles the ping-pong logic internally via bank_sel
    // bank_sel = 0: Read Bank 0, Write Bank 1
    // bank_sel = 1: Read Bank 1, Write Bank 0
    
    // Note: act_buffer_lat2 interface uses 'read_en' which AGU doesn't explicitly output.
    // However, AGU outputs valid addresses continuously during S_MAC.
    // We can tie read_en to valid_in (or a delayed version matching address phase).
    // Actually, AGU generates addresses in S_MAC. Let's assume read_en is active when AGU is running.
    // But wait, act_buffer_lat2 has internal pipeline.
    // Let's just tie read_en to 1 for now, or derive it from AGU state if exposed.
    // Since AGU doesn't output 'read_en', we can assume it's always reading if start was triggered,
    // or better, we can infer it. But for simplicity, let's tie it to 1 or valid_in logic.
    // Actually, 'valid_in' from AGU is delayed. The address 'act_read_base' is NOT delayed.
    // So we should enable read when we have a valid address.
    // In this simple top, we might just set read_en = 1 (always ready) or use a signal from AGU if we added one.
    // Let's assume read_en = 1 is safe as long as address is stable/valid.
    
    act_buffer_lat2 #(
        .DATA_W(DATA_W),
        .TILE_W(TILE_W),
        .ADDR_W(ACT_ADDR_W)
    ) u_act_buf (
        .clk(clk),
        .rst(rst),
        .bank_sel(pingpong_sel),
        
        // Read Port (Driven by AGU)
        .read_en(1'b1), // Always enable read, AGU controls address
        .read_base_addr(act_read_base),
        .act_vector(act_vec_raw),
        
        // Write Port (Driven by Drainer)
        .write_en(out_we),
        .write_addr(out_write_base),
        .write_data(drain_out_data)
    );

    // ============================================================
    // 3. Masking Logic
    // ============================================================
    // Apply mask_w to act_vec_raw before sending to PE Array
    integer i;
    always @(*) begin
        for (i = 0; i < TILE_W; i = i + 1) begin
            if (mask_w[i])
                act_vec_masked[i*DATA_W +: DATA_W] = act_vec_raw[i*DATA_W +: DATA_W];
            else
                act_vec_masked[i*DATA_W +: DATA_W] = {DATA_W{1'b0}};
        end
    end

    // ============================================================
    // 4. Weight Buffer
    // ============================================================
    wgt_buf #(
        .DATA_W(DATA_W),
        .TILE_SIZE(TILE_C) // Note: wgt_buf parameter is TILE_SIZE, here it maps to TILE_C (rows)
    ) u_wgt_buf (
        .clk(clk),
        .addr(wgt_read_base[12:0]), // Truncate if needed, wgt_buf uses 13 bits
        .en(1'b1),
        .wgt_vector(wgt_vec)
    );

    // ============================================================
    // 5. PE Array
    // ============================================================
    pe_array #(
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .DATA_W(DATA_W),
        .WGT_W(WGT_W),
        .PSUM_W(PSUM_W)
    ) u_pe_array (
        .clk(clk),
        .rst(rst),
        .act_vec(act_vec_masked), // Use masked activation vector
        .wgt_vec(wgt_vec),
        .valid_in(valid_in),
        .clear_psum(clear_psum),
        .psum_flat(psum_flat)
    );

    // ============================================================
    // 6. PE Drainer
    // ============================================================
    pe_drainer #(
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .PSUM_W(PSUM_W),
        .ACT_W(DATA_W)
    ) u_drainer (
        .clk(clk),
        .rst(rst),
        .data_ready(data_ready),
        .out_row_idx(out_row_idx),
        .q_act(q_act),
        .q_wgt(q_wgt),
        .q_out(q_out),
        .psum_flat(psum_flat),
        .drain_out_data(drain_out_data)
    );

endmodule
