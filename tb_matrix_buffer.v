`timescale 1ns/1ps
module tb_matrix_buffer;

reg        clk, rst;
reg [7:0]  byte_in;
reg        byte_valid;
wire       ready;
reg [3:0]  rd_addr;
wire [31:0] rd_data;

matrix_buffer dut (
    .clk(clk), .rst(rst),
    .byte_in(byte_in), .byte_valid(byte_valid),
    .ready(ready),
    .rd_addr(rd_addr), .rd_data(rd_data)
);

initial clk = 0;
always #5 clk = ~clk;

// Send one byte per clock (back-to-back)
task send_byte;
    input [7:0] b;
    begin
        @(posedge clk);
        byte_in    = b;
        byte_valid = 1;
        @(posedge clk);
        byte_valid = 0;
    end
endtask

integer i, errors;
reg [31:0] expected [0:15];

initial begin
    $dumpfile("tb_matrix_buffer.vcd");
    $dumpvars(0, tb_matrix_buffer);

    rst = 1; byte_valid = 0; errors = 0;
    repeat (5) @(posedge clk);
    rst = 0;

    // Fill expected[]: word N = 32'hAABBCCDD shifted by N
    // Send as little-endian bytes: LSB first
    for (i = 0; i < 16; i = i+1)
        expected[i] = 32'h01020304 + i;  // distinct per word

    for (i = 0; i < 16; i = i+1) begin
        send_byte(expected[i][7:0]);    // byte 0 (LSB)
        send_byte(expected[i][15:8]);   // byte 1
        send_byte(expected[i][23:16]);  // byte 2
        send_byte(expected[i][31:24]);  // byte 3 (MSB)
    end

    // Wait for ready pulse
    repeat (5) @(posedge clk);
    if (!ready) begin
        $display("FAIL: ready never pulsed"); errors = errors + 1;
    end else
        $display("PASS: ready pulsed");

    // Verify all 16 words via read port
    @(posedge clk);
    for (i = 0; i < 16; i = i+1) begin
        rd_addr = i;
        @(posedge clk); // 1-cycle read latency
        @(posedge clk);
        if (rd_data !== expected[i]) begin
            $display("FAIL word[%0d]: got %08X, expected %08X", i, rd_data, expected[i]);
            errors = errors + 1;
        end else
            $display("PASS word[%0d] = %08X", i, rd_data);
    end

    // --- Edge case: ready must NOT pulse before 64 bytes ---
    rst = 1; @(posedge clk); rst = 0;
    for (i = 0; i < 63; i = i+1) send_byte(8'hAA);  // only 63 bytes
    repeat (3) @(posedge clk);
    if (ready) begin
        $display("FAIL: ready pulsed early (only 63 bytes sent)"); errors = errors + 1;
    end else
        $display("PASS: no spurious ready on 63 bytes");

    if (errors == 0) $display("\n=== MATRIX BUFFER TESTS PASSED ===");
    else             $display("\n=== %0d MATRIX BUFFER TEST(S) FAILED ===", errors);
    $finish;
end
initial begin #5_000_000; $display("TIMEOUT"); $finish; end
endmodule