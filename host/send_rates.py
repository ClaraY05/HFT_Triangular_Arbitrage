"""
send_rates.py  --  Triangular Arbitrage FPGA Host Script
=========================================================
Transforms a 4×4 exchange rate matrix into Q16.16 fixed-point integers
(using the negative-log transform) and streams them to the Basys 3 via
UART at 115200 baud.

Usage:
    python send_rates.py [COM_PORT]
    python send_rates.py COM3          # Windows
    python send_rates.py /dev/ttyUSB1  # Linux

Dependencies:
    pip install pyserial

Matrix encoding:
    Each of the 16 rates is sent as a 4-byte little-endian signed integer.
    Total payload: 64 bytes.

Fixed-point encoding:
    value = round(-log(rate) * 65536)
    A rate of 1.0 → 0.  A rate > 1 → negative value (profitable direction).

Diagonal (self-rates) MUST be 1.0 → encoded as 0.
INF entries (no direct FX path) should be a large positive number
(e.g. 0x3FFF_FFFF) rather than 0, so the FW update doesn't incorrectly
treat them as free paths.
"""

import math
import struct
import sys
import time

try:
    import serial
except ImportError:
    print("pyserial not found.  Install with:  pip install pyserial")
    sys.exit(1)

# --------------------------------------------------------------------------
# Exchange rate matrix  (row = from, col = to)
# Currencies:  [0]=USD  [1]=EUR  [2]=GBP  [3]=JPY
#
# Replace with live rates from your data feed.
# Diagonal must be 1.0.
# Use 0 for pairs with no direct FX market (they become INF after transform).
# --------------------------------------------------------------------------
RATES = [
    #  USD      EUR      GBP      JPY
    [1.0000, 1.0850, 1.2700, 149.50],   # from USD
    [0.9220, 1.0000, 1.1710, 137.80],   # from EUR
    [0.7880, 0.8540, 1.0000, 117.70],   # from GBP
    [0.0067, 0.0073, 0.0085,  1.000],   # from JPY
]

SCALE  = 1 << 16          # Q16.16 scale factor
INF_Q  = 0x3FFF_FFFF      # "no path" sentinel (large positive signed int)
BAUD   = 115_200


def log_transform(rate_matrix: list[list[float]]) -> list[int]:
    """Convert rate matrix → list of 16 Q16.16 signed integers."""
    words = []
    for i, row in enumerate(rate_matrix):
        for j, r in enumerate(row):
            if i == j:
                words.append(0)          # self-loop: zero cost
            elif r <= 0.0:
                words.append(INF_Q)      # no path
            else:
                val = -math.log(r) * SCALE
                words.append(int(round(val)))
    return words


def pack_matrix(words: list[int]) -> bytes:
    """Pack 16 signed 32-bit integers as little-endian bytes (64 bytes)."""
    assert len(words) == 16
    return b"".join(struct.pack("<i", w) for w in words)


def check_arbitrage(words: list[int]) -> None:
    """Quick Python-side sanity check: simulate FW and print expected result."""
    INF = INF_Q
    dist = list(words)  # flat 4×4

    for k in range(4):
        for i in range(4):
            for j in range(4):
                through = dist[i*4+k] + dist[k*4+j]
                if through < dist[i*4+j]:
                    dist[i*4+j] = through

    print("\n--- Python FW sanity check ---")
    diagonals = [dist[0], dist[5], dist[10], dist[15]]
    for idx, d in enumerate(diagonals):
        profit_pct = (-d / SCALE) * 100 if d < 0 else 0.0
        flag = " *** ARBITRAGE ***" if d < 0 else ""
        print(f"  dist[{idx}][{idx}] = {d:+10d}  ({profit_pct:+.4f}%){flag}")
    print()


def send(port: str) -> None:
    words   = log_transform(RATES)
    payload = pack_matrix(words)

    print(f"Sending 4×4 matrix to {port} @ {BAUD} baud")
    print(f"Q16.16 values: {words}")
    check_arbitrage(words)

    with serial.Serial(port, BAUD, timeout=2) as ser:
        time.sleep(0.05)   # let FTDI enumerate
        ser.reset_input_buffer()
        n = ser.write(payload)
        ser.flush()
        print(f"Wrote {n} bytes.  Waiting for FPGA response...")
        time.sleep(0.5)    # give FPGA time to process


if __name__ == "__main__":
    port = sys.argv[1] if len(sys.argv) > 1 else ("COM3" if sys.platform == "win32"
                                                    else "/dev/ttyUSB1")
    send(port)
