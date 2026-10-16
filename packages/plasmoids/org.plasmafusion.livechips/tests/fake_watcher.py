#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in org.kde.StatusNotifierWatcher and the status items it lists, for chips_qml_test.py
(not installed), on a private session bus. The items are fake_status_items.py's, each under a name
of its own (org.kde.StatusNotifierItem-PID-N) at /ItemN. Commands, one per line on stdin:

  add N screen|recording [hold]   item N, the portal's "Screen casting" for Firefox or Spectacle's
                                  recording at 0:41, registered; with hold, its replies to GetAll
                                  wait for release
  drop N                          N unregisters (its object stays: a held reply can still go)
  release N                       N sends the GetAll replies it holds
  tick N                          N's recording runs on a second (NewToolTip)

It prints "ready", then "getall N" for each GetAll that reaches an item and "released N COUNT".
"""
import os
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

sys.dont_write_bytecode = True  # no __pycache__ in the checkout
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fake_status_items as fake  # noqa: E402

WATCHER = "org.kde.StatusNotifierWatcher"


class Watcher(dbus.service.Object):
    def __init__(self, bus):
        self.items = []
        dbus.service.Object.__init__(self, bus, "/StatusNotifierWatcher")

    @dbus.service.method(fake.PROPS, in_signature="ss", out_signature="v")
    def Get(self, interface, name):
        if name == "RegisteredStatusNotifierItems":
            return dbus.Array(self.items, signature="s")
        if name == "IsStatusNotifierHostRegistered":
            return dbus.Boolean(True)
        return dbus.Int32(0)

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemRegistered(self, key):
        pass

    @dbus.service.signal(WATCHER, signature="s")
    def StatusNotifierItemUnregistered(self, key):
        pass


class HeldItem(fake.Item):
    """An item whose GetAll replies can be held back."""

    def __init__(self, bus, number, props, path):
        self.number = number
        self.hold = False
        self.held = []
        fake.Item.__init__(self, bus, props, path=path)

    @dbus.service.method(fake.PROPS, in_signature="s", out_signature="a{sv}", async_callbacks=("ok", "err"))
    def GetAll(self, interface, ok, err):
        print("getall %d" % self.number, flush=True)
        reply = dbus.Dictionary(self.props if interface == fake.SNI else {}, signature="sv")
        if self.hold:
            self.held.append(lambda: ok(reply))
        else:
            ok(reply)


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    if bus.name_has_owner(WATCHER):
        raise SystemExit("this bus has a status notifier watcher already: run on a private bus (dbus-run-session)")
    names = [dbus.service.BusName(WATCHER, bus)]
    watcher = Watcher(bus)
    items = {}
    seconds = {}
    pending = [b""]

    def run(line):
        words = line.split()
        if not words:
            return
        number = int(words[1])
        key = "org.kde.StatusNotifierItem-%d-%d/Item%d" % (os.getpid(), number, number)
        if words[0] == "add":
            names.append(dbus.service.BusName(key.split("/")[0], bus))
            seconds[number] = 41
            props = fake.screen_props("Firefox", True) if words[2] == "screen" else fake.recording_props(seconds[number])
            item = HeldItem(bus, number, props, "/Item%d" % number)
            item.hold = "hold" in words[3:]
            items[number] = item
            watcher.items.append(key)
            watcher.StatusNotifierItemRegistered(key)
        elif words[0] == "drop":
            watcher.items.remove(key)
            watcher.StatusNotifierItemUnregistered(key)
        elif words[0] == "release":
            item = items[number]
            held, item.held, item.hold = item.held, [], False
            for send in held:
                send()
            print("released %d %d" % (number, len(held)), flush=True)
        elif words[0] == "tick":
            seconds[number] += 1
            items[number].props["ToolTip"] = fake.recording_tooltip(seconds[number])
            items[number].NewToolTip()

    def readable(fd, condition):
        data = os.read(fd, 4096)
        if not data:
            loop.quit()
            return False
        pending[0] += data
        while b"\n" in pending[0]:
            line, pending[0] = pending[0].split(b"\n", 1)
            run(line.decode())
        return True

    loop = GLib.MainLoop()
    GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, readable)
    print("ready", flush=True)
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
