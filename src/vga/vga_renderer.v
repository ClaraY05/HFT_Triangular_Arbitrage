`timescale 1ns/1ps
// vga_renderer.v -- 4x4 matrix grid with labels, legend, and status text.
// Layout (640x480): title at Y=8, column headers above the grid, row labels
// left of it, 4x4 grid of 80px cells at (120,60), legend and status below.
// Text uses an 8x8 font ROM holding only the characters needed.
module vga_renderer #(
    parameter CELL  = 80,
    parameter BORDER = 2
)(
    input  wire        pclk,
    input  wire [9:0]  px,
    input  wire [9:0]  py,
    input  wire        active,
    input  wire        profit_found,
    input  wire [15:0] loop_mask,
    input  wire [13:0] profit_pct_x100,  // profit in hundredths of % (e.g. 123 = 1.23%)
    input  wire [31:0] profit_val,        // raw Q16.16 magnitude (matches 7-seg display)
    output reg  [3:0]  r,
    output reg  [3:0]  g,
    output reg  [3:0]  b
);

// Grid geometry
localparam GRID_X  = 120;             // left edge of grid
localparam GRID_Y  = 60;              // top edge of grid
localparam GRID_W  = 4 * CELL;        // 320
localparam GRID_H  = 4 * CELL;        // 320

// 8x8 font ROM: 8 bytes per character, MSB = leftmost pixel
function [7:0] font_row;
    input [6:0] ch;
    input [2:0] row;
    reg [63:0] bits;
    begin
        case (ch)
            // Space
            7'h20: bits = 64'h0000000000000000;
            // A
            7'h41: bits = 64'h183C66667E666600;
            // B
            7'h42: bits = 64'h7C66667C66667C00;
            // C
            7'h43: bits = 64'h3C66606060663C00;
            // D
            7'h44: bits = 64'h786C6666666C7800;
            // E
            7'h45: bits = 64'h7E60607C60607E00;
            // F
            7'h46: bits = 64'h7E60607C60606000;
            // G
            7'h47: bits = 64'h3C66606E66663C00;
            // H
            7'h48: bits = 64'h6666667E66666600;
            // I
            7'h49: bits = 64'h3C18181818183C00;
            // J
            7'h4A: bits = 64'h1E0C0C0C0C6C3800;
            // K
            7'h4B: bits = 64'h666C7870786C6600;
            // L
            7'h4C: bits = 64'h606060606060FE00;
            // M
            7'h4D: bits = 64'h6377776B6B636300;
            // N
            7'h4E: bits = 64'h6666767E6E666600;
            // O
            7'h4F: bits = 64'h3C66666666663C00;
            // P
            7'h50: bits = 64'h7C66667C60606000;
            // Q
            7'h51: bits = 64'h3C66666666663C06;
            // R
            7'h52: bits = 64'h7C66667C786C6600;
            // S
            7'h53: bits = 64'h3C66603C06663C00;
            // T
            7'h54: bits = 64'hFF18181818181800;
            // U
            7'h55: bits = 64'h6666666666663C00;
            // V
            7'h56: bits = 64'h66666666663C1800;
            // W
            7'h57: bits = 64'h636B6B6B6B7F3600;
            // X
            7'h58: bits = 64'h66663C183C666600;
            // Y
            7'h59: bits = 64'h6666663C18181800;
            // Z
            7'h5A: bits = 64'hFE0C183060FE0000;
            // 0
            7'h30: bits = 64'h3C666E76666C3C00; // 0 with slash look
            // 1
            7'h31: bits = 64'h1818381818187E00;
            // 2
            7'h32: bits = 64'h3C66060C30607E00;
            // 3
            7'h33: bits = 64'h3C66061C06663C00;
            // 4
            7'h34: bits = 64'h0C1C3C6C7E0C0C00;
            // 5
            7'h35: bits = 64'h7E607C0606663C00;
            // 6
            7'h36: bits = 64'h1C30607C66663C00;
            // 7
            7'h37: bits = 64'h7E060C1830303000;
            // 8
            7'h38: bits = 64'h3C66663C66663C00;
            // 9
            7'h39: bits = 64'h3C66663E06663C00;
            // %
            7'h25: bits = 64'h6066060C18306300;
            // .
            7'h2E: bits = 64'h00000000003C3C00;
            // -
            7'h2D: bits = 64'h000000FF00000000;
            // :  (used in label separator)
            7'h3A: bits = 64'h00003C3C003C3C00;
            default: bits = 64'h0000000000000000;
        endcase
        font_row = bits[63 - row*8 -: 8];
    end
endfunction

// 1 when (px,py) is a lit pixel of character ch drawn at (cx,cy)
function is_char_pixel;
    input [9:0] px_in, py_in;
    input [9:0] cx, cy;
    input [6:0] ch;
    reg [9:0] dx, dy;
    reg [7:0] row_bits;
    begin
        dx = px_in - cx;
        dy = py_in - cy;
        if (px_in >= cx && px_in < cx+8 && py_in >= cy && py_in < cy+8) begin
            row_bits = font_row(ch, dy[2:0]);
            is_char_pixel = row_bits[7 - dx[2:0]];
        end else
            is_char_pixel = 1'b0;
    end
endfunction

// 3-char label at (cx,cy)
function is_label3;
    input [9:0] px_in, py_in;
    input [9:0] cx, cy;
    input [6:0] c0, c1, c2;
    begin
        is_label3 = is_char_pixel(px_in, py_in, cx,    cy, c0) |
                    is_char_pixel(px_in, py_in, cx+8,  cy, c1) |
                    is_char_pixel(px_in, py_in, cx+16, cy, c2);
    end
endfunction

// --- Title ---
localparam TX = 100;
localparam TY = 8;

wire title_px =
    is_char_pixel(px,py, TX+0,  TY, 7'h54) | // T
    is_char_pixel(px,py, TX+9,  TY, 7'h52) | // R
    is_char_pixel(px,py, TX+18, TY, 7'h49) | // I
    is_char_pixel(px,py, TX+27, TY, 7'h41) | // A
    is_char_pixel(px,py, TX+36, TY, 7'h4E) | // N
    is_char_pixel(px,py, TX+45, TY, 7'h47) | // G
    is_char_pixel(px,py, TX+54, TY, 7'h55) | // U
    is_char_pixel(px,py, TX+63, TY, 7'h4C) | // L
    is_char_pixel(px,py, TX+72, TY, 7'h41) | // A
    is_char_pixel(px,py, TX+81, TY, 7'h52) | // R
    is_char_pixel(px,py, TX+96, TY, 7'h41) | // A
    is_char_pixel(px,py, TX+105,TY, 7'h52) | // R
    is_char_pixel(px,py, TX+114,TY, 7'h42) | // B
    is_char_pixel(px,py, TX+123,TY, 7'h49) | // I
    is_char_pixel(px,py, TX+132,TY, 7'h54) | // T
    is_char_pixel(px,py, TX+141,TY, 7'h52) | // R
    is_char_pixel(px,py, TX+150,TY, 7'h41) | // A
    is_char_pixel(px,py, TX+159,TY, 7'h47) | // G
    is_char_pixel(px,py, TX+168,TY, 7'h45) | // E
    is_char_pixel(px,py, TX+183,TY, 7'h44) | // D
    is_char_pixel(px,py, TX+192,TY, 7'h45) | // E
    is_char_pixel(px,py, TX+201,TY, 7'h54) | // T
    is_char_pixel(px,py, TX+210,TY, 7'h45) | // E
    is_char_pixel(px,py, TX+219,TY, 7'h43) | // C
    is_char_pixel(px,py, TX+228,TY, 7'h54) | // T
    is_char_pixel(px,py, TX+237,TY, 7'h4F) | // O
    is_char_pixel(px,py, TX+246,TY, 7'h52);  // R

// --- Column headers, centered in each cell ---
localparam CH_Y = GRID_Y - 18;
wire col_hdr_px =
    is_label3(px,py, GRID_X + 0*CELL+28, CH_Y, 7'h55,7'h53,7'h44) |  // USD
    is_label3(px,py, GRID_X + 1*CELL+28, CH_Y, 7'h45,7'h55,7'h52) |  // EUR
    is_label3(px,py, GRID_X + 2*CELL+28, CH_Y, 7'h47,7'h42,7'h50) |  // GBP
    is_label3(px,py, GRID_X + 3*CELL+28, CH_Y, 7'h4A,7'h50,7'h59);   // JPY

// --- Row labels, left of grid ---
localparam RL_X = GRID_X - 34;
wire row_lbl_px =
    is_label3(px,py, RL_X, GRID_Y + 0*CELL+36, 7'h55,7'h53,7'h44) |  // USD
    is_label3(px,py, RL_X, GRID_Y + 1*CELL+36, 7'h45,7'h55,7'h52) |  // EUR
    is_label3(px,py, RL_X, GRID_Y + 2*CELL+36, 7'h47,7'h42,7'h50) |  // GBP
    is_label3(px,py, RL_X, GRID_Y + 3*CELL+36, 7'h4A,7'h50,7'h59);   // JPY

// --- "FROM" label above row labels ---
wire from_px =
    is_label3(px,py, RL_X, GRID_Y - 18, 7'h46,7'h52,7'h4F) |  // FRO
    is_char_pixel(px,py, RL_X+24, GRID_Y-18, 7'h4D);           // M

// --- Legend at bottom ---
localparam LEG_Y = GRID_Y + GRID_H + 14;
localparam LEG_X = GRID_X;

// 16x8 colour swatches
wire red_swatch  = (px >= LEG_X)    && (px < LEG_X+16)    && (py >= LEG_Y) && (py < LEG_Y+8);
wire grey_swatch = (px >= LEG_X+130) && (px < LEG_X+146) && (py >= LEG_Y) && (py < LEG_Y+8);

wire legend_text =
    is_char_pixel(px,py, LEG_X+20, LEG_Y, 7'h41) |  // A
    is_char_pixel(px,py, LEG_X+29, LEG_Y, 7'h52) |  // R
    is_char_pixel(px,py, LEG_X+38, LEG_Y, 7'h42) |  // B
    is_char_pixel(px,py, LEG_X+47, LEG_Y, 7'h49) |  // I
    is_char_pixel(px,py, LEG_X+56, LEG_Y, 7'h54) |  // T
    is_char_pixel(px,py, LEG_X+65, LEG_Y, 7'h52) |  // R
    is_char_pixel(px,py, LEG_X+74, LEG_Y, 7'h41) |  // A
    is_char_pixel(px,py, LEG_X+83, LEG_Y, 7'h47) |  // G
    is_char_pixel(px,py, LEG_X+92, LEG_Y, 7'h45) |  // E
    is_char_pixel(px,py, LEG_X+150,LEG_Y, 7'h4E) |  // N
    is_char_pixel(px,py, LEG_X+159,LEG_Y, 7'h4F) |  // O
    is_char_pixel(px,py, LEG_X+168,LEG_Y, 7'h4E) |  // N
    is_char_pixel(px,py, LEG_X+177,LEG_Y, 7'h45);   // E

// --- Status line ---
localparam ST_Y = LEG_Y + 24;
localparam ST_X = LEG_X;

// "PROFIT:" always shown in status area
wire status_label =
    is_char_pixel(px,py, ST_X+0,  ST_Y, 7'h50) |  // P
    is_char_pixel(px,py, ST_X+9,  ST_Y, 7'h52) |  // R
    is_char_pixel(px,py, ST_X+18, ST_Y, 7'h4F) |  // O
    is_char_pixel(px,py, ST_X+27, ST_Y, 7'h46) |  // F
    is_char_pixel(px,py, ST_X+36, ST_Y, 7'h49) |  // I
    is_char_pixel(px,py, ST_X+45, ST_Y, 7'h54) |  // T
    is_char_pixel(px,py, ST_X+54, ST_Y, 7'h3A);   // :

// Profit digits: profit_pct_x100 is hundredths of % (123 -> "01.23")
wire [13:0] pct = profit_pct_x100;          // 0..9999
wire [3:0]  dig3 = pct / 1000;              // thousands  (tens of %)
wire [3:0]  dig2 = (pct % 1000) / 100;     // hundreds   (ones of %)
wire [3:0]  dig1 = (pct % 100)  / 10;      // tens       (tenths of %)
wire [3:0]  dig0 = pct % 10;               // ones       (hundredths of %)

wire [6:0] d_tens  = 7'h30 + {3'b0, dig3};   // tens of integer %
wire [6:0] d_ones  = 7'h30 + {3'b0, dig2};   // ones of integer %
wire [6:0] d_tenth = 7'h30 + {3'b0, dig1};   // tenths of %
wire [6:0] d_hund  = 7'h30 + {3'b0, dig0};   // hundredths of %

// Blank leading tens digit if < 10%
wire blank_tens = (dig3 == 4'd0);

wire status_val =
    (blank_tens ? 1'b0 : is_char_pixel(px,py, ST_X+72, ST_Y, d_tens))  |
    is_char_pixel(px,py, ST_X+81,  ST_Y, d_ones)  |
    is_char_pixel(px,py, ST_X+90,  ST_Y, 7'h2E)   |  // .
    is_char_pixel(px,py, ST_X+99,  ST_Y, d_tenth) |
    is_char_pixel(px,py, ST_X+108, ST_Y, d_hund)  |
    is_char_pixel(px,py, ST_X+117, ST_Y, 7'h25);     // %

// "NO ARBITRAGE" shown only when no profit
wire no_arb_text =
    !profit_found && (
    is_char_pixel(px,py, ST_X+72, ST_Y, 7'h4E) |  // N
    is_char_pixel(px,py, ST_X+81, ST_Y, 7'h4F) |  // O
    is_char_pixel(px,py, ST_X+96, ST_Y, 7'h41) |  // A
    is_char_pixel(px,py, ST_X+105,ST_Y, 7'h52) |  // R
    is_char_pixel(px,py, ST_X+114,ST_Y, 7'h42) |  // B
    is_char_pixel(px,py, ST_X+123,ST_Y, 7'h49) |  // I
    is_char_pixel(px,py, ST_X+132,ST_Y, 7'h54) |  // T
    is_char_pixel(px,py, ST_X+141,ST_Y, 7'h52) |  // R
    is_char_pixel(px,py, ST_X+150,ST_Y, 7'h41) |  // A
    is_char_pixel(px,py, ST_X+159,ST_Y, 7'h47) |  // G
    is_char_pixel(px,py, ST_X+168,ST_Y, 7'h45));  // E

// --- "RAW: XXXX" line below the status (matches the 7-seg SW0=1 mode) ---
// Bits [15:0] of the Q16.16 magnitude; the integer part [31:16] is always 0
// for sub-100% profit.
localparam RW_Y = ST_Y + 16;
localparam RW_X = ST_X;

wire [15:0] raw_int  = profit_val[15:0];
wire [13:0] raw_disp = (raw_int > 16'd9999) ? 14'd9999 : raw_int[13:0];

wire [3:0]  rw_d3 = raw_disp / 1000;
wire [3:0]  rw_d2 = (raw_disp % 1000) / 100;
wire [3:0]  rw_d1 = (raw_disp % 100)  / 10;
wire [3:0]  rw_d0 = raw_disp % 10;

wire [6:0] rw_c3 = 7'h30 + {3'b0, rw_d3};
wire [6:0] rw_c2 = 7'h30 + {3'b0, rw_d2};
wire [6:0] rw_c1 = 7'h30 + {3'b0, rw_d1};
wire [6:0] rw_c0 = 7'h30 + {3'b0, rw_d0};

wire blank_rw_d3 = (rw_d3 == 4'd0);
wire blank_rw_d2 = blank_rw_d3 && (rw_d2 == 4'd0);
wire blank_rw_d1 = blank_rw_d2 && (rw_d1 == 4'd0);

// "RAW:" label
wire raw_label =
    is_char_pixel(px,py, RW_X+0,  RW_Y, 7'h52) |  // R
    is_char_pixel(px,py, RW_X+9,  RW_Y, 7'h41) |  // A
    is_char_pixel(px,py, RW_X+18, RW_Y, 7'h57) |  // W
    is_char_pixel(px,py, RW_X+27, RW_Y, 7'h3A);   // :

// 4 digits with leading-zero suppression
wire raw_val_px =
    (blank_rw_d3 ? 1'b0 : is_char_pixel(px,py, RW_X+45, RW_Y, rw_c3)) |
    (blank_rw_d2 ? 1'b0 : is_char_pixel(px,py, RW_X+54, RW_Y, rw_c2)) |
    (blank_rw_d1 ? 1'b0 : is_char_pixel(px,py, RW_X+63, RW_Y, rw_c1)) |
    is_char_pixel(px,py, RW_X+72, RW_Y, rw_c0);

// Grid pixel logic
wire in_grid = (px >= GRID_X) && (px < GRID_X + GRID_W) &&
               (py >= GRID_Y) && (py < GRID_Y + GRID_H);

wire [9:0] gx = in_grid ? (px - GRID_X) : 10'd0;
wire [9:0] gy = in_grid ? (py - GRID_Y) : 10'd0;

wire [1:0] col_idx = gx / CELL;
wire [1:0] row_idx = gy / CELL;

wire on_border = in_grid && ((gx % CELL < BORDER) || (gy % CELL < BORDER));
wire highlighted = in_grid && loop_mask[row_idx * 4 + col_idx];

// Registered colour output
always @(posedge pclk) begin
    if (!active) begin
        r <= 4'h0; g <= 4'h0; b <= 4'h0;

    // ---- Grid ----
    end else if (on_border) begin
        r <= 4'h0; g <= 4'h0; b <= 4'h0;   // border: black
    end else if (in_grid && profit_found && highlighted) begin
        r <= 4'hF; g <= 4'h2; b <= 4'h2;   // arbitrage cell: red
    end else if (in_grid) begin
        r <= 4'hA; g <= 4'hA; b <= 4'hA;   // normal cell: grey

    // ---- Legend swatches ----
    end else if (red_swatch) begin
        r <= 4'hF; g <= 4'h2; b <= 4'h2;
    end else if (grey_swatch) begin
        r <= 4'hA; g <= 4'hA; b <= 4'hA;

    // ---- Text layers (white) ----
    end else if (title_px || col_hdr_px || row_lbl_px || from_px ||
                 legend_text || status_label ||
                 (profit_found && status_val) ||
                 no_arb_text ||
                 raw_label ||
                 (profit_found && raw_val_px)) begin
        r <= 4'hF; g <= 4'hF; b <= 4'hF;   // white text

    // ---- Background ----
    end else begin
        r <= 4'h1; g <= 4'h1; b <= 4'h3;   // dark navy
    end
end

endmodule
