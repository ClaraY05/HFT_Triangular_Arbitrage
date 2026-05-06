`timescale 1ns/1ps
// receive 64 bytes → 16 × 32-bit word BRAM
module matrix_buffer (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  byte_in,
    input  wire        byte_valid,

    output reg         ready,       //one-cycle pulse: all 64 bytes stored

    input  wire [3:0]  rd_addr,     // word index 0-15
    output wire [31:0] rd_data
);

reg [31:0] mem [0:15]; //16 words of 32 bits each (BRAM)

reg [5:0] byte_cnt;     //counts 0..63  (6 bits)
reg [1:0] byte_pos;     //byte position within current 32-bit word (0..3)

always @(posedge clk) begin
    ready <= 1'b0;

    if (rst) begin
        byte_cnt <= 6'd0;
        byte_pos <= 2'd0;
    end else if (byte_valid) begin
        mem[ byte_cnt[5:2] ][ byte_pos*8 +: 8 ] <= byte_in;

        if (byte_cnt == 6'd63) begin
            ready    <= 1'b1;
            byte_cnt <= 6'd0;
            byte_pos <= 2'd0;
        end else begin
            byte_cnt <= byte_cnt + 1;
            byte_pos <= byte_pos + 1;   
        end
    end
end

reg [31:0] rd_reg;
always @(posedge clk)
    rd_reg <= mem[rd_addr];

assign rd_data = rd_reg;

endmodule
