#!/usr/bin/env python3
"""Watch the Playdate's USB serial port until a line appears.

    python3 tools/devwatch.py <port> <log> "autobench done" [--timeout 3600]

The autobench and the soak print every line they write to bench.txt and
soak.txt; on the device `print` goes to the USB serial port. This reads the
port in raw mode, with no echo (a plain `cat` on the tty echoed the device's
own output back to it, and the read stalled after 4 KB), appends what it reads
to <log>, and exits 0 once a line contains the text, 1 on timeout, 2 if the
port went away. Mounting the data disk stops the game, so wait with this
instead of mounting to look. Standard library only.
"""
import os
import select
import sys
import termios
import time
import tty


def main():
    args = sys.argv[1:]
    timeout = 3600.0
    if "--timeout" in args:
        i = args.index("--timeout")
        timeout = float(args[i + 1])
        del args[i:i + 2]
    port, log, want = args
    fd = os.open(port, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    attrs[3] &= ~(termios.ECHO | termios.ECHONL)
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    end = time.time() + timeout
    tail = b""
    target = want.encode()
    with open(log, "ab") as out:
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 2.0)
            if not r:
                continue
            try:
                chunk = os.read(fd, 4096)
            except OSError:
                return 2
            if not chunk:
                return 2
            out.write(chunk)
            out.flush()
            tail = (tail + chunk)[-4096:]
            if target in tail:
                return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
