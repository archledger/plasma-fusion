#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""List gdbus monitors belonging to one test's private session bus."""
import os
from pathlib import Path
import sys


def monitor_pids(address, proc_root=Path('/proc')):
    scope = b'DBUS_SESSION_BUS_ADDRESS=' + address.encode()
    result = []
    for proc in proc_root.iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.geteuid():
                continue
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            if len(args) < 2 or args[0].rsplit(b'/', 1)[-1] != b'gdbus' or args[1] != b'monitor':
                continue
            if scope in (proc / 'environ').read_bytes().split(b'\0'):
                result.append(int(proc.name))
        except OSError:
            # A process may end during the scan. Every other read failure is an
            # indeterminate scan, never evidence that cleanup succeeded.
            try:
                proc.stat()
            except FileNotFoundError:
                continue
            raise
    return sorted(result)


if __name__ == '__main__':
    if len(sys.argv) != 2 or not sys.argv[1]:
        raise SystemExit('usage: monitor-pids.py PRIVATE_SESSION_BUS_ADDRESS')
    for pid in monitor_pids(sys.argv[1]):
        print(pid)
