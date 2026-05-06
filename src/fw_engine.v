`timescale 1ns/1ps
// =============================================================================
// fw_engine.v  --  Floyd-Warshall all-pairs shortest path (4×4, 32-bit signed)
// =============================================================================
//
// Algorithm:
//   for k in 0..3:
//     for i in 0..3:
//       for j in 0..3:
//         if dist[i][k] + dist[k][j] < dist[i][j]:
//           dist[i][j] = dist[i][k] + dist[k][j]
//
// The 4×4 matrix is stored flat: dist[i][j] lives at index i*4+j.
// After run is asserted the engine loads the initial matrix from BRAM
// (16 consecutive reads with one-cycle read latency), then iterates for
// 64 update cycles (k=0..3, i=0..3, j=0..3).
//
// Timing:  ~80 cycles total (16 load + 64 compute + overhead).
// At 100 MHz that is < 1 µs, well within any HFT window.
//
// Outputs:
//   diag0..3  : dist[0][0], dist[1][1], dist[2][2], dist[3][3]
//   loop_mask : bit[r*4+c] set for cells that are on the arb path
//               (simplified: flags the entire row & col of the most
//                negative diagonal — full path reconstruction is an
//                extension described in docs/architecture.md)
//   done      : single-cycle pulse when computation is complete
// =============================================================================
module fw_engine (
    input  wire        clk,
    input  wire        rst,
    input  wire        run,        // one-cycle start pulse from control_fsm
    // BRAM read port (matrix_buffer has 1-cycle latency)
    output reg  [3:0]  mat_addr,
    input  wire [31:0] mat_data,
    // Results
    output reg         done,
    output wire [31:0] diag0,
    output wire [31:0] diag1,
    output wire [31:0] diag2,
    output wire [31:0] diag3,
    output reg  [15:0] loop_mask
);

// --------------------------------------------------------------------------
// Internal distance matrix  (16 × 32-bit signed registers)
// --------------------------------------------------------------------------
reg signed [31:0] dist [0:15];

// --------------------------------------------------------------------------
// State machine
// --------------------------------------------------------------------------
localparam S_IDLE = 2'd0,
           S_LOAD = 2'd1,
           S_COMP = 2'd2,
           S_DONE = 2'd3;

reg [1:0]  state;
reg [4:0]  load_cnt;    // counts 0..17 (16 reads + 1 pipeline flush)
reg [1:0]  k, i, j;    // loop indices
reg signed [31:0] through;  // dist[i][k] + dist[k][j]

// S_DONE temporaries — must be module-level regs in Verilog-2001
reg [1:0]         best_idx;
reg signed [31:0] best_val;
integer           mi, ni;   // loop counters for mask building

// --------------------------------------------------------------------------
// Sequential logic
// --------------------------------------------------------------------------
always @(posedge clk) begin
    done <= 1'b0;

    if (rst) begin
        state     <= S_IDLE;
        load_cnt  <= 0;
        loop_mask <= 16'h0000;
        mat_addr  <= 4'd0;
    end else begin
        case (state)

            // -----------------------------------------------------------------
            S_IDLE: begin
                if (run) begin
                    load_cnt <= 5'd0;
                    mat_addr <= 4'd0;
                    state    <= S_LOAD;
                end
            end

            // -----------------------------------------------------------------
            // Load phase: issue address N, capture data for address N-1
            // (BRAM has 1-cycle read latency)
            // -----------------------------------------------------------------
            S_LOAD: begin
                // Capture the previous read result (pipeline delay)
                if (load_cnt >= 5'd1 && load_cnt <= 5'd16)
                    dist[load_cnt - 1] <= $signed(mat_data);

                if (load_cnt == 5'd17) begin
                    // All 16 words loaded; begin computation
                    k     <= 2'd0;
                    i     <= 2'd0;
                    j     <= 2'd0;
                    state <= S_COMP;
                end else begin
                    mat_addr <= (load_cnt < 5'd16) ? load_cnt[3:0] : 4'd0;
                    load_cnt <= load_cnt + 1;
                end
            end

            // -----------------------------------------------------------------
            // Compute phase: one update per clock cycle
            // dist[i][j] = min(dist[i][j],  dist[i][k] + dist[k][j])
            // -----------------------------------------------------------------
            S_COMP: begin
                through = $signed(dist[{i, k}]) + $signed(dist[{k, j}]);
                if (through < $signed(dist[{i, j}]))
                    dist[{i, j}] <= through;

                // Advance j → i → k (innermost first)
                if (j == 2'd3) begin
                    j <= 2'd0;
                    if (i == 2'd3) begin
                        i <= 2'd0;
                        if (k == 2'd3)
                            state <= S_DONE;
                        else
                            k <= k + 1;
                    end else
                        i <= i + 1;
                end else
                    j <= j + 1;
            end

            // -----------------------------------------------------------------
            S_DONE: begin
                done <= 1'b1;

                // Find most-negative diagonal using module-level regs
                best_val = 32'sh7FFF_FFFF;
                best_idx = 2'd0;
                if ($signed(dist[0])  < best_val) begin best_val = dist[0];  best_idx = 2'd0; end
                if ($signed(dist[5])  < best_val) begin best_val = dist[5];  best_idx = 2'd1; end
                if ($signed(dist[10]) < best_val) begin best_val = dist[10]; best_idx = 2'd2; end
                if ($signed(dist[15]) < best_val) begin best_val = dist[15]; best_idx = 2'd3; end

                // Build loop_mask: highlight row + column of best_idx
                // Use integer index arithmetic to avoid packed-select issues
                loop_mask <= 16'h0000;
                if (best_val < 0) begin
                    for (mi = 0; mi < 4; mi = mi + 1)
                        loop_mask[best_idx * 4 + mi] <= 1'b1;   // row
                    for (ni = 0; ni < 4; ni = ni + 1)
                        loop_mask[ni * 4 + best_idx] <= 1'b1;   // col
                end

                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

// --------------------------------------------------------------------------
// Diagonal outputs  (combinational taps into dist registers)
// --------------------------------------------------------------------------
assign diag0 = dist[0];    // dist[0][0]
assign diag1 = dist[5];    // dist[1][1]
assign diag2 = dist[10];   // dist[2][2]
assign diag3 = dist[15];   // dist[3][3]

endmodule