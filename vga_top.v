`timescale 1ns/1ps
module vga_top (
    input  wire        clk,
    input  wire        rst,
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  r,
    output wire [3:0]  g,
    output wire [3:0]  b
);

wire pclk;
wire pll_locked;

`ifndef SIMULATION
    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk),
        .clk_out1 (pclk),
        .reset    (rst),
        .locked   (pll_locked)
    );
`else
    assign pclk       = clk;
    assign pll_locked = 1'b1;
`endif

wire vga_rst = rst || !pll_locked;

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