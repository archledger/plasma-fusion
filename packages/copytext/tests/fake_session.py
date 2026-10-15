#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Stand-ins for the two session services plasma-fusion-copytext calls, for helper-unit.sh on a
private session bus: Klipper's clipboard (org.kde.klipper /klipper setClipboardContents) and the
notification server (org.freedesktop.Notifications Notify). Each call is one JSON line in LOG.

  fake_session.py LOG [--no-klipper]

Prints "ready" once the names are owned; runs until stdin is closed. Requires python3-dbus and
python3-gobject.
"""

import json
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


def record(log, entry):
    with open(log, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry) + "\n")


class Klipper(dbus.service.Object):
    def __init__(self, bus, log):
        self.name = dbus.service.BusName("org.kde.klipper", bus)
        super().__init__(bus, "/klipper")
        self.log = log

    @dbus.service.method("org.kde.klipper.klipper", in_signature="s")
    def setClipboardContents(self, text):
        record(self.log, {"call": "setClipboardContents", "text": str(text)})


class Notifications(dbus.service.Object):
    def __init__(self, bus, log):
        self.name = dbus.service.BusName("org.freedesktop.Notifications", bus)
        super().__init__(bus, "/org/freedesktop/Notifications")
        self.log = log
        self.last = 0

    @dbus.service.method("org.freedesktop.Notifications", in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
        self.last += 1
        record(self.log, {"call": "Notify", "app": str(app), "icon": str(icon), "summary": str(summary),
                          "body": str(body), "actions": [str(a) for a in actions],
                          "hints": {str(k): (bool(v) if isinstance(v, dbus.Boolean) else str(v)) for k, v in hints.items()},
                          "timeout": int(timeout)})
        return dbus.UInt32(self.last)


def main():
    log = sys.argv[1]
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    services = [Notifications(bus, log)]
    if "--no-klipper" not in sys.argv[2:]:
        services.append(Klipper(bus, log))
    loop = GLib.MainLoop()
    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, lambda *_: (loop.quit(), False)[1])
    print("ready", flush=True)
    loop.run()


if __name__ == "__main__":
    main()
