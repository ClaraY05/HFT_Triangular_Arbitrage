# Triangular Arbitrage FPGA — Architecture Notes

## Fixed-point encoding

All values are **Q16.16 signed integers** (32-bit).

```
Python:   word = int(round(-math.log(rate) * 65536))
Hardware: profit_val / 65536.0 * 100  →  profit percentage
```

A rate of 1.0 encodes to 0. A rate > 1.0 (profitable leg) encodes to a
**negative** number. The Floyd-Warshall algorithm finds negative-weight cycles
in the negative-log space, which correspond to arbitrage opportunities.

## Floyd-Warshall timing

The engine loads 16 words (16 + 1 pipeline flush cycles) then runs
4×4×4 = 64 update cycles.  Total: ~82 cycles @ 100 MHz ≈ **820 ns**.

## loop_mask (simplified implementation)

The current `fw_engine.v` highlights the entire row and column of the
most negative diagonal index.  Full path reconstruction requires a
predecessor matrix `next[i][j]` updated alongside `dist[i][j]`:

```verilog
if (through < dist[{i,j}]) begin
    dist[{i,j}] <= through;
    next[{i,j}] <= k;         // remember which intermediate node
end
```

Path recovery then traces `0 → next[0][k] → next[k][j] → j → 0`
to find the exact arbitrage loop.  This is a recommended extension after
the base milestones are verified.

## Simulation note (VGA clock wizard)

`clk_wiz_0` is a Xilinx IP and is not available in open-source simulators.
For `tb_top.v` to compile cleanly, either:

1. Use Vivado's built-in simulator (xsim) — the IP stub is auto-generated.
2. Add a simulation model stub:

```verilog
// sim/clk_wiz_0_stub.v
module clk_wiz_0 (
    input  clk_in1,
    output clk_out1,
    input  reset,
    output locked
);
    assign clk_out1 = clk_in1;  // passthrough for sim
    assign locked   = 1'b1;
endmodule
```

## Milestone checklist

- [ ] **M1** UART + Buffer: flash LED0 when `buf_ready` pulses
- [ ] **M2** FW Engine: simulate `tb_fw_engine`, verify negative diagonal
- [ ] **M3** Arb Detector: check `profit_found` in `tb_top`
- [ ] **M4** 7-seg: verify BCD digits in simulation, then on board
- [ ] **M5** VGA: scope check hsync/vsync, then observe grid on monitor
- [ ] **M6** Integration: Python → UART → LEDs flash + VGA red cells

## Port mapping quick reference (Basys 3)

| Signal | Pin | Notes |
|--------|-----|-------|
| clk | W5 | 100 MHz XTAL |
| btnC (reset) | U18 | Centre button |
| sw0 (mode) | V17 | Rightmost switch |
| rx (UART) | B18 | USB-UART RX |
| led[0..15] | See XDC | Active high |
| seg[6:0] | See XDC | Active low (g..a) |
| an[3:0] | See XDC | Active low anodes |
| vga_hsync | P19 | |
| vga_vsync | R19 | |
| vga_r[3:0] | G19..N19 | 4-bit DAC via resistors |
| vga_g[3:0] | J17..D17 | |
| vga_b[3:0] | N18..J18 | |
