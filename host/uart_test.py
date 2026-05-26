#!/usr/bin/env python3
"""
uart_test.py  --  Send a digit (0-9) to the Basys 3 UART digit test project.

The FPGA expects a single ASCII character ('0'=0x30 through '9'=0x39) at
57600 baud, 8-N-1, no flow control.  On receipt it displays the digit on
all four seven-segment displays.

Usage
-----
  # One-shot: send the digit 7
  python uart_test.py --port COM3 --digit 7          # Windows
  python uart_test.py --port /dev/ttyUSB1 --digit 7  # Linux / macOS

  # Interactive mode (no --digit flag): type digits at the prompt
  python uart_test.py --port COM3

Common port names
-----------------
  Windows : COM3, COM4, … (check Device Manager → Ports)
  Linux   : /dev/ttyUSB0, /dev/ttyUSB1, /dev/ttyACM0
  macOS   : /dev/cu.usbserial-XXXX

Dependencies
------------
  pip install pyserial
"""

import argparse
import sys

try:
    import serial
except ImportError:
    sys.exit("pyserial is required:  pip install pyserial")


BAUD    = 57600
ECHO_IMEOUT = 1.0   # seconds


def send_and_verify(ser: "serial.Serial", digit: int) -> bool:
    """
    Send one ASCII digit, wait for the echo, and compare.
    Returns True if the echo matches.
    """
    if not 0 <= digit <= 9:
        raise ValueError(f"Digit must be 0-9, got {digit}")

    sent_byte = ord(str(digit))          # e.g. 7 -> 0x37
    ser.write(bytes([sent_byte]))

    echo = ser.read(1)                   # blocks up to ECHO_TIMEOUT seconds
    if not echo:
        print(f"  Sent 0x{sent_byte:02X} ('{chr(sent_byte)}')  →  "
              f"ERROR: no echo received (timeout {ECHO_TIMEOUT}s)")
        return False

    echo_byte = echo[0]
    ok = echo_byte == sent_byte
    status = "OK  ✓" if ok else f"MISMATCH ✗  (got 0x{echo_byte:02X} '{chr(echo_byte) if 32 <= echo_byte < 127 else '?'}')"
    print(f"  Sent 0x{sent_byte:02X} ('{chr(sent_byte)}')  →  "
          f"Echo 0x{echo_byte:02X}  [{status}]")
    return ok


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Send digit 0-9 to Basys 3 UART digit test and verify echo."
    )
    parser.add_argument("--port", "-p", required=True,
                        help="Serial port, e.g. COM3 or /dev/ttyUSB0")
    parser.add_argument("--digit", "-d", type=int, choices=range(10),
                        metavar="0-9",
                        help="Digit to send (omit for interactive mode)")
    args = parser.parse_args()

    print(f"Opening {args.port} at {BAUD} baud (8-N-1) …")
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

    print(f"Port open. Waiting for echo within {ECHO_TIMEOUT}s per byte.\n")

    if args.digit is not None:
        send_and_verify(ser, args.digit)
    else:
        print("Interactive mode — type a digit (0-9) and press Enter.")
        print("The FPGA echo will be printed alongside.\n")
        try:
            while True:
                try:
                    raw = input("  Digit > ").strip()
                except EOFError:
                    break
                if raw.lower() in ("q", "quit", "exit"):
                    break
                if len(raw) != 1 or raw not in "0123456789":
                    print("  ! Please enter a single digit 0-9.")
                    continue
                send_and_verify(ser, int(raw))
        except KeyboardInterrupt:
            print("\nInterrupted.")

    ser.close()
    print("Port closed.")


if __name__ == "__main__":
    main()