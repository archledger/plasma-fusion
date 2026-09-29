#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drive the pointer of a private headless KWin session and screenshot every cell of a test app.

    eipointer.py CELLS.json OUTDIR PREFIX [--hold MS]

KWin's virtual backend has no pointer device, so it hides the cursor. This script asks KWin for an
emulated-input connection (org.kde.KWin.EIS.RemoteDesktop.connectToEIS, the interface the remote
desktop portal uses), binds an absolute pointer through libei (ctypes, libei.so.1), moves it to
the centre of every cell listed in CELLS.json ({"cells": [{"name", "x", "y"}...]}) and runs
`spectacle -b -n -f -p` (screenshot including the pointer) for each. Writes OUTDIR/PREFIX-NAME.png
and OUTDIR/PREFIX-positions.json (the pointer position of every screenshot).

Only for the private test sessions of tools/vsession; never run it against a real desktop.
"""
import ctypes
import json
import os
import select
import subprocess
import sys
import time

import dbus

EI_EVENT_CONNECT, EI_EVENT_DISCONNECT, EI_EVENT_SEAT_ADDED = 1, 2, 3
EI_EVENT_DEVICE_ADDED, EI_EVENT_DEVICE_REMOVED, EI_EVENT_DEVICE_PAUSED, EI_EVENT_DEVICE_RESUMED = 5, 6, 7, 8
CAP_POINTER, CAP_POINTER_ABSOLUTE, CAP_BUTTON = 1 << 0, 1 << 1, 1 << 5

P = ctypes.c_void_p
lib = ctypes.CDLL('libei.so.1')
for name, res, args in [
    ('ei_new_sender', P, [P]), ('ei_configure_name', None, [P, ctypes.c_char_p]),
    ('ei_setup_backend_fd', ctypes.c_int, [P, ctypes.c_int]), ('ei_get_fd', ctypes.c_int, [P]),
    ('ei_dispatch', None, [P]), ('ei_get_event', P, [P]), ('ei_event_get_type', ctypes.c_int, [P]),
    ('ei_event_get_seat', P, [P]), ('ei_event_get_device', P, [P]), ('ei_event_unref', P, [P]),
    ('ei_device_has_capability', ctypes.c_bool, [P, ctypes.c_int]),
    ('ei_device_start_emulating', None, [P, ctypes.c_uint32]), ('ei_device_stop_emulating', None, [P]),
    ('ei_device_pointer_motion_absolute', None, [P, ctypes.c_double, ctypes.c_double]),
    ('ei_device_frame', None, [P, ctypes.c_uint64]), ('ei_now', ctypes.c_uint64, [P]),
]:
    f = getattr(lib, name)
    f.restype = res
    f.argtypes = args
lib.ei_seat_bind_capabilities.restype = ctypes.c_int  # variadic, 0-terminated


class Pointer:
    def __init__(self):
        kwin = dbus.SessionBus().get_object('org.kde.KWin', '/org/kde/KWin/EIS/RemoteDesktop')
        fd, self.cookie = kwin.connectToEIS(2, dbus_interface='org.kde.KWin.EIS.RemoteDesktop')
        self.ctx = lib.ei_new_sender(None)
        lib.ei_configure_name(self.ctx, b'pfv cursor test')
        if lib.ei_setup_backend_fd(self.ctx, fd.take()) != 0:
            raise SystemExit('libei: setup failed')
        self.device = None
        self.resumed = False
        self.seq = 0
        deadline = time.time() + 10
        while not self.resumed and time.time() < deadline:
            self.pump(0.2)
        if not self.resumed:
            raise SystemExit('libei: no absolute pointer device')
        lib.ei_device_start_emulating(self.device, self.seq)

    def pump(self, timeout):
        select.select([lib.ei_get_fd(self.ctx)], [], [], timeout)
        lib.ei_dispatch(self.ctx)
        while True:
            ev = lib.ei_get_event(self.ctx)
            if not ev:
                break
            t = lib.ei_event_get_type(ev)
            if t == EI_EVENT_SEAT_ADDED:
                lib.ei_seat_bind_capabilities(P(lib.ei_event_get_seat(ev)), ctypes.c_int(CAP_POINTER_ABSOLUTE),
                                              ctypes.c_int(CAP_POINTER), ctypes.c_int(CAP_BUTTON), ctypes.c_int(0))
            elif t == EI_EVENT_DEVICE_ADDED:
                dev = lib.ei_event_get_device(ev)
                if lib.ei_device_has_capability(dev, CAP_POINTER_ABSOLUTE):
                    self.device = dev
            elif t == EI_EVENT_DEVICE_RESUMED and self.device and lib.ei_event_get_device(ev) == self.device:
                self.resumed = True
            elif t == EI_EVENT_DISCONNECT:
                raise SystemExit('libei: disconnected')
            lib.ei_event_unref(ev)

    def move(self, x, y):
        lib.ei_device_pointer_motion_absolute(self.device, float(x), float(y))
        lib.ei_device_frame(self.device, lib.ei_now(self.ctx))
        lib.ei_dispatch(self.ctx)
        self.pump(0.05)


def shoot(path):
    subprocess.run(['spectacle', '-b', '-n', '-f', '-p', '-o', path],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)


def main():
    cells_file, outdir, prefix = sys.argv[1:4]
    hold = int(sys.argv[5]) / 1000 if len(sys.argv) > 5 and sys.argv[4] == '--hold' else 0.35
    for _ in range(100):
        if os.path.exists(cells_file):
            break
        time.sleep(0.2)
    cells = json.load(open(cells_file))['cells']
    ptr = Pointer()
    positions = {}
    # a small approach move first so the compositor sees motion into every cell
    for c in cells:
        ptr.move(c['x'] - 6, c['y'] - 6)
        time.sleep(0.05)
        ptr.move(c['x'], c['y'])
        time.sleep(hold)
        shoot(os.path.join(outdir, f"{prefix}-{c['name']}.png"))
        positions[c['name']] = [c['x'], c['y']]
    json.dump(positions, open(os.path.join(outdir, f'{prefix}-positions.json'), 'w'), indent=1)
    lib.ei_device_stop_emulating(ptr.device)
    lib.ei_dispatch(ptr.ctx)


if __name__ == '__main__':
    main()
