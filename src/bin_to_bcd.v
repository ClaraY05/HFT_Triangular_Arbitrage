`timescale 1ns/1ps
// bin_to_bcd.v -- 20-bit binary to 5 BCD digits (combinational double-dabble)
module bin_to_bcd (
    input  wire [19:0] bin,
    output wire [3:0]  ten_thou,
    output wire [3:0]  thou,
    output wire [3:0]  hund,
    output wire [3:0]  tens,
    output wire [3:0]  ones
);

// 20 BCD bits (5 digits) + 20 binary input bits
reg [39:0] scratch;

integer bit_i;
always @(*) begin
    scratch = {20'b0, bin};
    for (bit_i = 0; bit_i < 20; bit_i = bit_i + 1) begin
        // Add 3 to any BCD digit >= 5
        if (scratch[23:20] >= 4'd5) scratch[23:20] = scratch[23:20] + 4'd3;
        if (scratch[27:24] >= 4'd5) scratch[27:24] = scratch[27:24] + 4'd3;
        if (scratch[31:28] >= 4'd5) scratch[31:28] = scratch[31:28] + 4'd3;
        if (scratch[35:32] >= 4'd5) scratch[35:32] = scratch[35:32] + 4'd3;
        if (scratch[39:36] >= 4'd5) scratch[39:36] = scratch[39:36] + 4'd3;
        // Shift left
        scratch = scratch << 1;
    end
end

assign ones     = scratch[23:20];
assign tens     = scratch[27:24];
assign hund     = scratch[31:28];
assign thou     = scratch[35:32];
assign ten_thou = scratch[39:36];

endmodule
