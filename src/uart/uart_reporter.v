`timescale 1ns/1ps
// =============================================================================
// uart_reporter.v  --  UART TX manager for the arbitrage detector
// =============================================================================
//
// Two TX duties, naturally time-separated:
//
//   ECHO   During matrix receive — every byte uart_rx accepts is immediately
//          echoed back.  Python compares sent vs received byte-by-byte.
//          (Python sends one byte, waits for echo, then sends the next.)
//
//   REPORT After Floyd-Warshall completes — a 24-byte result packet is sent
//          so Python can read profit_found, profit_val, and all four diagonals.
//
// Packet format (24 bytes, all multi-byte fields little-endian):
//
//   Offset  Size  Field
//   ------  ----  -----------------------------------------------
//      0     1    0xAA          start header byte 0
//      1     1    0x55          start header byte 1
//      2     1    profit_found  0x00 = no arb, 0x01 = arb detected
//      3     4    profit_val    Q16.16 magnitude of best diagonal (LE)
//      7     4    diag0         dist[0][0] raw Q16.16 (LE)
//     11     4    diag1         dist[1][1] raw Q16.16 (LE)
//     15     4    diag2         dist[2][2] raw Q16.16 (LE)
//     19     4    diag3         dist[3][3] raw Q16.16 (LE)
//     23     1    0xFF          end marker
//
// TIMING NOTE — one-cycle delay on fw_done:
//   arb_detector registers profit_found/profit_val on the fw_done pulse, so
//   those values are only valid from the NEXT clock cycle onwards.  This
//   module therefore delays fw_done by one cycle (fw_done_d1) before latching
//   the packet.  diag0-3 come from fw_engine's dist[] registers which remain
//   stable until the next 'run' pulse, so they are also safe to read at
//   fw_done_d1.
//
// =============================================================================
module uart_reporter (
    input  wire        clk,
    input  wire        rst,

    // --- Echo path (from uart_rx) -------------------------------------------
    input  wire [7:0]  rx_data,    // byte just received
    input  wire        rx_valid,   // one-cycle pulse

    // --- Result path (from fw_engine / arb_detector) ------------------------
    input  wire        fw_done,         // one-cycle pulse from fw_engine
    input  wire        profit_found,    // registered output of arb_detector
    input  wire [31:0] profit_val,      // registered output of arb_detector
    input  wire [31:0] diag0,           // dist[0][0]  (combinational from fw_engine)
    input  wire [31:0] diag1,           // dist[1][1]
    input  wire [31:0] diag2,           // dist[2][2]
    input  wire [31:0] diag3,           // dist[3][3]

    // --- Interface to uart_tx -----------------------------------------------
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy
);

// --------------------------------------------------------------------------
// Packet storage  (24 bytes, indexed 0..23)
// --------------------------------------------------------------------------
localparam PKT_LEN = 24;

reg [7:0]  pkt [0:PKT_LEN-1];
reg [4:0]  byte_idx;     // 0..23
reg        report_pending;

// --------------------------------------------------------------------------
// One-cycle delay on fw_done so arb_detector outputs are stable
// --------------------------------------------------------------------------
reg fw_done_d1;
always @(posedge clk) fw_done_d1 <= (rst) ? 1'b0 : fw_done;

// --------------------------------------------------------------------------
// State machine
// --------------------------------------------------------------------------
localparam S_IDLE      = 3'd0,
           S_ECHO_SEND = 3'd1,   // pulse tx_start for echo byte
           S_ECHO_WAIT = 3'd2,   // wait for echo transmission to finish
           S_RPT_SEND  = 3'd3,   // pulse tx_start for current packet byte
           S_RPT_WAIT  = 3'd4;   // wait for that byte to finish

reg [2:0] state;

always @(posedge clk) begin
    // tx_start is a one-cycle pulse; default low every cycle
    tx_start <= 1'b0;

    if (rst) begin
        state          <= S_IDLE;
        report_pending <= 1'b0;
        byte_idx       <= 5'd0;
        tx_data        <= 8'h00;

    end else begin

        // ------------------------------------------------------------------
        // Latch result packet one cycle after fw_done.
        // This runs independently of state so we never miss a done pulse.
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

        // ------------------------------------------------------------------
        // State machine
        // ------------------------------------------------------------------
        case (state)

            // Wait for an echo request or a pending report
            S_IDLE: begin
                if (rx_valid) begin
                    // Echo takes priority — it happens during data receive,
                    // before any report is triggered
                    tx_data  <= rx_data;
                    tx_start <= 1'b1;
                    state    <= S_ECHO_WAIT;
                end else if (report_pending) begin
                    byte_idx <= 5'd0;
                    state    <= S_RPT_SEND;
                end
            end

            // tx_start was pulsed last cycle; wait for uart_tx to finish.
            // tx_busy goes HIGH the cycle after tx_start, so on the first
            // cycle here it may still be 0 — that is why we go via S_ECHO_SEND
            // only for the report (see below); for echo we pulsed from S_IDLE.
            // tx_busy will be 1 from the next cycle, so we will not exit early.
            S_ECHO_WAIT: begin
                if (!tx_busy)
                    state <= S_IDLE;
            end

            // Load current packet byte and pulse tx_start
            S_RPT_SEND: begin
                tx_data  <= pkt[byte_idx];
                tx_start <= 1'b1;
                state    <= S_RPT_WAIT;
            end

            // Wait for this packet byte to finish, then advance or finish
            S_RPT_WAIT: begin
                if (!tx_busy) begin
                    if (byte_idx == PKT_LEN - 1) begin
                        // Entire packet sent
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
