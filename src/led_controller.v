`timescale 1ns/1ps
// =============================================================================
// led_controller.v  --  Flash all 16 LEDs at ~2 Hz when arbitrage detected
// =============================================================================
// When profit_found is low  → all LEDs off.
// When profit_found is high → LEDs alternate on/off at FLASH_HZ.
// =============================================================================
module led_controller #(
    parameter CLK_HZ   = 100_000_000,
    parameter FLASH_HZ = 2              // blink frequency in Hz
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        profit_found,
    output reg  [15:0] led
);

localparam HALF_PERIOD = CLK_HZ / (FLASH_HZ * 2);  // cycles per half-period

reg [$clog2(HALF_PERIOD+1)-1:0] cnt;
reg phase;

always @(posedge clk) begin
    if (rst || !profit_found) begin
        led   <= 16'h0000;
        cnt   <= 0;
        phase <= 1'b0;
    end else begin
        // Toggle counter
        if (cnt == HALF_PERIOD - 1) begin
            cnt   <= 0;
            phase <= ~phase;
        end else
            cnt <= cnt + 1;

        led <= phase ? 16'hFFFF : 16'h0000;
    end
end

endmodule
