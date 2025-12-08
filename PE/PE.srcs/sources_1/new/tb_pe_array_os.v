`timescale 1ns/1ps

module tb_pe_array_os;

    localparam N       = 8;    // 8x8 outputs
    localparam K       = 3;    // 3x3 kernel
    localparam DATA_W  = 8;
    localparam WGT_W   = 8;
    localparam PSUM_W  = 32;
    localparam ACT_W   = N*N*DATA_W;          // 8*8*8 = 512
    localparam IN_H    = N + K - 1;           // Input feature map height = 10
    localparam IN_W    = N + K - 1;           // Width = 10
    localparam IN_SIZE = IN_H * IN_W;         // 100

    reg clk = 0;
    always #5 clk = ~clk; // 100MHz

    reg rst;
    reg valid_in;
    reg clear_psum;

    reg  [ACT_W-1:0] act_flat;   // 8x8 sub-blocks, each broadcast once
    reg  [WGT_W-1:0] wgt_scalar; // Current kernel element

    wire [N*N*PSUM_W-1:0] psum_out;

    // ------------------ DUT ------------------
    pe_array_with_bram #(
        .N      (N),
        .DATA_W (DATA_W),
        .WGT_W  (WGT_W),
        .PSUM_W (PSUM_W),
        .ACT_W  (ACT_W)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .act_flat  (act_flat),
        .wgt_scalar(wgt_scalar),
        .valid_in  (valid_in),
        .clear_psum(clear_psum),
        .psum_out  (psum_out)
    );

    // ====== Test Data ======

    // Input feature map A, 10x10 flattened to 1D
    reg signed [DATA_W-1:0] A      [0:IN_SIZE-1];
    // 3x3 kernel flattened
    reg signed [WGT_W-1:0]  KERNEL [0:K*K-1];
    // Golden result 8x8 flattened
    reg signed [PSUM_W-1:0] golden [0:N*N-1];

    integer i, j, r, s;
    integer val;
    integer gidx;
    integer err;
    integer oidx;
    reg signed [PSUM_W-1:0] hw;

    // Map (y,x) to 1D index of A
    function integer idxA;
        input integer y;
        input integer x;
        begin
            idxA = y*IN_W + x;
        end
    endfunction

    // Map (i,j) to 1D index of output/psum_out
    function integer idxO;
        input integer y;
        input integer x;
        begin
            idxO = y*N + x;
        end
    endfunction

    // Pack A[i+r][j+s] into act_flat (8x8) for current (r,s)
    task pack_act_flat_for_rs;
        input integer r_off;
        input integer s_off;
        integer yy, xx;
        integer out_idx;
        begin
            for (yy = 0; yy < N; yy = yy + 1) begin
                for (xx = 0; xx < N; xx = xx + 1) begin
                    out_idx = idxO(yy, xx);
                    act_flat[out_idx*DATA_W +: DATA_W] =
                        A[idxA(yy + r_off, xx + s_off)];
                end
            end
        end
    endtask

    initial begin
        $display("==== TB: 8x8 OS PE array test start ====");

        rst        = 1;
        valid_in   = 0;
        clear_psum = 0;
        act_flat   = 0;
        wgt_scalar = 0;

        // Reset
        repeat (3) @(posedge clk);
        rst = 0;

        // ---------- Initialize feature map A ----------
        // 10x10: A[y][x] = y*IN_W + x
        for (i = 0; i < IN_H; i = i + 1) begin
            for (j = 0; j < IN_W; j = j + 1) begin
                A[idxA(i,j)] = i*IN_W + j;
            end
        end

        // ---------- Initialize kernel ----------
        // KERNEL 3x3 = [1..9]
        val = 1;
        for (i = 0; i < K*K; i = i + 1) begin
            KERNEL[i] = val;
            val = val + 1;
        end

        // ---------- Compute Golden Result ----------
        // golden[i,j] = sum_{r,s} A[i+r, j+s] * K[r,s]
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                gidx = idxO(i,j);
                golden[gidx] = 0;

                for (r = 0; r < K; r = r + 1) begin
                    for (s = 0; s < K; s = s + 1) begin
                        golden[gidx] = golden[gidx] +
                            A[idxA(i+r, j+s)] * KERNEL[r*K + s];
                    end
                end
            end
        end

        $display("==== Golden model computed. Start hardware run ====");

        // ---------- Clear PSUM ----------
        clear_psum = 1;
        @(posedge clk);
        clear_psum = 0;

        // ---------- 9 cycles, corresponding to 3x3 kernel (r,s) ----------
        valid_in = 1;

        for (r = 0; r < K; r = r + 1) begin
            for (s = 0; s < K; s = s + 1) begin
                // Set current kernel element
                wgt_scalar = KERNEL[r*K + s];
                // Pack 8x8 A[i+r][j+s] with current offset
                pack_act_flat_for_rs(r, s);

                @(posedge clk);
            end
        end

        #1 valid_in = 0;

        // Wait a few cycles for pipeline to stabilize
        repeat (3) @(posedge clk);

        // ---------- Compare Hardware Result with Golden ----------
        err = 0;

        $display("==== Checking results ====");
        for (i = 0; i < N; i = i + 1) begin
            for (j = 0; j < N; j = j + 1) begin
                oidx = idxO(i,j);
                hw   = psum_out[oidx*PSUM_W +: PSUM_W];

                if (hw !== golden[oidx]) begin
                    $display("Mismatch at (%0d,%0d): HW=%0d, GOLD=%0d",
                             i, j, hw, golden[oidx]);
                    err = err + 1;
                end
            end
        end

        if (err == 0) begin
            $display("==== TEST PASSED! All 64 outputs match. ====");
        end else begin
            $display("==== TEST FAILED! %0d mismatches. ====", err);
        end

        $finish;
    end

endmodule
