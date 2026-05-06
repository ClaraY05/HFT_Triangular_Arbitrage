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

// Latch the one-cycle ready pulse
reg ready_seen;
always @(posedge clk)
    if (ready) ready_seen <= 1'b1;

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

    rst        = 1;
    byte_valid = 0;
    byte_in    = 0;
    rd_addr    = 0;
    ready_seen = 0;
    errors     = 0;

    repeat (5) @(posedge clk);
    rst = 0;

    // Build expected words
    for (i = 0; i < 16; i = i+1)
        expected[i] = 32'h01020304 + i;

    // Send all 64 bytes little-endian
    for (i = 0; i < 16; i = i+1) begin
        send_byte(expected[i][7:0]);
        send_byte(expected[i][15:8]);
        send_byte(expected[i][23:16]);
        send_byte(expected[i][31:24]);
    end

    // Wait a few cycles then check latched flag
    repeat (5) @(posedge clk);
    if (!ready_seen) begin
        $display("FAIL: ready never pulsed"); errors = errors + 1;
    end else
        $display("PASS: ready pulsed");

    // Verify all 16 words via read port
    @(posedge clk);
    for (i = 0; i < 16; i = i+1) begin
        rd_addr = i;
        @(posedge clk);
        @(posedge clk); // 1-cycle read latency
        if (rd_data !== expected[i]) begin
            $display("FAIL word[%0d]: got %08X, expected %08X", i, rd_data, expected[i]);
            errors = errors + 1;
        end else
            $display("PASS word[%0d] = %08X", i, rd_data);
    end

    // --- Edge case: ready must NOT pulse before 64 bytes ---
    ready_seen = 0;
    rst = 1; @(posedge clk); rst = 0;
    for (i = 0; i < 63; i = i+1) send_byte(8'hAA);
    repeat (3) @(posedge clk);
    if (ready_seen) begin
        $display("FAIL: ready pulsed early (only 63 bytes sent)"); errors=errors+1;
    end else
        $display("PASS: no spurious ready on 63 bytes");

    if (errors == 0) $display("\n=== MATRIX BUFFER TESTS PASSED ===");
    else             $display("\n=== %0d MATRIX BUFFER TEST(S) FAILED ===", errors);
    $finish;
end

initial begin #5_000_000; $display("TIMEOUT"); $finish; end

endmodule