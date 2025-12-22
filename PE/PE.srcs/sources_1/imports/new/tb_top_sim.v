`timescale 1ns/1ps
// Testbench: tb_top_sim.v
// Loads data/parameters/conv1.real.dat and data/im1/conv1.input.dat (text hex) into behavioral memories
// Instantiates conv_agu_cw, pe_array, pe_drainer and drives signals for simulation.

module tb_top_sim;

`ifndef SYNTHESIS

    // Parameters - match conv_agu_cw defaults
    // Set parameters to first conv layer dimensions (conv1): c_in=1, c_out=32, h_in=32, w_in=32, k=5
    parameter H_IN       = 32;
    parameter W_IN       = 32;
    parameter C_IN       = 1;
    parameter C_OUT      = 32;
    parameter K          = 5;
    parameter TILE_C     = 8;
    parameter TILE_W     = 8;
    parameter DATA_W     = 8;
    parameter WGT_W      = 8;
    parameter PSUM_W     = 32;

    // Derived sizes
    localparam ACT_PLANE = H_IN * W_IN;
    localparam WGT_PLANE = K * K * C_OUT; // weights per Ci

    // Clock / reset
    reg clk = 0;
    always #5 clk = ~clk; // 100MHz

    // Monitor clock progress to help debug stalls
    integer cyc = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc % 1000 == 0)
            $display("[TB] posedge at %0t rst=%0b start=%0b done=%0b", $time, rst, start, done);
    end

    reg rst;
    reg start;

    // AGU outputs
    wire [15:0] act_read_base;
    wire [15:0] wgt_read_base;
    wire [15:0] out_write_base;
    wire out_we;
    wire [3:0] out_row_idx;
    wire data_ready;
    wire clear_psum;
    wire valid_in;
    wire pingpong_sel;
    wire [TILE_W-1:0] mask_w;
    wire done;

    // PE side
    wire [TILE_W*DATA_W-1:0] act_vec;
    wire [TILE_C*WGT_W-1:0]  wgt_vec;
    wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat;
    wire [TILE_W*DATA_W-1:0] drain_out_data;

    // Quantization params
    reg [3:0] q_act = 4'd0;
    reg [3:0] q_wgt = 4'd0;
    reg [3:0] q_out = 4'd0;

    // Instantiate AGU
    conv_agu_cw #(
        .H_IN(H_IN), .W_IN(W_IN), .C_IN(C_IN),
        .C_OUT(C_OUT), .K(K),
        .TILE_C(TILE_C), .TILE_W(TILE_W)
    ) u_agu (
        .clk(clk), .rst(rst), .start(start),
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

    // Behavioral memories
    // Activation memory: flattened I[c,h,w] in row-major as described (we expect hex/text)
    reg signed [DATA_W-1:0] MEM_ACT [0:C_IN*H_IN*W_IN-1];
    // Weight memory: flatten as K[c_in,h,w,c_out] => per Ci contiguous K*K*C_OUT
    reg signed [WGT_W-1:0] MEM_WGT [0:C_IN*WGT_PLANE-1];

    // Expected output memory (golden): byte-per-line hex for $readmemh
    // Generated from data/im1/conv1.output.dat
    localparam EXP_WORDS = 32768;
    reg signed [DATA_W-1:0] MEM_EXP [0:EXP_WORDS-1];

    integer i, j, idx;

    // Debug helpers: counts and first-n values
    integer nz_count_act, nz_first_act;
    integer nz_count_wgt, nz_first_wgt;
    integer x_count_act, x_count_wgt;
    integer nz_count_exp, nz_first_exp;
    integer x_count_exp;

    integer cmp_total_bytes;
    integer cmp_mismatch_count;
    integer cmp_oob_count;
    integer cmp_printed;
    integer cmp_got_nonzero;
    integer cmp_exp_nonzero;

    initial begin
        $display("Loading activation file: conv1_for_tb.mem");
        $readmemh("conv1_for_tb.mem", MEM_ACT);

        $display("Loading weight file: conv1_bin_for_tb.mem");
        $readmemh("conv1_bin_for_tb.mem", MEM_WGT);

        $display("Loading expected output file: conv1_output_for_tb.mem");
        $readmemh("conv1_output_for_tb.mem", MEM_EXP);

        $display("Memory load done.");

        $display("Memory load done at time %0t", $time);

        // Simple verification: count X, non-zero, and first-nonzero indices
        nz_count_act = 0; nz_first_act = -1; x_count_act = 0;
        nz_count_wgt = 0; nz_first_wgt = -1; x_count_wgt = 0;
        nz_count_exp = 0; nz_first_exp = -1; x_count_exp = 0;
        for (i = 0; i < C_IN*H_IN*W_IN; i = i + 1) begin
            if (MEM_ACT[i] === {DATA_W{1'bx}}) begin
                x_count_act = x_count_act + 1;
            end else if (MEM_ACT[i] !== {DATA_W{1'b0}}) begin
                nz_count_act = nz_count_act + 1;
                if (nz_first_act == -1) nz_first_act = i;
            end
        end
        for (i = 0; i < C_IN*WGT_PLANE; i = i + 1) begin
            if (MEM_WGT[i] === {WGT_W{1'bx}}) begin
                x_count_wgt = x_count_wgt + 1;
            end else if (MEM_WGT[i] !== {WGT_W{1'b0}}) begin
                nz_count_wgt = nz_count_wgt + 1;
                if (nz_first_wgt == -1) nz_first_wgt = i;
            end
        end
        for (i = 0; i < EXP_WORDS; i = i + 1) begin
            if (MEM_EXP[i] === {DATA_W{1'bx}}) begin
                x_count_exp = x_count_exp + 1;
            end else if (MEM_EXP[i] !== {DATA_W{1'b0}}) begin
                nz_count_exp = nz_count_exp + 1;
                if (nz_first_exp == -1) nz_first_exp = i;
            end
        end

        $display("MEM_ACT: total=%0d nonzero=%0d x_count=%0d first_nonzero=%0d", C_IN*H_IN*W_IN, nz_count_act, x_count_act, nz_first_act);
        $display("MEM_WGT: total=%0d nonzero=%0d x_count=%0d first_nonzero=%0d", C_IN*WGT_PLANE, nz_count_wgt, x_count_wgt, nz_first_wgt);
        $display("MEM_EXP: total=%0d nonzero=%0d x_count=%0d first_nonzero=%0d", EXP_WORDS, nz_count_exp, x_count_exp, nz_first_exp);

        cmp_total_bytes = 0;
        cmp_mismatch_count = 0;
        cmp_oob_count = 0;
        cmp_printed = 0;
        cmp_got_nonzero = 0;
        cmp_exp_nonzero = 0;

        // Dump first 16 entries for inspection
        $display("MEM_ACT[0..15]:");
        for (i = 0; i < 16; i = i + 1) $display("  [%0d] = %0d (0x%0h)", i, MEM_ACT[i], MEM_ACT[i]);
        $display("MEM_WGT[0..15]:");
        for (i = 0; i < 16; i = i + 1) $display("  [%0d] = %0d (0x%0h)", i, MEM_WGT[i], MEM_WGT[i]);
    end

    // Compare golden output against drainer output.
    // Use a 1-cycle delay on out_we/base/row/data to match typical registered drainer timing.
    reg out_we_d1;
    reg [15:0] out_write_base_d1;
    reg [3:0] out_row_idx_d1;
    reg [TILE_W*DATA_W-1:0] drain_out_data_d1;

    always @(posedge clk) begin
        if (rst) begin
            out_we_d1 <= 1'b0;
            out_write_base_d1 <= 16'd0;
            out_row_idx_d1 <= 4'd0;
            drain_out_data_d1 <= {TILE_W*DATA_W{1'b0}};
        end else begin
            out_we_d1 <= out_we;
            out_write_base_d1 <= out_write_base;
            out_row_idx_d1 <= out_row_idx;
            drain_out_data_d1 <= drain_out_data;
        end
    end

    always @(posedge clk) begin : OUT_COMPARE
        integer bi;
        integer addr;
        reg [DATA_W-1:0] got_b;
        reg [DATA_W-1:0] exp_b;

        if (!rst && out_we_d1) begin
            for (bi = 0; bi < TILE_W; bi = bi + 1) begin
                addr = out_write_base_d1 + bi;
                got_b = drain_out_data_d1[bi*DATA_W +: DATA_W];
                if (addr < 0 || addr >= EXP_WORDS) begin
                    cmp_oob_count = cmp_oob_count + 1;
                end else begin
                    exp_b = MEM_EXP[addr];
                    cmp_total_bytes = cmp_total_bytes + 1;
                    if (got_b !== {DATA_W{1'b0}}) cmp_got_nonzero = cmp_got_nonzero + 1;
                    if (exp_b !== {DATA_W{1'b0}}) cmp_exp_nonzero = cmp_exp_nonzero + 1;
                    if (exp_b !== got_b) begin
                        cmp_mismatch_count = cmp_mismatch_count + 1;
                        if (cmp_printed < 40) begin
                            $display("[CMP] t=%0t addr=%0d got=0x%0h exp=0x%0h out_row=%0d out_write_base=%0d lane=%0d", $time, addr, got_b, exp_b, out_row_idx_d1, out_write_base_d1, bi);
                            cmp_printed = cmp_printed + 1;
                        end
                    end
                end
            end
        end
    end

    // Act vector pipeline: simulate BRAM+buffer latency -> total 3 cycles to PE
    reg [TILE_W*DATA_W-1:0] act_vec_pipe [0:2];
    reg [TILE_W*DATA_W-1:0] act_vec_next;

    // On act_read_base valid (AGU produces during S_MAC), sample MEM_ACT and create 8-wide word
    always @(*) begin : ACT_PACK
        integer ii;
        integer base;
        act_vec_next = {TILE_W*DATA_W{1'b0}};
        base = $signed(act_read_base); // treat as signed (padding may produce negative addresses)

        for (ii = 0; ii < TILE_W; ii = ii + 1) begin
            if ((base + ii) >= 0 && (base + ii) < (C_IN*H_IN*W_IN))
                act_vec_next[ii*DATA_W +: DATA_W] = MEM_ACT[base + ii];
            else
                act_vec_next[ii*DATA_W +: DATA_W] = {DATA_W{1'b0}};
        end
    end

    // Drive pipeline registers
    always @(posedge clk) begin
        if (rst) begin
            act_vec_pipe[0] <= 0;
            act_vec_pipe[1] <= 0;
            act_vec_pipe[2] <= 0;
        end else begin
            // Load at stage0 when AGU in S_MAC - AGU does not expose state, but act_read_base changes only in S_MAC
            act_vec_pipe[0] <= act_vec_next;
            act_vec_pipe[1] <= act_vec_pipe[0];
            act_vec_pipe[2] <= act_vec_pipe[1];
        end
    end

    assign act_vec = act_vec_pipe[2]; // available at PE after 3 cycles

    // Weight vector pipeline: assume 1-cycle BRAM latency
    reg [TILE_C*WGT_W-1:0] wgt_vec_reg;
    reg [TILE_C*WGT_W-1:0] wgt_vec_next;

    always @(*) begin : WGT_PACK
        integer jj;
        integer base;
        wgt_vec_next = {TILE_C*WGT_W{1'b0}};
        base = wgt_read_base;
    
        for (jj = 0; jj < TILE_C; jj = jj + 1) begin
            if ((base + jj) >= 0 && (base + jj) < (C_IN*WGT_PLANE))
                wgt_vec_next[jj*WGT_W +: WGT_W] = MEM_WGT[base + jj];
            else
                wgt_vec_next[jj*WGT_W +: WGT_W] = {WGT_W{1'b0}};
        end
    end
    always @(posedge clk) begin
        if (rst) begin
            wgt_vec_reg <= 0;
        end else begin
            wgt_vec_reg <= wgt_vec_next;
        end
    end

    assign wgt_vec = wgt_vec_reg;

    // Instantiate PE Array and Drainer
    pe_array #(
        .TILE_C(TILE_C), .TILE_W(TILE_W), .DATA_W(DATA_W), .WGT_W(WGT_W), .PSUM_W(PSUM_W)
    ) u_pe_array (
        .clk(clk), .rst(rst), .act_vec(act_vec), .wgt_vec(wgt_vec), .valid_in(valid_in), .clear_psum(clear_psum), .psum_flat(psum_flat)
    );

    pe_drainer #(
        .TILE_C(TILE_C), .TILE_W(TILE_W), .PSUM_W(PSUM_W), .ACT_W(DATA_W)
    ) u_drainer (
        .clk(clk), .rst(rst), .data_ready(data_ready), .out_row_idx(out_row_idx),
        .q_act(q_act), .q_wgt(q_wgt), .q_out(q_out), .psum_flat(psum_flat), .drain_out_data(drain_out_data)
    );

    // Stimulus
    initial begin
        $dumpfile("tb_top_sim.vcd");
        $dumpvars(0, tb_top_sim);

        rst = 1; start = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Start AGU");
        @(posedge clk); start = 1; @(posedge clk); start = 0;

        // Wait for done
        wait(done == 1);
        $display("AGU done at time %0t", $time);
        // Wait some cycles for writeback finish
        repeat (20) @(posedge clk);
        $display("[CMP] total_bytes=%0d mismatches=%0d oob=%0d got_nonzero=%0d exp_nonzero=%0d", cmp_total_bytes, cmp_mismatch_count, cmp_oob_count, cmp_got_nonzero, cmp_exp_nonzero);
        $display("Simulation finished");
        $finish;
    end

`endif

endmodule
