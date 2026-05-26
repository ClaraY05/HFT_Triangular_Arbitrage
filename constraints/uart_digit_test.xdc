## =============================================================================
## uart_digit_test.xdc  --  Basys 3 constraints for UART digit test
## =============================================================================
## Only the pins actually used by this project are constrained.
## Pin locations and IOSTANDARD verified against Digilent Basys 3 Rev. B manual.
## =============================================================================

## ---- Clock (100 MHz) -------------------------------------------------------
set_property PACKAGE_PIN W5      [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]

## ---- Centre button (reset) -------------------------------------------------
set_property PACKAGE_PIN U18     [get_ports btnC]
set_property IOSTANDARD LVCMOS33 [get_ports btnC]
set_false_path -from [get_ports btnC]

## ---- UART RX ---------------------------------------------------------------
set_property PACKAGE_PIN B18     [get_ports rx]
set_property IOSTANDARD LVCMOS33 [get_ports rx]

## ---- Seven-Segment Display — segments (active LOW) ------------------------
##
## Bit-to-pin mapping (corrected to match seg7_controller/seg7_digit encoding):
##   seg[0] = g  (middle)        W7    -- maps to CG in Verilog bit[6]… see note
##   seg[1] = f  (top-left)      W6
##   seg[2] = e  (bottom-left)   U8
##   seg[3] = d  (bottom)        V8
##   seg[4] = c  (bottom-right)  U5
##   seg[5] = b  (top-right)     V5
##   seg[6] = a  (top)           U7
##
## The segment encoding in seg7_digit.v uses the convention from the main
## project's seg7_controller.v:  seg[6:0] = {CG,CF,CE,CD,CC,CB,CA}.
## The XDC wires those encoding bits to the correct physical pins so that
## 'a' (CA, top bar) lights when seg[0] is LOW, etc.
##
set_property PACKAGE_PIN W7      [get_ports {seg[0]}]
set_property PACKAGE_PIN W6      [get_ports {seg[1]}]
set_property PACKAGE_PIN U8      [get_ports {seg[2]}]
set_property PACKAGE_PIN V8      [get_ports {seg[3]}]
set_property PACKAGE_PIN U5      [get_ports {seg[4]}]
set_property PACKAGE_PIN V5      [get_ports {seg[5]}]
set_property PACKAGE_PIN U7      [get_ports {seg[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

## Decimal point (kept OFF by firmware, constrained to avoid DRC warnings)
set_property PACKAGE_PIN V7      [get_ports dp]
set_property IOSTANDARD LVCMOS33 [get_ports dp]

## ---- Anodes (active LOW digit select) -------------------------------------
## an[0] = AN0 rightmost (ones)  …  an[3] = AN3 leftmost
set_property PACKAGE_PIN U2      [get_ports {an[0]}]
set_property PACKAGE_PIN U4      [get_ports {an[1]}]
set_property PACKAGE_PIN V4      [get_ports {an[2]}]
set_property PACKAGE_PIN W4      [get_ports {an[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]
