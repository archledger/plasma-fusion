#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Keyboard and pointer input for a private headless KWin session (test use only).

    fakeinput.py ACTION...

Speaks org_kde_kwin_fake_input on $WAYLAND_DISPLAY. KWin offers that interface only to
programs whose desktop file lists it (X-KDE-Wayland-Interfaces), so the test HOME carries one
for this Python interpreter. Actions, run in order:

    down KEY | up KEY | tap KEY     key by name (alt, tab, shift, meta, z, q, esc, left, ...)
    move X Y                        absolute pointer position
    glide X Y SECONDS               move there in small steps (for drags)
    press [left|right] | release [left|right] | click [left|right]
    sleep SECONDS
"""
import os
import socket
import struct
import sys
import time

KEYS = {
    "esc": 1, "1": 2, "2": 3, "3": 4, "4": 5, "tab": 15, "q": 16, "w": 17, "a": 30, "z": 44,
    "enter": 28, "ctrl": 29, "shift": 42, "grave": 41, "alt": 56, "space": 57, "meta": 125,
    "up": 103, "left": 105, "right": 106, "down": 108, "pageup": 104, "pagedown": 109,
    "e": 18, "h": 35, "l": 38, "n": 49, "o": 24, "s": 31, "t": 20,
}
BUTTONS = {"left": 0x110, "right": 0x111, "middle": 0x112}


class Wayland:
    def __init__(self):
        path = os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0"))
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.next_id = 3  # 1 is wl_display, 2 the registry
        self.buffer = b""
        self.globals = {}

    def new_id(self):
        i = self.next_id
        self.next_id += 1
        return i

    @staticmethod
    def string(s):
        data = s.encode() + b"\0"
        pad = (4 - len(data) % 4) % 4
        return struct.pack("<I", len(data)) + data + b"\0" * pad

    def send(self, obj, opcode, payload=b""):
        size = 8 + len(payload)
        self.sock.sendall(struct.pack("<II", obj, (size << 16) | opcode) + payload)

    def read_events(self, until_callback=None, timeout=5.0):
        deadline = time.time() + timeout
        self.sock.settimeout(0.2)
        while time.time() < deadline:
            try:
                chunk = self.sock.recv(65536)
            except socket.timeout:
                if until_callback is None:
                    return
                continue
            if not chunk:
                raise SystemExit("compositor closed the connection")
            self.buffer += chunk
            while len(self.buffer) >= 8:
                obj, word = struct.unpack("<II", self.buffer[:8])
                size, opcode = word >> 16, word & 0xFFFF
                if len(self.buffer) < size:
                    break
                body, self.buffer = self.buffer[8:size], self.buffer[size:]
                if obj == 1 and opcode == 0:  # wl_display.error
                    oid, code = struct.unpack("<II", body[:8])
                    raise SystemExit(f"wayland error on object {oid}: {code} {body[12:].split(b'\0')[0]!r}")
                if obj == 2 and opcode == 0:  # wl_registry.global
                    name, = struct.unpack("<I", body[:4])
                    length, = struct.unpack("<I", body[4:8])
                    iface = body[8:8 + length - 1].decode()
                    off = 8 + ((length + 3) & ~3)
                    version, = struct.unpack("<I", body[off:off + 4])
                    self.globals[iface] = (name, version)
                if until_callback is not None and obj == until_callback and opcode == 0:
                    return
        if until_callback is not None:
            raise SystemExit("timeout waiting for the compositor")

    def roundtrip(self):
        cb = self.new_id()
        self.send(1, 0, struct.pack("<I", cb))  # wl_display.sync
        self.read_events(until_callback=cb)


def main(actions):
    wl = Wayland()
    wl.send(1, 1, struct.pack("<I", 2))  # wl_display.get_registry -> 2
    wl.roundtrip()
    if "org_kde_kwin_fake_input" not in wl.globals:
        raise SystemExit("org_kde_kwin_fake_input is not offered to this program")
    name, version = wl.globals["org_kde_kwin_fake_input"]
    fake = wl.new_id()
    iface = "org_kde_kwin_fake_input"
    wl.send(2, 0, struct.pack("<I", name) + wl.string(iface) + struct.pack("<II", min(version, 4), fake))
    wl.send(fake, 0, wl.string("plasma-fusion tests") + wl.string("drive a private test session"))
    wl.roundtrip()

    def key(k, state):
        wl.send(fake, 10, struct.pack("<II", KEYS[k.lower()], state))
        wl.roundtrip()

    pos = [0.0, 0.0]
    i = 0
    while i < len(actions):
        a = actions[i]
        if a in ("down", "up", "tap"):
            k = actions[i + 1]
            if a in ("down", "tap"):
                key(k, 1)
            if a == "tap":
                time.sleep(0.05)
            if a in ("up", "tap"):
                key(k, 0)
            i += 2
        elif a == "move":
            pos[0], pos[1] = float(actions[i + 1]), float(actions[i + 2])
            wl.send(fake, 9, struct.pack("<ii", int(pos[0] * 256), int(pos[1] * 256)))
            wl.roundtrip()
            i += 3
        elif a == "glide":
            x, y, seconds = float(actions[i + 1]), float(actions[i + 2]), float(actions[i + 3])
            steps = max(2, int(seconds * 60))
            x0, y0 = pos
            for n in range(1, steps + 1):
                px, py = x0 + (x - x0) * n / steps, y0 + (y - y0) * n / steps
                wl.send(fake, 9, struct.pack("<ii", int(px * 256), int(py * 256)))
                wl.roundtrip()
                time.sleep(seconds / steps)
            pos[0], pos[1] = x, y
            i += 4
        elif a in ("click", "press", "release"):
            button = BUTTONS.get(actions[i + 1]) if i + 1 < len(actions) else None
            step = 2 if button else 1
            button = button or BUTTONS["left"]
            if a in ("click", "press"):
                wl.send(fake, 2, struct.pack("<II", button, 1))
                wl.roundtrip()
            if a == "click":
                time.sleep(0.05)
            if a in ("click", "release"):
                wl.send(fake, 2, struct.pack("<II", button, 0))
                wl.roundtrip()
            i += step
        elif a == "sleep":
            time.sleep(float(actions[i + 1]))
            wl.read_events()
            i += 2
        else:
            raise SystemExit(f"unknown action {a}")
    wl.roundtrip()


if __name__ == "__main__":
    main(sys.argv[1:])
