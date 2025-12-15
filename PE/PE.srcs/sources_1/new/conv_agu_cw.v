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
    output reg                      clear_psum,     // Clear 64 psums
    output reg                      valid_in,       // MAC valid cycle

    // --- Ping-pong selection ---
    output reg                      pingpong_sel,   // 0: BRAM0 read/1 write; 1: Vice versa

    // Optional: Layer done flag
    output reg                      done
);
    // ============================================================
    // Derived Parameters
    // ============================================================
    localparam integer H_OUT = H_IN - K + 1;
    localparam integer W_OUT = W_IN - K + 1;

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
    localparam S_CLEAR  = 2'd1;
    localparam S_MAC    = 2'd2;
    localparam S_WRITE  = 2'd3;

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

    // Write-back stage: Write 8x8 row within TILE_C cycles
    reg [15:0] cnt_co_write;  // 0..TILE_C-1
    // assign out_row_idx = cnt_co_write[3:0];

    // Integers for address calculation
    integer h_act, w_act;
    integer base_co;
    integer co_out;

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

    assign data_ready = (state == S_MAC) && mac_last_cycle;

    wire write_last_cycle = (cnt_co_write == TILE_C-1);

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
            // Clear psum for one cycle
            S_CLEAR: begin
                next_state = S_MAC;
            end
            // MAC stage: Ci x hk x wk
            S_MAC: begin
                if (mac_last_cycle)
                    next_state = S_WRITE;
            end
            // Write-back stage: TILE_C cycles, write one Co row per cycle
            S_WRITE: begin
                if (write_last_cycle) begin
                    if (last_tile)
                        next_state = S_IDLE;
                    else
                        next_state = S_CLEAR;
                end
            end
        endcase
    end

    // ============================================================
    // Counter Update Logic
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            cnt_h0       <= 0;
            base_c       <= 0;
            base_w       <= 0;
            cnt_ci       <= 0;
            cnt_hk       <= 0;
            cnt_wk       <= 0;
            cnt_co_write <= 0;
            pingpong_sel <= 0;
            done         <= 0;
        end else begin
            done <= 0;

            case (state)
                S_IDLE: begin
                    // Wait for start; automatically enter CLEAR after start
                    if (start) begin
                        // Toggle ping-pong at start of each layer
                        pingpong_sel <= ~pingpong_sel;
                        // Reset outer loops
                        cnt_h0       <= 0;
                        base_c       <= 0;
                        base_w       <= 0;
                    end
                end

                S_CLEAR: begin
                    // Prepare inner MAC loops
                    cnt_ci       <= 0;
                    cnt_hk       <= 0;
                    cnt_wk       <= 0;
                    cnt_co_write <= 0;
                end

                S_MAC: begin
                    // Ci -> hk -> wk triple loop
                    if (cnt_wk == K-1) begin
                        cnt_wk <= 0;
                        if (cnt_hk == K-1) begin
                            cnt_hk <= 0;
                            if (cnt_ci == C_IN-1)
                                cnt_ci <= 0;     // Will jump to WRITE
                            else
                                cnt_ci <= cnt_ci + 1;
                        end else begin
                            cnt_hk <= cnt_hk + 1;
                        end
                    end else begin
                        cnt_wk <= cnt_wk + 1;
                    end
                end

                S_WRITE: begin
                    // Write back Co row
                    if (cnt_co_write == TILE_C-1) begin
                        cnt_co_write <= 0;

                        // Prepare h0/base_c/base_w for next tile
                        if (base_w + TILE_W < W_OUT) begin
                            base_w <= base_w + TILE_W;  // Next column tile
                        end else begin
                            base_w <= 0;
                            if (base_c + TILE_C < C_OUT) begin
                                base_c <= base_c + TILE_C; // Next output channel group
                            end else begin
                                base_c <= 0;
                                if (cnt_h0 + 1 < H_OUT) begin
                                    cnt_h0 <= cnt_h0 + 1;   // Next row h0
                                end else begin
                                    cnt_h0 <= 0;
                                    done   <= 1;            // Layer done
                                end
                            end
                        end
                    end else begin
                        cnt_co_write <= cnt_co_write + 1;
                    end
                end
            endcase
        end
    end

    // ============================================================
    // Control Signals: clear_psum / valid_in / out_we
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            clear_psum <= 0;
            valid_in   <= 0;
            out_we     <= 0;
        end else begin
            clear_psum <= (state == S_CLEAR);
            valid_in   <= (state == S_MAC);
            out_we     <= (state == S_WRITE);
        end
    end

    // ============================================================
    // Address Generation: Based on (h0, base_c, base_w, Ci, hk, wk, co_write)
    // ============================================================

    // 1) ACT Buffer read base
    //    I[Ci, h, w], continuous 8 w starting from base_w + wk
    //    h = h0 + hk
    always @(posedge clk) begin
        if (rst) begin
            act_read_base <= 0;
        end else if (state == S_MAC) begin
            // Row coordinate & Column start
            h_act = cnt_h0 + cnt_hk;
            w_act = base_w + cnt_wk;

            act_read_base <=
                cnt_ci * ACT_PLANE +          // offset of Ci
                h_act * W_IN    +             // offset of row
                w_act;                        // offset of col (start, next 8 continuous)
        end
    end

    // 2) Weight Buffer read base
    //    K[Ci, hk, wk, Co], Co starts from base_c, continuous 8
    always @(posedge clk) begin
        if (rst) begin
            wgt_read_base <= 0;
        end else if (state == S_MAC) begin
            base_co = base_c;  // Start Co of this tile

            wgt_read_base <=
                cnt_ci * K_PLANE +              // offset of Ci
                cnt_hk * (K * C_OUT) +          // offset of hk
                cnt_wk * C_OUT       +          // offset of wk
                base_co;                        // offset of Co start
        end
    end

    // 3) Output ACT BRAM write base
    //    O[Co, h0, w0], write one Co row per cycle:
    //    Co = base_c + cnt_co_write
    //    w0 starts from base_w, continuous TILE_W
    always @(posedge clk) begin
        if (rst) begin
            out_write_base <= 0;
            out_row_idx    <= 0;
        end else if (state == S_WRITE) begin
            co_out = base_c + cnt_co_write;
            out_row_idx <= cnt_co_write[3:0];

            out_write_base <=
                co_out * OUT_PLANE +          // offset of Co
                cnt_h0 * W_OUT   +            // offset of h0 row
                base_w;                        // w0 start, next TILE_W continuous
        end
    end

endmodule
