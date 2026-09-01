`timescale 1ns/1ps
// vga_top.v -- VGA subsystem: pixel-clock PLL, CDC into pclk, sync + renderer
module vga_top (
    input  wire        clk,               // 100 MHz board clock
    input  wire        rst,
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    input  wire [13:0] profit_pct_x100,
    input  wire [31:0] profit_val,        // raw Q16.16 magnitude from arb_detector
    output wire        hsync,
    output wire        vsync,
    output wire [3:0]  r,
    output wire [3:0]  g,
    output wire [3:0]  b
);

wire pclk;
wire pll_locked;

`ifndef SIMULATION
    // Clocking Wizard: 100 MHz -> 25.175 MHz pixel clock
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

wire vga_rst = rst | ~pll_locked;

// Double-flop CDC for everything crossing 100 MHz clk -> pclk; without it
// the renderer latches metastable values and the display never updates
reg        pf_s1,  pf_s2;
reg [15:0] lm_s1,  lm_s2;
reg [13:0] pp_s1,  pp_s2;
reg [31:0] pv_s1,  pv_s2;

always @(posedge pclk or posedge vga_rst) begin
    if (vga_rst) begin
        pf_s1 <= 1'b0;  pf_s2 <= 1'b0;
        lm_s1 <= 16'h0; lm_s2 <= 16'h0;
        pp_s1 <= 14'h0; pp_s2 <= 14'h0;
        pv_s1 <= 32'h0; pv_s2 <= 32'h0;
    end else begin
        pf_s1 <= profit_found;    pf_s2 <= pf_s1;
        lm_s1 <= loop_mask;       lm_s2 <= lm_s1;
        pp_s1 <= profit_pct_x100; pp_s2 <= pp_s1;
        pv_s1 <= profit_val;      pv_s2 <= pv_s1;
    end
end

wire        pf_sync = pf_s2;
wire [15:0] lm_sync = lm_s2;
wire [13:0] pp_sync = pp_s2;
wire [31:0] pv_sync = pv_s2;

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
    .profit_found    (pf_sync),
    .loop_mask       (lm_sync),
    .profit_pct_x100 (pp_sync),
    .profit_val      (pv_sync),
    .r               (r),
    .g               (g),
    .b               (b)
);

endmodule
