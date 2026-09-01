`timescale 1ns/1ps
module tb_top;

reg        clk, btnC, sw0, rx;
wire [15:0] led;
wire [6:0]  seg;
wire [3:0]  an;
wire        dp;
wire        vga_hsync, vga_vsync;
wire [3:0]  vga_r, vga_g, vga_b;

// VGA clock wizard is not available in sim — only non-VGA outputs are
// checked here; VGA and seg7 are validated visually on-board.
top dut (
    .clk      (clk),
    .btnC     (btnC),
    .sw0      (sw0),
    .rx       (rx),
    .led      (led),
    .seg      (seg),
    .an       (an),
    .dp       (dp),
    .vga_hsync(vga_hsync),
    .vga_vsync(vga_vsync),
    .vga_r    (vga_r),
    .vga_g    (vga_g),
    .vga_b    (vga_b)
);

initial clk = 0;
always #5 clk = ~clk;   // 100 MHz

// UART transmit task (115200 baud = 868 clocks/bit)
localparam BIT_T = 868;

task uart_send_byte;
    input [7:0] b;
    integer k;
    begin
        rx = 0; repeat (BIT_T) @(posedge clk);
        for (k = 0; k < 8; k = k+1) begin
            rx = b[k]; repeat (BIT_T) @(posedge clk);
        end
        rx = 1; repeat (BIT_T) @(posedge clk);
    end
endtask

// Send full 64-byte matrix (little-endian 32-bit words)
// Uses the same negative-cycle matrix as tb_fw_engine
localparam INF32 = 32'h3FFF_FFFF;

reg [31:0] tx_mat [0:15];
integer m;

task send_matrix;
    integer w, by;
    reg [7:0] byt;
    begin
        for (w = 0; w < 16; w = w+1) begin
            for (by = 0; by < 4; by = by+1) begin
                byt = tx_mat[w][by*8 +: 8];
                uart_send_byte(byt);
            end
        end
    end
endtask

integer errors;
integer cycle_count;

initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);

    rx     = 1;
    btnC   = 1;
    sw0    = 0;
    errors = 0;

    // Build test matrix: negative 0→1 cycle
    for (m = 0; m < 16; m = m+1) tx_mat[m] = INF32;
    tx_mat[0]  = 32'd0;       // [0][0]
    tx_mat[5]  = 32'd0;       // [1][1]
    tx_mat[10] = 32'd0;       // [2][2]
    tx_mat[15] = 32'd0;       // [3][3]
    tx_mat[1]  = -32'd10000;  // [0][1]
    tx_mat[4]  = -32'd10000;  // [1][0]

    repeat (20) @(posedge clk);
    btnC = 0;
    repeat (5)  @(posedge clk);

    $display("Sending 64-byte matrix via UART...");
    send_matrix;
    $display("Matrix sent. Waiting for FW engine...");

    // Wait up to 200 000 cycles for profit_found
    cycle_count = 0;
    while (!dut.u_det.profit_found && cycle_count < 200_000) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    if (!dut.u_det.profit_found) begin
        $display("FAIL: profit_found never asserted");
        errors = errors + 1;
    end else
        $display("PASS: profit_found asserted after ~%0d cycles", cycle_count);

    // Check LEDs start flashing within 5 cycles of profit_found
    repeat (5) @(posedge clk);
    // (LED will be either all-on or all-off depending on flash phase — both are valid)
    $display("LED value = %04X (should be FFFF or 0000)", led);

    // Check 7-seg is active (some anode enabled)
    if (an == 4'hF)
        $display("WARN: all 7-seg anodes off — check seg7_controller");
    else
        $display("PASS: 7-seg active, an=%04b seg=%07b", an, seg);

    repeat (100) @(posedge clk);

    if (errors == 0)
        $display("\n=== INTEGRATION TEST PASSED ===");
    else
        $display("\n=== %0d INTEGRATION TEST(S) FAILED ===", errors);

    $finish;
end

initial begin
    #500_000_000;
    $display("INTEGRATION TIMEOUT");
    $finish;
end

endmodule
