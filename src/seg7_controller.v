`timescale 1ns/1ps
// displays the profit value from arb_detector
module seg7_controller #(
    parameter CLK_HZ     = 100_000_000,
    parameter REFRESH_HZ = 1000           //multiplexing refresh rate
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        sw_mode,    // 0=raw profit, 1=profit %
    input  wire [31:0] raw_val,    // from arb_detector (Q16.16)
    output reg  [6:0]  seg,        // segment outputs (active low)
    output reg  [3:0]  an,         // anode enables (active low)
    output reg         dp          // decimal point (active low)
);

localparam REFRESH_CNT = CLK_HZ / REFRESH_HZ / 4;  //per-digit period

wire [19:0] raw_20   = raw_val[19:0];
wire [47:0] pct_full = (48'd10000 * raw_val) >> 16;
wire [19:0] pct_20   = pct_full[19:0];

wire [19:0] disp_val = sw_mode ? pct_20 : raw_20;

wire [3:0] ten_thou, thou, hund, tens, ones;
bin_to_bcd u_bcd (
    .bin      (disp_val),
    .ten_thou (ten_thou),
    .thou     (thou),
    .hund     (hund),
    .tens     (tens),
    .ones     (ones)
);


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


reg [3:0] cur_val;
always @(*) begin
    case (digit)
        2'd3: cur_val = thou;
        2'd2: cur_val = hund;
        2'd1: cur_val = tens;
        2'd0: cur_val = ones;
    endcase
end


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
