`timescale 1ns/1ps
// =============================================================================
// vga_top.v  --  VGA subsystem: clock wizard + sync + renderer
// =============================================================================
//
// Instantiates:
//   clk_wiz_0    : Xilinx Clocking Wizard IP → 25.175 MHz pixel clock
//   vga_sync     : timing / counter / sync pulse generator
//   vga_renderer : pixel colour logic
//
// NOTE: clk_wiz_0 must be created in Vivado IP Catalog or via the provided
//       create_project.tcl.  Output clk_out1 = 25.175 MHz, RESET active-high.
// =============================================================================
module vga_top (
    input  wire        clk,           // 100 MHz system clock
    input  wire        rst,           // synchronous reset
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  r,
    output wire [3:0]  g,
    output wire [3:0]  b
);

// --------------------------------------------------------------------------
// Pixel clock: 100 MHz → 25.175 MHz via Clocking Wizard IP
// --------------------------------------------------------------------------
wire pclk;
wire pll_locked;

clk_wiz_0 u_clk_wiz (
    .clk_in1  (clk),
    .clk_out1 (pclk),
    .reset    (rst),
    .locked   (pll_locked)
);

// Hold VGA in reset until PLL locks
wire vga_rst = rst || !pll_locked;

// --------------------------------------------------------------------------
// Sync generator
// --------------------------------------------------------------------------
wire [9:0] px, py;
wire       active;

vga_sync u_sync (
    .pclk   (pclk),
    .rst    (vga_rst),
    .hsync  (hsync),
    .vsync  (vsync),
    .px     (px),
    .py     (py),
    .active (active)
);

// --------------------------------------------------------------------------
// Pixel renderer
// --------------------------------------------------------------------------
vga_renderer u_renderer (
    .pclk         (pclk),
    .px           (px),
    .py           (py),
    .active       (active),
    .profit_found (profit_found),
    .loop_mask    (loop_mask),
    .r            (r),
    .g            (g),
    .b            (b)
);

endmodule
