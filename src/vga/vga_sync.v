`timescale 1ns/1ps
// vga_sync.v -- 640x480 @ 60 Hz timing generator (25.175 MHz pixel clock).
// H: 640 active / 16 FP / 96 sync / 48 BP (800 total)
// V: 480 active / 10 FP /  2 sync / 33 BP (525 total)
// Syncs are active-LOW; 'active' is high in the visible region.
module vga_sync (
    input  wire        pclk,    // 25.175 MHz pixel clock
    input  wire        rst,
    output reg         hsync,
    output reg         vsync,
    output reg  [9:0]  px,      // current pixel column (0-799)
    output reg  [9:0]  py,      // current pixel row    (0-524)
    output wire        active   // high in visible region
);

// Horizontal parameters
localparam H_ACTIVE = 640,
           H_FP     = 16,
           H_SYNC   = 96,
           H_BP     = 48,
           H_TOTAL  = 800;

// Vertical parameters
localparam V_ACTIVE = 480,
           V_FP     = 10,
           V_SYNC   = 2,
           V_BP     = 33,
           V_TOTAL  = 525;

// Sync pulse windows (relative to end of active region)
localparam H_SYNC_START = H_ACTIVE + H_FP;               // 656
localparam H_SYNC_END   = H_ACTIVE + H_FP + H_SYNC;      // 752
localparam V_SYNC_START = V_ACTIVE + V_FP;               // 490
localparam V_SYNC_END   = V_ACTIVE + V_FP + V_SYNC;      // 492

// Pixel counters
always @(posedge pclk) begin
    if (rst) begin
        px <= 10'd0;
        py <= 10'd0;
    end else begin
        if (px == H_TOTAL - 1) begin
            px <= 10'd0;
            py <= (py == V_TOTAL - 1) ? 10'd0 : py + 1;
        end else
            px <= px + 1;
    end
end

// Sync signals (active low)
always @(posedge pclk) begin
    hsync <= ~(px >= H_SYNC_START && px < H_SYNC_END);
    vsync <= ~(py >= V_SYNC_START && py < V_SYNC_END);
end

// Active region
assign active = (px < H_ACTIVE) && (py < V_ACTIVE);

endmodule
