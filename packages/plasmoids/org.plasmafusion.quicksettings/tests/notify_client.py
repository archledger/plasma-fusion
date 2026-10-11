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
  notify_client.py job TITLE --entry DESKTOP_ENTRY --source PATH --dest PATH [--files N]
                   [--seconds S] [--fail MESSAGE] [--running] [--suspendable] [--killable]
      A file copy as KIO reports it (org.kde.JobViewServerV2): runs S seconds (default 1.5, longer
      than the server's delay before it shows a job), then finishes, or fails with MESSAGE; with
      --running it keeps running. Prints "running", "finished", and "suspend", "resume", "cancel"
      for what the user asks; exits when stdin is closed (or after a cancel).
  notify_client.py filemanager
      Owns org.freedesktop.FileManager1 and prints "show URL..." for each ShowItems call, until
      stdin is closed (where a test has no file manager).

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
    sub.add_parser("filemanager")
    job = sub.add_parser("job")
    job.add_argument("title")
    job.add_argument("--entry", required=True)
    job.add_argument("--source", required=True)
    job.add_argument("--dest", required=True)
    job.add_argument("--files", type=int, default=1)
    job.add_argument("--seconds", type=float, default=1.5)
    job.add_argument("--fail", default=None)
    job.add_argument("--running", action="store_true")
    job.add_argument("--suspendable", action="store_true")
    job.add_argument("--killable", action="store_true")
    args = parser.parse_args()

    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()

    def say(line):
        print(line, flush=True)

    # Quit when stdin is closed (the test or the person driving it is done).
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_HUP | GLib.IO_IN, lambda *a: (loop.quit(), False)[1])

    if args.command == "filemanager":
        run_file_manager(bus, loop, say)
        return
    if args.command == "job":
        run_job(bus, args, loop, say)
        return
    server = dbus.Interface(bus.get_object("org.freedesktop.Notifications", "/org/freedesktop/Notifications"),
                            "org.freedesktop.Notifications")
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
    state["id"] = int(server.Notify(args.app, dbus.UInt32(0), args.icon, args.summary, args.body,
                                    dbus.Array(actions, signature="s"),
                                    dbus.Dictionary(hints, signature="sv"), -1))
    say("id %d" % state["id"])
    loop.run()


def run_file_manager(bus, loop, say):
    import dbus.service

    class FileManager(dbus.service.Object):
        @dbus.service.method("org.freedesktop.FileManager1", in_signature="ass", out_signature="")
        def ShowItems(self, uris, startup_id):
            say("show " + " ".join(str(u) for u in uris))

    name = dbus.service.BusName("org.freedesktop.FileManager1", bus)
    FileManager(name, "/org/freedesktop/FileManager1")
    say("ready")
    loop.run()


def run_job(bus, args, loop, say):
    # KJob capabilities: Killable 1, Suspendable 2.
    capabilities = (1 if args.killable else 0) | (2 if args.suspendable else 0)
    views = dbus.Interface(bus.get_object("org.kde.JobViewServer", "/JobViewServer"), "org.kde.JobViewServerV2")
    path = views.requestView(args.entry, capabilities, dbus.Dictionary({}, signature="sv"))
    view = dbus.Interface(bus.get_object("org.kde.JobViewServer", path), "org.kde.JobViewV3")
    multiple = args.files > 1
    dest_dir = args.dest if multiple else args.dest.rsplit("/", 1)[0]
    properties = {
        "title": dbus.String(args.title),
        "percent": dbus.UInt32(40),
        "totalFiles": dbus.UInt64(args.files),
        "processedFiles": dbus.UInt64(0),
        "destUrl": dbus.String("file://" + dest_dir),
        "descriptionLabel1": dbus.String("Source"),
        "descriptionValue1": dbus.String(args.source),
        "descriptionLabel2": dbus.String("Destination"),
        "descriptionValue2": dbus.String(args.dest),
    }
    view.update(dbus.Dictionary(properties, signature="sv"))
    say("running")
    for signal in ("suspendRequested", "resumeRequested", "cancelRequested"):
        word = signal.replace("Requested", "")

        def handler(word=word):
            say(word)
            if word == "suspend":
                view.update(dbus.Dictionary({"suspended": dbus.Boolean(True)}, signature="sv"))
            elif word == "resume":
                view.update(dbus.Dictionary({"suspended": dbus.Boolean(False)}, signature="sv"))
            else:
                view.terminate(dbus.UInt32(1), "", dbus.Dictionary({}, signature="sv"))
                loop.quit()
        bus.add_signal_receiver(handler, signal, "org.kde.JobViewV3", path=path)

    def finish():
        if args.fail is not None:
            # KIO::ERR_DISK_FULL
            view.terminate(dbus.UInt32(43), args.fail, dbus.Dictionary({}, signature="sv"))
        else:
            view.update(dbus.Dictionary({"percent": dbus.UInt32(100), "processedFiles": dbus.UInt64(args.files)},
                                        signature="sv"))
            view.terminate(dbus.UInt32(0), "", dbus.Dictionary({}, signature="sv"))
        say("finished")
        return False

    if not args.running:
        GLib.timeout_add(int(args.seconds * 1000), finish)
    loop.run()


if __name__ == "__main__":
    main()
