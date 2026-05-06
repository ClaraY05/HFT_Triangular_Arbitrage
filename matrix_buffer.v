`timescale 1ns/1ps
// =============================================================================
// matrix_buffer.v  --  Receive 64 bytes → 16 × 32-bit word BRAM
// =============================================================================
// Protocol:
//   Python sends 16 × 32-bit signed integers in little-endian byte order.
//   Total: 64 bytes.  Once all 64 bytes are received 'ready' pulses for
//   one clock cycle.  The FW engine reads words via rd_addr / rd_data.
//
//   A new transfer can begin immediately; the buffer overwrites in-place.
// =============================================================================
module matrix_buffer (
    input  wire        clk,
    input  wire        rst,
    // From UART RX
    input  wire [7:0]  byte_in,
    input  wire        byte_valid,
    // Status
    output reg         ready,       // one-cycle pulse: all 64 bytes stored
    // Synchronous read port
    input  wire [3:0]  rd_addr,     // word index 0-15
    output wire [31:0] rd_data
);

// --------------------------------------------------------------------------
// 16-word × 32-bit memory  (Vivado infers Block RAM)
// --------------------------------------------------------------------------
reg [31:0] mem [0:15];

// --------------------------------------------------------------------------
// Byte accumulator
// --------------------------------------------------------------------------
reg [5:0] byte_cnt;     // counts 0..63  (6 bits)
reg [1:0] byte_pos;     // byte position within current 32-bit word (0..3)

always @(posedge clk) begin
    ready <= 1'b0;

    if (rst) begin
        byte_cnt <= 6'd0;
        byte_pos <= 2'd0;
    end else if (byte_valid) begin
        // Write this byte into the correct lane of the current word
        // Word index = byte_cnt[5:2],  lane = byte_pos (little-endian)
        mem[ byte_cnt[5:2] ][ byte_pos*8 +: 8 ] <= byte_in;

        if (byte_cnt == 6'd63) begin
            ready    <= 1'b1;
            byte_cnt <= 6'd0;
            byte_pos <= 2'd0;
        end else begin
            byte_cnt <= byte_cnt + 1;
            byte_pos <= byte_pos + 1;   // wraps naturally at 2'b11→2'b00
        end
    end
end

// Synchronous read (one-cycle latency — account for this in fw_engine)
reg [31:0] rd_reg;
always @(posedge clk)
    rd_reg <= mem[rd_addr];

assign rd_data = rd_reg;

endmodule
