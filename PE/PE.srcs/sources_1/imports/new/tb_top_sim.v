`timescale 1ns/1ps

module tb_top_sim;

`ifndef SYNTHESIS

    // -----------------------------
    // Parameters (conv1)
    // -----------------------------
    parameter H_IN   = 32;
    parameter W_IN   = 32;
    parameter C_IN   = 1;
    parameter C_OUT  = 32;
    parameter K      = 5;

    parameter TILE_C = 8;
    parameter TILE_W = 8;

    parameter DATA_W = 8;
    parameter WGT_W  = 8;
    parameter PSUM_W = 32;

    localparam integer ACT_PLANE = H_IN * W_IN;
    localparam integer WGT_PLANE = K * K * C_OUT; // per Ci

    // -----------------------------
    // Clock / Reset
    // -----------------------------
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst;
    reg start;

    integer cyc = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc % 1000 == 0)
            $display("[TB] t=%0t cyc=%0d rst=%0b start=%0b done=%0b", $time, cyc, rst, start, done);
    end

    // -----------------------------
    // AGU signals
    // -----------------------------
    wire [15:0] act_read_base;
    wire [15:0] wgt_read_base;
    wire [15:0] out_write_base;
    wire        out_we;
    wire [3:0]  out_row_idx;
    wire        data_ready;
    wire        clear_psum;
    wire        valid_in;
    wire        pingpong_sel;
    wire [TILE_W-1:0] mask_w;
    wire        done;

    // -----------------------------
    // PE/Drainer signals
    // -----------------------------
    wire [TILE_W*DATA_W-1:0] act_vec;
    wire [TILE_C*WGT_W-1:0]  wgt_vec;
    wire [TILE_C*TILE_W*PSUM_W-1:0] psum_flat;
    wire [TILE_W*DATA_W-1:0] drain_out_data;

    // Quantization
    reg [3:0] q_act = 0, q_wgt = 0, q_out = 0;

    // -----------------------------
    // Instantiate AGU
    // -----------------------------
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

    // -----------------------------
    // Behavioral memories (loaded by $readmemh)
    // -----------------------------
    reg signed [DATA_W-1:0] MEM_ACT [0:C_IN*H_IN*W_IN-1];
    reg signed [WGT_W-1:0]  MEM_WGT [0:C_IN*WGT_PLANE-1];

    localparam integer EXP_WORDS = 32768; // 32*32*32
    reg signed [DATA_W-1:0] MEM_EXP [0:EXP_WORDS-1];

    integer i;

    initial begin
        $display("Loading activation file: conv1_for_tb.mem");
        $readmemh("conv1_for_tb.mem", MEM_ACT);

        $display("Loading weight file: conv1_bin_for_tb.mem");
        $readmemh("conv1_bin_for_tb.mem", MEM_WGT);

        $display("Loading expected output file: conv1_output_for_tb.mem");
        $readmemh("conv1_output_for_tb.mem", MEM_EXP);

        $display("Memory load done at t=%0t", $time);
        $display("MEM_ACT[0]=0x%0h MEM_WGT[0]=0x%0h MEM_EXP[0]=0x%0h", MEM_ACT[0], MEM_WGT[0], MEM_EXP[0]);
    end

    // ============================================================
    // Pack ACT -> act_vec with padding clamp
    // Model latency: 3 cycles (likeÄãÖ®Ç°µÄ tb)
    // ============================================================
    reg [TILE_W*DATA_W-1:0] act_vec_next;
    reg [TILE_W*DATA_W-1:0] act_pipe0, act_pipe1, act_pipe2;

    always @(*) begin : ACT_PACK
        integer lane;
        integer base;
        act_vec_next = {TILE_W*DATA_W{1'b0}};

        // treat act_read_base as signed because AGU may emit negative for padding
        base = $signed(act_read_base);

        for (lane = 0; lane < TILE_W; lane = lane + 1) begin
            if ((base + lane) >= 0 && (base + lane) < (C_IN*H_IN*W_IN))
                act_vec_next[lane*DATA_W +: DATA_W] = MEM_ACT[base + lane];
            else
                act_vec_next[lane*DATA_W +: DATA_W] = {DATA_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            act_pipe0 <= 0;
            act_pipe1 <= 0;
            act_pipe2 <= 0;
        end else begin
            act_pipe0 <= act_vec_next;
            act_pipe1 <= act_pipe0;
            act_pipe2 <= act_pipe1;
        end
    end

    assign act_vec = act_pipe2;

    // ============================================================
    // Pack WGT -> wgt_vec
    // Model latency: 2 cycles (Æ¥ÅäÄã IP summary: read latency = 2)
    // ============================================================
    reg [TILE_C*WGT_W-1:0] wgt_vec_next;
    reg [TILE_C*WGT_W-1:0] wgt_pipe0, wgt_pipe1, wgt_pipe2;

    always @(*) begin : WGT_PACK
        integer lane;
        integer base;
        wgt_vec_next = {TILE_C*WGT_W{1'b0}};

        base = wgt_read_base; // unsigned is fine (weights have no padding negative addr)

        for (lane = 0; lane < TILE_C; lane = lane + 1) begin
            if ((base + lane) >= 0 && (base + lane) < (C_IN*WGT_PLANE))
                wgt_vec_next[lane*WGT_W +: WGT_W] = MEM_WGT[base + lane];
            else
                wgt_vec_next[lane*WGT_W +: WGT_W] = {WGT_W{1'b0}};
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            wgt_pipe0 <= 0;
            wgt_pipe1 <= 0;
            wgt_pipe2 <= 0;
        end else begin
            wgt_pipe0 <= wgt_vec_next;
            wgt_pipe1 <= wgt_pipe0;
            wgt_pipe2 <= wgt_pipe1;
        end
    end

    assign wgt_vec = wgt_pipe2;

    // -----------------------------
    // Instantiate PE + Drainer
    // -----------------------------
    pe_array_with_bram #(
        .TILE_C(TILE_C), .TILE_W(TILE_W),
        .DATA_W(DATA_W), .WGT_W(WGT_W), .PSUM_W(PSUM_W)
    ) u_pe_array (
        .clk(clk), .rst(rst),
        .act_vec(act_vec),
        .wgt_vec(wgt_vec),
        .valid_in(valid_in),
        .clear_psum(clear_psum),
        .psum_flat(psum_flat)
    );

    pe_drainer #(
        .TILE_C(TILE_C), .TILE_W(TILE_W),
        .PSUM_W(PSUM_W), .ACT_W(DATA_W)
    ) u_drainer (
        .clk(clk), .rst(rst),
        .data_ready(data_ready),
        .out_row_idx(out_row_idx),
        .q_act(q_act), .q_wgt(q_wgt), .q_out(q_out),
        .psum_flat(psum_flat),
        .drain_out_data(drain_out_data)
    );

    // ============================================================
    // Compare against golden
    // ============================================================
    reg out_we_d1;
    reg [15:0] out_write_base_d1;
    reg [3:0]  out_row_idx_d1;
    reg [TILE_W*DATA_W-1:0] drain_out_data_d1;

    integer cmp_total, cmp_mismatch, cmp_printed;

    always @(posedge clk) begin
        if (rst) begin
            out_we_d1 <= 0;
            out_write_base_d1 <= 0;
            out_row_idx_d1 <= 0;
            drain_out_data_d1 <= 0;
        end else begin
            out_we_d1 <= out_we;
            out_write_base_d1 <= out_write_base;
            out_row_idx_d1 <= out_row_idx;
            drain_out_data_d1 <= drain_out_data;
        end
    end

    always @(posedge clk) begin : OUT_CMP
        integer lane;
        integer addr;
        reg [DATA_W-1:0] got_b;
        reg [DATA_W-1:0] exp_b;

        if (!rst && out_we_d1) begin
            for (lane = 0; lane < TILE_W; lane = lane + 1) begin
                addr = out_write_base_d1 + lane;
                got_b = drain_out_data_d1[lane*DATA_W +: DATA_W];
                exp_b = MEM_EXP[addr];

                cmp_total = cmp_total + 1;
                if (got_b !== exp_b) begin
                    cmp_mismatch = cmp_mismatch + 1;
                    if (cmp_printed < 40) begin
                        $display("[CMP] t=%0t addr=%0d got=%0h exp=%0h row=%0d base=%0d lane=%0d",
                                 $time, addr, got_b, exp_b, out_row_idx_d1, out_write_base_d1, lane);
                        cmp_printed = cmp_printed + 1;
                    end
                end
            end
        end
    end

    // -----------------------------
    // Stimulus
    // -----------------------------
    initial begin
        $dumpfile("tb_top_sim.vcd");
        $dumpvars(0, tb_top_sim);

        cmp_total    = 0;
        cmp_mismatch = 0;
        cmp_printed  = 0;

        rst = 1; start = 0;
        repeat (10) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("Start AGU");
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;

        wait(done == 1);
        $display("DONE at t=%0t", $time);

        repeat (30) @(posedge clk);
        $display("[CMP SUMMARY] total=%0d mismatch=%0d", cmp_total, cmp_mismatch);
        $finish;
    end

`endif
endmodule
