`timescale 1ns/1ps

module matrix_buffer (
    input  wire        clk,
    input  wire        rst,

    input  wire [7:0]  byte_in,
    input  wire        byte_valid,

    output reg         ready,

    input  wire [3:0]  rd_addr,
    output wire [31:0] rd_data
);

reg [31:0] mem [0:15];

// Wait for the 0xAA 0x55 preamble, then assemble 64 bytes into 16 words
localparam WAIT_AA   = 2'd0;
localparam WAIT_55   = 2'd1;
localparam RECEIVE   = 2'd2;

reg [1:0] state;

reg [5:0] byte_cnt;
reg [1:0] byte_pos;

integer k;

always @(posedge clk) begin

    ready <= 1'b0;

    if (rst) begin

        state    <= WAIT_AA;
        byte_cnt <= 0;
        byte_pos <= 0;

        for (k = 0; k < 16; k = k + 1)
            mem[k] <= 32'd0;

    end
    else if (byte_valid) begin

        case (state)

            WAIT_AA: begin
                if (byte_in == 8'hAA)
                    state <= WAIT_55;
            end

            WAIT_55: begin
                if (byte_in == 8'h55) begin
                    state    <= RECEIVE;
                    byte_cnt <= 0;
                    byte_pos <= 0;
                end
                else begin
                    state <= WAIT_AA;
                end
            end

            RECEIVE: begin
                // little-endian reconstruction
                mem[byte_cnt[5:2]][byte_pos*8 +: 8] <= byte_in;

                if (byte_cnt == 6'd63) begin

                    ready <= 1'b1;

                    state <= WAIT_AA;

                    byte_cnt <= 0;
                    byte_pos <= 0;

                end
                else begin

                    byte_cnt <= byte_cnt + 1'b1;
                    byte_pos <= byte_pos + 1'b1;

                end
            end

        endcase
    end
end

// Registered read port (1-cycle latency)
reg [31:0] rd_reg;

always @(posedge clk)
    rd_reg <= mem[rd_addr];

assign rd_data = rd_reg;

endmodule