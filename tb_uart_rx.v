`timescale 1ns/1ps
// =============================================================================
// tb_uart_rx.v  --  Testbench for uart_rx
// =============================================================================
// Simulates a UART transmitter sending known bytes and checks that uart_rx
// correctly deserializes them.
// =============================================================================
module tb_uart_rx;

// Parameters matching DUT
localparam CLK_HZ = 100_000_000;
localparam BAUD   = 115200;
localparam BIT_T  = CLK_HZ / BAUD;  // clocks per bit = 868

// --------------------------------------------------------------------------
// DUT
// --------------------------------------------------------------------------
reg        clk, rst, rx;
wire [7:0] data;
wire       valid;

uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) dut (
    .clk   (clk),
    .rst   (rst),
    .rx    (rx),
    .data  (data),
    .valid (valid)
);

// --------------------------------------------------------------------------
// Clock: 10 ns period (100 MHz)
// --------------------------------------------------------------------------
initial clk = 0;
always #5 clk = ~clk;

// --------------------------------------------------------------------------
// Task: transmit one byte LSB-first (8-N-1)
// --------------------------------------------------------------------------
task uart_send;
    input [7:0] byte_val;
    integer i;
    begin
        // Start bit (low)
        rx = 0; repeat (BIT_T) @(posedge clk);
        // Data bits LSB first
        for (i = 0; i < 8; i = i+1) begin
            rx = byte_val[i]; repeat (BIT_T) @(posedge clk);
        end
        // Stop bit (high)
        rx = 1; repeat (BIT_T) @(posedge clk);
    end
endtask

// --------------------------------------------------------------------------
// Stimulus
// --------------------------------------------------------------------------
integer errors;
initial begin
    $dumpfile("tb_uart_rx.vcd");
    $dumpvars(0, tb_uart_rx);

    rx     = 1;   // idle high
    rst    = 1;
    errors = 0;
    repeat (10) @(posedge clk);
    rst = 0;

    // Test byte 1: 0xA5
    fork
        uart_send(8'hA5);
        begin
            @(posedge valid);
            if (data !== 8'hA5) begin
                $display("FAIL byte1: expected A5, got %02X", data);
                errors = errors + 1;
            end else
                $display("PASS byte1: 0x%02X", data);
        end
    join

    repeat (5) @(posedge clk);

    // Test byte 2: 0x3C
    fork
        uart_send(8'h3C);
        begin
            @(posedge valid);
            if (data !== 8'h3C) begin
                $display("FAIL byte2: expected 3C, got %02X", data);
                errors = errors + 1;
            end else
                $display("PASS byte2: 0x%02X", data);
        end
    join

    repeat (5) @(posedge clk);

    // Test byte 3: 0xFF
    fork
        uart_send(8'hFF);
        begin
            @(posedge valid);
            if (data !== 8'hFF) begin
                $display("FAIL byte3: expected FF, got %02X", data);
                errors = errors + 1;
            end else
                $display("PASS byte3: 0x%02X", data);
        end
    join

    repeat (10) @(posedge clk);

    if (errors == 0)
        $display("\n=== ALL UART TESTS PASSED ===");
    else
        $display("\n=== %0d UART TEST(S) FAILED ===", errors);

    $finish;
end

// Timeout watchdog
initial begin
    #50_000_000;
    $display("TIMEOUT");
    $finish;
end

endmodule
