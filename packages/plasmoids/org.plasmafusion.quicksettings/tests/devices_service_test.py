#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fusion's Disks & Devices service on Plasma's real data engines (offscreen, read-only).

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/devices_service_test.py
Requires PySide6 and plasma5support with its hotplug, soliddevice and devicenotifications engines.
It only reads: no device is mounted, removed or opened. With PF_DEVICES_EXPECT=N it also requires N
listed devices (the owned test VM with virtual USB sticks attached).
"""

import os
from pathlib import Path
import sys

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

here = Path(__file__).resolve().parent
app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
component = QQmlComponent(engine, QUrl.fromLocalFile(str(here.parent / "contents/ui/services/Devices.qml")))
devices = component.create()
if devices is None:
    raise SystemExit("Devices service did not load: " + "; ".join(e.toString() for e in component.errors()))
QTest.qWait(1500)
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


entries = devices.property("list")
entries = entries.toVariant() if hasattr(entries, "toVariant") else entries
count = devices.property("count")
check(isinstance(count, int) and count == len(entries), "the service lists %d device(s) from the engines" % count)
for entry in entries:
    check(entry["udi"] and entry["name"], "listed device has a UDI and a name: %s" % entry["name"])
    check(entry["openPredicate"] != "", "%s has an action to open it" % entry["name"])
expect = os.environ.get("PF_DEVICES_EXPECT")
if expect is not None:
    check(count == int(expect), "expected %s device(s)" % expect)
print("Disks & Devices service: %d checks, 0 failures" % checks)
