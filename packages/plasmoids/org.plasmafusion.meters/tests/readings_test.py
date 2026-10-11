#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The system meters' sensors (contents/ui/Readings.qml) on Plasma's real sensor module.

A stand-in ksystemstats (mock_ksystemstats.py) on a private bus counts what libksysguard
subscribes: nothing while every meter is off or the meters cannot be seen, only the sensors of
the meters turned on, everything while the pop-up is open, and values no faster than the rate
limit.

QT_QPA_PLATFORM=offscreen dbus-run-session \
  --config-file=packages/kwin/tests/offscreen/session-bus.conf -- \
  python3 packages/plasmoids/org.plasmafusion.meters/tests/readings_test.py
Requires PySide6, python3-dbus, python3-gobject and libksysguard's QML module.
"""

import math
from pathlib import Path
import subprocess
import sys
import time

import dbus
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
bus = dbus.SessionBus()
if bus.name_has_owner("org.kde.ksystemstats1") or bus.name_has_owner("org.kde.plasmashell"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
fixture = subprocess.Popen([sys.executable, str(here / "mock_ksystemstats.py")])
checks = 0
GIB = 1024 ** 3


def wait_for(predicate, message, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        QTest.qWait(20)
        if predicate():
            return
    raise AssertionError(message)


def listed(value):
    """A QML list property as a Python list (PySide6 hands a var property over as a QJSValue)."""
    return list(value.toVariant() if hasattr(value, "toVariant") else value)


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


try:
    wait_for(lambda: bus.name_has_owner("org.plasmafusion.TestStats"), "the stand-in ksystemstats did not start")
    test = dbus.Interface(bus.get_object("org.plasmafusion.TestStats", "/Test"), "org.plasmafusion.TestStats")

    def subscribed():
        return sorted(str(s) for s in test.Subscribed())

    def subscribe_calls():
        return [str(c[1]) for c in test.Calls() if str(c[0]) == "subscribe"]

    component = QQmlComponent(engine, QUrl.fromLocalFile(str(here.parent / "contents/ui/Readings.qml")))
    r = component.create()
    if r is None:
        raise AssertionError("Readings.qml did not load: " + "; ".join(e.toString() for e in component.errors()))
    r.setProperty("rateLimit", 0)

    # Every meter off: the widget subscribes nothing, even while it can be seen.
    r.setProperty("active", True)
    QTest.qWait(600)
    check(subscribed() == [] and subscribe_calls() == [], "every meter off: no sensor subscribed")

    # A meter on while the meters cannot be seen (covered, locked): still nothing.
    r.setProperty("active", False)
    r.setProperty("cpuWanted", True)
    QTest.qWait(600)
    check(subscribed() == [] and subscribe_calls() == [], "CPU on but the meters not seen: no sensor subscribed")

    r.setProperty("active", True)
    wait_for(lambda: subscribed() == ["cpu/all/usage"], "the CPU sensor was not subscribed")
    check(listed(r.property("subscribed")) == ["cpu/all/usage"], "CPU on: only cpu/all/usage subscribed")
    test.Push({"cpu/all/usage": 42.5})
    wait_for(lambda: r.property("cpu") == 42.5, "the CPU value did not arrive")
    check(True, "a CPU value from ksystemstats reaches the meter")

    r.setProperty("memoryWanted", True)
    r.setProperty("networkWanted", True)
    r.setProperty("temperatureWanted", True)
    want = sorted(["cpu/all/usage", "memory/physical/used", "memory/physical/total", "network/all/download",
                   "network/all/upload", "cpu/all/maximumTemperature"])
    wait_for(lambda: subscribed() == want, "the other sensors were not subscribed: %s" % subscribed())
    check("cpu/all/coreCount" not in subscribed(), "all four meters: their six sensors, not the pop-up's core count")
    test.Push({"memory/physical/used": 6 * GIB, "memory/physical/total": 16 * GIB, "network/all/download": 1234.0,
               "network/all/upload": 56.0, "cpu/all/maximumTemperature": 0.0})
    wait_for(lambda: r.property("download") == 1234.0 and r.property("memoryTotal") == 16 * GIB, "values did not arrive")
    check(r.property("memoryUsed") == 6 * GIB and r.property("upload") == 56.0, "memory and network values arrive")
    check(math.isnan(r.property("temperature")), "a temperature of 0 (no CPU sensor) is no reading")
    test.Push({"cpu/all/maximumTemperature": 61.0})
    wait_for(lambda: r.property("temperature") == 61.0, "the temperature did not arrive")
    check(True, "a real temperature reading arrives")

    # Network off: its two sensors go; the pop-up opened brings them back with the core count.
    r.setProperty("networkWanted", False)
    wait_for(lambda: "network/all/download" not in subscribed(), "the network sensors stayed subscribed")
    check("network/all/upload" not in subscribed() and "cpu/all/usage" in subscribed(),
          "a meter turned off unsubscribes its sensors only")
    r.setProperty("details", True)
    wait_for(lambda: "network/all/download" in subscribed() and "cpu/all/coreCount" in subscribed(),
             "the pop-up's sensors were not subscribed")
    check(True, "the pop-up open: every sensor it shows, the core count too")
    r.setProperty("details", False)
    wait_for(lambda: "cpu/all/coreCount" not in subscribed(), "the core count stayed subscribed")
    check("network/all/download" not in subscribed(), "the pop-up closed: back to the meters' sensors")

    # Not seen any more: everything unsubscribed.
    r.setProperty("active", False)
    wait_for(lambda: subscribed() == [], "sensors stayed subscribed while the meters cannot be seen")
    check(listed(r.property("subscribed")) == [], "the meters not seen: every sensor unsubscribed")

    # The rate limit: every value reaches the meter without one; with a 1 s limit, 15 values
    # 100 ms apart reach it once or twice (libksysguard drops what comes sooner).
    r.setProperty("active", True)
    r.setProperty("memoryWanted", False)
    r.setProperty("temperatureWanted", False)
    wait_for(lambda: subscribed() == ["cpu/all/usage"], "the CPU sensor did not come back")
    QTest.qWait(300)
    seen = []
    r.valueArrived.connect(lambda sensor: seen.append(str(sensor)))

    def burst(start):
        del seen[:]
        for i in range(15):
            test.Push({"cpu/all/usage": start + i})
            QTest.qWait(100)
        QTest.qWait(200)
        return seen.count("cpu/all/usage")

    check(burst(10.0) == 15, "without a rate limit every value reaches the meter")
    r.setProperty("rateLimit", 1000)
    updates = burst(40.0)
    check(1 <= updates <= 2, "with a 1 s rate limit, 15 values in 1.5 s give %d updates (1 or 2)" % updates)
    print(f"Meters readings: {checks} checks, 0 failures")
finally:
    fixture.terminate()
    fixture.wait(timeout=5)
