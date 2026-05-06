`timescale 1ns/1ps
// =============================================================================
// arb_detector.v  --  Check diagonals for negative weight cycle
// =============================================================================
//
// A negative value on the diagonal of the Floyd-Warshall distance matrix
// means there exists a negative-weight cycle through that vertex — i.e. a
// profitable triangular arbitrage loop.
//
// This module:
//   1. Samples all four diagonal values when 'done' pulses.
//   2. Sets 'profit_found' if any diagonal < 0.
//   3. Exposes 'profit_val' = magnitude of the most negative diagonal
//      (32-bit unsigned, positive representation).
//
// profit_val is in Q16.16 fixed-point (same encoding as the input matrix).
// The Python host or the 7-seg controller can convert to a percentage.
// =============================================================================
module arb_detector (
    input  wire        clk,
    input  wire        rst,
    input  wire        done,       // one-cycle pulse from fw_engine
    input  wire [31:0] diag0,     // dist[0][0]
    input  wire [31:0] diag1,     // dist[1][1]
    input  wire [31:0] diag2,     // dist[2][2]
    input  wire [31:0] diag3,     // dist[3][3]
    output reg         profit_found,
    output reg  [31:0] profit_val  // magnitude (always positive)
);

wire signed [31:0] d0 = $signed(diag0);
wire signed [31:0] d1 = $signed(diag1);
wire signed [31:0] d2 = $signed(diag2);
wire signed [31:0] d3 = $signed(diag3);

always @(posedge clk) begin
    if (rst) begin
        profit_found <= 1'b0;
        profit_val   <= 32'd0;
    end else if (done) begin
        profit_found <= 1'b0;
        profit_val   <= 32'd0;

        // Check each diagonal; keep the most negative (largest magnitude)
        if (d0 < 0) begin
            profit_found <= 1'b1;
            profit_val   <= -d0;
        end
        if (d1 < 0 && (profit_found == 0 || -d1 > $signed(profit_val))) begin
            profit_found <= 1'b1;
            profit_val   <= -d1;
        end
        if (d2 < 0 && (profit_found == 0 || -d2 > $signed(profit_val))) begin
            profit_found <= 1'b1;
            profit_val   <= -d2;
        end
        if (d3 < 0 && (profit_found == 0 || -d3 > $signed(profit_val))) begin
            profit_found <= 1'b1;
            profit_val   <= -d3;
        end
    end
end

endmodule
