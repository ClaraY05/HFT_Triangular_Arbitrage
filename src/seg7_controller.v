`timescale 1ns/1ps
// =============================================================================
// seg7_controller.v  --  4-digit multiplexed 7-segment display
// =============================================================================
//
// SW0 = 0  ->  Profit percentage mode  (default)
//              Displays XX.XX  e.g. "01.23" for 1.23%, "00.00" for no profit.
//              pct_val = (profit_val * 10000) >> 16  (Q16.16 -> hundredths of %)
//              After double-dabble: d3=tens-of-%, d2=ones-of-%, d1=tenths, d0=hundredths
//              Decimal point on AN2 (digit==2), giving: [d3][d2].[d1][d0]
//
// SW0 = 1  ->  Raw Q16.16 integer part debug mode.
//              Shows profit_val[29:16] as 0-16383, no decimal point.
//
// -----------------------------------------------------------------------------
// SEGMENT ENCODING  (verified against reference controller)
// -----------------------------------------------------------------------------
// Bit order in seg[6:0]:
//   seg[6]=CG(mid)  seg[5]=CF(top-left)  seg[4]=CE(bot-left)
//   seg[3]=CD(bot)  seg[2]=CC(bot-right) seg[1]=CB(top-right) seg[0]=CA(top)
//
// Active LOW (0=segment ON, 1=segment OFF).
//
//         CA(seg[0])
//          ----
//  CF(5) |    | CB(1)
//          -CG(6)-
//  CE(4) |    | CC(2)
//          ----
//         CD(seg[3])
//
// Encoding table  {CG,CF,CE,CD,CC,CB,CA}:
//   0 -> 7'b1000000   1 -> 7'b1111001   2 -> 7'b0100100   3 -> 7'b0110000
//   4 -> 7'b0011001   5 -> 7'b0010010   6 -> 7'b0000010   7 -> 7'b1111000
//   8 -> 7'b0000000   9 -> 7'b0010000
//
// -----------------------------------------------------------------------------
// ANODE MAPPING  (Basys3, active LOW)
// -----------------------------------------------------------------------------
//   digit_sel=3 -> AN3 (4'b0111) leftmost  = d3 (tens of %)
//   digit_sel=2 -> AN2 (4'b1011)           = d2 (ones of %) + dp in % mode
//   digit_sel=1 -> AN1 (4'b1101)           = d1 (tenths of %)
//   digit_sel=0 -> AN0 (4'b1110) rightmost = d0 (hundredths of %)
// =============================================================================
module seg7_controller #(
    parameter CLK_HZ     = 100_000_000,
    parameter REFRESH_HZ = 1000            // mux refresh (1 kHz -> 250 us/digit)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sw_mode,    // 0 = profit %, 1 = raw Q16.16 integer
    input  wire [31:0] raw_val,    // from arb_detector (Q16.16, always positive)
    output reg  [6:0]  seg,
    output reg  [3:0]  an,
    output reg         dp
);

localparam REFRESH_CNT = CLK_HZ / REFRESH_HZ / 4;  // cycles per digit slot

// --------------------------------------------------------------------------
// Compute display value
// --------------------------------------------------------------------------
// % mode: display_int = profit_val * 10000 / 65536
//   = value in hundredths of percent, 0..9999
//   e.g. 1.23% -> 123, shown as "01.23"
// Use 64-bit intermediate so Vivado does not truncate the multiply.
wire [63:0] pct_wide = ({32'b0, raw_val} * 64'd10000) >> 16;
wire [13:0] pct_val  = (pct_wide > 64'd9999) ? 14'd9999 : pct_wide[13:0];

// Raw mode: lower 16 bits of Q16.16 magnitude, shown as 0..9999.
// profit_val for realistic arbitrage (< 100%) is always < 65536, so all
// meaningful data lives in bits [15:0].  Bits [31:16] are the integer part
// and are permanently 0 for any sub-100% profit — which caused the display
// to be stuck at 0 when using the old profit_val[31:16] expression.
wire [13:0] raw_14 = (raw_val[15:0] > 16'd9999) ? 14'd9999 : raw_val[13:0];

wire [13:0] disp_val = sw_mode ? raw_14 : pct_val;

// --------------------------------------------------------------------------
// 14-bit binary -> 4-digit BCD  (double-dabble, combinational)
// --------------------------------------------------------------------------
reg [3:0] d3, d2, d1, d0;   // thousands, hundreds, tens, ones
reg [13:0] bcd_in;
integer bi;

always @(*) begin
    d3 = 4'd0; d2 = 4'd0; d1 = 4'd0; d0 = 4'd0;
    bcd_in = disp_val;
    for (bi = 0; bi < 14; bi = bi + 1) begin
        // Add-3 correction before each shift
        if (d3 >= 4'd5) d3 = d3 + 4'd3;
        if (d2 >= 4'd5) d2 = d2 + 4'd3;
        if (d1 >= 4'd5) d1 = d1 + 4'd3;
        if (d0 >= 4'd5) d0 = d0 + 4'd3;
        // Left-shift: carry MSB of each nibble into next lower digit
        d3     = {d3[2:0], d2[3]};
        d2     = {d2[2:0], d1[3]};
        d1     = {d1[2:0], d0[3]};
        d0     = {d0[2:0], bcd_in[13]};
        bcd_in = {bcd_in[12:0], 1'b0};
    end
end

// --------------------------------------------------------------------------
// Leading zero suppression
// d3 (thousands) is blanked when zero; d2 (hundreds) always shown
// so the display always reads at least "0X.XX"
// --------------------------------------------------------------------------
wire blank_d3 = (d3 == 4'd0);

// --------------------------------------------------------------------------
// Refresh counter and digit selector
// --------------------------------------------------------------------------
reg [$clog2(REFRESH_CNT+1)-1:0] cnt;
reg [1:0] digit;   // 0 = rightmost (AN0), 3 = leftmost (AN3)

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
// Select current digit value, blank flag, and decimal point
// --------------------------------------------------------------------------
// DECIMAL POINT:
//   pct_val is in hundredths of %.  After double-dabble:
//     d3=tens-%, d2=ones-%, d1=tenths-%, d0=hundredths-%
//   Display should read  [d3][d2].[d1][d0]  e.g. "01.23"
//   The decimal point is stored in the AN2 digit (digit==2), which is d2.
//   i.e. cur_dp = 0 (lit) when digit==2 AND sw_mode==0.
//
//   NOTE: In a common-anode display the decimal point DP pin is active-LOW,
//   the same as the segments.  cur_dp=0 turns the dot ON.
// --------------------------------------------------------------------------
reg [3:0] cur_val;
reg       cur_blank;
reg       cur_dp;

always @(*) begin
    cur_blank = 1'b0;
    cur_dp    = 1'b1;   // default: dot OFF (active-low, so 1=off)
    case (digit)
        2'd3: begin   // AN3, leftmost -- d3 = tens of integer %
            cur_val   = d3;
            cur_blank = blank_d3;
            cur_dp    = 1'b1;
        end
        2'd2: begin   // AN2 -- d2 = ones of integer %
            cur_val   = d2;
            cur_blank = 1'b0;
            // Decimal point sits AFTER this digit (between AN2 and AN1)
            // giving layout XX.XX -- lit in % mode, off in raw mode
            cur_dp    = sw_mode ? 1'b1 : 1'b0;
        end
        2'd1: begin   // AN1 -- d1 = tenths of %
            cur_val   = d1;
            cur_blank = 1'b0;
            cur_dp    = 1'b1;
        end
        2'd0: begin   // AN0, rightmost -- d0 = hundredths of %
            cur_val   = d0;
            cur_blank = 1'b0;
            cur_dp    = 1'b1;
        end
        default: begin
            cur_val   = 4'd0;
            cur_blank = 1'b1;
            cur_dp    = 1'b1;
        end
    endcase
end

// --------------------------------------------------------------------------
// 7-segment decode
// Encoding verified against reference controller:
//   seg[6]=CG  seg[5]=CF  seg[4]=CE  seg[3]=CD
//   seg[2]=CC  seg[1]=CB  seg[0]=CA   (active LOW)
// --------------------------------------------------------------------------
function [6:0] seg_decode;
    input [3:0] val;
    input       blank;
    begin
        if (blank) begin
            seg_decode = 7'b111_1111;  // all segments OFF
        end else begin
            case (val)
                //              CG CF CE CD CC CB CA
                4'd0: seg_decode = 7'b100_0000;
                4'd1: seg_decode = 7'b111_1001;
                4'd2: seg_decode = 7'b010_0100;
                4'd3: seg_decode = 7'b011_0000;
                4'd4: seg_decode = 7'b001_1001;
                4'd5: seg_decode = 7'b001_0010;
                4'd6: seg_decode = 7'b000_0010;
                4'd7: seg_decode = 7'b111_1000;
                4'd8: seg_decode = 7'b000_0000;
                4'd9: seg_decode = 7'b001_0000;
                default: seg_decode = 7'b111_1111;
            endcase
        end
    end
endfunction

// --------------------------------------------------------------------------
// Output registers  (registered to prevent glitches on anode transitions)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        seg <= 7'b111_1111;
        an  <= 4'b1111;
        dp  <= 1'b1;
    end else begin
        seg <= seg_decode(cur_val, cur_blank);
        an  <= ~(4'b0001 << digit);   // active-low: only selected anode goes LOW
        dp  <= cur_dp;
    end
end

endmodule
