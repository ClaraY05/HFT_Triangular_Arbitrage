`timescale 1ns/1ps
module uart_rx #( // (uart_rx.v) Universal Asynchronous Receiver-Transmitter Receiver
    parameter CLK_HZ = 100_000_000, // system clock frequency in Hz, (default 100 MHz)
    parameter BAUD   = 115200       // desired baud rate (default 115200)
)
(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,         // received byte, valid when 'valid' is high for one clock cycle
    output reg        valid         // pulse when a complete byte has been received
);

localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;  // (default 868 @ 100 MHz / 115200)

// Two-FlipFlop synchroniser on rx to avoid metastability
reg rx_s0, rx_s1;
always @(posedge clk) begin
    rx_s0 <= rx;
    rx_s1 <= rx_s0;
end

// State machine, detects and outputs valid bytes received
localparam S_IDLE  = 2'd0,
           S_START = 2'd1,
           S_DATA  = 2'd2,
           S_STOP  = 2'd3;

reg [1:0]               state;
reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_cnt;
reg [3:0]               bit_idx;
reg [7:0]               shift;

always @(posedge clk) begin
    valid <= 1'b0;

    if (rst) begin
        state   <= S_IDLE;
        clk_cnt <= 0;
        bit_idx <= 0;
    end else begin
        case (state)

            // Wait for falling edge
            S_IDLE: begin
                if (!rx_s1) begin
                    state   <= S_START;
                    clk_cnt <= CLKS_PER_BIT / 2; 
                end
            end

            S_START: begin
                if (clk_cnt == 0) begin
                    if (!rx_s1) begin
                        state   <= S_DATA;
                        bit_idx <= 0;
                        clk_cnt <= CLKS_PER_BIT;
                    end else
                        state <= S_IDLE; 
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            // Shift in 8 data bits, LSB first
            S_DATA: begin
                if (clk_cnt == 0) begin
                    shift   <= {rx_s1, shift[7:1]}; 
                    clk_cnt <= CLKS_PER_BIT;
                    if (bit_idx == 7)
                        state <= S_STOP;
                    else
                        bit_idx <= bit_idx + 1;
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            // Sample stop bit, output byte
            S_STOP: begin
                if (clk_cnt == 0) begin
                    if (rx_s1) begin    // stop bit must be high
                        data  <= shift;
                        valid <= 1'b1;
                    end
                    state <= S_IDLE;
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
