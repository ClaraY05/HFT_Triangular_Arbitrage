`timescale 1ns/1ps
// =============================================================================
// top.v  --  UART Digit Test  (Basys 3)
// =============================================================================
// A Python script sends an ASCII character '0'-'9' at 57600 baud.
// The FPGA latches the digit value and displays it on all four
// seven-segment digits so it is easy to read from across the desk.
//
// btnC  = synchronous reset (centre button)
// rx    = USB-UART RX pin (B18)
// =============================================================================
module top (
    input  wire        clk,      // 100 MHz
    input  wire        btnC,     // centre button = reset
    input  wire        rx,       // UART RX
    output wire [6:0]  seg,      // seven segments (active-LOW)
    output wire [3:0]  an,       // digit anodes  (active-LOW)
    output wire        dp        // decimal point (active-LOW; kept OFF)
);

// --------------------------------------------------------------------------
// Synchronous reset (one-flop)
// --------------------------------------------------------------------------
reg rst_r;
always @(posedge clk) rst_r <= btnC;
wire rst = rst_r;

// --------------------------------------------------------------------------
// UART receiver  (57 600, 8-N-1, identical parameters to the main project)
// --------------------------------------------------------------------------
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(
    .CLK_HZ (100_000_000),
    .BAUD   (57600)
) u_uart (
    .clk   (clk),
    .rst   (rst),
    .rx    (rx),
    .data  (rx_data),
    .valid (rx_valid)
);

// --------------------------------------------------------------------------
// Digit latch
// Accept ASCII '0' (0x30) through '9' (0x39); ignore everything else.
// The lower nibble of ASCII digits equals the numeric value: '3' -> 0x33
// but only bit[3:0] = 3, which is exactly what we want (0x30[3:0] = 0,
// 0x39[3:0] = 9).
// --------------------------------------------------------------------------
reg [3:0] digit;   // 0-9

always @(posedge clk) begin
    if (rst) begin
        digit <= 4'd0;
    end else if (rx_valid && rx_data >= 8'h30 && rx_data <= 8'h39) begin
        digit <= rx_data[3:0];   // lower nibble gives numeric value directly
    end
end

// --------------------------------------------------------------------------
// Seven-segment display (same digit shown on all four positions)
// --------------------------------------------------------------------------
seg7_digit #(
    .CLK_HZ     (100_000_000),
    .REFRESH_HZ (1000)
) u_seg (
    .clk   (clk),
    .rst   (rst),
    .digit (digit),
    .seg   (seg),
    .an    (an),
    .dp    (dp)
);

endmodule
