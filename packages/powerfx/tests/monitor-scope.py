#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check monitor ownership with real processes on two private D-Bus buses."""
import os
from pathlib import Path
import select
import subprocess
import sys
import time

scanner = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name('monitor-pids.py')
processes = []


def start(*args, **kwargs):
    process = subprocess.Popen(args, **kwargs)
    processes.append(process)
    return process


def bus():
    process = start('dbus-daemon', '--session', '--nofork', '--print-address=1',
                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    assert select.select([process.stdout], [], [], 5)[0], 'private bus did not start'
    return process.stdout.readline().strip()


def monitor(address, option='--session'):
    env = dict(os.environ, DBUS_SESSION_BUS_ADDRESS=address, DBUS_SYSTEM_BUS_ADDRESS=address)
    process = start('gdbus', 'monitor', option, '--dest', 'org.kde.plasmashell',
                    '--object-path', '/org/plasmafusion', env=env,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        assert process.poll() is None, 'test monitor exited during startup'
        if Path(f'/proc/{process.pid}/cmdline').read_bytes().split(b'\0')[0].endswith(b'gdbus'):
            return process
        time.sleep(0.01)
    raise AssertionError('monitor did not exec')


def scan(address):
    interpreter = 'bash' if scanner.suffix == '.sh' else sys.executable
    output = subprocess.check_output([interpreter, str(scanner), address], text=True, timeout=10)
    return {int(line) for line in output.splitlines()}


try:
    own_bus, other_bus = bus(), bus()
    own = monitor(own_bus)
    other = monitor(other_bus)
    seen = scan(own_bus)
    assert seen == {own.pid}, f'foreign monitor selected: got {seen}, expected {own.pid}'
    print('PASS a foreign session monitor is excluded')
    system = monitor(own_bus, '--system')
    assert scan(own_bus) == {own.pid, system.pid}, 'included a foreign monitor or missed an owned monitor'
    print('PASS only this test\'s session and system monitors are selected')
    assert scan(other_bus) == {other.pid}, 'independent bus selection failed'
    print('PASS another concurrent session remains independent')
    own.terminate()
    own.wait(timeout=5)
    assert scan(own_bus) == {system.pid}, 'a remaining owned monitor must still fail cleanup'
    print('PASS an owned survivor remains visible')
    system.terminate()
    system.wait(timeout=5)
    assert scan(own_bus) == set(), 'foreign monitor caused a false cleanup failure'
    assert other.poll() is None, 'scanner disturbed the foreign monitor'
    print('PASS cleanup ignores a live foreign monitor without stopping it')
finally:
    for process in reversed(processes):
        if process.poll() is None:
            process.terminate()
        process.wait(timeout=5)
        if process.stdout:
            process.stdout.close()
