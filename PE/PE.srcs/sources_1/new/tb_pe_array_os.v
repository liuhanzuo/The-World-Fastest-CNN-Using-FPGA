`timescale 1ns/1ps

module tb_pe_array_os;

    // ------------------------------------------------------------
    // Parameters: 8x8 array, 3x3 kernel, single row output (h0=0)
    // ------------------------------------------------------------
    localparam TILE_C  = 8;   // Channel parallelism (rows)
    localparam TILE_W  = 8;   // Width parallelism (columns)
    localparam K       = 3;   // 3x3 kernel
    localparam DATA_W  = 8;
    localparam WGT_W   = 8;
    localparam PSUM_W  = 32;

    // Input feature map size: only for one output row h0=0
    localparam IN_H    = 1 + K - 1;        // 3
    localparam IN_W    = TILE_W + K - 1;   // 8 + 2 = 10

    // ------------------------------------------------------------
    // Clock / Control Signals
    // ------------------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;    // 100 MHz

    reg rst;
    reg valid_in;
    reg clear_psum;

    // Array input: 8 activations + 8 weights per cycle
    reg  [TILE_W*DATA_W-1:0]  act_vec;
    reg  [TILE_C*WGT_W-1:0]   wgt_vec;

    // Array output: 8x8 psum flattened
    wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat;

    // --------------------- DUT ---------------------
    pe_array_with_bram #(
        .TILE_C (TILE_C),
        .TILE_W (TILE_W),
        .DATA_W (DATA_W),
        .WGT_W  (WGT_W),
        .PSUM_W (PSUM_W)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .act_vec   (act_vec),
        .wgt_vec   (wgt_vec),
        .valid_in  (valid_in),
        .clear_psum(clear_psum),
        .psum_flat (psum_flat)
    );

    // ------------------------------------------------------------
    // Test Data
    // ------------------------------------------------------------

    // Input feature map: A[h][w], 3x10
    reg signed [DATA_W-1:0] A      [0:IN_H-1][0:IN_W-1];
    // Kernel: 3x3 kernel for each output channel Co
    // KERNEL[Co][r*K + s]
    reg signed [WGT_W-1:0]  KERNEL [0:TILE_C-1][0:K*K-1];
    // Golden output: golden[Co][w0]
    reg signed [PSUM_W-1:0] golden [0:TILE_C-1][0:TILE_W-1];

    integer i, j, co, w0, r, s;
    integer err;
    reg signed [PSUM_W-1:0] hw;
    integer idx;

    // ------------------------------------------------------------
    // Pack A[0+r][w0+s] into act_vec[w0] for current (r,s)
    // ------------------------------------------------------------
    task pack_act_vec_for_rs;
        input integer r_off;
        input integer s_off;
        integer w;
        begin
            for (w = 0; w < TILE_W; w = w + 1) begin
                act_vec[w*DATA_W +: DATA_W] = A[0 + r_off][w + s_off];
            end
        end
    endtask

    // Pack kernel elements for each channel into wgt_vec[Co] for current (r,s)
    task pack_wgt_vec_for_rs;
        input integer r_off;
        input integer s_off;
        integer c;
        integer k_idx;
        begin
            k_idx = r_off*K + s_off;  // r*K + s
            for (c = 0; c < TILE_C; c = c + 1) begin
                wgt_vec[c*WGT_W +: WGT_W] = KERNEL[c][k_idx];
            end
        end
    endtask

    // ------------------------------------------------------------
    initial begin
        $display("==== TB: CxW OS PE array test start ====");

        rst        = 1;
        valid_in   = 0;
        clear_psum = 0;
        act_vec    = 0;
        wgt_vec    = 0;

        // Reset for a few cycles
        repeat (3) @(posedge clk);
        rst = 0;

        // ---------- Initialize Input A ----------
        // A[h][w] = h*IN_W + w
        for (i = 0; i < IN_H; i = i + 1) begin
            for (j = 0; j < IN_W; j = j + 1) begin
                A[i][j] = i*IN_W + j;
            end
        end

        // ---------- Initialize Kernel ----------
        // Different kernel for each Co to facilitate checking:
        // KERNEL[Co][r*K+s] = (Co+1)*10 + (r*K+s+1)
        for (co = 0; co < TILE_C; co = co + 1) begin
            for (i = 0; i < K*K; i = i + 1) begin
                KERNEL[co][i] = (co+1)*10 + (i+1);
            end
        end

        // ---------- Compute Golden Result ----------
        // golden[Co][w0] = sum_{r,s} A[0+r][w0+s] * KERNEL[Co][r*K+s]
        for (co = 0; co < TILE_C; co = co + 1) begin
            for (w0 = 0; w0 < TILE_W; w0 = w0 + 1) begin
                golden[co][w0] = 0;
                for (r = 0; r < K; r = r + 1) begin
                    for (s = 0; s < K; s = s + 1) begin
                        golden[co][w0] = golden[co][w0] +
                            A[0 + r][w0 + s] * KERNEL[co][r*K + s];
                    end
                end
            end
        end

        $display("==== Golden model computed. Start hardware run ====");

        // ---------- Clear all PSUMs ----------
        clear_psum = 1;
        @(posedge clk);
        clear_psum = 0;

        // ---------- 9 cycles to cover full 3x3 kernel ----------
        valid_in = 1;
        for (r = 0; r < K; r = r + 1) begin
            for (s = 0; s < K; s = s + 1) begin
                pack_act_vec_for_rs(r, s);
                pack_wgt_vec_for_rs(r, s);
                @(posedge clk);
            end
        end
        
        #1 valid_in = 0;

        // Wait a few cycles for data to stabilize
        repeat (3) @(posedge clk);

        // ---------- Compare Hardware Result with Golden ----------
        err = 0;
        $display("==== Checking results ====");
        for (co = 0; co < TILE_C; co = co + 1) begin
            for (w0 = 0; w0 < TILE_W; w0 = w0 + 1) begin
                idx = co*TILE_W + w0;  // Flattened index
                hw  = psum_flat[idx*PSUM_W +: PSUM_W];
                if (hw !== golden[co][w0]) begin
                    $display("Mismatch at Co=%0d, w0=%0d: HW=%0d, GOLD=%0d",
                             co, w0, hw, golden[co][w0]);
                    err = err + 1;
                end
            end
        end

        if (err == 0)
            $display("==== TEST PASSED! All 64 outputs match. ====");
        else
            $display("==== TEST FAILED! %0d mismatches. ====", err);

        $finish;
    end

endmodule
