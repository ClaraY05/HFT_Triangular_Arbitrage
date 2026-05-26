`timescale 1ns/1ps
// =============================================================================
// arb_detector.v  --  Check diagonals for negative weight cycle
// =============================================================================
// BUG FIX: The original code read 'profit_found' inside the same always block
// that wrote it.  In a clocked always block the register retains its OLD value
// throughout the entire cycle — the new value is not visible until the NEXT
// clock edge.  The chained comparisons:
//
//   if (d1 < 0 && (profit_found == 0 || ...))
//
// therefore always saw profit_found=0 (its reset value), meaning every
// negative diagonal set profit_found=1 unconditionally, and whichever branch
// executed last (d3) won — producing wrong profit_val and a false positive
// whenever d3 happened to be slightly negative due to quantisation.
//
// Fix: use combinational intermediate wires to track the running best across
// the four checks, then commit to registers in a single assignment.
// =============================================================================
module arb_detector (
    input  wire        clk,
    input  wire        rst,
    input  wire        done,        // one-cycle pulse from fw_engine
    input  wire [31:0] diag0,      // dist[0][0]
    input  wire [31:0] diag1,      // dist[1][1]
    input  wire [31:0] diag2,      // dist[2][2]
    input  wire [31:0] diag3,      // dist[3][3]
    output reg         profit_found,
    output reg  [31:0] profit_val   // magnitude of most-negative diagonal
);

wire signed [31:0] d0 = $signed(diag0);
wire signed [31:0] d1 = $signed(diag1);
wire signed [31:0] d2 = $signed(diag2);
wire signed [31:0] d3 = $signed(diag3);

// --------------------------------------------------------------------------
// Noise floor threshold
// --------------------------------------------------------------------------
// Q16.16 fixed-point: 1 LSB = 1/65536. log() rounding on large-magnitude
// rates (especially JPY ~149.5) leaves a residual of a few LSBs on the
// diagonal after Floyd-Warshall even when rates are perfectly consistent.
// NOISE_FLOOR = 32 corresponds to ~0.049% — well below any real arbitrage
// signal (mode 1 produces ~983 LSBs) but safely above quantisation noise.
localparam NOISE_FLOOR = 32'd32;

// --------------------------------------------------------------------------
// Combinational best-of-four selection
// --------------------------------------------------------------------------
// best_mag: magnitude (positive) of the most-negative diagonal, or 0
// found:    1 if any diagonal is negative AND exceeds the noise floor
reg         comb_found;
reg  [31:0] comb_mag;

always @(*) begin
    comb_found = 1'b0;
    comb_mag   = 32'd0;

    if (d0 < 0 && (-d0 > $signed(NOISE_FLOOR))) begin
        comb_found = 1'b1;
        comb_mag   = -d0;
    end

    // Each subsequent check only overwrites if the new magnitude is larger
    if (d1 < 0 && (-d1 > $signed(NOISE_FLOOR))) begin
        comb_found = 1'b1;
        if (-d1 > $signed(comb_mag)) comb_mag = -d1;
    end
    if (d2 < 0 && (-d2 > $signed(NOISE_FLOOR))) begin
        comb_found = 1'b1;
        if (-d2 > $signed(comb_mag)) comb_mag = -d2;
    end
    if (d3 < 0 && (-d3 > $signed(NOISE_FLOOR))) begin
        comb_found = 1'b1;
        if (-d3 > $signed(comb_mag)) comb_mag = -d3;
    end
end

// --------------------------------------------------------------------------
// Register on done pulse
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        profit_found <= 1'b0;
        profit_val   <= 32'd0;
    end else if (done) begin
        profit_found <= comb_found;
        profit_val   <= comb_mag;
    end
end

endmodule
