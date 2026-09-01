`timescale 1ns/1ps
// uart_tx.v -- 8-N-1 UART transmitter; pulse 'start' to send a byte,
// 'busy' stays high for the duration of the frame
module uart_tx #(
    parameter CLK_HZ = 100_000_000,
    parameter BAUD   = 57600
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       start,
    output reg        tx,
    output reg        busy
);

localparam integer CLKS_PER_BIT = CLK_HZ / BAUD;

localparam S_IDLE  = 2'd0,
           S_START = 2'd1,
           S_DATA  = 2'd2,
           S_STOP  = 2'd3;

reg [1:0]                         state;
reg [$clog2(CLKS_PER_BIT+1)-1:0] clk_cnt;
reg [2:0]                         bit_idx;
reg [7:0]                         shift;

always @(posedge clk) begin
    if (rst) begin
        state   <= S_IDLE;
        tx      <= 1'b1;
        busy    <= 1'b0;
        clk_cnt <= 0;
        bit_idx <= 0;
        shift   <= 0;
    end else begin
        case (state)

            S_IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                if (start) begin
                    shift   <= data;
                    busy    <= 1'b1;
                    clk_cnt <= CLKS_PER_BIT - 1;
                    state   <= S_START;
                end
            end

            // Send start bit (LOW)
            S_START: begin
                tx <= 1'b0;
                if (clk_cnt == 0) begin
                    clk_cnt <= CLKS_PER_BIT - 1;
                    bit_idx <= 0;
                    state   <= S_DATA;
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            // Send 8 data bits, LSB first
            S_DATA: begin
                tx <= shift[0];
                if (clk_cnt == 0) begin
                    shift   <= {1'b0, shift[7:1]};   // shift right
                    clk_cnt <= CLKS_PER_BIT - 1;
                    if (bit_idx == 7)
                        state <= S_STOP;
                    else
                        bit_idx <= bit_idx + 1;
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            // Send stop bit (HIGH)
            S_STOP: begin
                tx <= 1'b1;
                if (clk_cnt == 0) begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                end else
                    clk_cnt <= clk_cnt - 1;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
