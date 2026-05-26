`timescale 1ns/1ps
// =============================================================================
// top.v  --  UART Digit Test  (Basys 3)  — with echo
// =============================================================================
// A Python script sends an ASCII character '0'-'9' at 57600 baud.
// The FPGA:
//   1. Displays the digit on all four seven-segment positions.
//   2. Echoes the raw received byte back over UART TX so the Python
//      script can confirm what the FPGA actually received.
//
// btnC = synchronous reset (centre button)
// rx   = USB-UART RX pin (B18)
// tx   = USB-UART TX pin (A18)
// =============================================================================
module top (
    input  wire        clk,
    input  wire        btnC,
    input  wire        rx,
    output wire        tx,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);

// --------------------------------------------------------------------------
// Synchronous reset
// --------------------------------------------------------------------------
reg rst_r;
always @(posedge clk) rst_r <= btnC;
wire rst = rst_r;

// --------------------------------------------------------------------------
// UART RX
// --------------------------------------------------------------------------
wire [7:0] rx_data;
wire       rx_valid;

uart_rx #(
    .CLK_HZ (100_000_000),
    .BAUD   (57600)
) u_uart_rx (
    .clk   (clk),
    .rst   (rst),
    .rx    (rx),
    .data  (rx_data),
    .valid (rx_valid)
);

// --------------------------------------------------------------------------
// UART TX  —  echo the received byte straight back
// rx_valid is already a single-cycle pulse, so use it directly as 'start'.
// 'busy' is not checked here: at 57600 baud one frame takes ~174 µs, and
// the Python sender waits for an echo reply before sending the next digit,
// so back-to-back collisions won't happen in normal use.
// --------------------------------------------------------------------------
uart_tx #(
    .CLK_HZ (100_000_000),
    .BAUD   (57600)
) u_uart_tx (
    .clk   (clk),
    .rst   (rst),
    .data  (rx_data),   // echo the exact byte received
    .start (rx_valid),  // send immediately on valid pulse
    .tx    (tx),
    .busy  ()           // unused — see note above
);

// --------------------------------------------------------------------------
// Digit latch  (accept ASCII '0'–'9'; ignore anything else)
// --------------------------------------------------------------------------
reg [3:0] digit;

always @(posedge clk) begin
    if (rst) begin
        digit <= 4'd0;
    end else if (rx_valid && rx_data >= 8'h30 && rx_data <= 8'h39) begin
        digit <= rx_data[3:0];
    end
end

// --------------------------------------------------------------------------
// Seven-segment display
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
