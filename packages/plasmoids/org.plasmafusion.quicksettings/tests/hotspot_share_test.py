#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Quick settings widgets (one per screen's top bar) show the same hotspot state: plasma-nm's
handler of a widget follows only a hotspot it started, so the widgets share it (Instances); a new
widget's handler, which looks the hotspot's connection up, and a stop from any widget set it; a start
request on its way is shared too, so no widget sends a second one meanwhile.
Read-only: nothing is started or stopped (the stop runs with no hotspot connection recorded).
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
shared.setData(b'import QtQuick\nimport org.kde.plasma.networkmanagement as PlasmaNM\nimport "../global"\n'
               b'QtObject { function setHotspot(on: bool) { Instances.hotspotActive = on; }\n'
               b' function setStarting(on: bool) { Instances.hotspotStarting = on; }\n'
               b' readonly property string recorded: String(PlasmaNM.Configuration.hotspotConnectionPath) }\n',
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
QMetaObject.invokeMethod(probe, "setStarting", Q_ARG(bool, True))
QTest.qWait(100)
check(first.property("hotspotStarting") and second.property("hotspotStarting"),
      "a start request from one widget shows as starting in both (no second request)")
QMetaObject.invokeMethod(probe, "setStarting", Q_ARG(bool, False))
QTest.qWait(100)

# A state left on with no handler that sees the hotspot (it was running when the widgets came, then
# ended): a new widget's handler looks it up and turns the shared state off.
QMetaObject.invokeMethod(probe, "setHotspot", Q_ARG(bool, True))
third = network.create()
QTest.qWait(300)
check(third is not None and not first.property("hotspotActive") and not third.property("hotspotActive"),
      "a new widget's handler finds no hotspot and turns the shared state off")
# The same, stopped from a widget: off in every widget, though no handler had anything to stop.
# Only with no hotspot connection recorded (plasma-nm stops the recorded one).
if probe.property("recorded"):
    print("SKIP a hotspot connection is recorded here: not pressing stop")
else:
    QMetaObject.invokeMethod(probe, "setHotspot", Q_ARG(bool, True))
    QTest.qWait(100)
    QMetaObject.invokeMethod(second, "toggleHotspot")
    QTest.qWait(100)
    check(not first.property("hotspotActive") and not second.property("hotspotActive") and not third.property("hotspotActive"),
          "stopping from a widget turns it off everywhere, with no handler that saw it running")
print(f"Hotspot share: {checks} checks, 0 failures")
