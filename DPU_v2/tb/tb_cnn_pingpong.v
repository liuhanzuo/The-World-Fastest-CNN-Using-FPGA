`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench: tb_cnn_pingpong
// Description: 测试使用全局共享Ping-Pong BRAM架构的CNN
//              这是真正的端到端测试：所有层共享两个全局BRAM Bank
//
// Ping-Pong BRAM架构:
//   Conv1:   读Bank0(输入图像) -> 写Bank1
//   Pool1:   读Bank1 -> 写Bank0
//   Conv2:   读Bank0 -> 写Bank1
//   Conv3:   读Bank1 -> 写Bank0
//   Conv4:   读Bank0 -> 写Bank1
//   AvgPool: 读Bank1 -> 写Bank0
//   FC:      读Bank0 -> 输出
//////////////////////////////////////////////////////////////////////////////////

module tb_cnn_pingpong;

    // ============================================================
    // Parameters
    // ============================================================
    parameter DATA_W = 8;
    parameter TILE_C = 8;
    parameter TILE_W = 8;
    parameter ADDR_W = 16;
    
    // ============================================================
    // Clock and Reset
    // ============================================================
    reg clk;
    reg rst;  // 低电平复位 (resetn)
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk;  // 100MHz
    end
    
    // ============================================================
    // 测试数据存储 (64-bit words)
    // ============================================================
    // Conv1 权重
    reg [63:0] conv1_wgt_raw [0:99];      // 800/8 = 100 words
    // Conv1 输入 (64-bit words)
    reg [63:0] conv1_in_raw [0:127];      // 1024/8 = 128 words
    
    // Conv2 权重
    reg [63:0] conv2_wgt_raw [0:2303];    // 18432/8 = 2304 words
    
    // Conv3 权重
    reg [63:0] conv3_wgt_raw [0:4607];    // 36864/8 = 4608 words
    
    // Conv4 权重
    reg [63:0] conv4_wgt_raw [0:9215];    // 73728/8 = 9216 words
    
    // FC 权重
    reg signed [DATA_W-1:0] fc_wgt_raw [0:1279];  // 10*128 = 1280 bytes
    
    // 期望输出 (用于验证)
    reg [63:0] conv1_exp_raw [0:4095];    // 32768/8 = 4096 words
    reg [63:0] pool1_exp_raw [0:1023];    // 8192/8 = 1024 words
    reg [63:0] conv2_exp_raw [0:2047];    // 16384/8 = 2048 words
    reg [63:0] conv3_exp_raw [0:511];     // 4096/8 = 512 words
    reg [63:0] conv4_exp_raw [0:255];     // 2048/8 = 256 words
    reg [63:0] avgpool_exp_raw [0:15];    // 128/8 = 16 words
    reg signed [DATA_W-1:0] fc_exp_raw [0:9];  // 10 bytes
    
    // ============================================================
    // CNN Top Instance (Ping-Pong BRAM Architecture)
    // ============================================================
    reg start;
    
    // 输入图像加载接口
    reg img_we;
    reg [ADDR_W-1:0] img_addr;
    reg [DATA_W-1:0] img_data;
    
    // 权重加载接口
    reg conv1_wgt_we, conv2_wgt_we, conv3_wgt_we, conv4_wgt_we, fc_wgt_we;
    reg [ADDR_W-1:0] conv1_wgt_addr, conv2_wgt_addr, conv3_wgt_addr, conv4_wgt_addr, fc_wgt_addr;
    reg [TILE_C*DATA_W-1:0] conv1_wgt_data, conv2_wgt_data, conv3_wgt_data, conv4_wgt_data;
    reg [DATA_W-1:0] fc_wgt_data;
    
    // 输出
    wire [3:0] pred_class;
    wire signed [DATA_W-1:0] pred_score;
    wire done;
    
    cnn_top #(
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W),
        .TILE_W(TILE_W),
        .TILE_C(TILE_C)
    ) u_cnn_top (
        .clk(clk),
        .resetn(rst),
        .start(start),
        
        // 输入图像
        .img_we(img_we),
        .img_addr(img_addr),
        .img_data(img_data),
        
        // Conv1权重
        .conv1_wgt_we(conv1_wgt_we),
        .conv1_wgt_addr(conv1_wgt_addr),
        .conv1_wgt_data(conv1_wgt_data),
        
        // Conv2权重
        .conv2_wgt_we(conv2_wgt_we),
        .conv2_wgt_addr(conv2_wgt_addr),
        .conv2_wgt_data(conv2_wgt_data),
        
        // Conv3权重
        .conv3_wgt_we(conv3_wgt_we),
        .conv3_wgt_addr(conv3_wgt_addr),
        .conv3_wgt_data(conv3_wgt_data),
        
        // Conv4权重
        .conv4_wgt_we(conv4_wgt_we),
        .conv4_wgt_addr(conv4_wgt_addr),
        .conv4_wgt_data(conv4_wgt_data),
        
        // FC权重
        .fc_wgt_we(fc_wgt_we),
        .fc_wgt_addr(fc_wgt_addr),
        .fc_wgt_data(fc_wgt_data),
        
        // 输出
        .pred_class(pred_class),
        .pred_score(pred_score),
        .done(done)
    );
    
    // ============================================================
    // 中间层结果验证（直接访问全局BRAM）
    // ============================================================
    integer i, j;
    integer match_cnt, mismatch_cnt;
    reg signed [DATA_W-1:0] actual_byte, expect_byte;
    integer expected_class;
    reg [3:0] layer_pass;  // 各层是否通过
    
    // ============================================================
    // 时间测量变量
    // ============================================================
    integer cycle_counter;           // 全局时钟周期计数器
    integer start_cycle;             // 推理开始时的周期数
    integer conv1_start, conv1_end;  // Conv1 开始/结束周期
    integer pool1_start, pool1_end;  // Pool1 开始/结束周期
    integer conv2_start, conv2_end;  // Conv2 开始/结束周期
    integer conv3_start, conv3_end;  // Conv3 开始/结束周期
    integer conv4_start, conv4_end;  // Conv4 开始/结束周期
    integer avgpool_start, avgpool_end;  // AvgPool 开始/结束周期
    integer fc_start, fc_end;        // FC 开始/结束周期
    integer total_inference_cycles;  // 总推理周期数
    real time_per_layer_us;          // 每层时间(us)
    real total_time_us;              // 总时间(us)
    real throughput;                 // 吞吐量 (images/s)
    
    // 时钟周期计数器
    always @(posedge clk or negedge rst) begin
        if (!rst)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;
    end
    
    // ============================================================
    // 主测试流程
    // ============================================================
    initial begin
        $display("================================================================");
        $display("  Ping-Pong BRAM CNN Hardware Simulation (im1)");
        $display("================================================================");
        $display("");
        $display("Architecture: Global Shared Ping-Pong BRAM");
        $display("  - Bank0 and Bank1 are shared by all layers");
        $display("  - Each layer reads from one bank, writes to the other");
        $display("  - No layer has its own internal activation BRAM");
        $display("");
        $display("Ping-Pong Schedule:");
        $display("  Conv1:   Read Bank0 -> Write Bank1");
        $display("  Pool1:   Read Bank1 -> Write Bank0");
        $display("  Conv2:   Read Bank0 -> Write Bank1");
        $display("  Conv3:   Read Bank1 -> Write Bank0");
        $display("  Conv4:   Read Bank0 -> Write Bank1");
        $display("  AvgPool: Read Bank1 -> Write Bank0");
        $display("  FC:      Read Bank0 -> Output");
        $display("================================================================");
        
        // 初始化
        rst = 0;  // 复位激活
        start = 0;
        img_we = 0;
        conv1_wgt_we = 0; conv2_wgt_we = 0;
        conv3_wgt_we = 0; conv4_wgt_we = 0;
        fc_wgt_we = 0;
        layer_pass = 0;
        
        // 加载测试数据
        $display("\n[Loading test data...]");
        $readmemh("scripts/sim_data/im1/conv1_act.hex", conv1_in_raw);
        $readmemh("scripts/sim_data/im1/conv1_wgt.hex", conv1_wgt_raw);
        $readmemh("scripts/sim_data/im1/conv1_exp.hex", conv1_exp_raw);
        $readmemh("scripts/sim_data/im1/pool1_exp.hex", pool1_exp_raw);
        $readmemh("scripts/sim_data/im1/conv2_wgt.hex", conv2_wgt_raw);
        $readmemh("scripts/sim_data/im1/conv2_exp.hex", conv2_exp_raw);
        $readmemh("scripts/sim_data/im1/conv3_wgt.hex", conv3_wgt_raw);
        $readmemh("scripts/sim_data/im1/conv3_exp.hex", conv3_exp_raw);
        $readmemh("scripts/sim_data/im1/conv4_wgt.hex", conv4_wgt_raw);
        $readmemh("scripts/sim_data/im1/conv4_exp.hex", conv4_exp_raw);
        $readmemh("scripts/sim_data/im1/avgpool_exp.hex", avgpool_exp_raw);
        $readmemh("scripts/sim_data/im1/fc_wgt.hex", fc_wgt_raw);
        $readmemh("scripts/sim_data/im1/fc_exp.hex", fc_exp_raw);
        
        #100;
        rst = 1;  // 释放复位
        #20;
        
        // ========================================
        // Step 1: 加载输入图像到Bank0
        // ========================================
        $display("\n--- Loading input image to Bank0 ---");
        for (i = 0; i < 128; i = i + 1) begin
            // 每个 64-bit word 包含 8 字节
            for (j = 0; j < 8; j = j + 1) begin
                @(posedge clk); #1;
                img_we = 1;
                img_addr = i * 8 + j;
                img_data = conv1_in_raw[i][j*8 +: 8];
            end
        end
        @(posedge clk); #1; img_we = 0;
        $display("  Input image loaded: 1x32x32 = 1024 bytes");
        
        // ========================================
        // Step 2: 加载所有权重
        // ========================================
        $display("\n--- Loading all weights ---");
        
        // Conv1 权重 (800 bytes = 100 words)
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk); #1;
            conv1_wgt_we = 1;
            conv1_wgt_addr = i;
            conv1_wgt_data = conv1_wgt_raw[i];
        end
        @(posedge clk); #1; conv1_wgt_we = 0;
        $display("  Conv1 weights: 32x1x5x5 = 800 bytes");
        
        // Conv2 权重 (18432 bytes = 2304 words)
        for (i = 0; i < 2304; i = i + 1) begin
            @(posedge clk); #1;
            conv2_wgt_we = 1;
            conv2_wgt_addr = i;
            conv2_wgt_data = conv2_wgt_raw[i];
        end
        @(posedge clk); #1; conv2_wgt_we = 0;
        $display("  Conv2 weights: 64x32x3x3 = 18432 bytes");
        
        // Conv3 权重 (36864 bytes = 4608 words)
        for (i = 0; i < 4608; i = i + 1) begin
            @(posedge clk); #1;
            conv3_wgt_we = 1;
            conv3_wgt_addr = i;
            conv3_wgt_data = conv3_wgt_raw[i];
        end
        @(posedge clk); #1; conv3_wgt_we = 0;
        $display("  Conv3 weights: 64x64x3x3 = 36864 bytes");
        
        // Conv4 权重 (73728 bytes = 9216 words)
        for (i = 0; i < 9216; i = i + 1) begin
            @(posedge clk); #1;
            conv4_wgt_we = 1;
            conv4_wgt_addr = i;
            conv4_wgt_data = conv4_wgt_raw[i];
        end
        @(posedge clk); #1; conv4_wgt_we = 0;
        $display("  Conv4 weights: 128x64x3x3 = 73728 bytes");
        
        // FC 权重 (1280 bytes)
        for (i = 0; i < 1280; i = i + 1) begin
            @(posedge clk); #1;
            fc_wgt_we = 1;
            fc_wgt_addr = i;
            fc_wgt_data = fc_wgt_raw[i];
        end
        @(posedge clk); #1; fc_wgt_we = 0;
        $display("  FC weights: 10x128 = 1280 bytes");
        
        // ========================================
        // Step 3: 启动CNN推理
        // ========================================
        $display("\n================================================================");
        $display("  Starting CNN Inference (all layers use shared BRAM)");
        $display("================================================================");
        
        // 记录推理开始时间
        @(posedge clk); 
        start_cycle = cycle_counter;
        conv1_start = cycle_counter;
        start = 1;
        @(posedge clk); start = 0;
        
        // 监视状态变化并记录时间
        fork
            begin
                // 监视Conv1完成
                wait(u_cnn_top.conv1_done);
                conv1_end = cycle_counter;
                pool1_start = cycle_counter;
                $display("\n--- [Layer 1] Conv1 completed @ cycle %0d (took %0d cycles) ---", conv1_end, conv1_end - conv1_start);
                verify_conv1();
            end
            begin
                // 监视Pool1完成
                wait(u_cnn_top.pool1_done);
                pool1_end = cycle_counter;
                conv2_start = cycle_counter;
                $display("\n--- [Layer 2] Pool1 completed @ cycle %0d (took %0d cycles) ---", pool1_end, pool1_end - pool1_start);
                verify_pool1();
            end
            begin
                // 监视Conv2完成
                wait(u_cnn_top.conv2_done);
                conv2_end = cycle_counter;
                conv3_start = cycle_counter;
                $display("\n--- [Layer 3] Conv2 completed @ cycle %0d (took %0d cycles) ---", conv2_end, conv2_end - conv2_start);
                verify_conv2();
            end
            begin
                // 监视Conv3完成
                wait(u_cnn_top.conv3_done);
                conv3_end = cycle_counter;
                conv4_start = cycle_counter;
                $display("\n--- [Layer 4] Conv3 completed @ cycle %0d (took %0d cycles) ---", conv3_end, conv3_end - conv3_start);
                verify_conv3();
            end
            begin
                // 监视Conv4完成
                wait(u_cnn_top.conv4_done);
                conv4_end = cycle_counter;
                avgpool_start = cycle_counter;
                $display("\n--- [Layer 5] Conv4 completed @ cycle %0d (took %0d cycles) ---", conv4_end, conv4_end - conv4_start);
                verify_conv4();
            end
            begin
                // 监视AvgPool完成
                wait(u_cnn_top.avgpool_done);
                avgpool_end = cycle_counter;
                fc_start = cycle_counter;
                $display("\n--- [Layer 6] AvgPool completed @ cycle %0d (took %0d cycles) ---", avgpool_end, avgpool_end - avgpool_start);
                verify_avgpool();
            end
        join_none
        
        // 等待整个网络完成
        wait(done);
        fc_end = cycle_counter;
        total_inference_cycles = fc_end - start_cycle;
        $display("\n--- [Layer 7] FC completed @ cycle %0d (took %0d cycles) ---", fc_end, fc_end - fc_start);
        
        // ========================================
        // 验证最终结果
        // ========================================
        // 找到期望的类别
        expected_class = 0;
        for (i = 1; i < 10; i = i + 1) begin
            if (fc_exp_raw[i] > fc_exp_raw[expected_class])
                expected_class = i;
        end
        
        $display("  Predicted class: %0d (score=%0d)", pred_class, pred_score);
        $display("  Expected class:  %0d (score=%0d)", expected_class, fc_exp_raw[expected_class]);
        
        if (pred_class == expected_class) begin
            $display("  [PASSED] FC - Prediction CORRECT!");
            layer_pass[6] = 1;
        end else begin
            $display("  [FAILED] FC - Prediction INCORRECT");
        end
        
        // ========================================
        // 总结
        // ========================================
        #100;
        $display("\n================================================================");
        $display("                    TEST SUMMARY");
        $display("================================================================");
        $display("  Architecture: Ping-Pong Shared BRAM (2 Banks)");
        $display("  Total BRAM: 2 x 32KB = 64KB (shared by all layers)");
        $display("");
        $display("  Layer Results:");
        $display("    1. Conv1:   %s", layer_pass[0] ? "PASSED" : "FAILED");
        $display("    2. Pool1:   %s", layer_pass[1] ? "PASSED" : "FAILED");
        $display("    3. Conv2:   %s", layer_pass[2] ? "PASSED" : "FAILED");
        $display("    4. Conv3:   %s", layer_pass[3] ? "PASSED" : "FAILED");
        $display("    5. Conv4:   %s", layer_pass[4] ? "PASSED" : "FAILED");
        $display("    6. AvgPool: %s", layer_pass[5] ? "PASSED" : "FAILED");
        $display("    7. FC:      %s", layer_pass[6] ? "PASSED" : "FAILED");
        $display("");
        
        if (layer_pass == 7'b1111111) begin
            $display("  ****************************************************");
            $display("  *  ALL LAYERS PASSED - PING-PONG BRAM SUCCESS!     *");
            $display("  ****************************************************");
        end else begin
            $display("  !!! SOME LAYERS FAILED !!!");
        end
        $display("================================================================");
        
        // ========================================
        // 详细时间报告
        // ========================================
        total_time_us = total_inference_cycles * 0.01;  // 100MHz -> 10ns per cycle -> 0.01us per cycle
        throughput = 1000000.0 / total_time_us;  // images per second
        
        $display("");
        $display("================================================================");
        $display("                    TIMING REPORT");
        $display("================================================================");
        $display("  Clock Frequency: 100 MHz (10 ns period)");
        $display("");
        $display("  Per-Layer Cycle Count:");
        $display("    +-----------+------------+------------+-----------+");
        $display("    | Layer     | Cycles     | Time (us)  | Time (ms) |");
        $display("    +-----------+------------+------------+-----------+");
        $display("    | Conv1     | %10d | %10.2f | %9.4f |", conv1_end - conv1_start, (conv1_end - conv1_start) * 0.01, (conv1_end - conv1_start) * 0.00001);
        $display("    | Pool1     | %10d | %10.2f | %9.4f |", pool1_end - pool1_start, (pool1_end - pool1_start) * 0.01, (pool1_end - pool1_start) * 0.00001);
        $display("    | Conv2     | %10d | %10.2f | %9.4f |", conv2_end - conv2_start, (conv2_end - conv2_start) * 0.01, (conv2_end - conv2_start) * 0.00001);
        $display("    | Conv3     | %10d | %10.2f | %9.4f |", conv3_end - conv3_start, (conv3_end - conv3_start) * 0.01, (conv3_end - conv3_start) * 0.00001);
        $display("    | Conv4     | %10d | %10.2f | %9.4f |", conv4_end - conv4_start, (conv4_end - conv4_start) * 0.01, (conv4_end - conv4_start) * 0.00001);
        $display("    | AvgPool   | %10d | %10.2f | %9.4f |", avgpool_end - avgpool_start, (avgpool_end - avgpool_start) * 0.01, (avgpool_end - avgpool_start) * 0.00001);
        $display("    | FC        | %10d | %10.2f | %9.4f |", fc_end - fc_start, (fc_end - fc_start) * 0.01, (fc_end - fc_start) * 0.00001);
        $display("    +-----------+------------+------------+-----------+");
        $display("    | TOTAL     | %10d | %10.2f | %9.4f |", total_inference_cycles, total_time_us, total_time_us / 1000.0);
        $display("    +-----------+------------+------------+-----------+");
        $display("");
        $display("  Performance Metrics:");
        $display("    - Total Inference Time: %.4f ms", total_time_us / 1000.0);
        $display("    - Throughput: %.2f images/second @ 100MHz", throughput);
        $display("    - Latency: %0d clock cycles", total_inference_cycles);
        $display("================================================================");
        
        #100;
        $finish;
    end
    
    // ============================================================
    // 验证任务：检查各层输出
    // ============================================================
    
    // Conv1: 输出在Bank1 (32x32x32 = 32768 bytes = 4096 words)
    task verify_conv1;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 4096; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank1[vi];
            expect_word = conv1_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank1: Match %0d/%0d (%.1f%%)", 
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] Conv1");
            layer_pass[0] = 1;
        end else begin
            $display("  [FAILED] Conv1 - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // Pool1: 输出在Bank0 (32x16x16 = 8192 bytes = 1024 words)
    task verify_pool1;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 1024; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank0[vi];
            expect_word = pool1_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank0: Match %0d/%0d (%.1f%%)",
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] Pool1");
            layer_pass[1] = 1;
        end else begin
            $display("  [FAILED] Pool1 - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // Conv2: 输出在Bank1 (64x16x16 = 16384 bytes = 2048 words)
    task verify_conv2;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 2048; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank1[vi];
            expect_word = conv2_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank1: Match %0d/%0d (%.1f%%)",
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] Conv2");
            layer_pass[2] = 1;
        end else begin
            $display("  [FAILED] Conv2 - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // Conv3: 输出在Bank0 (64x8x8 = 4096 bytes = 512 words)
    task verify_conv3;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 512; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank0[vi];
            expect_word = conv3_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank0: Match %0d/%0d (%.1f%%)",
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] Conv3");
            layer_pass[3] = 1;
        end else begin
            $display("  [FAILED] Conv3 - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // Conv4: 输出在Bank1 (128x4x4 = 2048 bytes = 256 words)
    task verify_conv4;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 256; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank1[vi];
            expect_word = conv4_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank1: Match %0d/%0d (%.1f%%)",
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] Conv4");
            layer_pass[4] = 1;
        end else begin
            $display("  [FAILED] Conv4 - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // AvgPool: 输出在Bank0 (128 bytes = 16 words)
    task verify_avgpool;
        integer vi, vj;
        integer vmatch, vmismatch;
        reg [63:0] actual_word, expect_word;
    begin
        vmatch = 0; vmismatch = 0;
        for (vi = 0; vi < 16; vi = vi + 1) begin
            actual_word = u_cnn_top.bram_bank0[vi];
            expect_word = avgpool_exp_raw[vi];
            for (vj = 0; vj < 8; vj = vj + 1) begin
                if (actual_word[vj*8 +: 8] == expect_word[vj*8 +: 8])
                    vmatch = vmatch + 1;
                else
                    vmismatch = vmismatch + 1;
            end
        end
        $display("  Output in Bank0: Match %0d/%0d (%.1f%%)",
                 vmatch, vmatch+vmismatch, 100.0*vmatch/(vmatch+vmismatch));
        if (vmismatch == 0) begin
            $display("  [PASSED] AvgPool");
            layer_pass[5] = 1;
        end else begin
            $display("  [FAILED] AvgPool - %0d mismatches", vmismatch);
        end
    end
    endtask
    
    // ============================================================
    // 超时保护
    // ============================================================
    initial begin
        #500000000;  // 500ms 超时
        $display("ERROR: Timeout!");
        $finish;
    end

endmodule
