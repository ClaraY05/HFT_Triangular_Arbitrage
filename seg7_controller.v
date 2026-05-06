`timescale 1ns/1ps
// =============================================================================
// seg7_controller.v  --  4-digit multiplexed 7-segment display
// =============================================================================
//
// Displays the profit value from arb_detector on the Basys 3 four-digit
// seven-segment display.
//
// sw_mode = 0  →  show raw profit_val[19:0]  (bottom 20 bits of Q16.16)
// sw_mode = 1  →  show profit_val scaled to ×10000 for a 4-decimal display
//                 (i.e. treat profit_val as Q16.16 → multiply by 10000,
//                  display result as XXXX with decimal point after digit 1)
//
// Digit ordering:  [3]=most-significant … [0]=least-significant
// Decimal point    is lit on digit 1 (tens position) when sw_mode=1 to
//                  indicate the value is a percentage (e.g. 0123 = 1.23%)
//
// Refresh rate: ~1 kHz (one digit per 250 µs at 100 MHz)
// =============================================================================
module seg7_controller #(
    parameter CLK_HZ     = 100_000_000,
    parameter REFRESH_HZ = 1000           // multiplexing refresh rate
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sw_mode,    // 0=raw, 1=profit %
    input  wire [31:0] raw_val,    // from arb_detector (Q16.16)
    output reg  [6:0]  seg,        // segment outputs (active low)
    output reg  [3:0]  an,         // anode enables (active low)
    output reg         dp          // decimal point (active low)
);

localparam REFRESH_CNT = CLK_HZ / REFRESH_HZ / 4;  // per-digit period

// --------------------------------------------------------------------------
// Derive display value
// --------------------------------------------------------------------------
// Raw mode:  show lower 20 bits directly
// Percent:   profit_val is Q16.16 → value = profit_val / 65536
//            Multiply by 10000 to get 4 decimal places: (val * 10000) >> 16
//            Use 48-bit intermediate to avoid overflow.
wire [19:0] raw_20   = raw_val[19:0];
wire [47:0] pct_full = (48'd10000 * raw_val) >> 16;
wire [19:0] pct_20   = pct_full[19:0];

wire [19:0] disp_val = sw_mode ? pct_20 : raw_20;

// --------------------------------------------------------------------------
// Binary → BCD
// --------------------------------------------------------------------------
wire [3:0] ten_thou, thou, hund, tens, ones;
bin_to_bcd u_bcd (
    .bin      (disp_val),
    .ten_thou (ten_thou),
    .thou     (thou),
    .hund     (hund),
    .tens     (tens),
    .ones     (ones)
);

// We only have 4 digits: show thou / hund / tens / ones
// (ten_thou overflows the display; clamp display to 4 digits)

// --------------------------------------------------------------------------
// Refresh counter and digit multiplexer
// --------------------------------------------------------------------------
reg [$clog2(REFRESH_CNT+1)-1:0] cnt;
reg [1:0] digit;

always @(posedge clk) begin
    if (rst) begin
        cnt   <= 0;
        digit <= 2'd0;
    end else if (cnt == REFRESH_CNT - 1) begin
        cnt   <= 0;
        digit <= digit + 1;
    end else
        cnt <= cnt + 1;
end

// --------------------------------------------------------------------------
// Digit select and value pick
// --------------------------------------------------------------------------
reg [3:0] cur_val;
always @(*) begin
    case (digit)
        2'd3: cur_val = thou;
        2'd2: cur_val = hund;
        2'd1: cur_val = tens;
        2'd0: cur_val = ones;
    endcase
end

// --------------------------------------------------------------------------
// 7-segment decode (common anode → active low)
// Segment order:  seg[6]=g, seg[5]=f, seg[4]=e, seg[3]=d,
//                 seg[2]=c, seg[1]=b, seg[0]=a
// --------------------------------------------------------------------------
function [6:0] seg_decode;
    input [3:0] val;
    case (val)
        4'd0: seg_decode = 7'b100_0000;  //  0
        4'd1: seg_decode = 7'b111_1001;  //  1
        4'd2: seg_decode = 7'b010_0100;  //  2
        4'd3: seg_decode = 7'b011_0000;  //  3
        4'd4: seg_decode = 7'b001_1001;  //  4
        4'd5: seg_decode = 7'b001_0010;  //  5
        4'd6: seg_decode = 7'b000_0010;  //  6
        4'd7: seg_decode = 7'b111_1000;  //  7
        4'd8: seg_decode = 7'b000_0000;  //  8
        4'd9: seg_decode = 7'b001_0000;  //  9
        default: seg_decode = 7'b111_1111;  // blank
    endcase
endfunction

// --------------------------------------------------------------------------
// Output registers
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        seg <= 7'b111_1111;
        an  <= 4'b1111;
        dp  <= 1'b1;
    end else begin
        seg <= seg_decode(cur_val);
        an  <= ~(4'b0001 << digit);   // active-low anode
        // Decimal point: lit on digit 1 (between hund and tens) in % mode
        dp  <= (sw_mode && digit == 2'd2) ? 1'b0 : 1'b1;
    end
end

endmodule
