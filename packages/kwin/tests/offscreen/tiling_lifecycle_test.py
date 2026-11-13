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

from PySide6.QtCore import QObject, QTimer, QUrl, Slot, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine

from render import I18n


class ScriptConfig(QObject):
    """The KWin scripting functions the module exposes to QML scripts, as a context object
    (the stand-in module carries no KWin singleton). MasterFraction is prefilled so the test
    also proves the tiler's settings reach the native tile."""

    def __init__(self):
        super().__init__()
        # MasterFraction exercises the tiler's settings path; IgnoreApps names winB's app in
        # the harness (org.fusion.files), for the ignored-member detach scenario.
        self.settings = {"MasterFraction": 0.4, "IgnoreApps": "org.fusion.files"}
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


# The script's own journal lines (console.info), kept for the teardown count below and passed on.
messages = []


def keep_message(mode, context, message):
    messages.append(message)
    print(message, file=sys.stderr)


qInstallMessageHandler(keep_message)
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
def run_harness(initial=None):
    """One harness instance run to its end, past the script's 1 s settling timer."""
    instance = component.createWithInitialProperties(initial) if initial else component.create()

    def poll():
        if instance.property("done"):
            QTimer.singleShot(1300, app.quit)
        else:
            QTimer.singleShot(50, poll)

    QTimer.singleShot(50, poll)
    app.exec()
    return instance


harness = run_harness()
teardowns = sum("tiling: off (native teardown)" in message for message in messages)

problems = list(harness.property("problems").toVariant() or [])
facade_calls = list(harness.property("facadeCalls").toVariant() or [])
for problem in problems:
    failures.append(str(problem))

counts = {}
snapshot = harness.property("snapshot")
snapshot = snapshot.toVariant() if hasattr(snapshot, "toVariant") else snapshot
for key in ("createTile", "admitTile", "releaseTile", "registerProvider", "trackWindow"):
    counts[key] = (snapshot or {}).get(key)
# Six accepted sessions (toggle, post-teardown toggle, teardown-proof toggle, the first-desktop
# session, the invoked-view toggle, the ignored-member toggle) plus one refused create and one
# tree whose admission was refused; seven admissions, one of them refused; five releases (the
# run's own un-toggles, the invocation's teardown included, and the refused admission's tree -
# the native teardown releases nothing, the last session is left standing for the settle pass,
# and the destruction-time untoggle is outside the snapshot). Five windows tracked: the master
# and the four the script saw open (the second desktop's master appears only as the tiler's
# target).
check(counts.get("registerProvider") == 1, "registerProvider once")
check(counts.get("createTile") == 8, "createTile eight times (6 sessions + 1 refused + 1 refused admission), got %s" % counts.get("createTile"))
check(counts.get("admitTile") == 7, "admitTile seven times, got %s" % counts.get("admitTile"))
check(counts.get("releaseTile") == 5, "releaseTile five times, got %s" % counts.get("releaseTile"))
check(counts.get("trackWindow") == 7, "trackWindow for the seven windows, got %s" % counts.get("trackWindow"))
# The mock's releaseTile reports the tree's end before it returns, as the compositor's does. The
# untoggle has ended its session by then: the run has one native teardown (the scenario that
# ends the tree behind the script's back), not one more for every release the script asked for.
check(teardowns == 1, "one native teardown in the run, got %s" % teardowns)

# Invariant 7, the ignore policy and the float record, after the settling pass fired: the only
# records are the live-joined windows' saved floats (c, d and g at their open geometries) -
# never a cell rectangle, nothing for the adopted windows, and nothing at all for the ignored
# app's second window (e) or the reflow-starved member's late cell commit (a).
recorded = [c for c in facade_calls if c["op"] == "record"]
expected_floats = {("c", 300, 500, 260, 260), ("d", 200, 300, 240, 200), ("g", 430, 150, 260, 300)}
got_floats = {(c["window"], c["x"], c["y"], c["width"], c["height"]) for c in recorded}
check(got_floats == expected_floats,
      "only the joined windows' floats were recorded (a cell, an ignored app and a late commit never were): got %s" % sorted(got_floats))

# A second run against the facade of a fork build from before restoreWindow: the tiler stays off
# (it could start a session and never end it) and says so, and the placement memory keeps its
# native transport.
older = run_harness({"legacyFacade": True})
for problem in list(older.property("problems").toVariant() or []):
    failures.append("older facade: " + str(problem))
older_counts = older.property("snapshot")
older_counts = older_counts.toVariant() if hasattr(older_counts, "toVariant") else older_counts
check((older_counts or {}).get("createTile") == 0, "older facade: no tree was created")
check((older_counts or {}).get("trackWindow") == 3, "older facade: the three open windows were tracked natively")
check(any("the native facade has no restoreWindow" in message for message in messages),
      "older facade: the tiler said why it stays off")

if failures:
    for failure in failures:
        print("FAIL tiling_lifecycle_test.py: " + failure)
    sys.exit(1)
print("tiling_lifecycle_test.py: ok")
