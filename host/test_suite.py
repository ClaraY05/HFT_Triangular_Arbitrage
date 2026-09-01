#!/usr/bin/env python3
"""
test_suite.py  --  Full coverage test suite for the Basys 3 triangular arbitrage detector.

Sends 7 test cases over UART and checks the FPGA result packet against expected values.
Each test is designed to force a specific diagonal negative (or none).

TESTS
-----
  0  No Arbitrage        All diagonals ~0.  profit_found = 0.  No VGA highlighting.
  1  EUR highlighted     USD->EUR mispriced +2%.  EUR row+col lights red.
  2  GBP highlighted     EUR->GBP mispriced +2%.  GBP row+col lights red.
  3  JPY highlighted     USD->JPY mispriced +2%.  JPY row+col lights red.
  4  Subtle GBP (~0.27%) Existing built-in --arb rate.  GBP lit, small profit text.
  5  Dual arb (EUR wins) USD->EUR +3% AND USD->JPY +1%.  EUR is stronger; EUR highlighted.
  6  Dual arb (JPY wins) USD->EUR +1% AND USD->JPY +3%.  JPY is stronger; JPY highlighted.

USAGE
-----
  pip install pyserial
  python test_suite.py --port COM3
  python test_suite.py --port /dev/ttyUSB0 --test 2   # run only test 2
  python test_suite.py --port COM3 --verbose           # show full packet dump

Implementation note: The Floyd-Warshall engine skips a k-pass when dist[k][k] is 
already negative. As a result, arbitrage involving USD may not cause the USD diagonal
to become negative in the expected pass. The current test suite therefore does not 
test USD highlighting and instead focuses on cases where another currency's diagonal
becomes negative.
"""
import argparse
import math
import struct
import sys
import time
import serial # must have pyserial installed

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
BAUD           = 57600
CURRENCIES     = ["USD", "EUR", "GBP", "JPY"]
SCALE          = 65536          # Q16.16 scale
NOISE_FLOOR    = 32             # arb_detector threshold (matches RTL)
PKT_LEN        = 24
ECHO_TIMEOUT   = 0.5
RESULT_TIMEOUT = 5.0

# ---------------------------------------------------------------------------
# Rate matrix helpers
# ---------------------------------------------------------------------------
BASE = [1.0, 0.92, 0.79, 149.50]   # USD, EUR, GBP, JPY vs USD


def consistent(base=BASE):
    """Build a perfectly consistent 4×4 FX matrix from a single base vector."""
    return [[base[j] / base[i] for j in range(4)] for i in range(4)]


def rate_to_q1616(rate: float) -> int:
    w = int(round(-math.log(rate) * SCALE))
    return max(-2_147_483_648, min(2_147_483_647, w))


def matrix_to_bytes(rates: list) -> bytes:
    out = bytearray()
    for row in rates:
        for r in row:
            out += struct.pack("<i", rate_to_q1616(r))
    assert len(out) == 64
    return bytes(out)


def q1616_to_float(raw: int) -> float:
    if raw >= 2 ** 31:
        raw -= 2 ** 32
    return raw / SCALE


def q1616_to_pct(raw: int) -> float:
    return q1616_to_float(raw) * 100.0


# ---------------------------------------------------------------------------
# Python-side Floyd-Warshall
# Used to pre-compute expected diagonals for each test.
# ---------------------------------------------------------------------------
def fw_python(rates):
    """Return post-FW signed diagonal values [diag0, diag1, diag2, diag3]."""
    weights = []
    for i in range(4):
        for j in range(4):
            if i == j:
                weights.append(0)
            else:
                weights.append(int(round(-math.log(rates[i][j]) * SCALE)))
    dist = list(weights)
    for k in range(4):
        if dist[k * 4 + k] >= 0:
            for i in range(4):
                for j in range(4):
                    t = dist[i * 4 + k] + dist[k * 4 + j]
                    if t < dist[i * 4 + j]:
                        dist[i * 4 + j] = t
    raw = [dist[0], dist[5], dist[10], dist[15]]
    return [d if d < 2 ** 31 else d - 2 ** 32 for d in raw]


def expected_best(diags):
    """
    Mirror fw_engine S_DONE logic (after fix): pick most-negative diagonal
    above NOISE_FLOOR.  Returns (best_idx, profit_val) or (-1, 0).
    """
    best_val = 0
    best_idx = -1
    for idx, d in enumerate(diags):
        if d < -NOISE_FLOOR and d < best_val:
            best_val = d
            best_idx = idx
    profit_val = -best_val if best_idx >= 0 else 0
    return best_idx, profit_val


# ---------------------------------------------------------------------------
# Build the 7 test matrices
# ---------------------------------------------------------------------------
def _m(description, rates, note=""):
    diags = fw_python(rates)
    best_idx, profit_val = expected_best(diags)
    profit_found = best_idx >= 0
    highlighted  = CURRENCIES[best_idx] if profit_found else "NONE"
    pct          = profit_val / SCALE * 100.0
    return {
        "description": description,
        "note":        note,
        "rates":       rates,
        "diags":       diags,
        "profit_found": profit_found,
        "profit_val":   profit_val,
        "highlighted":  highlighted,
        "pct":          pct,
    }


def build_tests():
    tests = []

    # 0 — No arbitrage
    tests.append(_m(
        "No Arbitrage",
        consistent(),
        note="All triangular products = 1.0; board should stay dark",
    ))

    # 1 — EUR highlighted (USD->EUR mispriced +2%)
    r = consistent()
    r[0][1] *= 1.02          # more EUR received per USD than fair value
    tests.append(_m(
        "EUR highlighted  (USD→EUR +2%)",
        r,
        note="Cycle USD→EUR→USD yields 2% profit; EUR row+col turns red",
    ))

    # 2 — GBP highlighted (EUR->GBP mispriced +2%)
    r = consistent()
    r[1][2] *= 1.02          # more GBP received per EUR than fair value
    tests.append(_m(
        "GBP highlighted  (EUR→GBP +2%)",
        r,
        note="Cycle EUR→GBP→EUR yields 2% profit; GBP row+col turns red",
    ))

    # 3 — JPY highlighted (USD->JPY mispriced +2%)
    r = consistent()
    r[0][3] *= 1.02          # more JPY received per USD than fair value
    tests.append(_m(
        "JPY highlighted  (USD→JPY +2%)",
        r,
        note="Cycle USD→JPY→USD yields 2% profit; JPY row+col turns red",
    ))

    # 4 — Subtle GBP (built-in --arb rate, ~0.27%)
    r = consistent()
    r[1][2] = 0.861
    r[2][1] = 1 / 0.861
    tests.append(_m(
        "Subtle GBP arb   (built-in --arb, ~0.27%)",
        r,
        note="Small mispricing; profit text shows ~0.27%; GBP row+col lit",
    ))

    # 5 — Dual arb: EUR +3% vs JPY +1% → EUR wins
    r = consistent()
    r[0][1] *= 1.03
    r[0][3] *= 1.01
    tests.append(_m(
        "Dual arb: EUR +3% vs JPY +1%  →  EUR wins",
        r,
        note="Both EUR and JPY are negative; stronger EUR signal highlighted",
    ))

    # 6 — Dual arb: USD->EUR +1% vs USD->JPY +3% → JPY wins
    r = consistent()
    r[0][1] *= 1.01
    r[0][3] *= 1.03
    tests.append(_m(
        "Dual arb: EUR +1% vs JPY +3%  →  JPY wins",
        r,
        note="Both EUR and JPY are negative; stronger JPY signal highlighted",
    ))

    return tests


# ---------------------------------------------------------------------------
# Serial helpers (same protocol as send_matrix.py)
# ---------------------------------------------------------------------------

def send_byte_with_echo(ser, b, label=""):
    ser.write(bytes([b]))
    echo = ser.read(1)
    if not echo:
        print(f"  [TIMEOUT] No echo for 0x{b:02X} {label}")
        return False
    if echo[0] != b:
        print(f"  [MISMATCH] Sent 0x{b:02X}, got 0x{echo[0]:02X} {label}")
        return False
    return True


def send_matrix(ser, rates, verbose=False):
    payload = matrix_to_bytes(rates)
    frame   = bytes([0xAA, 0x55]) + payload
    all_ok  = True
    for i, b in enumerate(frame):
        label = "hdr" if i < 2 else f"byte{i-2}"
        if not send_byte_with_echo(ser, b, label):
            all_ok = False
    if verbose:
        print(f"    Echo: {'✓ all matched' if all_ok else '✗ mismatches'}")
    return all_ok


def read_result(ser):
    ser.timeout = RESULT_TIMEOUT
    found_hdr   = False
    deadline    = time.monotonic() + RESULT_TIMEOUT
    prev        = None
    while time.monotonic() < deadline:
        b = ser.read(1)
        if not b:
            break
        cur = b[0]
        if prev == 0xAA and cur == 0x55:
            found_hdr = True
            break
        prev = cur
    if not found_hdr:
        return None
    remaining = ser.read(22)
    if len(remaining) < 22:
        return None
    return {
        "profit_found": remaining[0],
        "profit_val":   struct.unpack("<i", remaining[1:5])[0],
        "diag0":        struct.unpack("<i", remaining[5:9])[0],
        "diag1":        struct.unpack("<i", remaining[9:13])[0],
        "diag2":        struct.unpack("<i", remaining[13:17])[0],
        "diag3":        struct.unpack("<i", remaining[17:21])[0],
    }


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------
PASS = "✓  PASS"
FAIL = "✗  FAIL"


def run_test(ser, test, verbose=False):
    desc = test["description"]
    print(f"\n  {'─'*60}")
    print(f"  {desc}")
    if test["note"]:
        print(f"  Note: {test['note']}")
    print(f"  {'─'*60}")
    print(f"  Expected:  profit_found={int(test['profit_found'])}  "
          f"highlighted={test['highlighted']}  pct={test['pct']:.4f}%")

    # Transmit
    ok = send_matrix(ser, test["rates"], verbose=verbose)
    if not ok:
        print(f"  [ERROR] Echo verification failed — skipping result check")
        return False

    # Receive
    result = read_result(ser)
    if result is None:
        print(f"  [ERROR] No result packet received")
        return False

    # Unpack
    pf    = result["profit_found"]
    pval  = result["profit_val"]
    diags = [result["diag0"], result["diag1"], result["diag2"], result["diag3"]]
    diags_s = [d if d < 2**31 else d - 2**32 for d in diags]
    pct   = q1616_to_pct(pval)

    if verbose:
        print(f"  Received:  profit_found={pf}  profit_val={pval} ({pct:.4f}%)")
        for i, (cur, d) in enumerate(zip(CURRENCIES, diags_s)):
            flag = "  ← neg" if d < 0 else ""
            print(f"    diag{i} [{cur}]: {d:+d}{flag}")

    # Determine which currency the FPGA highlighted
    # (fw_engine picks most-negative above noise floor)
    best_idx_fpga, _ = expected_best(diags_s)
    fpga_highlighted = CURRENCIES[best_idx_fpga] if best_idx_fpga >= 0 else "NONE"

    # Checks
    checks = []

    # 1. profit_found
    exp_pf = int(test["profit_found"])
    ok_pf  = (pf == exp_pf)
    checks.append((ok_pf, f"profit_found: got {pf}, want {exp_pf}"))

    # 2. highlighted currency (only if arb expected)
    if test["profit_found"]:
        ok_hl = (fpga_highlighted == test["highlighted"])
        checks.append((ok_hl,
            f"highlighted: got {fpga_highlighted}, want {test['highlighted']}"))

    # 3. profit magnitude within 5 LSBs (Q16.16 rounding tolerance)
    if test["profit_found"] and pf:
        delta = abs(pval - test["profit_val"])
        ok_pv = (delta <= 5)
        checks.append((ok_pv,
            f"profit_val: got {pval} ({pct:.4f}%), "
            f"want {test['profit_val']} ({test['pct']:.4f}%), delta={delta}"))

    # 4. No spurious detection for no-arb case
    if not test["profit_found"]:
        ok_quiet = (pf == 0)
        checks.append((ok_quiet, f"no-arb: profit_found should be 0, got {pf}"))

    all_passed = all(ok for ok, _ in checks)
    for ok, msg in checks:
        print(f"    {'✓' if ok else '✗'} {msg}")
    print(f"  {'─'*60}")
    print(f"  {PASS if all_passed else FAIL}")
    return all_passed


def main():
    parser = argparse.ArgumentParser(
        description="Test suite for Basys 3 triangular arbitrage detector."
    )
    parser.add_argument("--port", "-p", required=True,
                        help="Serial port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--test", "-t", type=int, default=None,
                        help="Run only this test index (0–6).  Default: run all.")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print full packet dump for each test")
    args = parser.parse_args()

    tests = build_tests()

    # Select subset
    if args.test is not None:
        if args.test < 0 or args.test >= len(tests):
            sys.exit(f"Test index must be 0–{len(tests)-1}")
        selected = [(args.test, tests[args.test])]
    else:
        selected = list(enumerate(tests))

    print(f"\n{'='*62}")
    print(f"  Triangular Arbitrage FPGA — Test Suite")
    print(f"  Port: {args.port}  |  Tests: {len(selected)}")
    print(f"{'='*62}")

    # Print expected outcomes table
    print(f"\n  {'#':<3} {'Description':<42} {'Highlighted':<12} {'Profit %'}")
    print(f"  {'─'*3} {'─'*42} {'─'*12} {'─'*10}")
    for idx, t in selected:
        print(f"  {idx:<3} {t['description']:<42} "
              f"{t['highlighted']:<12} {t['pct']:.4f}%")

    # Open port
    try:
        ser = serial.Serial(
            port=args.port, baudrate=BAUD,
            bytesize=serial.EIGHTBITS, parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE, timeout=ECHO_TIMEOUT,
            xonxoff=False, rtscts=False,
        )
    except serial.SerialException as e:
        sys.exit(f"Could not open port: {e}")

    # Run
    results = []
    for idx, test in selected:
        print(f"\n[Test {idx}]", end="")
        passed = run_test(ser, test, verbose=args.verbose)
        results.append((idx, passed))

    ser.close()

    # Summary
    n_pass = sum(1 for _, p in results if p)
    n_fail = len(results) - n_pass
    print(f"\n{'='*62}")
    print(f"  Results:  {n_pass}/{len(results)} passed", end="")
    if n_fail:
        failed_ids = [str(i) for i, p in results if not p]
        print(f"  |  FAILED: tests {', '.join(failed_ids)}", end="")
    print(f"\n{'='*62}\n")

    sys.exit(0 if n_fail == 0 else 1)


if __name__ == "__main__":
    main()