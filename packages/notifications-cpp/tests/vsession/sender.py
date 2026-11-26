#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#

import json
import os
import signal
import sys
from pathlib import Path

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

request_file = Path(sys.argv[1])
DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
service = "org.freedesktop.Notifications"
path = "/org/freedesktop/Notifications"
notifications = dbus.Interface(bus.get_object(service, path), service)
loop = GLib.MainLoop()
last_request = None


def record(event, **fields):
    print(json.dumps({"event": event, **fields}), flush=True)


def closed(nid, reason):
    record("closed", id=int(nid), reason=int(reason))


def action(nid, key):
    record("action", id=int(nid), key=str(key))


def on_signal(signum, frame):
    record("signal", signum=int(signum))
    os._exit(128 + signum)


def drive():
    global last_request
    if not request_file.exists():
        return GLib.SOURCE_CONTINUE
    request = json.loads(request_file.read_text())
    if request == last_request:
        return GLib.SOURCE_CONTINUE
    last_request = request
    record("request", op=request["op"], label=request.get("label"))
    if request["op"] == "stop":
        loop.quit()
        return GLib.SOURCE_REMOVE
    if request["op"] == "close":
        notifications.CloseNotification(dbus.UInt32(request["id"]), timeout=3)
        record("cleanup", id=request["id"])
    else:
        hints = {}
        # Without a "desktop-entry" hint the stock code gives a notification a default action
        # only when a window of the named application is open.
        if request.get("entry", "org.kde.kwrite"):
            hints["desktop-entry"] = dbus.String(request.get("entry", "org.kde.kwrite"))
        nid = notifications.Notify(
            "Private focus probe",
            dbus.UInt32(request.get("replaces", 0)),
            "",
            "focus-probe/" + request["label"],
            "Synthetic alert for the keyboard-focus probe.",
            dbus.Array(request.get("actions", ["default", "Open"]), signature="s"),
            dbus.Dictionary(hints, signature="sv"),
            dbus.Int32(request.get("timeout", 45000)),
            timeout=3,
        )
        record("sent", label=request["label"], id=int(nid))
    return GLib.SOURCE_CONTINUE


for name in ("SIGTERM", "SIGHUP", "SIGINT", "SIGQUIT"):
    signal.signal(getattr(signal, name), on_signal)
bus.add_signal_receiver(closed, "NotificationClosed", service, bus_name=service, path=path)
bus.add_signal_receiver(action, "ActionInvoked", service, bus_name=service, path=path)
record("ready", pid=os.getpid(), name=bus.get_unique_name())
GLib.timeout_add(100, drive)
try:
    loop.run()
except Exception as error:  # the scenario reads this log to explain a lost sender
    record("error", text=repr(error))
    raise
record("end")
