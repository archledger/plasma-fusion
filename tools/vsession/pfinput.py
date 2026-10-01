#!/usr/bin/env python3
# Emulated pointer and keyboard input for a private KWin session (tools/vsession), through
# KWin's EIS D-Bus interface (org.kde.KWin.EIS.RemoteDesktop) and libei. Test tool only.
#
#   pfinput.py 'move 100 20' 'click 1300 17' 'key tab' 'key shift+tab' 'scroll 1300 17 -1' 'sleep 0.5'
#
# Commands (coordinates in logical px of the whole virtual screen):
#   move X Y                       absolute pointer motion
#   click X Y [left|right|middle]  move, press, release
#   down [BUTTON] / up [BUTTON]    press / release a pointer button
#   drag X1 Y1 X2 Y2 [STEPS [STEP_S [PRESS_HOLD_S [DROP_HOLD_S]]]]
#                                  press at X1 Y1, move in STEPS steps (default 10, STEP_S 0.02 s
#                                  apart), release at X2 Y2; the optional holds wait after the press
#                                  and before the release (default 0; slow drags for drag-and-drop)
#   scroll X Y STEPS               wheel steps at X Y (negative: up)
#   key COMBO                      press and release, e.g. key meta, key ctrl+alt+t, key alt+f4
#   keydown KEY / keyup KEY        hold / release one key (e.g. Alt for a held Alt+Tab). Every key
#                                  still held when the command list ends is released before exit:
#                                  KWin 6.7.5 crashes when an EIS client exits holding a key.
#                                  A pointer button pressed with 'down' is released when this
#                                  client exits: to hold it across a screenshot, run the call in
#                                  the background (pfinput 'down' 'sleep 2' 'up' & shot x; wait).
#   tap X Y [HOLD_S]               one-finger touch tap (HOLD_S default 0.08; 0.8 = long press)
#   hold X Y [HOLD_S]              one-finger long press (HOLD_S default 0.8)
#   swipe X1 Y1 X2 Y2 [SECONDS]    one-finger touch swipe in 10 steps (default 0.2 s)
#   hswipe X1 Y1 X2 Y2 HOLD_S      one-finger swipe in 20 steps 16 ms apart, then held HOLD_S
#                                  before lifting (edge swipes that must not fling)
#   mswipe N X Y DX DY [STEPS [STEP_S]]
#                                  N fingers 30 px apart from X Y, moved together by DX DY in
#                                  STEPS steps (default 15) STEP_S apart (default 0.016). Virtual
#                                  outputs report no physical size, so KWin's touchscreen gestures
#                                  do not recognise it; apps and Plasma still get the touch points.
#   type TEXT                      press and release each character: letters (typed lower-case),
#                                  digits, spaces and - = [ ] ; ' ` \ , . /
#   sweep X1 X2 Y SECONDS          pointer back and forth between X1 and X2 at height Y, 2 s per
#                                  direction, at most one motion every 8 ms; each motion also waits
#                                  up to 10 ms for KWin's events, so about 98 motions/s in practice
#                                  (the rate of the perf-measure study; the count is marked)
#   mark LABEL                     append {"mark", "epoch", "mono"} to $PFINPUT_MARKS (default
#                                  $PFPERF_MARKS, then marks.jsonl in $OUT or $PFV/out; never in
#                                  the working directory, which is the host user's HOME by default)
#   sleep SECONDS
# Touch is requested from KWin only when a touch command is given, or with PFINPUT_TOUCH=1.
# PFINPUT_WAIT (seconds, default 5): how long to wait for KWin's input devices at the start; the
# client goes on with what it has after that and logs which device was missing.
# In a lock-capable session (PFV_LOCK=1) the client refuses Return, Enter and 'type' while the
# screen is locked: a password typed there would be checked against the host user (pam_faillock).
import ctypes, json, os, select, sys, time
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
ei.ei_device_touch_new.argtypes = [P]; ei.ei_device_touch_new.restype = P
ei.ei_touch_down.argtypes = [P, ctypes.c_double, ctypes.c_double]
ei.ei_touch_motion.argtypes = [P, ctypes.c_double, ctypes.c_double]
ei.ei_touch_up.argtypes = [P]
ei.ei_touch_unref.argtypes = [P]; ei.ei_touch_unref.restype = P

CAP_POINTER, CAP_ABS, CAP_KEYBOARD, CAP_TOUCH, CAP_SCROLL, CAP_BUTTON = 1, 2, 4, 8, 16, 32
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}
KEYS = {"esc": 1, "escape": 1, "tab": 15, "return": 28, "enter": 28, "space": 57, "up": 103,
        "left": 105, "right": 106, "down": 108, "shift": 42, "ctrl": 29, "alt": 56, "meta": 125,
        "pageup": 104, "pagedown": 109, "a": 30, "b": 48}
# More keys (linux/input-event-codes.h); the names above keep their codes.
for _i, _c in enumerate("qwertyuiop"):
    KEYS[_c] = 16 + _i
for _i, _c in enumerate("asdfghjkl"):
    KEYS[_c] = 30 + _i
for _i, _c in enumerate("zxcvbnm"):
    KEYS[_c] = 44 + _i
for _i, _c in enumerate("1234567890"):
    KEYS[_c] = 2 + _i
for _i in range(1, 11):
    KEYS["f%d" % _i] = 58 + _i
KEYS.update({"f11": 87, "f12": 88, "minus": 12, "equal": 13, "backspace": 14, "leftbrace": 26,
             "rightbrace": 27, "semicolon": 39, "apostrophe": 40, "grave": 41, "backslash": 43,
             "comma": 51, "period": 52, "dot": 52, "slash": 53, "capslock": 58, "rightshift": 54,
             "rightctrl": 97, "rightalt": 100, "altgr": 100, "print": 99, "sysrq": 99, "home": 102,
             "end": 107, "insert": 110, "delete": 111, "del": 111, "super": 125, "rightmeta": 126,
             "menu": 127, "mute": 113, "volumedown": 114, "volumeup": 115})

ARGS = sys.argv[1:]
TOUCH_CMDS = (["tap"], ["hold"], ["swipe"], ["hswipe"], ["hdrag"], ["mswipe"])
WANT_TOUCH = os.environ.get("PFINPUT_TOUCH") == "1" or any(c.split()[:1] in TOUCH_CMDS for c in ARGS)
CHARS = {"-": "minus", "=": "equal", "[": "leftbrace", "]": "rightbrace", ";": "semicolon", "'": "apostrophe",
         "`": "grave", "\\": "backslash", ",": "comma", ".": "period", "/": "slash"}
# Key names of keydown/keyup are checked before anything is sent: an unknown name must not end
# the client while another key is held.
for _cmd in ARGS:
    _a = _cmd.split()
    if _a[:1] in (["keydown"], ["keyup"]) and (len(_a) < 2 or _a[1].lower() not in KEYS):
        sys.exit("unknown key in '%s'" % _cmd)
    if _a[:1] == ["type"] and any(ch.lower() not in KEYS and ch not in CHARS for ch in "".join(_a[1:])):
        sys.exit("cannot type '%s' (letters, digits and - = [ ] ; ' ` \\ , . / only)" % _cmd)

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

# Lock-capable sessions: nothing that could submit a password while the screen is locked.
SUBMITS = ("return", "enter")
if os.environ.get("PFV_LOCK") == "1" and any(
        c.split()[:1] == ["type"] or (c.split()[:1] in (["key"], ["keydown"]) and len(c.split()) > 1
                                     and any(k in SUBMITS for k in c.split()[1].lower().split("+")))
        for c in ARGS):
    try:
        _act = bus.call_sync("org.freedesktop.ScreenSaver", "/ScreenSaver", "org.freedesktop.ScreenSaver",
                             "GetActive", None, GLib.VariantType("(b)"), Gio.DBusCallFlags.NONE, 2000,
                             None).unpack()[0]
    except GLib.Error:
        _act = False
    if _act:
        sys.exit("the screen is locked: refusing Return, Enter and 'type' (never enter a password here)")
res, fds = bus.call_with_unix_fd_list_sync(
    "org.kde.KWin", "/org/kde/KWin/EIS/RemoteDesktop", "org.kde.KWin.EIS.RemoteDesktop",
    "connectToEIS", GLib.Variant("(i)", (7 if WANT_TOUCH else 3,)), GLib.VariantType("(hi)"),
    Gio.DBusCallFlags.NONE, -1, None, None)
fd = fds.get(res.unpack()[0])

ctx = ei.ei_new_sender(None)
ei.ei_configure_name(ctx, b"pfinput")
if ei.ei_setup_backend_fd(ctx, fd) != 0:
    sys.exit("ei_setup_backend_fd failed")

state = {"abs": None, "kbd": None, "touch": None, "resumed": set()}


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
            if WANT_TOUCH:
                ei.ei_seat_bind_capabilities.argtypes = [P] + [ctypes.c_int] * 5 + [P]
                ei.ei_seat_bind_capabilities(seat, CAP_ABS, CAP_BUTTON, CAP_SCROLL, CAP_KEYBOARD, CAP_TOUCH, None)
            else:
                ei.ei_seat_bind_capabilities.argtypes = [P] + [ctypes.c_int] * 4 + [P]
                ei.ei_seat_bind_capabilities(seat, CAP_ABS, CAP_BUTTON, CAP_SCROLL, CAP_KEYBOARD, None)
        elif t == 5:  # device added
            dev = ei.ei_device_ref(ei.ei_event_get_device(ev))
            if ei.ei_device_has_capability(dev, CAP_ABS):
                state["abs"] = dev
            if ei.ei_device_has_capability(dev, CAP_KEYBOARD):
                state["kbd"] = dev
            if WANT_TOUCH and ei.ei_device_has_capability(dev, CAP_TOUCH):
                state["touch"] = dev
        elif t == 8:  # resumed
            state["resumed"].add(ei.ei_event_get_device(ev))
        elif t == 2:
            sys.exit("EIS disconnected")
        ei.ei_event_unref(ev)


def ready():
    if not WANT_TOUCH:
        return state["abs"] and state["kbd"] and len(state["resumed"]) >= 2
    # KWin puts touch on the absolute device: count distinct devices
    devs = {d for d in (state["abs"], state["kbd"], state["touch"]) if d}
    return state["abs"] and state["kbd"] and state["touch"] and len(state["resumed"]) >= len(devs)


_wait = float(os.environ.get("PFINPUT_WAIT") or 5)
_t0 = time.time()
deadline = _t0 + _wait
while time.time() < deadline and not ready():
    pump()
if not ready():
    print("devices not all ready after %.1f s (pointer %s, keyboard %s, touch %s, resumed %d); going on" % (
        time.time() - _t0, bool(state["abs"]), bool(state["kbd"]), bool(state["touch"]), len(state["resumed"])),
        file=sys.stderr)
if not state["abs"]:
    sys.exit("no absolute pointer device")

seq = [1]
emulating = set()
held = []


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


def hold(seconds):
    t = time.time() + seconds
    while time.time() < t:
        pump(0.05)


def mark(label):
    path = os.environ.get("PFINPUT_MARKS") or os.environ.get("PFPERF_MARKS")
    if not path:
        out = os.environ.get("OUT") or (os.path.join(os.environ["PFV"], "out") if os.environ.get("PFV") else "")
        if not out or not os.path.isdir(out):
            print("mark %s: no PFINPUT_MARKS, OUT or PFV; not written" % label, file=sys.stderr)
            return
        path = os.path.join(out, "marks.jsonl")
    with open(path, "a") as f:
        f.write(json.dumps({"mark": label, "epoch": time.time(), "mono": time.monotonic()}) + "\n")


def touch(points, hold_s):
    d = state["touch"]
    if not d:
        print("no touch device", file=sys.stderr)
        return
    start(d)
    t = ei.ei_device_touch_new(d)
    ei.ei_touch_down(t, float(points[0][0]), float(points[0][1])); frame(d)
    for x, y in points[1:]:
        time.sleep(hold_s / max(1, len(points) - 1))
        ei.ei_touch_motion(t, float(x), float(y)); frame(d)
    if len(points) == 1:
        time.sleep(hold_s)
    ei.ei_touch_up(t); frame(d)
    ei.ei_touch_unref(t)


def fingers(n, x, y, dx, dy, steps, step_s):
    d = state["touch"]
    if not d:
        print("no touch device", file=sys.stderr)
        return
    start(d)
    pts = []
    for i in range(n):
        t = ei.ei_device_touch_new(d)
        ei.ei_touch_down(t, x + i * 30.0, y)
        pts.append((t, x + i * 30.0, y))
    frame(d)
    for k in range(1, steps + 1):
        for t, px, py in pts:
            ei.ei_touch_motion(t, px + dx * k / steps, py + dy * k / steps)
        frame(d); time.sleep(step_s)
    for t, _, _ in pts:
        ei.ei_touch_up(t)
    frame(d)
    for t, _, _ in pts:
        ei.ei_touch_unref(t)


def release_held():
    d = state["kbd"]
    while held:
        c = held.pop()
        print("releasing held key %d" % c, file=sys.stderr)
        ei.ei_device_keyboard_key(d, c, False); frame(d); time.sleep(0.02)


try:
    for cmd in ARGS:
        a = cmd.split()
        if a[0] == "move":
            move(a[1], a[2])
        elif a[0] == "click":
            move(a[1], a[2]); time.sleep(0.08)
            b = a[3] if len(a) > 3 else "left"
            button(b, True); time.sleep(0.06); button(b, False)
        elif a[0] == "down":
            button(a[1] if len(a) > 1 else "left", True)
            if not any(c.split()[:1] == ["up"] for c in ARGS):
                print("'down' without 'up' in this call: the button is released when this client exits",
                      file=sys.stderr)
        elif a[0] == "up":
            button(a[1] if len(a) > 1 else "left", False)
        elif a[0] == "drag":  # drag x1 y1 x2 y2 [steps [step_s [press_hold_s [drop_hold_s]]]]
            steps = int(a[5]) if len(a) > 5 else 10
            step_s = float(a[6]) if len(a) > 6 else 0.02
            move(a[1], a[2]); time.sleep(0.08); button("left", True)
            if len(a) > 7:
                hold(float(a[7]))
            x1, y1, x2, y2 = map(float, a[1:5])
            for i in range(1, steps + 1):
                move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
                if len(a) > 6:
                    hold(step_s)
                else:
                    time.sleep(step_s)
            if len(a) > 8:
                hold(float(a[8]))
            button("left", False)
        elif a[0] == "scroll":
            move(a[1], a[2]); time.sleep(0.05)
            d = state["abs"]; start(d)
            ei.ei_device_scroll_discrete(d, 0, int(float(a[3]) * 120)); frame(d)
        elif a[0] == "key":
            key(a[1])
        elif a[0] in ("keydown", "keyup"):
            d = state["kbd"]; start(d)
            c = KEYS[a[1].lower()]
            if a[0] == "keydown":
                ei.ei_device_keyboard_key(d, c, True); frame(d)
                held.append(c)
            else:
                ei.ei_device_keyboard_key(d, c, False); frame(d)
                if c in held:
                    held.remove(c)
        elif a[0] == "tap":
            touch([(a[1], a[2])], float(a[3]) if len(a) > 3 else 0.08)
        elif a[0] == "hold":
            touch([(a[1], a[2])], float(a[3]) if len(a) > 3 else 0.8)
        elif a[0] == "hswipe":
            x1, y1, x2, y2, hs = map(float, a[1:6])
            d = state["touch"]
            if not d:
                print("no touch device", file=sys.stderr)
            else:
                start(d)
                t = ei.ei_device_touch_new(d)
                ei.ei_touch_down(t, x1, y1); frame(d)
                for i in range(1, 21):
                    ei.ei_touch_motion(t, x1 + (x2 - x1) * i / 20, y1 + (y2 - y1) * i / 20); frame(d)
                    time.sleep(0.016)
                hold(hs)
                ei.ei_touch_up(t); frame(d)
                ei.ei_touch_unref(t)
        elif a[0] == "hdrag":
            # touch down, hold still PRE s, move to x2,y2 in 20 steps, hold POST s, up (a drag that
            # starts with a long press, e.g. a dock icon lifted for a split)
            x1, y1, x2, y2, pre, post = map(float, a[1:7])
            d = state["touch"]
            if not d:
                print("no touch device", file=sys.stderr)
            else:
                start(d)
                t = ei.ei_device_touch_new(d)
                ei.ei_touch_down(t, x1, y1); frame(d)
                hold(pre)
                for i in range(1, 21):
                    ei.ei_touch_motion(t, x1 + (x2 - x1) * i / 20, y1 + (y2 - y1) * i / 20); frame(d)
                    time.sleep(0.02)
                hold(post)
                ei.ei_touch_up(t); frame(d)
                ei.ei_touch_unref(t)
        elif a[0] == "mswipe":
            fingers(int(a[1]), float(a[2]), float(a[3]), float(a[4]), float(a[5]),
                    int(a[6]) if len(a) > 6 else 15, float(a[7]) if len(a) > 7 else 0.016)
        elif a[0] == "type":
            for ch in " ".join(a[1:]):
                key("space" if ch == " " else CHARS.get(ch, ch.lower()))
        elif a[0] == "swipe":
            x1, y1, x2, y2 = map(float, a[1:5])
            touch([(x1 + (x2 - x1) * i / 10, y1 + (y2 - y1) * i / 10) for i in range(11)],
                  float(a[5]) if len(a) > 5 else 0.2)
        elif a[0] == "sweep":
            x1, x2, y, secs = float(a[1]), float(a[2]), float(a[3]), float(a[4])
            t0 = time.monotonic(); n = 0
            while time.monotonic() - t0 < secs:
                ph = ((time.monotonic() - t0) / 2.0) % 2.0
                move(x1 + (x2 - x1) * (ph if ph <= 1 else 2 - ph), y); n += 1
                nxt = t0 + n * 0.008
                while time.monotonic() < nxt:
                    pump(max(0.0, nxt - time.monotonic()))
            mark("sweep-events-%d" % n)
        elif a[0] == "mark":
            mark(a[1])
            continue
        elif a[0] == "sleep":
            t = time.time() + float(a[1])
            while time.time() < t:
                pump(0.05)
        else:
            print("unknown command '%s'" % cmd, file=sys.stderr)
        time.sleep(0.05)
        pump(0.01)
finally:
    if held:
        release_held()

for d in list(emulating):
    ei.ei_device_stop_emulating(d)
pump(0.1)
