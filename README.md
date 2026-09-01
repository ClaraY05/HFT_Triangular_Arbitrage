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

# 5. Run the automated test suite from the host, port may be COMX or /dev/ttyUSBx depending on OS
pip install pyserial
python host/test_suite.py --port /dev/ttyUSB0
python host/test_suite.py --port COM3 --test 2   # single test
python host/test_suite.py --port COM3 --verbose  # full packet dump
```

## How it works

1. **Python** (`test_suite.py`) computes `–log(rate)` for each cell and encodes it as a Q16.16 signed integer, prepends a `0xAA 0x55` magic-byte preamble, and streams 66 bytes via USB-UART at 57600 baud.
2. **UART RX** deserializes bytes; **matrix_buffer** waits for the `0xAA 0x55` preamble then assembles the following 64 bytes into 16 × 32-bit words in BRAM.
3. **control_fsm** triggers **fw_engine** once the full matrix is buffered.
4. **fw_engine** runs the negative-cycle-detection variant of Floyd-Warshall in 64 clock cycles (~640 ns @ 100 MHz): standard min-plus relaxation over the `-log(rate)` weights, skipping any k-pass where `dist[k][k] < 0` so an already-detected cycle can't cascade through paths relayed via `k`.
5. **arb_detector** checks the diagonal: `dist[i][i] < 0` (above a 32-LSB noise floor) → node `i` sits on a negative cycle → profitable arbitrage. Reports the most-negative diagonal.
6. **Outputs**: LEDs flash at 2 Hz; 7-seg shows profit magnitude in `XX.XX%` (SW0=0) or raw Q16.16 integer (SW0=1); VGA highlights the arbitrage row and column in red.
7. **uart_reporter** echoes every received byte back to the host and sends a 24-byte result packet (profit_found, profit_val, diag0–3) after computation completes, readable by `test_suite.py`.

## Host scripts

| Script | Purpose |
|---|---|
| `test_suite.py` | Automated 7-case test suite. Sends matrices designed to highlight each currency (EUR, GBP, JPY) individually, test dual-arb tie-breaking, and confirm no false positives. Verifies the FPGA's 24-byte result packet against Python-computed expected values. |
| `uart_test.py` | Single-byte echo tester for UART bring-up. Sends ASCII digits `0`–`9` and checks the echo byte matches. Run this first to confirm UART framing and baud rate before sending matrices. See [UART digit test setup](#uart-digit-test-setup). |

--- 

## UART digit test setup

A minimal echo design for UART bring-up: the FPGA displays each received ASCII digit (`0`–`9`) on the seven-segment display and echoes the raw byte back so `uart_test.py` can verify framing and baud rate (57600, 8-N-1).

This is a **separate build** from the main design — both `src/top.v` and `src/uart/uart_top.v` declare `module top`, so they cannot coexist in one synthesis run.

1. **Create a Vivado project** targeting the Basys 3 (`xc7a35tcpg236-1`) and add only these sources:
   - `src/uart/uart_top.v` (top module — the digit-test `top`)
   - `src/uart/uart_rx.v`
   - `src/uart/uart_tx.v`
   - `src/uart/seg7_digit.v`

   Do **not** add `src/top.v` or the other main-design sources.

2. **Add the constraints file** — you must use `constraints/uart_digit_test.xdc`, **not** `basys3.xdc`. The digit test has its own port list (`clk`, `btnC`, `rx`, `tx`, `seg`, `an`, `dp`) and the main constraints file will not match it.

3. **Build and program**: run synthesis → implementation → bitstream generation, then program the board via Hardware Manager.

4. **Run the echo test** from the host:

   ```bash
   pip install pyserial
   python host/uart_test.py --port /dev/ttyUSB1 --digit 7   # one-shot
   python host/uart_test.py --port COM3                     # interactive mode
   ```

   Each sent digit should appear on all four seven-segment positions and be echoed back with an `OK ✓`. Press **btnC** (centre button) to reset. Once every digit echoes correctly, the UART link is good and you can move on to `test_suite.py` with the main bitstream.


## Full Test setup

The `sim/` directory contains self-checking testbenches for every module of the main design, plus a full integration test. Each prints `PASS`/`FAIL` lines to the Tcl console and ends with an overall summary.

| Testbench | Covers |
|---|---|
| `tb_uart_rx.v` | UART byte deserialization at 57600 baud |
| `tb_matrix_buffer.v` | `0xAA 0x55` preamble detection and 64-byte → 16-word assembly |
| `tb_control_fsm.v` | Buffer-ready → engine-start handshake |
| `tb_fw_engine.v` | Floyd-Warshall correctness on known matrices (checks diagonal signs) |
| `tb_arb_detector.v` | Negative-diagonal detection, noise floor, most-negative tie-breaking |
| `tb_top.v` | Full integration: UART bytes in → `buf_ready` → `done` → `profit_found` → LED flash |

To run a testbench:

1. Add `sim/*.v` to the project as **simulation-only sources** (Add Sources → Add or create simulation sources), alongside the `src/` design files. Do not include `src/uart/uart_top.v` (it clashes with `src/top.v` — see the digit-test note above).
2. In the Sources window under *Simulation Sources*, right-click the testbench you want (e.g. `tb_fw_engine`) → **Set as Top**.
3. **Run Simulation → Run Behavioral Simulation**, then let it run to `$finish` (`run all` in the Tcl console if it pauses).
4. Check the Tcl console for the summary, e.g. `=== ALL FW ENGINE TESTS PASSED ===`.

Recommended order: `tb_uart_rx` → `tb_matrix_buffer` → `tb_control_fsm` → `tb_fw_engine` → `tb_arb_detector` → `tb_top`, mirroring the datapath. Note `tb_top` simulates real UART timing at 57600 baud, so it needs a few ms of simulated time; VGA output is only spot-checked in sim (the clock-wizard IP is stubbed) and is validated visually on-board.

Simulation checks the RTL only — after it passes, verify on hardware with the host-side suite (`python host/test_suite.py --port <PORT>`, step 6 of the Quick start), which exercises the same logic end-to-end over a real UART link.