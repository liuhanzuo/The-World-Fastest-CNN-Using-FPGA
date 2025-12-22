// ================================================================
// conv_agu_cw.v
// AGU for CxW dual-parallel, OS, kernel-serial convolution
// - Generates:
//   * act_read_base  -> To ACT Buffer (Input BRAM wide port base)
//   * wgt_read_base  -> To Weight Buffer (Wide port base)
//   * out_write_base -> Output BRAM row start address
//   * out_we         -> Output BRAM write enable (TILE_C cycles)
//   * pingpong_sel   -> 0: BRAM0 read / BRAM1 write; 1: Vice versa
//   * clear_psum     -> Clear 64 PE psums
//   * valid_in       -> PE MAC valid signal
// ================================================================
module conv_agu_cw #(
    // Input feature map parameters
    parameter H_IN        = 10,
    parameter W_IN        = 10,
    parameter C_IN        = 16,

    // Output feature map parameters
    parameter C_OUT       = 16,

    // Kernel size
    parameter K           = 3,

    // Tile parallelism parameters
    parameter TILE_C      = 8,   // Row parallelism Co
    parameter TILE_W      = 8,   // Column parallelism w0

    // Address width (set larger as needed)
    parameter ACT_ADDR_W  = 16,
    parameter WGT_ADDR_W  = 16,
    parameter OUT_ADDR_W  = 16
)(
    input  wire                     clk,
    input  wire                     rst,

    input  wire                     start,       // Pulse high for 1 cycle to start a layer

    // --- To ACT Buffer (Input BRAM) ---
    output reg  [ACT_ADDR_W-1:0]    act_read_base,  // One base per cycle, wide port reads 8 I

    // --- To Weight Buffer ---
    output reg  [WGT_ADDR_W-1:0]    wgt_read_base,  // One base per cycle, wide port reads 8 K

    // --- To Output ACT BRAM (Input for next layer) ---
    output reg  [OUT_ADDR_W-1:0]    out_write_base, // Start address for writing a row of 8 w
    output reg                      out_we,         // Write enable
    output reg  [3:0]               out_row_idx,    // Current write row index (0..TILE_C-1)
    output wire                     data_ready,     // Pulse to latch psums

    // --- To PE Array ---
    output wire                      clear_psum,     // Clear 64 psums
    output reg                      valid_in,       // MAC valid cycle

    // --- Ping-pong selection ---
    output reg                      pingpong_sel,   // 0: BRAM0 read/1 write; 1: Vice versa

    // --- mask for padding ---
    output reg [TILE_W-1:0]        mask_w,         // Mask for valid output w positions, activation buffer needed
    // Optional: Layer done flag
    output reg                      done
);
    // ============================================================
    // Derived Parameters
    // ============================================================
    // This project's Python reference (data/structure/net.py) uses SAME padding for conv layers.
    // For odd K, SAME padding is PAD = K/2 (e.g. K=5 -> PAD=2), yielding H_OUT=H_IN and W_OUT=W_IN.
    localparam integer PAD   = K / 2;
    localparam integer H_OUT = H_IN;
    localparam integer W_OUT = W_IN;

    // Use constants to reduce multiplication
    localparam integer ACT_PLANE  = H_IN * W_IN;    // Elements per Ci
    localparam integer K_PLANE    = K * K * C_OUT;  // Weights per Ci
    localparam integer OUT_PLANE  = H_OUT * W_OUT;  // Outputs per Co

    // Tile counts
    localparam integer NUM_TILE_C = (C_OUT + TILE_C - 1) / TILE_C;
    localparam integer NUM_TILE_W = (W_OUT + TILE_W - 1) / TILE_W;

    // ============================================================
    // FSM States
    // ============================================================
    localparam S_IDLE   = 2'd0;
    localparam S_CLEAR  = 2'd1; // Initial clear only
    localparam S_MAC    = 2'd2;
    localparam S_GAP    = 2'd3; // Wait state between tiles

    reg [1:0] state, next_state;

    // ============================================================
    // Loop Counters (Hardware for-loops)
    // ============================================================

    // h0: Output height direction
    reg [15:0] cnt_h0;

    // Tile Co / W base addresses (Unit is output index, not tile index)
    reg [15:0] base_c;  // 0, TILE_C, 2*TILE_C, ...
    reg [15:0] base_w;  // 0, TILE_W, 2*TILE_W, ...

    // Ci, hk, wk for MAC stage
    reg [15:0] cnt_ci;
    reg [15:0] cnt_hk;
    reg [15:0] cnt_wk;

    // Gap counter
    reg [3:0]  cnt_gap;
    localparam GAP_CYCLES = 5; // Wait 5 cycles (N+1..N+5), start next at N+6

    // Integers for address calculation
    integer h_act, w_act;
    integer base_co;
    integer co_out;
    integer i;

    // ------------------------------------------------------------
    // FSM State Transition
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    wire mac_last_cycle =
        (cnt_ci == C_IN-1) &&
        (cnt_hk == K-1) &&
        (cnt_wk == K-1);

    // Check if current tile is the last tile of the feature map
    wire last_tile =
        (cnt_h0  == H_OUT-1) &&
        (base_c + TILE_C >= C_OUT) &&
        (base_w + TILE_W >= W_OUT);

    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (start)
                    next_state = S_CLEAR;
            end
            // Clear psum for one cycle (Initial clear)
            S_CLEAR: begin
                next_state = S_MAC;
            end
            // MAC stage: Ci x hk x wk
            S_MAC: begin
                if (mac_last_cycle) begin
                    if (last_tile)
                        next_state = S_IDLE;
                    else
                        next_state = S_GAP;
                end
            end
            // Gap stage: Wait for pipeline to drain/setup next
            S_GAP: begin
                if (cnt_gap == GAP_CYCLES)
                    next_state = S_MAC;
            end
        endcase
    end

    // ============================================================
    // Counter Update Logic (Main FSM)
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            cnt_h0       <= 0;
            base_c       <= 0;
            base_w       <= 0;
            cnt_ci       <= 0;
            cnt_hk       <= 0;
            cnt_wk       <= 0;
            cnt_gap      <= 0;
            pingpong_sel <= 0;
            done         <= 0;
        end else begin
            done <= 0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        pingpong_sel <= ~pingpong_sel;
                        cnt_h0       <= 0;
                        base_c       <= 0;
                        base_w       <= 0;
                    end
                end

                S_CLEAR: begin
                    cnt_ci       <= 0;
                    cnt_hk       <= 0;
                    cnt_wk       <= 0;
                    cnt_gap      <= 0;
                end

                S_MAC: begin
                    // Ci -> hk -> wk triple loop
                    if (cnt_wk == K-1) begin
                        cnt_wk <= 0;
                        if (cnt_hk == K-1) begin
                            cnt_hk <= 0;
                            if (cnt_ci == C_IN-1) begin
                                cnt_ci <= 0;
                                // If last tile, done will be set in next cycle logic or here
                                if (last_tile) done <= 1;
                            end else begin
                                cnt_ci <= cnt_ci + 1;
                            end
                        end else begin
                            cnt_hk <= cnt_hk + 1;
                        end
                    end else begin
                        cnt_wk <= cnt_wk + 1;
                    end
                end

                S_GAP: begin
                    if (cnt_gap == GAP_CYCLES) begin
                        cnt_gap <= 0;
                        // Update outer loops for next tile
                        if (base_w + TILE_W < W_OUT) begin
                            base_w <= base_w + TILE_W;
                        end else begin
                            base_w <= 0;
                            if (base_c + TILE_C < C_OUT) begin
                                base_c <= base_c + TILE_C;
                            end else begin
                                base_c <= 0;
                                if (cnt_h0 + 1 < H_OUT) begin
                                    cnt_h0 <= cnt_h0 + 1;
                                end else begin
                                    cnt_h0 <= 0; // Should not happen if last_tile check works
                                end
                            end
                        end
                    end else begin
                        cnt_gap <= cnt_gap + 1;
                    end
                end
            endcase
        end
    end

    // ============================================================
    // Pipeline Control Signals
    // ============================================================
    
    // Delays:
    // valid_in:   4 cycles (N -> N+4)
    // data_ready: 9 cycles (N -> N+9)
    // clear_psum: 9 cycles (N -> N+9)

    reg [4:0] valid_in_pipe;
    reg [9:0] data_ready_pipe;
    reg [9:0] clear_psum_pipe;
    
    // Mask pipeline (match valid_in delay = 3)
    // reg [TILE_W-1:0] mask_pipe [0:2];
    // reg [TILE_W-1:0] mask_next; // Combinational mask
    reg [TILE_W-1:0] mask; // Combinational mask
    always @(posedge clk) begin
        if (rst) begin
            valid_in_pipe   <= 0;
            data_ready_pipe <= 0;
            clear_psum_pipe <= 0;
            valid_in        <= 0;
            mask_w          <= 0;
            // mask_pipe[0]    <= 0;
            // mask_pipe[1]    <= 0;
            // mask_pipe[2]    <= 0;
        end else begin
            // valid_in pipeline
            valid_in_pipe <= {valid_in_pipe[3:0], (state == S_MAC)};
            valid_in      <= valid_in_pipe[4];

            // no need to wait, act buffer should dapai
            // mask_pipe[0] <= mask_next;
            // mask_pipe[1] <= mask_pipe[0];
            // mask_pipe[2] <= mask_pipe[1];
            // mask_w       <= mask_pipe[2];

            // data_ready pipeline (pulse at end of MAC)
            data_ready_pipe <= {data_ready_pipe[7:0], (state == S_MAC) && mac_last_cycle};

            // clear_psum pipeline (pulse at end of MAC)
            clear_psum_pipe <= {clear_psum_pipe[8:0], (state == S_MAC) && mac_last_cycle};

            // register mask for external use (act buffer)
            mask_w <= mask;
        end
    end
    
    assign data_ready = data_ready_pipe[8]; // Output at N+8
    
    // clear_psum is OR of initial clear and pipeline clear
    assign clear_psum = (state == S_CLEAR) || clear_psum_pipe[9]; // Output at N+9

    // ============================================================
    // Write Back Logic (Independent FSM/Counter)
    // ============================================================
    
    reg [15:0] w_base_c, w_base_w, w_cnt_h0;
    reg        write_active;
    reg [3:0]  cnt_write_row;
    
    // Latch parameters at end of MAC (Cycle N)
    always @(posedge clk) begin
        if (rst) begin
            w_base_c <= 0;
            w_base_w <= 0;
            w_cnt_h0 <= 0;
        end else if ((state == S_MAC) && mac_last_cycle) begin
            w_base_c <= base_c;
            w_base_w <= base_w;
            w_cnt_h0 <= cnt_h0;
        end
    end
    
    // Write FSM
    always @(posedge clk) begin
        if (rst) begin
            write_active   <= 0;
            cnt_write_row  <= 0;
            out_we         <= 0;
            out_write_base <= 0;
            out_row_idx    <= 0;
        end else begin
            // Trigger write on data_ready (N+7)
            // Start writing at N+8
            if (data_ready) begin
                write_active  <= 1;
                cnt_write_row <= 0;
            end
            
            if (write_active) begin
                out_we      <= 1;
                out_row_idx <= cnt_write_row;
                
                // Calculate address
                co_out = w_base_c + cnt_write_row;
                out_write_base <=
                    co_out * OUT_PLANE +
                    w_cnt_h0 * W_OUT +
                    w_base_w;
                
                if (cnt_write_row == TILE_C - 1) begin
                    write_active <= 0;
                    cnt_write_row <= 0;
                end else begin
                    cnt_write_row <= cnt_write_row + 1;
                end
            end else begin
                out_we <= 0;
            end
        end
    end

    // ============================================================
    // Address Generation (Read Side)
    // ============================================================

    // 1) ACT Buffer read base
    always @(posedge clk) begin
        if (rst) begin
            act_read_base <= 0;
        end else if (state == S_MAC) begin
            // SAME padding: input index = output index + kernel index - PAD
            h_act = cnt_h0 + cnt_hk - PAD;
            w_act = base_w + cnt_wk - PAD;

            act_read_base <=
                cnt_ci * ACT_PLANE +
                h_act * W_IN +
                w_act;
        end
    end
    
    // Mask Combinational Logic (Registered in pipeline block)
    always @(*) begin
        if (state == S_MAC) begin
            h_act = cnt_h0 + cnt_hk - PAD;
            w_act = base_w + cnt_wk - PAD;
            
            if (h_act < 0 || h_act >= H_IN) begin
                mask = {TILE_W{1'b0}};
            end else begin
                for (i = 0; i < TILE_W; i = i + 1) begin
                    if ((w_act + i) < 0 || (w_act + i) >= W_IN)
                        mask[i] = 1'b0;
                    else
                        mask[i] = 1'b1;
                end
            end
        end else begin
            mask = {TILE_W{1'b0}};
        end
    end

    // 2) Weight Buffer read base
    always @(posedge clk) begin
        if (rst) begin
            wgt_read_base <= 0;
        end else if (state == S_MAC) begin
            base_co = base_c;

            wgt_read_base <=
                cnt_ci * K_PLANE +
                cnt_hk * (K * C_OUT) +
                cnt_wk * C_OUT +
                base_co;
        end
    end

    // 3) Output ACT BRAM write base
    //    O[Co, h0, w0], write one Co row per cycle:
    //    Co = base_c + cnt_co_write
    //    w0 starts from base_w, continuous TILE_W
    //    (Moved to Write Back Logic block)

endmodule
