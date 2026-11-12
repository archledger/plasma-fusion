#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The dynamic tiler's native lifecycle, offscreen: the real placement main.qml under the
stand-in org.kde.kwin module and a mock TransientTilingApi facade.

The harness QML drives the toggle, the untoggle, the native teardown and a refused tree, and
asserts the geometry and the facade calls; this driver additionally waits past the settling
timer so the invariant-7 check is honest (a late settle pass must not record managed windows
either) and re-checks the call counts.

    QT_QPA_PLATFORM=offscreen python3 tiling_lifecycle_test.py [PACKAGES_KWIN_DIR]

PACKAGES_KWIN_DIR defaults to this checkout's packages/kwin; the CI lane passes the staged
tree's .local/share/kwin.
"""
import os
import sys

from PySide6.QtCore import QObject, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

from render import I18n


class ScriptConfig(QObject):
    """The KWin scripting functions the module exposes to QML scripts, as a context object
    (the stand-in module carries no KWin singleton). MasterFraction is prefilled so the test
    also proves the tiler's settings reach the native tile."""

    def __init__(self):
        super().__init__()
        self.settings = {"MasterFraction": 0.4}
        self.calls = []

    @Slot(str, "QVariant", result="QVariant")
    def readConfig(self, key, fallback):
        return self.settings.get(key, fallback)

    @Slot(str, "QVariant")
    def writeConfig(self, key, value):
        self.settings[key] = value

    @Slot(str, str, str, str)
    def callDBus(self, service, path, interface, method):
        self.calls.append([service, path, interface, method])


here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.abspath(os.path.join(here, "..", "..", "..", ".."))
packages_kwin = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(repo, "packages", "kwin")

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
engine.addImportPath(os.path.join(here, "stubs"))
# Keep every context QObject referenced for the engine's lifetime: a temporary would be
# garbage-collected by Python while QML still resolves through it (a dangling pointer).
i18n = I18n()
engine.rootContext().setContextObject(i18n)
engine.rootContext().setContextProperty("packagesRoot", packages_kwin)
config = ScriptConfig()
engine.rootContext().setContextProperty("KWin", config)
component = QQmlComponent(engine, QUrl.fromLocalFile(os.path.join(here, "tiling-harness.qml")))
if component.status() != QQmlComponent.Ready:
    print("FAIL tiling_lifecycle_test.py: the harness did not load: "
          + "; ".join(e.toString() for e in component.errors()))
    sys.exit(1)
harness = component.create()


def finish():
    app.quit()


def poll():
    if harness.property("done"):
        QTimer.singleShot(1300, finish)  # past the script's 1 s settling timer
    else:
        QTimer.singleShot(50, poll)


QTimer.singleShot(50, poll)
app.exec()

problems = list(harness.property("problems").toVariant() or [])
facade_calls = list(harness.property("facadeCalls").toVariant() or [])
for problem in problems:
    failures.append(str(problem))

counts = {}
for call in facade_calls:
    counts[call["op"]] = counts.get(call["op"], 0) + 1
# Three accepted sessions (toggle, post-teardown toggle, cleanup toggle after the teardown
# proof) plus one refused create; three admissions; two releases (the two un-toggles - the
# native teardown releases nothing because its tree is already gone).
check(counts.get("registerProvider") == 1, "registerProvider once")
check(counts.get("createTile") == 4, "createTile four times (3 sessions + 1 refused), got %s" % counts.get("createTile"))
check(counts.get("admitTile") == 3, "admitTile three times, got %s" % counts.get("admitTile"))
check(counts.get("releaseTile") == 2, "releaseTile twice, got %s" % counts.get("releaseTile"))
check(counts.get("trackWindow") == 4, "trackWindow for the four windows, got %s" % counts.get("trackWindow"))
# Invariant 7 end-to-end: after the settling timer passed, no managed window's automatic
# rectangle ever reached the placement writer (a late settle pass included).
recorded = [c for c in facade_calls if c["op"] == "record"]
check(not recorded, "no automatic geometry was recorded for managed windows, got %s" % recorded)

if failures:
    for failure in failures:
        print("FAIL tiling_lifecycle_test.py: " + failure)
    sys.exit(1)
print("tiling_lifecycle_test.py: ok")
