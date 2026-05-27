"""
send_rates.py  --  Triangular Arbitrage FPGA Host Script
=========================================================
Usage:
    python send_rates.py [COM_PORT] [mode]

    mode 0  (default) : NO arbitrage  -- mathematically consistent rates,
                        all triangular products = 1.0, board stays dark.
    mode 1            : ARBITRAGE ~1.5% -- GBP/EUR mispriced by 1.5%,
                        produces a clear USD->GBP->EUR->USD cycle.
    mode 2            : BIG ARBITRAGE ~120% -- obvious 1.5x demo cycle.

Examples:
    python send_rates.py /dev/tty.usbserial-XXXXX 0   # no arb
    python send_rates.py /dev/tty.usbserial-XXXXX 1   # subtle arb
    python send_rates.py /dev/tty.usbserial-XXXXX 2   # big demo arb
    python send_rates.py COM3 1                         # Windows

BUG FIX: The original mode 0 rates were inconsistent cross-rates
(e.g. USD/EUR * EUR/GBP != USD/GBP), which created a real ~1.8-4%
triangular arbitrage opportunity even in the "no arbitrage" test case.
Mode 0 now derives all cross-rates from a single consistent base so
that every triangular product equals exactly 1.0.
"""

import math, struct, sys, time

try:
    import serial
except ImportError:
    print("pip install pyserial")
    sys.exit(1)

SCALE = 1 << 16          # Q16.16 scale factor
INF_Q = 0x3FFF_FFFF      # sentinel for "no direct FX path"
BAUD  = 115_200
LABELS = ["USD", "EUR", "GBP", "JPY"]

# --------------------------------------------------------------------------
# Rate matrices
# --------------------------------------------------------------------------

# --- Mode 0: Consistent no-arbitrage rates ---
# Derive all crosses from base rates so every triangular product = 1.0.
# Base (USD as numeraire):
_USD_EUR = 0.9217    # EUR per 1 USD
_USD_GBP = 0.7889    # GBP per 1 USD
_USD_JPY = 149.50    # JPY per 1 USD

_NO_ARB = [
    # from\to      USD                     EUR                        GBP                        JPY
    [1.0,          _USD_EUR,               _USD_GBP,                  _USD_JPY             ],  # USD
    [1/_USD_EUR,   1.0,                    _USD_GBP/_USD_EUR,         _USD_JPY/_USD_EUR    ],  # EUR
    [1/_USD_GBP,   _USD_EUR/_USD_GBP,      1.0,                       _USD_JPY/_USD_GBP    ],  # GBP
    [1/_USD_JPY,   _USD_EUR/_USD_JPY,      _USD_GBP/_USD_JPY,         1.0                  ],  # JPY
]

# --- Mode 1: ~1.5% mispricing on GBP->EUR ---
# All other rates identical to mode 0; only rates[2][1] (GBP->EUR) is bumped.
_GBP_EUR_FAIR      = _USD_EUR / _USD_GBP
_GBP_EUR_MISPRICED = _GBP_EUR_FAIR * 1.015   # 1.5% too high

_ARB_SUBTLE = [
    [1.0,          _USD_EUR,               _USD_GBP,                  _USD_JPY             ],  # USD
    [1/_USD_EUR,   1.0,                    _USD_GBP/_USD_EUR,         _USD_JPY/_USD_EUR    ],  # EUR
    [1/_USD_GBP,   _GBP_EUR_MISPRICED,     1.0,                       _USD_JPY/_USD_GBP    ],  # GBP
    [1/_USD_JPY,   _USD_EUR/_USD_JPY,      _USD_GBP/_USD_JPY,         1.0                  ],  # JPY
]

# --- Mode 2: Obvious demo cycle (not realistic) ---
_ARB_BIG = [
    [1.000, 1.500, 0.001, 0.001],
    [0.001, 1.000, 1.500, 0.001],
    [1.500, 0.001, 1.000, 0.001],
    [0.001, 0.001, 0.001, 1.000],
]

MATRICES = {
    0: {"name": "NO ARBITRAGE (consistent cross-rates)",          "rates": _NO_ARB},
    1: {"name": "ARBITRAGE ~1.5%  (GBP->EUR mispriced by 1.5%)", "rates": _ARB_SUBTLE},
    2: {"name": "BIG ARBITRAGE ~120%  (demo cycle)",             "rates": _ARB_BIG},
}

# --------------------------------------------------------------------------
# Encoding helpers
# --------------------------------------------------------------------------
def log_transform(rates):
    words = []
    for i, row in enumerate(rates):
        for j, r in enumerate(row):
            if i == j:
                words.append(0)
            elif r <= 1e-9:
                words.append(INF_Q)
            else:
                words.append(int(round(-math.log(r) * SCALE)))
    return words

def pack_matrix(words):
    assert len(words) == 16
    return b"".join(struct.pack("<i", w) for w in words)

def fw_check(words):
    """Python-side Floyd-Warshall sanity check — prints expected FPGA result."""
    dist = list(words)
    for k in range(4):
        for i in range(4):
            for j in range(4):
                t = dist[i*4+k] + dist[k*4+j]
                if t < dist[i*4+j]:
                    dist[i*4+j] = t

    print("  FROM\\TO  " + "  ".join(f"{l:>8}" for l in LABELS))
    print("  " + "-" * 44)
    for i in range(4):
        row_str = f"  {LABELS[i]:3}    "
        for j in range(4):
            v = dist[i*4+j]
            if v >= INF_Q // 2:
                row_str += "     INF"
            else:
                row_str += f"  {v:+6d}"
        print(row_str)

    print("\n  Diagonals (negative = arbitrage cycle found):")
    any_arb = False
    for idx, d in enumerate([dist[0], dist[5], dist[10], dist[15]]):
        pct = (-d / SCALE) * 100 if d < 0 else 0.0
        flag = "  <-- *** ARBITRAGE ***" if d < 0 else ""
        print(f"    dist[{LABELS[idx]}][{LABELS[idx]}] = {d:+8d}  ({pct:+.4f}%){flag}")
        if d < 0:
            any_arb = True
    if not any_arb:
        print("    No negative cycle — board should stay dark.")
    print()

def send(port, mode):
    m = MATRICES[mode]
    print(f"\n{'='*60}")
    print(f"  Mode {mode}: {m['name']}")
    print(f"{'='*60}\n")
    words   = log_transform(m["rates"])
    payload = pack_matrix(words)
    fw_check(words)
    print(f"  Sending to {port} @ {BAUD} baud ({len(payload)} bytes) ...")
    with serial.Serial(port, BAUD, timeout=2) as ser:
        time.sleep(0.05)
        ser.reset_input_buffer()
        n = ser.write(payload)
        ser.flush()
        time.sleep(0.5)
        print(f"  Sent {n} bytes.  Watch the board!\n")

if __name__ == "__main__":
    port = sys.argv[1] if len(sys.argv) > 1 else (
        "COM3" if sys.platform == "win32" else "/dev/ttyUSB1"
    )
    mode = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    if mode not in MATRICES:
        print(f"Mode must be 0, 1, or 2.  Got {mode}.")
        sys.exit(1)
    send(port, mode)
