`timescale 1ns/1ps
// uart_reporter.v -- echoes each received byte and sends a 24-byte result
// packet after every Floyd-Warshall run.
//
// tx_busy rises one cycle after tx_start (uart_tx is clocked), so every send
// passes through a one-cycle ARM state before the WAIT state checks !tx_busy;
// checking immediately would see busy still low and drop the byte.
//
// Packet (24 bytes, little-endian fields):
//   AA 55 | profit_found | profit_val[4] | diag0..diag3[4 each] | FF
module uart_reporter (
    input  wire        clk,
    input  wire        rst,

    // Echo path
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // Result path
    input  wire        fw_done,
    input  wire        profit_found,
    input  wire [31:0] profit_val,
    input  wire [31:0] diag0,
    input  wire [31:0] diag1,
    input  wire [31:0] diag2,
    input  wire [31:0] diag3,

    // uart_tx interface
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    input  wire        tx_busy
);

localparam PKT_LEN = 24;

reg [7:0] pkt [0:PKT_LEN-1];
reg [4:0] byte_idx;
reg       report_pending;

// Delay fw_done one cycle so arb_detector's registered outputs are stable
reg fw_done_d1;
always @(posedge clk) fw_done_d1 <= rst ? 1'b0 : fw_done;

localparam S_IDLE      = 3'd0,
           S_ECHO_ARM  = 3'd1,
           S_ECHO_WAIT = 3'd2,
           S_RPT_SEND  = 3'd3,
           S_RPT_ARM   = 3'd4,
           S_RPT_WAIT  = 3'd5;

reg [2:0] state;

always @(posedge clk) begin
    tx_start <= 1'b0;   // default: no pulse

    if (rst) begin
        state          <= S_IDLE;
        report_pending <= 1'b0;
        byte_idx       <= 5'd0;
        tx_data        <= 8'h00;

    end else begin

        // Latch result packet one cycle after fw_done
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
                    state    <= S_ECHO_ARM;
                end else if (report_pending) begin
                    byte_idx <= 5'd0;
                    state    <= S_RPT_SEND;
                end
            end

            // One dead cycle so tx_busy is high before WAIT checks it
            S_ECHO_ARM: begin
                state <= S_ECHO_WAIT;
            end

            S_ECHO_WAIT: begin
                if (!tx_busy)
                    state <= S_IDLE;
            end

            S_RPT_SEND: begin
                tx_data  <= pkt[byte_idx];
                tx_start <= 1'b1;
                state    <= S_RPT_ARM;
            end

            // One dead cycle so tx_busy is high before WAIT checks it
            S_RPT_ARM: begin
                state <= S_RPT_WAIT;
            end

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
