#!/usr/bin/env python3
"""
send_matrix.py  --  Send a 4x4 exchange-rate matrix to the Basys 3 arbitrage
                    detector and read back the result packet.

PROTOCOL
--------
TX (Python → FPGA):
  0xAA 0x55          start-of-frame header
  64 bytes           4x4 matrix of signed Q16.16 values, row-major,
                     each word little-endian.
                     value = round(-log(rate) * 65536)

  The FPGA echoes every byte back immediately.  This script reads each
  echo before sending the next byte, giving byte-level verification.

RX (FPGA → Python, after Floyd-Warshall completes):
  Offset  Bytes  Field
     0      1    0xAA          start header
     1      1    0x55          start header
     2      1    profit_found  0x00 = no arbitrage, 0x01 = detected
     3      4    profit_val    Q16.16 magnitude of most-negative diagonal (LE)
     7      4    diag0         dist[0][0] raw Q16.16 (LE)
    11      4    diag1         dist[1][1] raw Q16.16 (LE)
    15      4    diag2         dist[2][2] raw Q16.16 (LE)
    19      4    diag3         dist[3][3] raw Q16.16 (LE)
    23      1    0xFF          end marker

CURRENCIES
----------
  Index 0 = USD
  Index 1 = EUR
  Index 2 = GBP
  Index 3 = JPY

  rates[i][j] = units of currency j received for 1 unit of currency i.
  Diagonal (self-loops) must be 1.0 (weight = 0).

USAGE
-----
  pip install pyserial

  # Send the built-in no-arbitrage matrix
  python send_matrix.py --port COM3

  # Send the built-in arbitrage matrix
  python send_matrix.py --port /dev/ttyUSB0 --arb

  # Send a custom CSV file  (4 rows × 4 cols, diagonal = 1.0)
  python send_matrix.py --port COM3 --csv rates.csv

DEPENDENCIES
------------
  pyserial (required)
  numpy    (optional — used only for CSV loading)
"""

import argparse
import math
import struct
import sys
import time

try:
    import serial
except ImportError:
    sys.exit("pyserial is required:  pip install pyserial")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BAUD        = 57600
CURRENCIES  = ["USD", "EUR", "GBP", "JPY"]
PKT_LEN     = 24          # result packet length
ECHO_TIMEOUT = 0.5        # seconds per echo byte
RESULT_TIMEOUT = 3.0      # seconds to wait for the result packet

# ---------------------------------------------------------------------------
# Built-in exchange rate matrices
# ---------------------------------------------------------------------------

# Realistic mid-market rates (no guaranteed arbitrage)
RATES_NO_ARB = [
    #  USD       EUR       GBP       JPY
    [1.0000,   0.9200,   0.7900,  149.50],   # FROM USD
    [1.0870,   1.0000,   0.8590,  162.70],   # FROM EUR
    [1.2660,   1.1640,   1.0000,  189.40],   # FROM GBP
    [0.00669,  0.00615,  0.00528,   1.00 ],   # FROM JPY
]

# Same rates but USD→EUR→GBP→USD creates a small ~0.3% arbitrage loop.
# USD→EUR: 0.9200, EUR→GBP: 0.8590, GBP→USD: 1.2750
# Product: 0.9200 × 0.8590 × 1.2750 = 1.0073  (>1 → profit)
RATES_ARB = [
    #  USD       EUR       GBP       JPY
    [1.0000,   0.9200,   0.7900,  149.50],   # FROM USD
    [1.0870,   1.0000,   0.8590,  162.70],   # FROM EUR
    [1.2750,   1.1640,   1.0000,  189.40],   # FROM GBP  ← USD rate bumped
    [0.00669,  0.00615,  0.00528,   1.00 ],   # FROM JPY
]

# ---------------------------------------------------------------------------
# Conversion helpers
# ---------------------------------------------------------------------------

def rate_to_q1616(rate: float) -> int:
    """
    Convert an exchange rate to a signed Q16.16 fixed-point edge weight.
    weight = -log(rate) * 65536, rounded and clamped to signed 32-bit.
    """
    if rate <= 0:
        raise ValueError(f"Rate must be positive, got {rate}")
    w = -math.log(rate) * 65536.0
    w_int = int(round(w))
    # Clamp to signed 32-bit range
    return max(-2_147_483_648, min(2_147_483_647, w_int))


def matrix_to_bytes(rates: list) -> bytes:
    """
    Flatten a 4×4 rate matrix to 64 bytes (signed 32-bit LE per element).
    """
    out = bytearray()
    for row in rates:
        for r in row:
            w = rate_to_q1616(r)
            out += struct.pack('<i', w)
    assert len(out) == 64
    return bytes(out)


def q1616_to_float(raw: int) -> float:
    """Convert a signed Q16.16 integer (as Python int) to a float."""
    # Treat as signed 32-bit
    if raw >= 2**31:
        raw -= 2**32
    return raw / 65536.0


def q1616_to_pct(raw: int) -> float:
    """Q16.16 profit magnitude → percentage (multiply by 100)."""
    return q1616_to_float(raw) * 100.0

# ---------------------------------------------------------------------------
# Serial helpers
# ---------------------------------------------------------------------------

def send_byte_with_echo(ser: serial.Serial, b: int, label: str = "") -> bool:
    """
    Send one byte; read back the echo; return True if they match.
    """
    ser.write(bytes([b]))
    echo = ser.read(1)
    if not echo:
        print(f"  [TIMEOUT] No echo for byte 0x{b:02X}{' (' + label + ')' if label else ''}")
        return False
    e = echo[0]
    if e != b:
        print(f"  [MISMATCH] Sent 0x{b:02X}, got 0x{e:02X}{' (' + label + ')' if label else ''}")
        return False
    return True


def send_matrix_with_echo(ser: serial.Serial, rates: list) -> bool:
    """
    Send the full 66-byte frame (0xAA 0x55 + 64 data bytes) with echo
    verification on each byte.  Returns True if all echoes matched.
    """
    payload = matrix_to_bytes(rates)
    frame   = bytes([0xAA, 0x55]) + payload

    print(f"\n  Sending {len(frame)} bytes (header + 64-byte matrix payload)…")
    all_ok = True

    # Header bytes
    if not send_byte_with_echo(ser, 0xAA, "header[0]"):
        all_ok = False
    if not send_byte_with_echo(ser, 0x55, "header[1]"):
        all_ok = False

    # Payload: 16 words × 4 bytes each
    for word_idx in range(16):
        row = word_idx // 4
        col = word_idx % 4
        for byte_pos in range(4):
            b = payload[word_idx * 4 + byte_pos]
            label = f"[{CURRENCIES[row]}→{CURRENCIES[col]}] byte{byte_pos}"
            if not send_byte_with_echo(ser, b, label):
                all_ok = False

    return all_ok


def read_result_packet(ser: serial.Serial) -> dict | None:
    """
    Wait for and parse the 24-byte result packet.
    Scans the incoming stream for the 0xAA 0x55 header, then reads 22 more
    bytes and validates the 0xFF end marker.
    Returns a dict with parsed fields, or None on failure.
    """
    print(f"\n  Waiting for result packet (timeout {RESULT_TIMEOUT}s)…")
    ser.timeout = RESULT_TIMEOUT

    # Scan for 0xAA 0x55 header
    found_header = False
    deadline = time.monotonic() + RESULT_TIMEOUT
    prev = None
    while time.monotonic() < deadline:
        b = ser.read(1)
        if not b:
            break
        cur = b[0]
        if prev == 0xAA and cur == 0x55:
            found_header = True
            break
        prev = cur

    if not found_header:
        print("  [ERROR] Result packet header (0xAA 0x55) not received.")
        return None

    # Read remaining 22 bytes (profit_found + profit_val + 4 diags + 0xFF)
    remaining = ser.read(22)
    if len(remaining) < 22:
        print(f"  [ERROR] Short result packet: got {len(remaining)+2}/24 bytes.")
        return None

    # Parse
    profit_found = remaining[0]
    profit_val   = struct.unpack('<i', remaining[1:5])[0]    # signed 32-bit LE
    diag0        = struct.unpack('<i', remaining[5:9])[0]
    diag1        = struct.unpack('<i', remaining[9:13])[0]
    diag2        = struct.unpack('<i', remaining[13:17])[0]
    diag3        = struct.unpack('<i', remaining[17:21])[0]
    end_marker   = remaining[21]

    if end_marker != 0xFF:
        print(f"  [WARNING] End marker expected 0xFF, got 0x{end_marker:02X}")

    return {
        "profit_found": profit_found,
        "profit_val":   profit_val,
        "diag0":        diag0,
        "diag1":        diag1,
        "diag2":        diag2,
        "diag3":        diag3,
    }


def print_result(result: dict) -> None:
    """Pretty-print the parsed result packet."""
    found = result["profit_found"]
    pval  = result["profit_val"]
    diags = [result["diag0"], result["diag1"], result["diag2"], result["diag3"]]

    print("\n" + "=" * 60)
    print("  FPGA RESULT")
    print("=" * 60)

    if found:
        pct = q1616_to_pct(pval)
        print(f"  ✓  Arbitrage DETECTED")
        print(f"     Profit magnitude : {pct:.4f}%")
        print(f"     profit_val (raw) : 0x{pval & 0xFFFFFFFF:08X}  ({pval})")
    else:
        print("  –  No arbitrage detected")
        print(f"     profit_val (raw) : 0x{pval & 0xFFFFFFFF:08X}  ({pval})")

    print()
    print("  Diagonal values (dist[i][i] after Floyd-Warshall):")
    print("  Negative → negative-weight cycle = arbitrage on that currency")
    print()
    for idx, (cur, d) in enumerate(zip(CURRENCIES, diags)):
        fval = q1616_to_float(d)
        flag = "  ← NEGATIVE CYCLE" if d < 0 else ""
        print(f"    diag{idx} [{cur}]: 0x{d & 0xFFFFFFFF:08X}  = {fval:+.6f}{flag}")

    print("=" * 60)


def print_matrix(rates: list) -> None:
    """Print the exchange rate matrix being sent."""
    print("\n  Exchange rate matrix (rates[i][j] = i→j):")
    header = "        " + "  ".join(f"{c:>8}" for c in CURRENCIES)
    print(header)
    for i, (row, cur) in enumerate(zip(rates, CURRENCIES)):
        vals = "  ".join(f"{r:8.5f}" for r in row)
        print(f"  {cur}:  {vals}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Send exchange rate matrix to Basys 3 arbitrage detector."
    )
    parser.add_argument("--port", "-p", required=True,
                        help="Serial port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--arb", action="store_true",
                        help="Use the built-in arbitrage test matrix")
    parser.add_argument("--csv", metavar="FILE",
                        help="Load a 4×4 CSV of exchange rates instead")
    parser.add_argument("--no-echo-check", action="store_true",
                        help="Skip echo verification (still reads echoes)")
    args = parser.parse_args()

    # Select rate matrix
    if args.csv:
        try:
            import csv
            with open(args.csv) as f:
                rates = [[float(x) for x in row] for row in csv.reader(f)]
            if len(rates) != 4 or any(len(r) != 4 for r in rates):
                sys.exit("CSV must be exactly 4 rows × 4 columns")
        except Exception as e:
            sys.exit(f"Could not load CSV: {e}")
    elif args.arb:
        rates = RATES_ARB
        print("Using built-in ARBITRAGE test matrix (USD→EUR→GBP→USD ~0.7% profit)")
    else:
        rates = RATES_NO_ARB
        print("Using built-in NO-ARBITRAGE matrix  (use --arb to test detection)")

    print_matrix(rates)

    # Open port
    print(f"\n  Opening {args.port} at {BAUD} baud (8-N-1)…")
    try:
        ser = serial.Serial(
            port     = args.port,
            baudrate = BAUD,
            bytesize = serial.EIGHTBITS,
            parity   = serial.PARITY_NONE,
            stopbits = serial.STOPBITS_ONE,
            timeout  = ECHO_TIMEOUT,
            xonxoff  = False,
            rtscts   = False,
        )
    except serial.SerialException as exc:
        sys.exit(f"Could not open port: {exc}")

    # Send matrix with echo verification
    all_echoes_ok = send_matrix_with_echo(ser, rates)
    if all_echoes_ok:
        print("\n  ✓  All 66 echo bytes matched — matrix received correctly")
    else:
        print("\n  ✗  Echo mismatches detected — FPGA may have received wrong data")
        if not args.no_echo_check:
            print("     Aborting.  Use --no-echo-check to proceed anyway.")
            ser.close()
            return

    # Read result packet
    result = read_result_packet(ser)
    if result:
        print_result(result)
    else:
        print("  Failed to receive result packet.")

    ser.close()
    print("\n  Port closed.")


if __name__ == "__main__":
    main()
