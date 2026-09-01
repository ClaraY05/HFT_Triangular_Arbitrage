`timescale 1ns/1ps
// arb_detector.v -- check Floyd-Warshall diagonals for a negative cycle.
// The best-of-four selection is combinational and committed in one clocked
// assignment; comparisons chained inside the clocked block would read the
// stale pre-edge value of profit_found.
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

// log() rounding leaves a few LSBs of residual on the diagonal even for
// consistent rates; 32 LSBs (~0.049%) is above that noise but well below a
// real signal (~983 LSBs for the 1.5% test case).
localparam NOISE_FLOOR = 32'd32;

// Best-of-four: magnitude of the most-negative diagonal exceeding the floor
reg         comb_found;
reg  [31:0] comb_mag;

always @(*) begin
    comb_found = 1'b0;
    comb_mag   = 32'd0;

    if (d0 < 0 && (-d0 > $signed(NOISE_FLOOR))) begin
        comb_found = 1'b1;
        comb_mag   = -d0;
    end

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

// Commit on the done pulse
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
