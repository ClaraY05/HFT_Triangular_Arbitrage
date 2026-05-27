`timescale 1ns/1ps
// =============================================================================
// uart_reporter.v  --  UART TX manager for the arbitrage detector
// =============================================================================
//
// BUG FIX: Added S_ECHO_ARM and S_RPT_ARM states to absorb the one-cycle
// gap between pulsing tx_start and uart_tx asserting tx_busy.
//
// Root cause: uart_tx is a clocked FSM. When tx_start fires, it sets
// busy<=1'b1 in the same clock edge — but that new value is not visible
// to uart_reporter until the NEXT cycle. The original S_ECHO_WAIT /
// S_RPT_WAIT checked !tx_busy immediately after the tx_start pulse, saw
// busy=0, and exited early. For the 24-byte result packet this meant every
// odd byte's tx_start fired while uart_tx was still busy on the even byte
// and was silently dropped — producing a malformed or absent packet.
//
// Fix: insert a one-cycle ARM state after each tx_start pulse. The ARM
// state does nothing except wait one cycle so that tx_busy is guaranteed
// to have risen before the WAIT state checks it.
//
// State diagram:
//
//   IDLE ──rx_valid──► ECHO_ARM ──► ECHO_WAIT ──!busy──► IDLE
//      └─report_pending─► RPT_SEND ──► RPT_ARM ──► RPT_WAIT ──!busy──┐
//                              ▲──────────────────────────────────────┘
//                              (loop until all PKT_LEN bytes sent, then → IDLE)
//
// Packet format (24 bytes, little-endian multi-byte fields):
//   [0]    0xAA           header
//   [1]    0x55           header
//   [2]    profit_found   0x00 / 0x01
//   [3:6]  profit_val     Q16.16 magnitude (LE)
//   [7:10] diag0          dist[0][0] (LE)
//   [11:14] diag1         dist[1][1] (LE)
//   [15:18] diag2         dist[2][2] (LE)
//   [19:22] diag3         dist[3][3] (LE)
//   [23]   0xFF           end marker
// =============================================================================
module uart_reporter (
    input  wire        clk,
    input  wire        rst,

    // --- Echo path -----------------------------------------------------------
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // --- Result path ---------------------------------------------------------
    input  wire        fw_done,
    input  wire        profit_found,
    input  wire [31:0] profit_val,
    input  wire [31:0] diag0,
    input  wire [31:0] diag1,
    input  wire [31:0] diag2,
    input  wire [31:0] diag3,

    // --- uart_tx interface ---------------------------------------------------
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy
);

localparam PKT_LEN = 24;

reg [7:0] pkt [0:PKT_LEN-1];
reg [4:0] byte_idx;
reg       report_pending;

// --------------------------------------------------------------------------
// One-cycle delay on fw_done so arb_detector outputs are stable
// --------------------------------------------------------------------------
reg fw_done_d1;
always @(posedge clk) fw_done_d1 <= rst ? 1'b0 : fw_done;

// --------------------------------------------------------------------------
// State machine
// --------------------------------------------------------------------------
localparam S_IDLE      = 3'd0,
           S_ECHO_ARM  = 3'd1,   // absorb one cycle after tx_start pulse (echo)
           S_ECHO_WAIT = 3'd2,   // wait for uart_tx busy to clear (echo)
           S_RPT_SEND  = 3'd3,   // load byte and pulse tx_start (report)
           S_RPT_ARM   = 3'd4,   // absorb one cycle after tx_start pulse (report)
           S_RPT_WAIT  = 3'd5;   // wait for uart_tx busy to clear (report)

reg [2:0] state;

always @(posedge clk) begin
    tx_start <= 1'b0;   // default: no pulse

    if (rst) begin
        state          <= S_IDLE;
        report_pending <= 1'b0;
        byte_idx       <= 5'd0;
        tx_data        <= 8'h00;

    end else begin

        // ------------------------------------------------------------------
        // Latch result packet one cycle after fw_done (arb_detector outputs
        // are registered on the fw_done edge and visible from the next cycle)
        // ------------------------------------------------------------------
        if (fw_done_d1) begin
            pkt[0]  <= 8'hAA;
            pkt[1]  <= 8'h55;
            pkt[2]  <= {7'b0, profit_found};
            pkt[3]  <= profit_val[7:0];
            pkt[4]  <= profit_val[15:8];
            pkt[5]  <= profit_val[23:16];
            pkt[6]  <= profit_val[31:24];
            pkt[7]  <= diag0[7:0];
            pkt[8]  <= diag0[15:8];
            pkt[9]  <= diag0[23:16];
            pkt[10] <= diag0[31:24];
            pkt[11] <= diag1[7:0];
            pkt[12] <= diag1[15:8];
            pkt[13] <= diag1[23:16];
            pkt[14] <= diag1[31:24];
            pkt[15] <= diag2[7:0];
            pkt[16] <= diag2[15:8];
            pkt[17] <= diag2[23:16];
            pkt[18] <= diag2[31:24];
            pkt[19] <= diag3[7:0];
            pkt[20] <= diag3[15:8];
            pkt[21] <= diag3[23:16];
            pkt[22] <= diag3[31:24];
            pkt[23] <= 8'hFF;
            report_pending <= 1'b1;
        end

        case (state)

            S_IDLE: begin
                if (rx_valid) begin
                    tx_data  <= rx_data;
                    tx_start <= 1'b1;
                    state    <= S_ECHO_ARM;     // ARM: wait one cycle for busy to rise
                end else if (report_pending) begin
                    byte_idx <= 5'd0;
                    state    <= S_RPT_SEND;
                end
            end

            // One dead cycle — tx_busy rises here but isn't checked yet
            S_ECHO_ARM: begin
                state <= S_ECHO_WAIT;
            end

            // Now tx_busy is guaranteed high; wait for it to fall
            S_ECHO_WAIT: begin
                if (!tx_busy)
                    state <= S_IDLE;
            end

            S_RPT_SEND: begin
                tx_data  <= pkt[byte_idx];
                tx_start <= 1'b1;
                state    <= S_RPT_ARM;          // ARM: wait one cycle for busy to rise
            end

            // One dead cycle — tx_busy rises here but isn't checked yet
            S_RPT_ARM: begin
                state <= S_RPT_WAIT;
            end

            // Now tx_busy is guaranteed high; wait for it to fall
            S_RPT_WAIT: begin
                if (!tx_busy) begin
                    if (byte_idx == PKT_LEN - 1) begin
                        report_pending <= 1'b0;
                        state          <= S_IDLE;
                    end else begin
                        byte_idx <= byte_idx + 1;
                        state    <= S_RPT_SEND;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
