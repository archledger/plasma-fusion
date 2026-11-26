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


def replied(nid, text):
    # KDE's server sends a reply to the application as a signal addressed to it alone.
    record("replied", id=int(nid), text=str(text))


job_views = {}


def start_job(request):
    # A job is not a notification on the bus: the applet serves org.kde.JobViewServer itself when
    # jobs show in notifications (the default), and KIO asks it for a view and updates that. The
    # view of the first interface takes a name, an icon and a number; the later ones take hints.
    label = request["label"]
    server = dbus.Interface(bus.get_object("org.kde.JobViewServer", "/JobViewServer", introspect=False), "org.kde.JobViewServer")
    path = server.requestView(dbus.String("Private focus probe"), dbus.String("dialog-information"), dbus.Int32(0))
    view = dbus.Interface(bus.get_object("org.kde.JobViewServer", str(path), introspect=False), "org.kde.JobViewV3")
    view.update(
        dbus.Dictionary(
            {
                "title": dbus.String("focus-probe/" + label),
                "infoMessage": dbus.String("Synthetic job for the keyboard-focus probe."),
                "percent": dbus.Int32(50),
            },
            signature="sv",
        )
    )
    job_views[label] = view
    record("job", label=label, path=str(path))


def end_job(request):
    view = job_views.pop(request["label"], None)
    if view is None:
        raise KeyError("no such job: " + request["label"])
    view.terminate(dbus.UInt32(0), dbus.String(""), dbus.Dictionary({}, signature="sv"))
    record("job-ended", label=request["label"])


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
    handle(request)
    return GLib.SOURCE_CONTINUE


def handle(request):
    """Does one request. An error is recorded and the sender serves on, so that the scenario's
    later requests (stop among them) are still read."""
    if request["op"] == "stop":
        loop.quit()
        return
    try:
        if request["op"] == "close":
            notifications.CloseNotification(dbus.UInt32(request["id"]), timeout=3)
            record("cleanup", id=request["id"])
        elif request["op"] == "job":
            start_job(request)
        elif request["op"] == "job-end":
            end_job(request)
        else:
            hints = {}
            # Without a "desktop-entry" hint the stock code gives a notification a default action
            # only when a window of the named application is open.
            if request.get("entry", "org.kde.kwrite"):
                hints["desktop-entry"] = dbus.String(request.get("entry", "org.kde.kwrite"))
            # The spec's other shapes: urgency 2 is critical, "resident" never expires.
            for name, value in request.get("hints", {}).items():
                if isinstance(value, bool):
                    hints[name] = dbus.Boolean(value)
                elif isinstance(value, int):
                    hints[name] = dbus.Byte(value)  # urgency is a byte on the bus
                else:
                    hints[name] = dbus.String(value)
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
    except Exception as error:
        record("error", op=request["op"], text=repr(error))


for name in ("SIGTERM", "SIGHUP", "SIGINT", "SIGQUIT"):
    signal.signal(getattr(signal, name), on_signal)
bus.add_signal_receiver(closed, "NotificationClosed", service, bus_name=service, path=path)
bus.add_signal_receiver(action, "ActionInvoked", service, bus_name=service, path=path)
bus.add_signal_receiver(replied, "NotificationReplied", service, bus_name=service, path=path)
record("ready", pid=os.getpid(), name=bus.get_unique_name())
GLib.timeout_add(100, drive)
try:
    loop.run()
except Exception as error:  # the scenario reads this log to explain a lost sender
    record("error", text=repr(error))
    raise
record("end")
