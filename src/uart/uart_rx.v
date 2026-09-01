`timescale 1ns/1ps
// uart_rx.v -- 8-N-1 UART receiver; 'valid' pulses one cycle per byte
module uart_rx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 57600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid
);

localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

// Two-FF synchroniser on rx to avoid metastability
reg rx_s0, rx_s1;
always @(posedge clk) begin
    rx_s0 <= rx;
    rx_s1 <= rx_s0;
end

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

            // Wait for falling edge (start bit)
            S_IDLE: begin
                if (!rx_s1) begin
                    state   <= S_START;
                    clk_cnt <= CLKS_PER_BIT / 2;  // sample mid-bit
                end
            end

            // Verify start bit is still low at mid-point
            S_START: begin
                if (clk_cnt == 0) begin
                    if (!rx_s1) begin
                        state   <= S_DATA;
                        bit_idx <= 0;
                        clk_cnt <= CLKS_PER_BIT;
                    end else
                        state <= S_IDLE;  // glitch, abort
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            // Shift in 8 data bits, LSB first
            S_DATA: begin
                if (clk_cnt == 0) begin
                    shift   <= {rx_s1, shift[7:1]};  // LSB-first shift
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
                    if (rx_s1) begin    // stop bit must be high (valid frame)
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
