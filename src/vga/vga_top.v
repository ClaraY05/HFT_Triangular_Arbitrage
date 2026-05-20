`timescale 1ns/1ps
// =============================================================================
// vga_top.v  --  VGA subsystem top
// =============================================================================
// BUG FIX: The previous version replaced clk_wiz_0 with a fabric register
// clock divider (reg pclk toggled in always @(posedge clk)).  Vivado cannot
// route a fabric register as a clock net — the result is that vga_sync and
// vga_renderer never receive a valid pixel clock and the display goes dark.
//
// Fix: restore the clk_wiz_0 instantiation (Xilinx PLL/MMCM) which properly
// drives the FPGA clock network.  The SIMULATION guard is preserved so that
// tb_top.v still compiles without the IP stub.
// =============================================================================
module vga_top (
    input  wire        clk,               // 100 MHz board clock
    input  wire        rst,
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    input  wire [13:0] profit_pct_x100,
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  r,
    output wire [3:0]  g,
    output wire [3:0]  b
);

wire pclk;
wire pll_locked;

`ifndef SIMULATION
    // Xilinx Clocking Wizard: 100 MHz -> 25.175 MHz pixel clock
    // Configure in Vivado IP Catalog: Clocking Wizard, name = clk_wiz_0
    //   Input:  100 MHz
    //   Output: 25.175 MHz
    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk),
        .clk_out1 (pclk),
        .reset    (rst),
        .locked   (pll_locked)
    );
`else
    // Simulation passthrough (clk_wiz_0 IP not available in open-source sims)
    assign pclk       = clk;
    assign pll_locked = 1'b1;
`endif

// Hold VGA in reset until PLL has locked
wire vga_rst = rst | ~pll_locked;

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
    .pclk            (pclk),
    .px              (px),
    .py              (py),
    .active          (active),
    .profit_found    (profit_found),
    .loop_mask       (loop_mask),
    .profit_pct_x100 (profit_pct_x100),
    .r               (r),
    .g               (g),
    .b               (b)
);

endmodule
