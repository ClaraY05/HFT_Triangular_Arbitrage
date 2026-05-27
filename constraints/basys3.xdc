## =============================================================================
## basys3.xdc  --  Basys 3 Artix-7 pin constraints
## =============================================================================
## All pins verified against Digilent Basys 3 Reference Manual (rev B).
## =============================================================================

## ---- Clock (100 MHz oscillator) -------------------------------------------
set_property PACKAGE_PIN W5      [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

## ---- Buttons ---------------------------------------------------------------
set_property PACKAGE_PIN U18     [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]

## ---- Switches --------------------------------------------------------------
set_property PACKAGE_PIN V17     [get_ports sw0]
set_property IOSTANDARD LVCMOS33 [get_ports sw0]

## ---- UART RX ---------------------------------------------------------------
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]


## ---- UART TX ---------------------------------------------------------------
set_property PACKAGE_PIN A18     [get_ports tx]
set_property IOSTANDARD LVCMOS33 [get_ports tx]
## ---- LEDs [15:0] -----------------------------------------------------------
set_property PACKAGE_PIN U16     [get_ports {led[0]}]
set_property PACKAGE_PIN E19     [get_ports {led[1]}]
set_property PACKAGE_PIN U19     [get_ports {led[2]}]
set_property PACKAGE_PIN V19     [get_ports {led[3]}]
set_property PACKAGE_PIN W18     [get_ports {led[4]}]
set_property PACKAGE_PIN U15     [get_ports {led[5]}]
set_property PACKAGE_PIN U14     [get_ports {led[6]}]
set_property PACKAGE_PIN V14     [get_ports {led[7]}]
set_property PACKAGE_PIN V13     [get_ports {led[8]}]
set_property PACKAGE_PIN V3      [get_ports {led[9]}]
set_property PACKAGE_PIN W3      [get_ports {led[10]}]
set_property PACKAGE_PIN U3      [get_ports {led[11]}]
set_property PACKAGE_PIN P3      [get_ports {led[12]}]
set_property PACKAGE_PIN N3      [get_ports {led[13]}]
set_property PACKAGE_PIN P1      [get_ports {led[14]}]
set_property PACKAGE_PIN L1      [get_ports {led[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## ---- Seven-Segment Display — segments (active LOW) ------------------------
##
## FIX: seg bit order corrected to match seg7_controller encoding convention:
##   seg[0] = g  (middle segment)      pin W7
##   seg[1] = f  (top-left)            pin W6
##   seg[2] = e  (bottom-left)         pin U8
##   seg[3] = d  (bottom)              pin V8
##   seg[4] = c  (bottom-right)        pin U5
##   seg[5] = b  (top-right)           pin V5
##   seg[6] = a  (top)                 pin U7
##
## The physical pins are unchanged from the Basys3 reference manual.
## Only the Verilog bit indices have been corrected to match the controller's
## encoding where seg[6:0] = {a, b, c, d, e, f, g} (MSB=a, LSB=g).
##
##         a(seg[6])
##          ----
## f(seg[1])|    |b(seg[5])
##          -g(seg[0])-
## e(seg[2])|    |c(seg[4])
##          ----
##         d(seg[3])
##
set_property PACKAGE_PIN W7      [get_ports {seg[0]}]   ;# g (middle)
set_property PACKAGE_PIN W6      [get_ports {seg[1]}]   ;# f (top-left)
set_property PACKAGE_PIN U8      [get_ports {seg[2]}]   ;# e (bottom-left)
set_property PACKAGE_PIN V8      [get_ports {seg[3]}]   ;# d (bottom)
set_property PACKAGE_PIN U5      [get_ports {seg[4]}]   ;# c (bottom-right)
set_property PACKAGE_PIN V5      [get_ports {seg[5]}]   ;# b (top-right)
set_property PACKAGE_PIN U7      [get_ports {seg[6]}]   ;# a (top)
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

## Decimal point
set_property PACKAGE_PIN V7      [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

## Anodes (active LOW digit select)
## an[0]=AN0 rightmost (ones)  ...  an[3]=AN3 leftmost (thousands)
set_property PACKAGE_PIN U2      [get_ports {an[0]}]
set_property PACKAGE_PIN U4      [get_ports {an[1]}]
set_property PACKAGE_PIN V4      [get_ports {an[2]}]
set_property PACKAGE_PIN W4      [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

## ---- VGA -------------------------------------------------------------------
set_property PACKAGE_PIN P19     [get_ports vga_hsync]
set_property PACKAGE_PIN R19     [get_ports vga_vsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports vga_vsync]

## Red [3:0]
set_property PACKAGE_PIN G19     [get_ports {vga_r[0]}]
set_property PACKAGE_PIN H19     [get_ports {vga_r[1]}]
set_property PACKAGE_PIN J19     [get_ports {vga_r[2]}]
set_property PACKAGE_PIN N19     [get_ports {vga_r[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]

## Green [3:0]
set_property PACKAGE_PIN J17     [get_ports {vga_g[0]}]
set_property PACKAGE_PIN H17     [get_ports {vga_g[1]}]
set_property PACKAGE_PIN G17     [get_ports {vga_g[2]}]
set_property PACKAGE_PIN D17     [get_ports {vga_g[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]

## Blue [3:0]
set_property PACKAGE_PIN N18     [get_ports {vga_b[0]}]
set_property PACKAGE_PIN L18     [get_ports {vga_b[1]}]
set_property PACKAGE_PIN K18     [get_ports {vga_b[2]}]
set_property PACKAGE_PIN J18     [get_ports {vga_b[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]

## ---- Timing exceptions -----------------------------------------------------
set_false_path -from [get_ports btnC]
set_false_path -from [get_ports sw0]
