`timescale 1ns/1ps
module tb_arb_detector;

reg        clk, rst, done;
reg [31:0] diag0, diag1, diag2, diag3;
wire       profit_found;
wire [31:0] profit_val;

arb_detector dut (
    .clk(clk), .rst(rst), .done(done),
    .diag0(diag0), .diag1(diag1), .diag2(diag2), .diag3(diag3),
    .profit_found(profit_found), .profit_val(profit_val)
);

initial clk = 0;
always #5 clk = ~clk;

task pulse_done;
    begin @(posedge clk); done = 1; @(posedge clk); done = 0; end
endtask

integer errors;
localparam INF = 32'h3FFF_FFFF;

initial begin
    $dumpfile("tb_arb_detector.vcd");
    $dumpvars(0, tb_arb_detector);
    errors = 0; done = 0;
    rst = 1; repeat(4) @(posedge clk); rst = 0;

    // --- Test 1: no negative diagonal ? no profit ---
    diag0=0; diag1=INF; diag2=INF; diag3=INF;
    pulse_done;
    @(posedge clk);
    if (profit_found) begin
        $display("FAIL T1: profit_found should be 0"); errors=errors+1;
    end else $display("PASS T1: no profit on all-positive diags");

    // --- Test 2: diag0 negative only ---
    diag0 = -32'd5000; diag1=0; diag2=0; diag3=0;
    pulse_done;
    @(posedge clk);
    if (!profit_found || profit_val !== 32'd5000) begin
        $display("FAIL T2: profit_found=%0b profit_val=%0d", profit_found, profit_val);
        errors=errors+1;
    end else $display("PASS T2: diag0 negative detected, val=%0d", profit_val);

    // --- Test 3: multiple negative, picks most negative ---
    diag0=-32'd1000; diag1=-32'd9999; diag2=-32'd500; diag3=0;
    pulse_done;
    @(posedge clk);
    if (!profit_found || profit_val !== 32'd9999) begin
        $display("FAIL T3: expected profit_val=9999, got %0d", profit_val);
        errors=errors+1;
    end else $display("PASS T3: most negative selected, val=%0d", profit_val);

    // --- Test 4: reset clears state ---
    rst = 1; @(posedge clk); rst = 0; @(posedge clk);
    if (profit_found) begin
        $display("FAIL T4: profit_found should clear after reset"); errors=errors+1;
    end else $display("PASS T4: reset clears profit_found");

    if (errors==0) $display("\n=== ARB DETECTOR TESTS PASSED ===");
    else           $display("\n=== %0d ARB DETECTOR TEST(S) FAILED ===", errors);
    $finish;
end
initial begin #1_000_000; $display("TIMEOUT"); $finish; end
endmodule