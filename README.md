# Triangular Arbitrage Detection Engine

Hardware-accelerated triangular arbitrage detector running on a **Basys 3 (Artix-7)** FPGA.

## Repo layout

```
arb_fpga/
├── src/
│   ├── top.v               ← top-level interconnect
│   ├── uart_rx.v           ← 8-N-1 UART deserializer
│   ├── matrix_buffer.v     ← 64-byte → 16×32-bit BRAM
│   ├── control_fsm.v       ← IDLE→LOAD→RUN→DONE sequencer
│   ├── fw_engine.v         ← Floyd-Warshall core (4×4, 32-bit signed)
│   ├── arb_detector.v      ← diagonal < 0 checker
│   ├── led_controller.v    ← 2 Hz flash on profit
│   ├── seg7_controller.v   ← 4-digit BCD display
│   ├── bin_to_bcd.v        ← double-dabble converter
│   └── vga/
│       ├── vga_sync.v      ← 640×480 @ 60 Hz timing
│       ├── vga_renderer.v  ← 4×4 grid painter
│       └── vga_top.v       ← clock wizard + sync + renderer
├── sim/
│   ├── tb_uart_rx.v        ← UART unit test
│   ├── tb_fw_engine.v      ← FW algorithm unit test (known arb cycle)
│   └── tb_top.v            ← full integration test
├── host/
│   └── send_rates.py       ← Python: log-transform + UART stream
├── constraints/
│   └── basys3.xdc          ← all pin assignments
├── vivado/
│   └── create_project.tcl  ← one-shot project + IP setup
└── docs/
    └── architecture.md     ← encoding, timing, extension notes
```

## Quick start

```bash
# 1. Create Vivado project (from repo root)
vivado -mode batch -source vivado/create_project.tcl

# 2. Open and simulate
#    In Vivado: set sim top to tb_fw_engine, Run Simulation

# 3. Synthesise + implement + generate bitstream
#    In Vivado: Run All (or via Tcl):
#    launch_runs synth_1; wait_on_run synth_1
#    launch_runs impl_1 -to_step write_bitstream; wait_on_run impl_1

# 4. Program board
#    Hardware Manager → Auto Connect → Program Device

# 5. Send a rate matrix from the host
pip install pyserial
python host/send_rates.py COM3        # Windows
python host/send_rates.py /dev/ttyUSB1  # Linux
```

## How it works

1. **Python** computes `–log(rate)` for each cell and encodes it as a Q16.16 signed integer, then streams 64 bytes via USB-UART.
2. **UART RX** deserializes bytes; **matrix_buffer** assembles them into 16 × 32-bit words in BRAM.
3. **control_fsm** triggers **fw_engine** once the full matrix is buffered.
4. **fw_engine** runs Floyd-Warshall in 64 clock cycles (~820 ns @ 100 MHz).
5. **arb_detector** checks the diagonal: `dist[i][i] < 0` → negative cycle → profitable arbitrage.
6. **Outputs**: LEDs flash at 2 Hz, 7-seg shows profit magnitude, VGA highlights the arbitrage cells in red.

## Fixed-point math

```
encoded  = round(–log(rate) × 65536)
profit % = (profit_val / 65536) × 100
```

See `docs/architecture.md` for loop_mask reconstruction and simulation notes.
