#!/usr/bin/env python3
"""
Tang Nano 20K Serial Monitor for VS Code
Auto-detects USB serial device (BL616 / FTDI) and monitors output at 115200 baud.
"""

import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

def find_port():
    if not serial:
        return None
    ports = serial.tools.list_ports.comports()
    for p in ports:
        desc = (p.description or "") + " " + (p.manufacturer or "")
        if any(keyword in desc.lower() for keyword in ["ftdi", "usb serial", "ch34", "cp210", "bl616", "tang"]):
            return p.device
    # Return first non-Bluetooth port if available
    for p in ports:
        if "bluetooth" not in (p.description or "").lower():
            return p.device
    return None

def main():
    if not serial:
        print("[ERROR] pyserial is not installed.")
        print("Please run: pip install pyserial")
        print("Or use the PowerShell monitor: .\\serial_monitor.ps1")
        sys.exit(1)

    port = sys.argv[1] if len(sys.argv) > 1 else find_port()
    baud = int(sys.argv[2]) if len(sys.argv) > 2 else 115200

    if not port:
        print("[ERROR] No USB serial port detected. Please specify port: python serial_monitor.py COMx")
        sys.exit(1)

    print("=" * 60)
    print(f"  VS Code Serial Monitor: TinyQV RV2A03 (Tang Nano 20K)")
    print(f"  Port      : {port}")
    print(f"  Baud Rate : {baud} 8N1")
    print(f"  Exit      : Press Ctrl+C to disconnect")
    print("=" * 60 + "\n")

    try:
        ser = serial.Serial(port, baud, timeout=0.1)
    except Exception as e:
        print(f"[ERROR] Failed to open {port}: {e}")
        sys.exit(1)

    print(f"Connected to {port}. Press S1 on Tang Nano 20K to reset SoC...\n")

    try:
        while True:
            data = ser.read(1024)
            if data:
                sys.stdout.write(data.decode("utf-8", errors="replace"))
                sys.stdout.flush()
            else:
                time.sleep(0.01)
    except KeyboardInterrupt:
        print("\n\n[DISCONNECTED]")
    finally:
        ser.close()

if __name__ == "__main__":
    main()
