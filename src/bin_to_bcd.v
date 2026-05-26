`timescale 1ns/1ps
// =============================================================================
// bin_to_bcd.v  --  20-bit binary → 5 BCD digits (double-dabble)
// =============================================================================
// Combinational.  Maximum input value 999999 fits in 20 bits (2^20 = 1048576).
// The 5 output digits represent: [ten-thousands][thousands][hundreds][tens][ones]
//
// Double-dabble (shift-and-add-3) algorithm:
//   For each bit from MSB to LSB:
//     1. If any BCD nibble >= 5, add 3 to it.
//     2. Shift the entire scratch register left by 1, bringing in the next bit.
// =============================================================================
module bin_to_bcd (
    input  wire [19:0] bin,
    output wire [3:0]  ten_thou,
    output wire [3:0]  thou,
    output wire [3:0]  hund,
    output wire [3:0]  tens,
    output wire [3:0]  ones
);

// Scratch register: 20 BCD bits (5 digits) + 20 binary input bits
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
