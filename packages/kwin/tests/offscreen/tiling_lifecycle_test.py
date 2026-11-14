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

from PySide6.QtCore import QCoreApplication, QEvent, QObject, QTimer, QUrl, Slot, qInstallMessageHandler
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlContext, QQmlEngine

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


class KWinScript(QObject):
    """A declarative script as KWin makes and unloads one (src/scripting/scripting.cpp,
    DeclarativeScript): one object owns, in this order, the script's own context (a child of
    the engine's root context, carrying the KWin context property), the component, the KWin
    object and the script's root object. Unloading is deleteLater() on that object, and its
    children go in the order they came: the context first, so the script's
    Component.onDestruction runs while the context it was made in is being torn down."""

    def __init__(self, engine):
        super().__init__()
        self.context = QQmlContext(engine.rootContext(), self)
        self.component = QQmlComponent(engine, self)
        self.config = ScriptConfig()
        self.config.setParent(self)
        self.context.setContextProperty("KWin", self.config)

    def make(self, url):
        self.component.loadUrl(QUrl(url))
        if self.component.status() != QQmlComponent.Ready:
            print("FAIL tiling_lifecycle_test.py: the script did not load: "
                  + "; ".join(e.toString() for e in self.component.errors()))
            return None
        made = self.component.create(self.context)
        if made is not None:
            made.setParent(self)
        return made


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


def retire(instance, name):
    """End a run whose results have been read. The stand-in Workspace is one object for the
    whole engine, so a script left alive answers the next run's windows as well: with its
    own session, its own mock facade and its own lines in the journal.

    The script goes with a session live or just ended (its own untoggle on destruction): a
    throw on that path shows only as the engine's message, so the lines of the retirement
    are read for one. (Until 2026-11-14 one such line was let through, a readConfig of the
    engine's teardown: it was the script's own handler answering its teardown's writes, the
    path that crashed KWin, and no teardown reads a setting now.)"""
    before_retire = len(messages)
    instance.deleteLater()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    app.processEvents()
    thrown = [message for message in messages[before_retire:] if "TypeError" in message]
    check(not thrown, "%s: the script went without a throw, got %s" % (name, thrown))


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
# Seven accepted sessions (toggle, post-teardown toggle, teardown-proof toggle, the session whose
# admission lands the master, the first-desktop session, the invoked-view toggle, the
# ignored-member toggle) plus one refused create and one tree whose admission was refused; eight
# admissions, one of them refused; six releases (the run's own un-toggles, the invocation's
# teardown included, and the refused admission's tree - the native teardown releases nothing,
# the last session is left standing for the settle pass, and the destruction-time untoggle is
# outside the snapshot). Seven windows tracked: the three open at the start and the four the
# script saw open (the second desktop's master appears only as the tiler's target).
check(counts.get("registerProvider") == 1, "registerProvider once")
check(counts.get("createTile") == 9, "createTile nine times (7 sessions + 1 refused + 1 refused admission), got %s" % counts.get("createTile"))
check(counts.get("admitTile") == 8, "admitTile eight times, got %s" % counts.get("admitTile"))
check(counts.get("releaseTile") == 6, "releaseTile six times, got %s" % counts.get("releaseTile"))
check(counts.get("trackWindow") == 7, "trackWindow for the seven windows, got %s" % counts.get("trackWindow"))
# The mock's releaseTile reports the tree's end before it returns, as the compositor's does. The
# untoggle has ended its session by then: the run has one native teardown (the scenario that
# ends the tree behind the script's back), not one more for every release the script asked for.
check(teardowns == 1, "one native teardown in the run, got %s" % teardowns)

# Invariant 7, the ignore policy and the float record, after the settling pass fired: the only
# records are the live-joined windows' saved floats (c, d and g at their open geometries) and
# the master's own floating frame, recorded by its first toggle (the native layer admits a
# window from the place the memory has for its app) - never a cell or the tile's rectangle,
# nothing for the adopted stack windows, and nothing at all for the ignored app's second
# window (e) or the reflow-starved member's late cell commit (a).
recorded = [c for c in facade_calls if c["op"] == "record"]
expected_floats = {("c", 300, 500, 260, 260), ("d", 200, 300, 240, 200), ("g", 430, 150, 260, 300),
                   ("master", 40, 80, 620, 420)}
got_floats = {(c["window"], c["x"], c["y"], c["width"], c["height"]) for c in recorded}
check(got_floats == expected_floats,
      "only the joined windows' floats and the master's own were recorded (a cell, the tile, an ignored app and a late commit"
      " never were): got %s" % sorted(got_floats))

retire(harness, "first run")

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

retire(older, "older facade")

# A run against the facade of a fork build that restores but has neither floatingFrame nor
# settleWindow: the toggle records nothing of the window (the harness checks it), and a session
# starts and ends where the memory has the window's own place.
interim = run_harness({"interimFacade": True})
for problem in list(interim.property("problems").toVariant() or []):
    failures.append("interim facade: " + str(problem))
interim_counts = interim.property("snapshot")
interim_counts = interim_counts.toVariant() if hasattr(interim_counts, "toVariant") else interim_counts
check((interim_counts or {}).get("createTile") == 2 and (interim_counts or {}).get("admitTile") == 2
      and (interim_counts or {}).get("restoreWindow") == 1,
      "interim facade: one refused admission, one session started and restored, got %s" % interim_counts)
retire(interim, "interim facade")

# A third run: the master a native teardown released without restoring it (a removed desktop, a
# second window of its app, a move of the master). The harness asserts the geometry, the settle
# answers and the records step by step; the journal lines are checked here.
before = len(messages)
released = run_harness({"scenario": "released"})
for problem in list(released.property("problems").toVariant() or []):
    failures.append(str(problem))
journal = messages[before:]
settled = sum("a released master's record is settled" in message for message in journal)
held = sum("a released master has not settled; its record is held" in message for message in journal)
refused = sum("the admission was refused (7)" in message for message in journal)
check(settled == 13, "released: thirteen records were settled (returned, moved, re-checked, unresized, unmaximized, at the toggle, left alone,"
      " after its app's second window, in its quiet second, released in the gap, transferred, the display back, after a closed one),"
      " got %s" % settled)
check(held == 4, "released: four records were held (a drag held still, maximized, unanswered, no float to return to), got %s" % held)
check(refused == 1, "released: one admission stayed refused, after its retries, got %s" % refused)
check(sum("the tree was refused" in message for message in journal) == 1,
      "released: the newer press was refused once and the dropped retry asked for nothing")
# No TypeError in the run. The script was destroyed with a master's record held, then the
# master's drag ended and a tree ended: a callback left connected to the window or to the facade
# runs in a context that is gone and says so. And a reference to a destroyed window handed to
# the facade does not convert: the mock throws as the compositor does, from inside a signal
# handler, where only the engine's message shows it.
errors = [message for message in journal if "TypeError" in message]
check(not errors, "released: no call into a destroyed script and no destroyed window handed to the facade, got %s" % errors)
retire(released, "released")

# A fourth run: the script unloaded mid-session as KWin unloads a declarative script
# (KWinScript): its own context goes first, and the script's Component.onDestruction runs while
# that context is being torn down. In KWin a handler of the dying script that ran then and read
# a setting through the KWin context property crashed the compositor (2026-11-14); here the same
# read throws (KWin is gone), or the process crashes. Nothing of the script may run there but
# its own teardown: no TypeError and no ReferenceError at all, a readConfig one included. The
# harness checks that the session ended all the same and that nothing answers afterwards.
# The same with the master released by the native layer in between (unloadVacated): the
# teardown goes through the released master's settle, which records once it is settled.


def run_unload(name, initial):
    before = len(messages)
    holder = KWinScript(engine)
    unload = component.createWithInitialProperties(initial)
    state = {"made": False, "gone": False}

    def drive():
        if not state["made"] and unload.property("scriptWanted"):
            state["made"] = True
            unload.setProperty("kwinScript", holder.make(unload.property("scriptWanted")))
        if state["made"] and not state["gone"] and unload.property("unloadWanted"):
            state["gone"] = True
            holder.deleteLater()
            QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
            app.processEvents()
            unload.setProperty("unloaded", True)
        if unload.property("done"):
            QTimer.singleShot(300, app.quit)
        else:
            QTimer.singleShot(20, drive)

    QTimer.singleShot(20, drive)
    app.exec()
    for problem in list(unload.property("problems").toVariant() or []):
        failures.append(str(problem))
    check(state["gone"], "%s: the harness asked for the unload and the driver unloaded the script" % name)
    thrown = [message for message in messages[before:] if "TypeError" in message or "ReferenceError" in message]
    check(not thrown, "%s: nothing of the script ran in its dying context but its own teardown, got %s" % (name, thrown))
    retire(unload, name)


run_unload("unload", {"scenario": "unload"})
run_unload("unload (vacated)", {"scenario": "unload", "unloadVacated": True})

if failures:
    for failure in failures:
        print("FAIL tiling_lifecycle_test.py: " + failure)
    sys.exit(1)
print("tiling_lifecycle_test.py: ok")
