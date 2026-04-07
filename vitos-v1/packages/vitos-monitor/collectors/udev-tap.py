#!/usr/bin/env python3
"""USB / udev event collector — emits events to the VITOS bus."""
import json
import socket
import subprocess
import time

BUS = "/run/vitos/bus.sock"


def emit(ev):
    line = (json.dumps(ev) + "\n").encode()
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(BUS)
        s.sendall(line)
        s.close()
    except OSError:
        pass


def main():
    p = subprocess.Popen(
        ["udevadm", "monitor", "--udev", "--subsystem-match=usb"],
        stdout=subprocess.PIPE,
        text=True,
    )
    cur = {}
    for line in p.stdout:
        line = line.strip()
        if line.startswith("UDEV"):
            if cur:
                emit({
                    "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "type": "usb_event",
                    **cur,
                })
                cur = {}
            parts = line.split()
            if len(parts) >= 4:
                cur["action"] = parts[2]
                cur["devpath"] = parts[3]
        elif "=" in line:
            k, _, v = line.partition("=")
            cur[k.strip()] = v.strip()


if __name__ == "__main__":
    main()
