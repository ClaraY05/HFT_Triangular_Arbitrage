`timescale 1ns/1ps
// uart_top.v -- UART digit test (Basys 3): displays a received ASCII digit
// '0'-'9' on all four 7-seg positions and echoes the raw byte back.
// btnC = synchronous reset. Separate build from the main design.
module top (
    input  wire        clk,
    input  wire        btnC,
    input  wire        rx,
    output wire        tx,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp
);

// Synchronous reset
reg rst_r;
always @(posedge clk) rst_r <= btnC;
wire rst = rst_r;

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

// Echo the received byte straight back. 'busy' is unchecked: the host waits
// for each echo before sending the next digit, so frames never collide.
uart_tx #(
    .CLK_HZ (100_000_000),
    .BAUD   (57600)
) u_uart_tx (
    .clk   (clk),
    .rst   (rst),
    .data  (rx_data),
    .start (rx_valid),
    .tx    (tx),
    .busy  ()
);

// Latch ASCII '0'-'9'; ignore anything else
reg [3:0] digit;

always @(posedge clk) begin
    if (rst) begin
        digit <= 4'd0;
    end else if (rx_valid && rx_data >= 8'h30 && rx_data <= 8'h39) begin
        digit <= rx_data[3:0];
    end
end

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
