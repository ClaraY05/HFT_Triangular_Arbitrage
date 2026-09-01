`timescale 1ns/1ps
// seg7_digit.v -- show one digit (0-9) on all four Basys 3 positions.
// seg[6:0] = {CG,CF,CE,CD,CC,CB,CA}, active-LOW — same encoding as
// seg7_controller.v; uart_digit_test.xdc maps these bits to the pins.
module seg7_digit #(
    parameter CLK_HZ     = 100_000_000,
    parameter REFRESH_HZ = 1000            // anode refresh; 1 kHz = 250 µs per digit
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  digit,   // value 0-9 to display
    output reg  [6:0]  seg,
    output reg  [3:0]  an,
    output reg         dp
);

localparam integer REFRESH_CNT = CLK_HZ / REFRESH_HZ / 4;  // cycles per digit slot

function [6:0] seg_decode;
    input [3:0] val;
    begin
        case (val)
            //             CG CF CE CD CC CB CA
            4'd0: seg_decode = 7'b100_0000;   // 0
            4'd1: seg_decode = 7'b111_1001;   // 1
            4'd2: seg_decode = 7'b010_0100;   // 2
            4'd3: seg_decode = 7'b011_0000;   // 3
            4'd4: seg_decode = 7'b001_1001;   // 4
            4'd5: seg_decode = 7'b001_0010;   // 5
            4'd6: seg_decode = 7'b000_0010;   // 6
            4'd7: seg_decode = 7'b111_1000;   // 7
            4'd8: seg_decode = 7'b000_0000;   // 8
            4'd9: seg_decode = 7'b001_0000;   // 9
            default: seg_decode = 7'b111_1111; // blank
        endcase
    end
endfunction

// Refresh counter and digit selector
reg [$clog2(REFRESH_CNT+1)-1:0] cnt;
reg [1:0] sel;   // 0 = AN0 (rightmost) … 3 = AN3 (leftmost)

always @(posedge clk) begin
    if (rst) begin
        cnt <= 0;
        sel <= 2'd0;
    end else if (cnt == REFRESH_CNT - 1) begin
        cnt <= 0;
        sel <= sel + 1;
    end else begin
        cnt <= cnt + 1;
    end
end

// Registered outputs prevent glitches on digit transitions
always @(posedge clk) begin
    if (rst) begin
        seg <= 7'b111_1111;   // all segments OFF
        an  <= 4'b1111;       // all anodes OFF
        dp  <= 1'b1;          // decimal point OFF
    end else begin
        seg <= seg_decode(digit);
        an  <= ~(4'b0001 << sel);   // active-LOW: only selected anode goes LOW
        dp  <= 1'b1;                // keep decimal point off
    end
end

endmodule
