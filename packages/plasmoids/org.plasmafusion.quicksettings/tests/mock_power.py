#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Private-bus PowerDevil/ScreenSaver endpoints for the native inhibition test."""

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
names = ["org.kde.Solid.PowerManagement", "org.freedesktop.PowerManagement",
         "org.freedesktop.PowerManagement.Inhibit", "org.freedesktop.ScreenSaver"]
sleep = {}
screen = {}
cookie = 0


class Inhibitor(dbus.service.Object):
    def __init__(self, path, holds):
        super().__init__(bus, path)
        self.holds = holds

    def add(self, app, reason, sender):
        global cookie
        cookie += 1
        self.holds[cookie] = (app, reason, sender)
        return dbus.UInt32(cookie)


class Sleep(Inhibitor):
    @dbus.service.method("org.freedesktop.PowerManagement.Inhibit", in_signature="ss",
                         out_signature="u", sender_keyword="sender")
    def Inhibit(self, app, reason, sender=None):
        value = self.add(app, reason, sender)
        fdo.HasInhibitChanged(True)
        return value

    @dbus.service.method("org.freedesktop.PowerManagement.Inhibit", in_signature="u")
    def UnInhibit(self, value):
        self.holds.pop(int(value))
        fdo.HasInhibitChanged(bool(sleep))


class Screen(Inhibitor):
    @dbus.service.method("org.freedesktop.ScreenSaver", in_signature="ss", out_signature="u",
                         sender_keyword="sender")
    def Inhibit(self, app, reason, sender=None):
        return self.add(app, reason, sender)

    @dbus.service.method("org.freedesktop.ScreenSaver", in_signature="u")
    def UnInhibit(self, value):
        self.holds.pop(int(value))


class Power(dbus.service.Object):
    @dbus.service.method("org.kde.Solid.PowerManagement", out_signature="b")
    def isLidPresent(self):
        return False


class FdoPower(dbus.service.Object):
    @dbus.service.signal("org.freedesktop.PowerManagement.Inhibit", signature="b")
    def HasInhibitChanged(self, active):
        pass

    @dbus.service.method("org.freedesktop.PowerManagement.Inhibit", out_signature="b")
    def HasInhibit(self):
        return bool(sleep)


class Policy(dbus.service.Object):
    @dbus.service.method("org.freedesktop.DBus.Properties", in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return dbus.Array([], signature="(ssssu)", variant_level=1)

    @dbus.service.method("org.kde.Solid.PowerManagement.PolicyAgent", out_signature="a{ss}")
    def ListInhibitions(self):
        return {}


class TestPower(dbus.service.Object):
    @dbus.service.method("org.plasmafusion.TestPower", out_signature="uu")
    def Counts(self):
        return len(sleep), len(screen)

    @dbus.service.method("org.plasmafusion.TestPower", in_signature="b")
    def SetAvailable(self, available):
        for name in names:
            if available:
                bus.request_name(name)
            else:
                bus.release_name(name)


def owner_changed(name, old, new):
    if old and not new:
        for holds in (sleep, screen):
            for value, record in list(holds.items()):
                if record[2] == name:
                    del holds[value]


bus.add_signal_receiver(owner_changed, "NameOwnerChanged", "org.freedesktop.DBus")
for name in [*names, "org.plasmafusion.TestPower"]:
    bus.request_name(name)
fdo = FdoPower(bus, "/org/freedesktop/PowerManagement")
objects = [Sleep("/org/freedesktop/PowerManagement/Inhibit", sleep),
           Screen("/ScreenSaver", screen),
           Power(bus, "/org/kde/Solid/PowerManagement"),
           fdo,
           Policy(bus, "/org/kde/Solid/PowerManagement/PolicyAgent"),
           TestPower(bus, "/Test")]
GLib.MainLoop().run()
