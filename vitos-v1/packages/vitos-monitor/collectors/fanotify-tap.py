#!/usr/bin/env python3
"""fanotify file-access collector — emits events to the VITOS bus."""
import ctypes
import ctypes.util
import json
import os
import socket
import struct
import sys
import time

BUS = "/run/vitos/bus.sock"
WATCH = ["/etc", "/var/lib/vitos", "/home"]

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
FAN_CLASS_NOTIF = 0x00000000
FAN_CLOEXEC = 0x00000001
FAN_NONBLOCK = 0x00000002
FAN_ACCESS = 0x00000001
FAN_OPEN = 0x00000020
FAN_MARK_ADD = 0x00000001
FAN_MARK_FILESYSTEM = 0x00000100
O_RDONLY = 0


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
    fd = libc.fanotify_init(FAN_CLASS_NOTIF | FAN_CLOEXEC, O_RDONLY)
    if fd < 0:
        print("fanotify_init failed (need CAP_SYS_ADMIN)", file=sys.stderr)
        sys.exit(1)
    for path in WATCH:
        if libc.fanotify_mark(fd, FAN_MARK_ADD, FAN_OPEN | FAN_ACCESS,
                              -100, path.encode()) != 0:
            print(f"fanotify_mark failed for {path}", file=sys.stderr)

    HEADER = struct.Struct("IBBHIi")
    while True:
        data = os.read(fd, 4096)
        offset = 0
        while offset + HEADER.size <= len(data):
            event_len, vers, _r, _r2, mask, pid_or_fd = HEADER.unpack_from(data, offset)
            try:
                target = os.readlink(f"/proc/self/fd/{pid_or_fd}")
            except OSError:
                target = "?"
            if pid_or_fd >= 0:
                os.close(pid_or_fd)
            emit({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "type": "file_access",
                "mask": mask,
                "path": target,
            })
            offset += event_len


if __name__ == "__main__":
    main()
