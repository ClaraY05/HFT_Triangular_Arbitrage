`timescale 1ns/1ps
module tb_control_fsm;

reg  clk, rst, buf_ready, fw_done;
wire run;

control_fsm dut (
    .clk(clk), .rst(rst),
    .buf_ready(buf_ready), .fw_done(fw_done),
    .run(run)
);

initial clk = 0;
always #5 clk = ~clk;

integer errors, run_count;

initial begin
    $dumpfile("tb_control_fsm.vcd");
    $dumpvars(0, tb_control_fsm);
    errors=0; buf_ready=0; fw_done=0;
    rst=1; repeat(4) @(posedge clk); rst=0;

    // --- Test 1: buf_ready ? run asserts exactly once ---
    run_count = 0;
    @(posedge clk); buf_ready=1;
    @(posedge clk); buf_ready=0;

    // Count run pulses over next 10 cycles
    repeat(10) begin
        @(posedge clk);
        if (run) run_count = run_count + 1;
    end
    if (run_count !== 1) begin
        $display("FAIL T1: run pulsed %0d times (expected 1)", run_count); errors=errors+1;
    end else $display("PASS T1: run pulsed exactly once");

    // --- Test 2: fw_done ? FSM returns to IDLE (no spurious run) ---
    @(posedge clk); fw_done=1;
    @(posedge clk); fw_done=0;
    run_count=0;
    repeat(5) begin @(posedge clk); if(run) run_count=run_count+1; end
    if (run_count !== 0) begin
        $display("FAIL T2: spurious run after fw_done"); errors=errors+1;
    end else $display("PASS T2: no spurious run after fw_done");

    // --- Test 3: second matrix triggers a new run ---
    run_count=0;
    @(posedge clk); buf_ready=1;
    @(posedge clk); buf_ready=0;
    repeat(10) begin @(posedge clk); if(run) run_count=run_count+1; end
    if (run_count !== 1) begin
        $display("FAIL T3: second buf_ready produced %0d run pulses", run_count); errors=errors+1;
    end else $display("PASS T3: second matrix triggers run correctly");

    if (errors==0) $display("\n=== CONTROL FSM TESTS PASSED ===");
    else           $display("\n=== %0d CONTROL FSM TEST(S) FAILED ===", errors);
    $finish;
end
initial begin #1_000_000; $display("TIMEOUT"); $finish; end
endmodule