`timescale 1ns/1ps

module tb_conv_agu_cw;

`ifndef SYNTHESIS

    // Parameters
    parameter H_IN        = 5;
    parameter W_IN        = 5;
    parameter C_IN        = 2;
    parameter C_OUT       = 2;
    parameter K           = 3;
    parameter TILE_C      = 2;
    parameter TILE_W      = 2;
    parameter ACT_ADDR_W  = 16;
    parameter WGT_ADDR_W  = 16;
    parameter OUT_ADDR_W  = 16;

    // Inputs
    reg clk;
    reg rst;
    reg start;

    // Outputs
    wire [ACT_ADDR_W-1:0] act_read_base;
    wire [WGT_ADDR_W-1:0] wgt_read_base;
    wire [OUT_ADDR_W-1:0] out_write_base;
    wire out_we;
    wire [3:0] out_row_idx;
    wire clear_psum;
    wire valid_in;
    wire pingpong_sel;
    wire done;

    // Instantiate the Unit Under Test (UUT)
    conv_agu_cw #(
        .H_IN(H_IN),
        .W_IN(W_IN),
        .C_IN(C_IN),
        .C_OUT(C_OUT),
        .K(K),
        .TILE_C(TILE_C),
        .TILE_W(TILE_W),
        .ACT_ADDR_W(ACT_ADDR_W),
        .WGT_ADDR_W(WGT_ADDR_W),
        .OUT_ADDR_W(OUT_ADDR_W)
    ) uut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .act_read_base(act_read_base),
        .wgt_read_base(wgt_read_base),
        .out_write_base(out_write_base),
        .out_we(out_we),
        .out_row_idx(out_row_idx),
        .clear_psum(clear_psum),
        .valid_in(valid_in),
        .pingpong_sel(pingpong_sel),
        .done(done)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz
    end

    // Test Logic
    initial begin
        // Initialize Inputs
        rst = 1;
        start = 0;

        // Wait 100 ns for global reset to finish
        #100;
        rst = 0;
        #20;

        $display("==== Test Start ====");
        $display("Params: H_IN=%0d, W_IN=%0d, C_IN=%0d, C_OUT=%0d, K=%0d, TILE_C=%0d, TILE_W=%0d", 
                 H_IN, W_IN, C_IN, C_OUT, K, TILE_C, TILE_W);

        // Start the AGU
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Monitor outputs
        // wait(done);
        while (!done) @(posedge clk);
        @(posedge clk);
        
        $display("==== Test Finished ====");
        $finish;
    end

    // Monitor process
    always @(posedge clk) begin
        if (valid_in) begin
            $display("Time=%0t | MAC Valid | ACT Base=%0d | WGT Base=%0d", 
                     $time, act_read_base, wgt_read_base);
        end
        if (out_we) begin
            $display("Time=%0t | WRITE En  | OUT Base=%0d | Row Idx=%0d", 
                     $time, out_write_base, out_row_idx);
        end
        if (clear_psum) begin
            $display("Time=%0t | CLEAR PSUM", $time);
        end
    end

`endif

endmodule
