`timescale 1ns/1ps
// =============================================================================
// top.v  --  Triangular Arbitrage Detection Engine  (Basys 3)
// =============================================================================
// Data flow:
//   Python → USB-UART → uart_rx → matrix_buffer (BRAM)
//              → control_fsm → fw_engine → arb_detector
//              → led_controller / seg7_controller / vga_top
// =============================================================================
module top (
    input  wire        clk,       // 100 MHz on-board clock
    input  wire        btnC,      // centre button = synchronous reset
    input  wire        sw0,       // 7-seg mode: 0=raw value, 1=profit %
    input  wire        rx,        // UART RX from USB-UART bridge (pin B18)
    // Outputs
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire [3:0]  an,
    output wire        dp,
    output wire        vga_hsync,
    output wire        vga_vsync,
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

// --------------------------------------------------------------------------
// Synchronous reset (one flip-flop synchroniser on btnC)
// --------------------------------------------------------------------------
reg rst_r;
wire rst = rst_r;
always @(posedge clk) rst_r <= btnC;

// --------------------------------------------------------------------------
// UART RX  (115200-8-N-1)
// --------------------------------------------------------------------------
wire       byte_valid;
wire [7:0] byte_data;

uart_rx #(
    .CLK_HZ (100_000_000),
    .BAUD   (115200)
) u_uart (
    .clk   (clk),
    .rst   (rst),
    .rx    (rx),
    .data  (byte_data),
    .valid (byte_valid)
);

// --------------------------------------------------------------------------
// Matrix buffer  (16 × 32-bit words in inferred BRAM)
// --------------------------------------------------------------------------
wire        buf_ready;
wire [3:0]  mat_addr;
wire [31:0] mat_data;

matrix_buffer u_buf (
    .clk        (clk),
    .rst        (rst),
    .byte_in    (byte_data),
    .byte_valid (byte_valid),
    .ready      (buf_ready),
    .rd_addr    (mat_addr),
    .rd_data    (mat_data)
);

// --------------------------------------------------------------------------
// Control FSM  (IDLE → LOAD → RUN → DONE → IDLE)
// --------------------------------------------------------------------------
wire fsm_run;
wire fw_done;

control_fsm u_fsm (
    .clk       (clk),
    .rst       (rst),
    .buf_ready (buf_ready),
    .fw_done   (fw_done),
    .run       (fsm_run)
);

// --------------------------------------------------------------------------
// Floyd-Warshall engine
// --------------------------------------------------------------------------
wire [31:0] diag0, diag1, diag2, diag3;
wire [15:0] loop_mask;

fw_engine u_fw (
    .clk      (clk),
    .rst      (rst),
    .run      (fsm_run),
    .mat_addr (mat_addr),
    .mat_data (mat_data),
    .done     (fw_done),
    .diag0    (diag0),
    .diag1    (diag1),
    .diag2    (diag2),
    .diag3    (diag3),
    .loop_mask(loop_mask)
);

// --------------------------------------------------------------------------
// Arbitrage detector
// --------------------------------------------------------------------------
wire        profit_found;
wire [31:0] profit_val;

arb_detector u_det (
    .clk          (clk),
    .rst          (rst),
    .done         (fw_done),
    .diag0        (diag0),
    .diag1        (diag1),
    .diag2        (diag2),
    .diag3        (diag3),
    .profit_found (profit_found),
    .profit_val   (profit_val)
);

// --------------------------------------------------------------------------
// LED controller  (all 16 flash at ~2 Hz on profit)
// --------------------------------------------------------------------------
led_controller u_led (
    .clk          (clk),
    .rst          (rst),
    .profit_found (profit_found),
    .led          (led)
);

// --------------------------------------------------------------------------
// Seven-segment display  (BCD profit value)
// --------------------------------------------------------------------------
seg7_controller u_seg (
    .clk     (clk),
    .rst     (rst),
    .sw_mode (sw0),
    .raw_val (profit_val),
    .seg     (seg),
    .an      (an),
    .dp      (dp)
);

// --------------------------------------------------------------------------
// VGA  (640×480, 4×4 matrix grid, red highlight on arb cells)
// --------------------------------------------------------------------------
vga_top u_vga (
    .clk          (clk),
    .rst          (rst),
    .profit_found (profit_found),
    .loop_mask    (loop_mask),
    .hsync        (vga_hsync),
    .vsync        (vga_vsync),
    .r            (vga_r),
    .g            (vga_g),
    .b            (vga_b)
);

endmodule
