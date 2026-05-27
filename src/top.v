`timescale 1ns/1ps
// =============================================================================
// top.v  --  Arbitrage detector top-level  (with UART TX reporting)
// =============================================================================
// Added vs original:
//   - 'tx' output port
//   - uart_tx instance
//   - uart_reporter instance (echo + result packet)
// Everything else is unchanged.
// =============================================================================
module top (
    input  wire        clk,
    input  wire        btnC,
    input  wire        sw0,
    input  wire        rx,
    output wire        tx,        // <<< NEW: UART TX (pin A18)
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
// Synchronous reset
// --------------------------------------------------------------------------
reg rst_r;
wire rst = rst_r;
always @(posedge clk) rst_r <= btnC;

// --------------------------------------------------------------------------
// UART RX
// --------------------------------------------------------------------------
wire       byte_valid;
wire [7:0] byte_data;
uart_rx #(.CLK_HZ(100_000_000), .BAUD(57600)) u_uart_rx (
    .clk(clk), .rst(rst), .rx(rx), .data(byte_data), .valid(byte_valid)
);

// --------------------------------------------------------------------------
// Matrix buffer
// --------------------------------------------------------------------------
wire        buf_ready;
wire [3:0]  mat_addr;
wire [31:0] mat_data;
matrix_buffer u_buf (
    .clk(clk), .rst(rst),
    .byte_in(byte_data), .byte_valid(byte_valid),
    .ready(buf_ready),
    .rd_addr(mat_addr), .rd_data(mat_data)
);

// --------------------------------------------------------------------------
// Control FSM
// --------------------------------------------------------------------------
wire fsm_run, fw_done;
control_fsm u_fsm (
    .clk(clk), .rst(rst),
    .buf_ready(buf_ready), .fw_done(fw_done), .run(fsm_run)
);

// --------------------------------------------------------------------------
// Floyd-Warshall engine
// --------------------------------------------------------------------------
wire [31:0] diag0, diag1, diag2, diag3;
wire [15:0] loop_mask;
fw_engine u_fw (
    .clk(clk), .rst(rst), .run(fsm_run),
    .mat_addr(mat_addr), .mat_data(mat_data),
    .done(fw_done),
    .diag0(diag0), .diag1(diag1), .diag2(diag2), .diag3(diag3),
    .loop_mask(loop_mask)
);

// --------------------------------------------------------------------------
// Arbitrage detector
// --------------------------------------------------------------------------
wire        profit_found;
wire [31:0] profit_val;
arb_detector u_det (
    .clk(clk), .rst(rst), .done(fw_done),
    .diag0(diag0), .diag1(diag1), .diag2(diag2), .diag3(diag3),
    .profit_found(profit_found), .profit_val(profit_val)
);

// Compute profit_pct_x100: (profit_val * 10000) >> 16, clamped to 9999
// profit_val is Q16.16 so this gives XX.XX% as integer XXYY
wire [47:0] pct_wide = ({16'd0, profit_val} * 48'd10000) >> 16;
wire [13:0] profit_pct_x100 = (pct_wide > 48'd9999) ? 14'd9999 : pct_wide[13:0];

// --------------------------------------------------------------------------
// UART TX
// --------------------------------------------------------------------------
wire [7:0] rep_tx_data;
wire       rep_tx_start;
wire       rep_tx_busy;

uart_tx #(.CLK_HZ(100_000_000), .BAUD(57600)) u_uart_tx (
    .clk  (clk),
    .rst  (rst),
    .data (rep_tx_data),
    .start(rep_tx_start),
    .tx   (tx),
    .busy (rep_tx_busy)
);

// --------------------------------------------------------------------------
// UART reporter  (echo during receive + result packet after FW completes)
// --------------------------------------------------------------------------
uart_reporter u_reporter (
    .clk          (clk),
    .rst          (rst),
    // Echo path
    .rx_data      (byte_data),
    .rx_valid     (byte_valid),
    // Result path
    .fw_done      (fw_done),
    .profit_found (profit_found),
    .profit_val   (profit_val),
    .diag0        (diag0),
    .diag1        (diag1),
    .diag2        (diag2),
    .diag3        (diag3),
    // uart_tx interface
    .tx_data      (rep_tx_data),
    .tx_start     (rep_tx_start),
    .tx_busy      (rep_tx_busy)
);

// --------------------------------------------------------------------------
// LEDs
// --------------------------------------------------------------------------
led_controller u_led (
    .clk(clk), .rst(rst), .profit_found(profit_found), .led(led)
);

// --------------------------------------------------------------------------
// Seven-segment display
// --------------------------------------------------------------------------
seg7_controller u_seg (
    .clk(clk), .rst(rst), .sw_mode(sw0),
    .raw_val(profit_val), .seg(seg), .an(an), .dp(dp)
);

// --------------------------------------------------------------------------
// VGA
// --------------------------------------------------------------------------
vga_top u_vga (
    .clk(clk), .rst(rst),
    .profit_found(profit_found),
    .loop_mask(loop_mask),
    .profit_pct_x100(profit_pct_x100),
    .profit_val(profit_val),
    .hsync(vga_hsync), .vsync(vga_vsync),
    .r(vga_r), .g(vga_g), .b(vga_b)
);

endmodule
