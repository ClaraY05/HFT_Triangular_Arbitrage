`timescale 1ns/1ps
// =============================================================================
// vga_renderer.v  --  4×4 matrix grid painter
// =============================================================================
//
// Draws a centred 4×4 grid on a 640×480 display.
// Each cell is CELL_SIZE × CELL_SIZE pixels with a BORDER-wide black border.
//
// Cell colours:
//   No profit        → all cells light grey
//   Profit detected  → cells flagged in loop_mask are RED, others grey
//
// Grid origin: top-left corner of the 4×4 block (pixels)
//   GRID_X = (640 - 4*CELL_SIZE) / 2  = 120  (for CELL_SIZE=100)
//   GRID_Y = (480 - 4*CELL_SIZE) / 2  =  40
//
// loop_mask encoding: bit[row*4 + col] is 1 when that cell is highlighted.
// =============================================================================
module vga_renderer #(
    parameter CELL_SIZE = 100,   // pixels per cell (must divide evenly)
    parameter BORDER    = 2      // border thickness in pixels
)(
    input  wire        pclk,
    input  wire [9:0]  px,
    input  wire [9:0]  py,
    input  wire        active,
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    output reg  [3:0]  r,
    output reg  [3:0]  g,
    output reg  [3:0]  b
);

// --------------------------------------------------------------------------
// Grid geometry
// --------------------------------------------------------------------------
localparam GRID_W  = 4 * CELL_SIZE;       // 400 px
localparam GRID_H  = 4 * CELL_SIZE;       // 400 px
localparam GRID_X  = (640 - GRID_W) / 2; // 120
localparam GRID_Y  = (480 - GRID_H) / 2; //  40

// --------------------------------------------------------------------------
// Pixel classification
// --------------------------------------------------------------------------
wire in_grid = (px >= GRID_X) && (px < GRID_X + GRID_W) &&
               (py >= GRID_Y) && (py < GRID_Y + GRID_H);

// Position within the grid block
wire [9:0] gx = px - GRID_X;
wire [9:0] gy = py - GRID_Y;

// Cell indices (integer divide by CELL_SIZE)
wire [1:0] col_idx = gx / CELL_SIZE;
wire [1:0] row_idx = gy / CELL_SIZE;

// Is this pixel on a cell border line?
wire on_border = (gx % CELL_SIZE < BORDER) ||
                 (gy % CELL_SIZE < BORDER);

// Is this cell's bit set in loop_mask?
wire highlighted = loop_mask[{row_idx, col_idx}];

// --------------------------------------------------------------------------
// Colour output (registered for clean timing)
// --------------------------------------------------------------------------
always @(posedge pclk) begin
    if (!active) begin
        // Blanking: drive zero (black)
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
    end else if (!in_grid) begin
        // Background: dark navy
        r <= 4'h1; g <= 4'h1; b <= 4'h4;
    end else if (on_border) begin
        // Grid lines: black
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
    end else if (profit_found && highlighted) begin
        // Highlighted arbitrage cell: vivid red
        r <= 4'hF; g <= 4'h0; b <= 4'h0;
    end else begin
        // Normal cell: light grey
        r <= 4'hB; g <= 4'hB; b <= 4'hB;
    end
end

endmodule
