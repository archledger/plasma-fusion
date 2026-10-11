#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise Fusion's real QML and Plasma's native control on a private D-Bus bus.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/keepawake_test.py
Requires PySide6, python3-dbus, python3-gobject and PowerDevil's QML module. Also the timed Keep awake
(F7): the shared end, the end on time, one release.
"""

from pathlib import Path
import subprocess
import sys
import time

import dbus
from PySide6.QtCore import Q_ARG, QMetaObject, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
bus = dbus.SessionBus()
if bus.name_has_owner("org.kde.Solid.PowerManagement") or bus.name_has_owner("org.freedesktop.ScreenSaver"):
    raise SystemExit("Run on a fresh private bus; refusing a live desktop bus")
app = QGuiApplication(sys.argv[:1])
app.setDesktopFileName("org.plasmafusion.keepawake-test")
engine = QQmlEngine()
fixture = subprocess.Popen([sys.executable, str(here / "mock_power.py")])
checks = 0


def wait_for(predicate, message):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        QTest.qWait(20)
        if predicate():
            return
    raise AssertionError(message)


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


try:
    wait_for(lambda: bus.name_has_owner("org.plasmafusion.TestPower"), "fixture did not start")
    test = dbus.Interface(bus.get_object("org.plasmafusion.TestPower", "/Test"), "org.plasmafusion.TestPower")
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(here.parent / "contents/ui/services/KeepAwake.qml")))
    first = component.create()
    if first is None:
        raise AssertionError("Keep awake service did not load: " + "; ".join(e.toString() for e in component.errors()))
    second = component.create()
    wait_for(lambda: first.property("available"), "PowerDevil did not become available")
    check(not first.property("active") and tuple(test.Counts()) == (0, 0), "off by default, no inhibitors acquired")

    # Another app inhibits sleep; that must not be confused with the user's manual switch.
    power = dbus.Interface(bus.get_object("org.freedesktop.PowerManagement.Inhibit",
                                         "/org/freedesktop/PowerManagement/Inhibit"),
                           "org.freedesktop.PowerManagement.Inhibit")
    other = power.Inhibit("org.example.Download", "Downloading")
    QTest.qWait(100)
    check(not first.property("active"), "an application inhibitor does not turn the manual switch on")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: tuple(test.Counts()) == (2, 1) and first.property("active"), "sleep and screen inhibition not both acquired")
    check(second.property("active"), "two controls share the native manual state")
    check(tuple(test.Counts()) == (2, 1), "one activation holds sleep AND automatic-lock/display inhibitors")

    QMetaObject.invokeMethod(second, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: tuple(test.Counts()) == (1, 0) and not first.property("active"), "manual inhibition not released")
    check(not second.property("active"), "turning off synchronizes both controls")
    check(tuple(test.Counts()) == (1, 0), "turning off releases both own cookies and preserves the other app")
    power.UnInhibit(other)

    test.SetAvailable(False)
    wait_for(lambda: not first.property("available"), "service disappearance not observed")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    QTest.qWait(100)
    check(not first.property("active") and tuple(test.Counts()) == (0, 0), "unavailable service cannot report or acquire inhibition")
    test.SetAvailable(True)
    wait_for(lambda: first.property("available"), "service return not observed")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: first.property("active") and tuple(test.Counts()) == (1, 1), "cannot inhibit after service returns")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: not first.property("active") and tuple(test.Counts()) == (0, 0), "final release did not finish")
    check(tuple(test.Counts()) == (0, 0), "service recovery and repeated use leave no cookies behind")
    # Two quick taps: the second, before the first reply, is ignored. The native monitor keeps one
    # pair of cookies, so a second inhibit would leave a pair nothing could release.
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: first.property("active"), "a quick double tap did not turn it on")
    QTest.qWait(300)
    check(tuple(test.Counts()) == (1, 1), "a quick double tap acquires one inhibition pair")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: not first.property("active"), "turning off after a double tap failed")
    QTest.qWait(300)
    check(tuple(test.Counts()) == (0, 0), "turning off after a double tap leaves no cookies behind")
    # The tiles of two screens (two widgets, one native monitor) tapped before the first reply.
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    QMetaObject.invokeMethod(second, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: first.property("active"), "two widgets' taps did not turn it on")
    QTest.qWait(300)
    check(tuple(test.Counts()) == (1, 1), "two widgets tapped at once acquire one inhibition pair")
    QMetaObject.invokeMethod(second, "toggle", Q_ARG(str, "Manually block sleep and screen locking"))
    wait_for(lambda: not first.property("active"), "turning off after two widgets' taps failed")
    QTest.qWait(300)
    check(tuple(test.Counts()) == (0, 0), "turning off from the other widget leaves no cookies behind")

    # Keep awake for a while (F7): the end is shared by the widgets, a widget ends it on time with
    # its sheet closed (there is none here), once, and leaves no cookies behind.
    reason = "Manually block sleep and screen locking"

    def until_in(ms):
        return time.time() * 1000 + ms

    QMetaObject.invokeMethod(first, "keepAwakeUntil", Q_ARG(str, reason), Q_ARG(float, until_in(1500)))
    wait_for(lambda: first.property("active") and tuple(test.Counts()) == (1, 1), "a timed Keep awake did not start")
    check(second.property("until") == first.property("until") > 0, "both widgets know when it ends")
    check(first.property("minutesLeft") == 1, "it shows a minute left")
    QTest.qWait(500)
    check(first.property("active"), "it is still on before its end")
    wait_for(lambda: not first.property("active"), "a timed Keep awake did not end on time")
    QTest.qWait(500)
    check(tuple(test.Counts()) == (0, 0) and not second.property("active"), "at its end it is off, with both cookies released once")
    check(first.property("until") == 0 and second.property("until") == 0, "an ended timer leaves no end behind")

    # Turned off before its end: turning it on again lasts past the old end.
    QMetaObject.invokeMethod(first, "keepAwakeUntil", Q_ARG(str, reason), Q_ARG(float, until_in(1200)))
    wait_for(lambda: first.property("active"), "a second timed Keep awake did not start")
    QMetaObject.invokeMethod(second, "toggle", Q_ARG(str, reason))
    wait_for(lambda: not first.property("active"), "turning a timed Keep awake off failed")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, reason))
    wait_for(lambda: first.property("active"), "turning Keep awake on again failed")
    QTest.qWait(1800)
    check(first.property("active") and first.property("until") == 0, "after turning it off, an old end does not end the next one")

    # A timed one made "until turned off" keeps going; a time chosen while on replaces the end.
    QMetaObject.invokeMethod(second, "keepAwakeUntil", Q_ARG(str, reason), Q_ARG(float, until_in(800)))
    QTest.qWait(100)
    check(first.property("until") > 0 and tuple(test.Counts()) == (1, 1), "a time chosen while on sets the end without a second inhibition")
    QMetaObject.invokeMethod(first, "keepAwakeUntil", Q_ARG(str, reason), Q_ARG(float, 0.0))
    QTest.qWait(1300)
    check(first.property("active") and second.property("until") == 0, "until turned off: it stays on past the earlier end")
    QMetaObject.invokeMethod(first, "toggle", Q_ARG(str, reason))
    wait_for(lambda: not first.property("active") and tuple(test.Counts()) == (0, 0), "final release after the timed checks")
    print(f"Keep awake: {checks} checks, 0 failures")
finally:
    fixture.terminate()
    fixture.wait(timeout=5)
