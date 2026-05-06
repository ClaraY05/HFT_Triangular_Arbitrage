`timescale 1ns/1ps
module tb_fw_engine;

reg        clk, rst, run;
wire [3:0] mat_addr;
reg [31:0] mat_data;
wire       done;
wire [31:0] diag0, diag1, diag2, diag3;
wire [15:0] loop_mask;

fw_engine dut (
    .clk       (clk),
    .rst       (rst),
    .run       (run),
    .mat_addr  (mat_addr),
    .mat_data  (mat_data),
    .done      (done),
    .diag0     (diag0),
    .diag1     (diag1),
    .diag2     (diag2),
    .diag3     (diag3),
    .loop_mask (loop_mask)
);

initial clk = 0;
always #5 clk = ~clk;

localparam INF = 32'h3FFF_FFFF;
localparam signed [31:0] NEG = -32'd10000;

reg [31:0] test_mat [0:15];
integer i;

// BRAM model
reg [3:0] addr_d;
always @(posedge clk) begin
    addr_d   <= mat_addr;
    mat_data <= test_mat[addr_d];
end

// Capture diagonals on the done pulse itself
reg [31:0] cap_diag0, cap_diag1, cap_diag2, cap_diag3;
reg [15:0] cap_mask;
always @(posedge clk) begin
    if (done) begin
        cap_diag0 <= diag0;
        cap_diag1 <= diag1;
        cap_diag2 <= diag2;
        cap_diag3 <= diag3;
        cap_mask  <= loop_mask;
    end
end

integer errors;
integer cycle_count;

initial begin
    $dumpfile("tb_fw_engine.vcd");
    $dumpvars(0, tb_fw_engine);

    // FIX 3: initialise test_mat before anything runs
    for (i = 0; i < 16; i = i+1) test_mat[i] = INF;
    test_mat[0]  = 32'd0;
    test_mat[5]  = 32'd0;
    test_mat[10] = 32'd0;
    test_mat[15] = 32'd0;
    test_mat[1]  = NEG;   // [0][1] = -10000
    test_mat[4]  = NEG;   // [1][0] = -10000

    rst    = 1;
    run    = 0;
    errors = 0;
    repeat (5) @(posedge clk);
    rst = 0;
    repeat (2) @(posedge clk);

    @(posedge clk); run = 1;
    @(posedge clk); run = 0;

    // FIX 1 & 2: poll for done explicitly, don't rely on disable fork
    cycle_count = 0;
    while (!done && cycle_count < 200) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end

    if (!done) begin
        $display("TIMEOUT: done never asserted after 200 cycles");
        $finish;
    end

    // FIX 2: wait one more cycle for cap registers to settle
    @(posedge clk);

    $display("diag0 = %0d (expected -20000)", $signed(cap_diag0));
    $display("diag1 = %0d (expected -40000)", $signed(cap_diag1));
    $display("diag2 = %0d (expected 0)",      $signed(cap_diag2));
    $display("diag3 = %0d (expected 0)",      $signed(cap_diag3));
    $display("loop_mask = %04X", cap_mask);

    if ($signed(cap_diag0) >= 0) begin
        $display("FAIL: diag0 should be negative, got %0d", $signed(cap_diag0));
        errors = errors + 1;
    end else
        $display("PASS: diag0 = %0d", $signed(cap_diag0));

    if ($signed(cap_diag1) >= 0) begin
        $display("FAIL: diag1 should be negative, got %0d", $signed(cap_diag1));
        errors = errors + 1;
    end else
        $display("PASS: diag1 = %0d", $signed(cap_diag1));

    if (errors == 0)
        $display("\n=== ALL FW ENGINE TESTS PASSED ===");
    else
        $display("\n=== %0d FW ENGINE TEST(S) FAILED ===", errors);

    $finish;
end

initial begin
    #1_000_000;
    $display("TIMEOUT - FW engine did not assert done");
    $finish;
end

endmodule