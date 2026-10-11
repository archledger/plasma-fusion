#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A small notification client for the notification tests (the service test and the VM checks).

  notify_client.py notify SUMMARY BODY [--app NAME] [--entry DESKTOP_ENTRY] [--icon ICON]
                   [--image PATH] [--url URL] [--action ID=LABEL]... [--reply LABEL] [--resident]
      Sends one notification and stays to print what the user does with it, one line each:
      "id N", "action ID", "reply TEXT", "closed REASON"; it exits when the notification is closed
      or stdin is closed. --reply adds an inline reply ("inline-reply" action, x-kde-reply-* hints).
  notify_client.py inhibit DESKTOP_ENTRY REASON
      Holds Do Not Disturb for the application, prints "inhibited", until stdin is closed.

Requires python3-dbus and python3-gobject (the GLib main loop for the signals).
"""

import argparse
import sys

import dbus
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    notify = sub.add_parser("notify")
    notify.add_argument("summary")
    notify.add_argument("body")
    notify.add_argument("--app", default="Notify client")
    notify.add_argument("--entry", default="")
    notify.add_argument("--icon", default="")
    notify.add_argument("--image", default="")
    notify.add_argument("--url", action="append", default=[])
    notify.add_argument("--action", action="append", default=[])
    notify.add_argument("--reply", default=None)
    notify.add_argument("--resident", action="store_true")
    inhibit = sub.add_parser("inhibit")
    inhibit.add_argument("entry")
    inhibit.add_argument("reason")
    args = parser.parse_args()

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    server = dbus.Interface(bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications"),
                            "org.freedesktop.Notifications")
    loop = GLib.MainLoop()

    def say(line):
        print(line, flush=True)

    # Quit when stdin is closed (the test or the person driving it is done).
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_IN, lambda *a: (loop.quit(), False)[1])

    if args.command == "inhibit":
        cookie = server.Inhibit(args.entry, args.reason, dbus.Dictionary({}, signature="sv"))
        say("inhibited")
        loop.run()
        server.UnInhibit(cookie)
        return

    actions = []
    for item in args.action:
        key, _, label = item.partition("=")
        actions += [key, label or key]
    hints = {}
    if args.entry:
        hints["desktop-entry"] = dbus.String(args.entry)
    if args.image:
        hints["image-path"] = dbus.String(args.image)
    if args.url:
        hints["x-kde-urls"] = dbus.Array(args.url, signature="s")
    if args.resident:
        hints["resident"] = dbus.Boolean(True)
    if args.reply is not None:
        actions += ["inline-reply", args.reply]
        hints["x-kde-reply-placeholder-text"] = dbus.String("Reply to the test…")
    state = {"id": 0}

    def on_action(nid, key):
        if nid == state["id"]:
            say("action " + key)

    def on_reply(nid, text):
        if nid == state["id"]:
            say("reply " + text)

    def on_closed(nid, reason):
        if nid == state["id"]:
            say("closed %d" % reason)
            loop.quit()

    bus.add_signal_receiver(on_action, "ActionInvoked", "org.freedesktop.Notifications")
    bus.add_signal_receiver(on_reply, "NotificationReplied", "org.freedesktop.Notifications")
    bus.add_signal_receiver(on_closed, "NotificationClosed", "org.freedesktop.Notifications")
    state["id"] = int(server.Notify(args.app, 0, args.icon, args.summary, args.body, actions,
                                    dbus.Dictionary(hints, signature="sv"), -1))
    say("id %d" % state["id"])
    loop.run()


if __name__ == "__main__":
    main()
