`timescale 1ns/1ps
// flash all 16 LEDs at ~2 Hz when arbitrage detected
module led_controller #(
    parameter CLK_HZ   = 100_000_000,
    parameter FLASH_HZ = 2              //blink frequency in Hz
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        profit_found,
    output reg  [15:0] led
);

localparam HALF_PERIOD = CLK_HZ / (FLASH_HZ * 2);  //cycles per half-period

reg [$clog2(HALF_PERIOD+1)-1:0] cnt;
reg phase;

always @(posedge clk) begin
    if (rst || !profit_found) begin
        led   <= 16'h0000;
        cnt   <= 0;
        phase <= 1'b0;
    end else begin
        //toggle counter
        if (cnt == HALF_PERIOD - 1) begin
            cnt   <= 0;
            phase <= ~phase;
        end else
            cnt <= cnt + 1;

        led <= phase ? 16'hFFFF : 16'h0000; //all on in PHASE 1(when profit_found=high), all off in PHASE 0(when profit_found=low)
    end
end

endmodule
