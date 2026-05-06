`timescale 1ns/1ps
module vga_renderer #( // (vga_renderer.v)4×4 matrix grid painter
    parameter SCREEN_W = 640,    // screen width (pixels)
    parameter SCREEN_H = 480,    // screen height (pixels)
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

// Grid geometry
localparam GRID_W  = 4 * CELL_SIZE;      
localparam GRID_H  = 4 * CELL_SIZE;       
localparam GRID_X  = (SCREEN_W - GRID_W) / 2;
localparam GRID_Y  = (SCREEN_H - GRID_H) / 2;

// Pixel classification
wire in_grid = (px >= GRID_X) && (px < GRID_X + GRID_W) &&
               (py >= GRID_Y) && (py < GRID_Y + GRID_H);

wire [9:0] gx = px - GRID_X;
wire [9:0] gy = py - GRID_Y;
wire [1:0] col_idx = gx / CELL_SIZE;
wire [1:0] row_idx = gy / CELL_SIZE;
wire on_border = (gx % CELL_SIZE < BORDER) ||
                 (gy % CELL_SIZE < BORDER);
wire highlighted = loop_mask[{row_idx, col_idx}];

// Colour output
always @(posedge pclk) begin
    if (!active) begin
        // Blanking: screen is black
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
    end else if (!in_grid) begin
        // Set Background: dark navy
        r <= 4'h1; g <= 4'h1; b <= 4'h4;
    end else if (on_border) begin
        // Set Grid lines: black
        r <= 4'h0; g <= 4'h0; b <= 4'h0;
    end else if (profit_found && highlighted) begin
        // Profit detected: cells flagged in loop_mask are RED, other grey
        r <= 4'hF; g <= 4'h0; b <= 4'h0;
    end else begin
        // No profit: all cells light grey
        r <= 4'hB; g <= 4'hB; b <= 4'hB;
    end
end

endmodule
