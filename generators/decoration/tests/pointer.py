#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): move the pointer of a (virtual) KWin session.

    pointer.py X Y [press SECONDS]

Asks KWin for an emulated-input connection (org.kde.KWin.EIS.RemoteDesktop.connectToEIS, the
call xdg-desktop-portal-kde uses for remote desktop) and sends one absolute pointer motion to
X, Y (logical pixels) through libei. With "press SECONDS" the left button is then held for that
long, the pointer moves 200 px down and the button is released there (a press on a title-bar
button that is released outside it does not click). Only for private test sessions: the pointer
stays where it was moved when the script exits.
"""
import ctypes
import select
import sys
import time

from gi.repository import Gio, GLib

EI_EVENT_SEAT_ADDED = 3
EI_EVENT_DEVICE_ADDED = 5
EI_EVENT_DEVICE_RESUMED = 8
EI_EVENT_DISCONNECT = 2
EI_DEVICE_CAP_POINTER_ABSOLUTE = 1 << 1
PORTAL_POINTER = 2
EI_DEVICE_CAP_BUTTON = 1 << 5
BTN_LEFT = 0x110


def main():
    x, y = float(sys.argv[1]), float(sys.argv[2])
    hold = float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[3] == "press" else None
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    res, fds = bus.call_with_unix_fd_list_sync(
        "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop",
        "connectToEIS", GLib.Variant("(i)", (PORTAL_POINTER,)), GLib.VariantType("(hi)"),
        Gio.DBusCallFlags.NONE, 5000, None, None)
    handle, _cookie = res.unpack()
    fd = fds.get(handle)

    ei = ctypes.CDLL("libei.so.1")
    ei.ei_new_sender.restype = ctypes.c_void_p
    ei.ei_new_sender.argtypes = [ctypes.c_void_p]
    ei.ei_configure_name.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    ei.ei_setup_backend_fd.argtypes = [ctypes.c_void_p, ctypes.c_int]
    ei.ei_get_fd.argtypes = [ctypes.c_void_p]
    ei.ei_dispatch.argtypes = [ctypes.c_void_p]
    ei.ei_get_event.restype = ctypes.c_void_p
    ei.ei_get_event.argtypes = [ctypes.c_void_p]
    ei.ei_event_get_type.argtypes = [ctypes.c_void_p]
    ei.ei_event_get_seat.restype = ctypes.c_void_p
    ei.ei_event_get_seat.argtypes = [ctypes.c_void_p]
    ei.ei_event_get_device.restype = ctypes.c_void_p
    ei.ei_event_get_device.argtypes = [ctypes.c_void_p]
    ei.ei_event_unref.restype = ctypes.c_void_p
    ei.ei_event_unref.argtypes = [ctypes.c_void_p]
    ei.ei_device_has_capability.restype = ctypes.c_bool
    ei.ei_device_has_capability.argtypes = [ctypes.c_void_p, ctypes.c_int]
    ei.ei_device_start_emulating.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
    ei.ei_device_stop_emulating.argtypes = [ctypes.c_void_p]
    ei.ei_device_pointer_motion_absolute.argtypes = [ctypes.c_void_p, ctypes.c_double, ctypes.c_double]
    ei.ei_device_frame.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
    ei.ei_now.restype = ctypes.c_uint64
    ei.ei_now.argtypes = [ctypes.c_void_p]
    ei.ei_device_button_button.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_bool]

    def frame(dev, action):
        action()
        ei.ei_device_frame(dev, ei.ei_now(ctx))
        ei.ei_dispatch(ctx)

    ctx = ei.ei_new_sender(None)
    ei.ei_configure_name(ctx, b"pf-test-pointer")
    if ei.ei_setup_backend_fd(ctx, fd) != 0:
        sys.exit("ei_setup_backend_fd failed")
    efd = ei.ei_get_fd(ctx)
    done_at = None
    deadline = time.time() + 5
    while time.time() < deadline:
        if done_at and time.time() - done_at > 0.3:
            return 0
        select.select([efd], [], [], 0.1)
        ei.ei_dispatch(ctx)
        while True:
            ev = ei.ei_get_event(ctx)
            if not ev:
                break
            t = ei.ei_event_get_type(ev)
            if t == EI_EVENT_SEAT_ADDED:
                seat = ei.ei_event_get_seat(ev)
                ei.ei_seat_bind_capabilities(ctypes.c_void_p(seat), ctypes.c_int(EI_DEVICE_CAP_POINTER_ABSOLUTE),
                                             ctypes.c_int(EI_DEVICE_CAP_BUTTON), ctypes.c_void_p(None))
            elif t == EI_EVENT_DEVICE_RESUMED and done_at is None:
                dev = ei.ei_event_get_device(ev)
                if ei.ei_device_has_capability(dev, EI_DEVICE_CAP_POINTER_ABSOLUTE):
                    # one emulation sequence: KWin releases held buttons when emulation stops
                    ei.ei_device_start_emulating(dev, 1)
                    frame(dev, lambda: ei.ei_device_pointer_motion_absolute(dev, x, y))
                    if hold is not None and ei.ei_device_has_capability(dev, EI_DEVICE_CAP_BUTTON):
                        time.sleep(0.2)
                        frame(dev, lambda: ei.ei_device_button_button(dev, BTN_LEFT, True))
                        time.sleep(hold)
                        frame(dev, lambda: ei.ei_device_pointer_motion_absolute(dev, x, y + 200))
                        time.sleep(0.2)
                        frame(dev, lambda: ei.ei_device_button_button(dev, BTN_LEFT, False))
                    ei.ei_device_stop_emulating(dev)
                    ei.ei_dispatch(ctx)
                    done_at = time.time()
            elif t == EI_EVENT_DISCONNECT:
                sys.exit("disconnected by the compositor")
            ei.ei_event_unref(ev)
    sys.exit("timed out" if done_at is None else 0)


if __name__ == "__main__":
    sys.exit(main())
