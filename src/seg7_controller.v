`timescale 1ns/1ps
// seg7_controller.v -- 4-digit multiplexed 7-segment display
// SW0=0: profit percent as "XX.XX" (hundredths of %, dp after AN2)
// SW0=1: raw Q16.16 magnitude 0-9999, no decimal point
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

// Percent mode: hundredths of % (1.23% -> 123), clamped to 9999.
// 64-bit intermediate so the multiply is not truncated.
wire [63:0] pct_wide = ({32'b0, raw_val} * 64'd10000) >> 16;
wire [13:0] pct_val  = (pct_wide > 64'd9999) ? 14'd9999 : pct_wide[13:0];

// Raw mode: bits [15:0] of the Q16.16 magnitude (integer part [31:16] is
// always 0 for sub-100% profit), clamped to 9999.
wire [13:0] raw_14 = (raw_val[15:0] > 16'd9999) ? 14'd9999 : raw_val[13:0];

wire [13:0] disp_val = sw_mode ? raw_14 : pct_val;

// 14-bit binary -> 4-digit BCD (combinational double-dabble)
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

// Blank the thousands digit when zero so the display reads at least "0X.XX"
wire blank_d3 = (d3 == 4'd0);

// Refresh counter and digit selector
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

// Select current digit value, blank flag, and decimal point.
// dp is active-LOW like the segments; it sits after the AN2 digit ("XX.XX")
// and is lit only in percent mode.
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

// 7-segment decode: seg[6:0] = {CG,CF,CE,CD,CC,CB,CA}, active LOW
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

// Registered outputs prevent glitches on anode transitions
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
