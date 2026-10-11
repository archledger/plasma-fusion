#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in ksystemstats (org.kde.ksystemstats1) on a private session bus for readings_test.py.

It answers the sensor metadata the way ksystemstats 6.7.5 does (the reply type is
a{s(sssuidd)}: name, short name, description, value type, unit, minimum, maximum), counts every
subscribe and unsubscribe, and sends newSensorData when the test asks (org.plasmafusion.TestStats
on /Test).
"""

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()

# id: (name, short name, unit) as ksystemstats 6.7.5 describes them (value type 6 = double;
# units: 1002 percent, 100 bytes, 200 bytes per second, 1000 degrees Celsius, -1 none).
SENSORS = {
    "cpu/all/usage": ("Total Usage", "Usage", 1002, 0.0, 100.0),
    "cpu/all/coreCount": ("Number of Cores", "Cores", -1, 0.0, 0.0),
    "memory/physical/used": ("Used Physical Memory", "Used", 100, 0.0, 0.0),
    "memory/physical/total": ("Total Physical Memory", "Total", 100, 0.0, 0.0),
    "network/all/download": ("Download Rate", "Download", 200, 0.0, 0.0),
    "network/all/upload": ("Upload Rate", "Upload", 200, 0.0, 0.0),
    "cpu/all/maximumTemperature": ("Maximum CPU Temperature", "Max Temperature", 1000, 0.0, 0.0),
}
subscriptions = {}
calls = []
values = {}


def info(ids):
    out = dbus.Dictionary({}, signature="s(sssuidd)")
    for sensor in ids:
        if sensor in SENSORS:
            name, short, unit, low, high = SENSORS[sensor]
            out[sensor] = dbus.Struct((name, short, "", dbus.UInt32(6), dbus.Int32(unit),
                                       dbus.Double(low), dbus.Double(high)), signature="sssuidd")
    return out


class Stats(dbus.service.Object):
    @dbus.service.method("org.kde.ksystemstats1", out_signature="a{s(sssuidd)}")
    def allSensors(self):
        return info(SENSORS)

    @dbus.service.method("org.kde.ksystemstats1", in_signature="as", out_signature="a{s(sssuidd)}")
    def sensors(self, ids):
        calls.append(("sensors", ",".join(ids)))
        return info([str(i) for i in ids])

    @dbus.service.method("org.kde.ksystemstats1", in_signature="as", out_signature="a(sv)")
    def sensorData(self, ids):
        calls.append(("sensorData", ",".join(ids)))
        return dbus.Array([dbus.Struct((str(i), dbus.Double(values[str(i)], variant_level=1)))
                           for i in ids if str(i) in values], signature="(sv)")

    @dbus.service.method("org.kde.ksystemstats1", in_signature="as")
    def subscribe(self, ids):
        calls.append(("subscribe", ",".join(ids)))
        for i in ids:
            subscriptions[str(i)] = subscriptions.get(str(i), 0) + 1

    @dbus.service.method("org.kde.ksystemstats1", in_signature="as")
    def unsubscribe(self, ids):
        calls.append(("unsubscribe", ",".join(ids)))
        for i in ids:
            subscriptions[str(i)] = max(0, subscriptions.get(str(i), 0) - 1)

    @dbus.service.signal("org.kde.ksystemstats1", signature="a(sv)")
    def newSensorData(self, data):
        pass


class Test(dbus.service.Object):
    @dbus.service.method("org.plasmafusion.TestStats", out_signature="as")
    def Subscribed(self):
        return sorted(k for k, v in subscriptions.items() if v > 0)

    @dbus.service.method("org.plasmafusion.TestStats", out_signature="a(ss)")
    def Calls(self):
        return calls

    @dbus.service.method("org.plasmafusion.TestStats", in_signature="a{sd}")
    def Push(self, data):
        # As ksystemstats: only subscribed sensors are sent.
        out = []
        for k, v in data.items():
            values[str(k)] = float(v)
            if subscriptions.get(str(k), 0) > 0:
                out.append(dbus.Struct((str(k), dbus.Double(float(v), variant_level=1))))
        if out:
            stats.newSensorData(dbus.Array(out, signature="(sv)"))


stats = Stats(bus, "/org/kde/ksystemstats1")
test = Test(bus, "/Test")
# Kept: a BusName releases its name when it is garbage collected.
names = [dbus.service.BusName("org.kde.ksystemstats1", bus), dbus.service.BusName("org.plasmafusion.TestStats", bus)]
GLib.MainLoop().run()
