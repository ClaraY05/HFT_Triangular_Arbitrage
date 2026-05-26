#!/usr/bin/env python3
"""
send_digit.py  --  Send a digit (0-9) to the Basys 3 UART digit test project.

The FPGA expects a single ASCII character ('0'=0x30 through '9'=0x39) at
57600 baud, 8-N-1, no flow control.  On receipt it displays the digit on
all four seven-segment displays.

Usage
-----
  # One-shot: send the digit 7
  python send_digit.py --port COM3 --digit 7          # Windows
  python send_digit.py --port /dev/ttyUSB1 --digit 7  # Linux / macOS

  # Interactive mode (no --digit flag): type digits at the prompt
  python send_digit.py --port COM3

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
TIMEOUT = 1.0   # seconds


def send_digit(ser: "serial.Serial", digit: int) -> None:
    """Send one ASCII digit character and print a confirmation line."""
    if not 0 <= digit <= 9:
        raise ValueError(f"Digit must be 0-9, got {digit}")
    char = str(digit).encode("ascii")   # e.g. b'7' = 0x37
    ser.write(char)
    print(f"  Sent: '{chr(char[0])}' (0x{char[0]:02X}) → FPGA should show  [{digit}][{digit}][{digit}][{digit}]")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Send digit 0-9 to Basys 3 UART digit test over UART."
    )
    parser.add_argument(
        "--port", "-p",
        required=True,
        help="Serial port, e.g. COM3 or /dev/ttyUSB0",
    )
    parser.add_argument(
        "--digit", "-d",
        type=int,
        choices=range(10),
        metavar="0-9",
        help="Digit to send (omit for interactive mode)",
    )
    args = parser.parse_args()

    print(f"Opening {args.port} at {BAUD} baud (8-N-1) …")
    try:
        ser = serial.Serial(
            port     = args.port,
            baudrate = BAUD,
            bytesize = serial.EIGHTBITS,
            parity   = serial.PARITY_NONE,
            stopbits = serial.STOPBITS_ONE,
            timeout  = TIMEOUT,
            xonxoff  = False,
            rtscts   = False,
        )
    except serial.SerialException as exc:
        sys.exit(f"Could not open port: {exc}")

    print(f"Port open. FPGA baud: {BAUD}, 8-N-1\n")

    if args.digit is not None:
        # One-shot mode
        send_digit(ser, args.digit)
    else:
        # Interactive mode
        print("Interactive mode — type a digit (0-9) and press Enter.")
        print("Press Ctrl-C or type 'q' to quit.\n")
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

                send_digit(ser, int(raw))

        except KeyboardInterrupt:
            print("\nInterrupted.")

    ser.close()
    print("Port closed. Done.")


if __name__ == "__main__":
    main()
