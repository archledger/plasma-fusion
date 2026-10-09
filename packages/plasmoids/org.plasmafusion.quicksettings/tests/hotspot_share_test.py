#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Two quick settings widgets (one per screen's top bar) show the same hotspot state: plasma-nm's
handler of a widget only knows of a hotspot it started, so the widgets share it (Instances).
Read-only: nothing is started; it only loads the network service twice.
QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/hotspot_share_test.py"""
import os
from pathlib import Path
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import Q_ARG, QMetaObject, QUrl  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQml import QQmlComponent, QQmlEngine  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

SERVICES = Path(__file__).resolve().parent.parent / "contents/ui/services"
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
network = QQmlComponent(engine, QUrl.fromLocalFile(str(SERVICES / "Network.qml")))
first, second = network.create(), network.create()
if first is None or second is None:
    errors = "; ".join(e.toString() for e in network.errors())
    if "is not installed" in errors:
        print("SKIP plasma-nm's QML module is not installed: " + errors)
        sys.exit(0)
    raise AssertionError("the network service did not load: " + errors)
shared = QQmlComponent(engine)
shared.setData(b'import QtQuick\nimport "../global"\nQtObject { function setHotspot(on: bool) { Instances.hotspotActive = on; } }\n',
               QUrl.fromLocalFile(str(SERVICES / "shared-probe.qml")))
probe = shared.create()
assert probe is not None, "; ".join(e.toString() for e in shared.errors())
QTest.qWait(300)
if first.property("hotspotActive"):
    print("SKIP a hotspot is running here")
    sys.exit(0)
check(not second.property("hotspotActive"), "no hotspot: both widgets show it off")
QMetaObject.invokeMethod(probe, "setHotspot", Q_ARG(bool, True))
QTest.qWait(100)
check(first.property("hotspotActive") and second.property("hotspotActive"),
      "a hotspot one widget's handler started shows in both widgets")
QMetaObject.invokeMethod(probe, "setHotspot", Q_ARG(bool, False))
QTest.qWait(100)
check(not first.property("hotspotActive") and not second.property("hotspotActive"), "and its end in both")
print(f"Hotspot share: {checks} checks, 0 failures")
