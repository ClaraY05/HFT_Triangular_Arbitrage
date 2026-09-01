# Triangular Arbitrage Detection Engine

Hardware-accelerated triangular arbitrage detector running on a **Basys 3 (Artix-7)** FPGA. Developed in 3 weeks for UCLA's CS M152A course.

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

# 5. Send a rate matrix from the host, may use COMX or /dev/ttyUSBx depending on OS
pip install pyserial
python host/send_rates.py /dev/ttyUSB1 0   # no arbitrage
python host/send_rates.py /dev/ttyUSB1 1   # ~1.5% GBP/EUR mispricing
python host/send_rates.py /dev/ttyUSB1 2   # large demo cycle (~120%)
python host/send_rates.py COM3 1            # Windows

# 6. (Optional) Run the full automated test suite
python host/test_suite.py --port /dev/ttyUSB0
python host/test_suite.py --port COM3 --test 2   # single test
python host/test_suite.py --port COM3 --verbose  # full packet dump
```

## How it works

1. **Python** (`send_rates.py`) computes `–log(rate)` for each cell and encodes it as a Q16.16 signed integer, prepends a `0xAA 0x55` magic-byte preamble, and streams 66 bytes via USB-UART at 57600 baud.
2. **UART RX** deserializes bytes; **matrix_buffer** waits for the `0xAA 0x55` preamble then assembles the following 64 bytes into 16 × 32-bit words in BRAM.
3. **control_fsm** triggers **fw_engine** once the full matrix is buffered.
4. **fw_engine** runs Floyd-Warshall in 64 clock cycles (~640 ns @ 100 MHz), skipping any k-pass where `dist[k][k] < 0`.
5. **arb_detector** checks the diagonal: `dist[i][i] < 0` (above a 32-LSB noise floor) → negative cycle → profitable arbitrage. Reports the most-negative diagonal.
6. **Outputs**: LEDs flash at 2 Hz; 7-seg shows profit magnitude in `XX.XX%` (SW0=0) or raw Q16.16 integer (SW0=1); VGA highlights the arbitrage row and column in red.
7. **uart_reporter** echoes every received byte back to the host and sends a 24-byte result packet (profit_found, profit_val, diag0–3) after computation completes, readable by `test_suite.py`.

## Host scripts

| Script | Purpose |
|---|---|
| `send_rates.py` | Sends one of 3 preset rate matrices (mode 0: no arb, mode 1: ~1.5% GBP arb, mode 2: ~120% demo). Also runs a Python-side Floyd-Warshall sanity check and prints expected diagonals before transmitting. |
| `test_suite.py` | Automated 7-case test suite. Sends matrices designed to highlight each currency (EUR, GBP, JPY) individually, test dual-arb tie-breaking, and confirm no false positives. Verifies the FPGA's 24-byte result packet against Python-computed expected values. |
| `uart_test.py` | Single-byte echo tester for UART bring-up. Sends ASCII digits `0`–`9` and checks the echo byte matches. Run this first to confirm UART framing and baud rate before sending matrices. |
| `send_matrix.py` | Low-level framing helper (preamble + 64-byte payload). Used internally by `test_suite.py`. |