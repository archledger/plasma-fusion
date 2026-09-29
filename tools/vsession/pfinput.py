#!/usr/bin/env python3
# Emulated pointer and keyboard input for a private KWin session (tools/vsession), through
# KWin's EIS D-Bus interface (org.kde.KWin.EIS.RemoteDesktop) and libei. Test tool only.
#
#   pfinput.py 'move 100 20' 'click 1300 17' 'key tab' 'key shift+tab' 'scroll 1300 17 -1' 'sleep 0.5'
import ctypes, os, select, sys, time
from gi.repository import Gio, GLib

ei = ctypes.CDLL("libei.so.1")
P = ctypes.c_void_p
ei.ei_new_sender.restype = P; ei.ei_new_sender.argtypes = [P]
ei.ei_configure_name.argtypes = [P, ctypes.c_char_p]
ei.ei_setup_backend_fd.argtypes = [P, ctypes.c_int]; ei.ei_setup_backend_fd.restype = ctypes.c_int
ei.ei_get_fd.argtypes = [P]; ei.ei_get_fd.restype = ctypes.c_int
ei.ei_dispatch.argtypes = [P]
ei.ei_get_event.argtypes = [P]; ei.ei_get_event.restype = P
ei.ei_event_get_type.argtypes = [P]; ei.ei_event_get_type.restype = ctypes.c_int
ei.ei_event_get_seat.argtypes = [P]; ei.ei_event_get_seat.restype = P
ei.ei_event_get_device.argtypes = [P]; ei.ei_event_get_device.restype = P
ei.ei_event_unref.argtypes = [P]; ei.ei_event_unref.restype = P
ei.ei_seat_ref.argtypes = [P]; ei.ei_seat_ref.restype = P
ei.ei_device_ref.argtypes = [P]; ei.ei_device_ref.restype = P
ei.ei_device_has_capability.argtypes = [P, ctypes.c_int]; ei.ei_device_has_capability.restype = ctypes.c_bool
ei.ei_device_start_emulating.argtypes = [P, ctypes.c_uint32]
ei.ei_device_stop_emulating.argtypes = [P]
ei.ei_device_pointer_motion_absolute.argtypes = [P, ctypes.c_double, ctypes.c_double]
ei.ei_device_button_button.argtypes = [P, ctypes.c_uint32, ctypes.c_bool]
ei.ei_device_scroll_discrete.argtypes = [P, ctypes.c_int32, ctypes.c_int32]
ei.ei_device_keyboard_key.argtypes = [P, ctypes.c_uint32, ctypes.c_bool]
ei.ei_device_frame.argtypes = [P, ctypes.c_uint64]
ei.ei_now.argtypes = [P]; ei.ei_now.restype = ctypes.c_uint64

CAP_POINTER, CAP_ABS, CAP_KEYBOARD, CAP_TOUCH, CAP_SCROLL, CAP_BUTTON = 1, 2, 4, 8, 16, 32
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}
KEYS = {"esc": 1, "escape": 1, "tab": 15, "return": 28, "enter": 28, "space": 57, "up": 103,
        "left": 105, "right": 106, "down": 108, "shift": 42, "ctrl": 29, "alt": 56, "meta": 125,
        "pageup": 104, "pagedown": 109, "a": 30, "b": 48}

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
res, fds = bus.call_with_unix_fd_list_sync(
    "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop",
    "connectToEIS", GLib.Variant("(i)", (3,)), GLib.VariantType("(hi)"), Gio.DBusCallFlags.NONE, -1, None, None)
fd = fds.get(res.unpack()[0])

ctx = ei.ei_new_sender(None)
ei.ei_configure_name(ctx, b"pfinput")
if ei.ei_setup_backend_fd(ctx, fd) != 0:
    sys.exit("ei_setup_backend_fd failed")

state = {"abs": None, "kbd": None, "resumed": set()}


def pump(timeout=0.05):
    r, _, _ = select.select([ei.ei_get_fd(ctx)], [], [], timeout)
    ei.ei_dispatch(ctx)
    while True:
        ev = ei.ei_get_event(ctx)
        if not ev:
            break
        t = ei.ei_event_get_type(ev)
        if t == 3:  # seat added
            seat = ei.ei_seat_ref(ei.ei_event_get_seat(ev))
            ei.ei_seat_bind_capabilities.argtypes = [P] + [ctypes.c_int] * 4 + [P]
            ei.ei_seat_bind_capabilities(seat, CAP_ABS, CAP_BUTTON, CAP_SCROLL, CAP_KEYBOARD, None)
        elif t == 5:  # device added
            dev = ei.ei_device_ref(ei.ei_event_get_device(ev))
            if ei.ei_device_has_capability(dev, CAP_ABS):
                state["abs"] = dev
            if ei.ei_device_has_capability(dev, CAP_KEYBOARD):
                state["kbd"] = dev
        elif t == 8:  # resumed
            state["resumed"].add(ei.ei_event_get_device(ev))
        elif t == 2:
            sys.exit("EIS disconnected")
        ei.ei_event_unref(ev)


deadline = time.time() + 5
while time.time() < deadline and not (state["abs"] and state["kbd"] and len(state["resumed"]) >= 2):
    pump()
if not state["abs"]:
    sys.exit("no absolute pointer device")

seq = [1]
emulating = set()


def start(dev):
    if dev not in emulating:
        ei.ei_device_start_emulating(dev, seq[0]); seq[0] += 1
        emulating.add(dev)


def frame(dev):
    ei.ei_device_frame(dev, ei.ei_now(ctx))
    pump(0.01)


pos = [0.0, 0.0]


def move(x, y):
    d = state["abs"]; start(d)
    ei.ei_device_pointer_motion_absolute(d, float(x), float(y)); frame(d)
    pos[:] = [float(x), float(y)]


def button(name, down):
    d = state["abs"]; start(d)
    ei.ei_device_button_button(d, BUTTONS[name], down); frame(d)


def key(combo):
    d = state["kbd"]; start(d)
    parts = combo.lower().split("+")
    codes = [KEYS[p] for p in parts]
    for c in codes:
        ei.ei_device_keyboard_key(d, c, True); frame(d); time.sleep(0.02)
    for c in reversed(codes):
        ei.ei_device_keyboard_key(d, c, False); frame(d); time.sleep(0.02)


for cmd in sys.argv[1:]:
    a = cmd.split()
    if a[0] == "move":
        move(a[1], a[2])
    elif a[0] == "click":
        move(a[1], a[2]); time.sleep(0.08)
        b = a[3] if len(a) > 3 else "left"
        button(b, True); time.sleep(0.06); button(b, False)
    elif a[0] == "down":
        button(a[1] if len(a) > 1 else "left", True)
    elif a[0] == "up":
        button(a[1] if len(a) > 1 else "left", False)
    elif a[0] == "drag":  # drag x1 y1 x2 y2
        move(a[1], a[2]); time.sleep(0.08); button("left", True)
        x1, y1, x2, y2 = map(float, a[1:5])
        for i in range(1, 11):
            move(x1 + (x2 - x1) * i / 10, y1 + (y2 - y1) * i / 10); time.sleep(0.02)
        button("left", False)
    elif a[0] == "scroll":
        move(a[1], a[2]); time.sleep(0.05)
        d = state["abs"]; start(d)
        ei.ei_device_scroll_discrete(d, 0, int(float(a[3]) * 120)); frame(d)
    elif a[0] == "key":
        key(a[1])
    elif a[0] == "sleep":
        t = time.time() + float(a[1])
        while time.time() < t:
            pump(0.05)
    time.sleep(0.05)
    pump(0.01)

for d in list(emulating):
    ei.ei_device_stop_emulating(d)
pump(0.1)
