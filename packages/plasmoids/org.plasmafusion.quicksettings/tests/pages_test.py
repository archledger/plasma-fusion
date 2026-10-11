#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drive quick settings' drill-down pages in the staged real QML, with a stand-in backend.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 pages_test.py STAGE_HOME
(STAGE_HOME: the build's stage, `STAGE=... tools/build.sh quicksettings`; the pages need the shared
blocks the build copies into contents/ui/components.)
"""

import os
from pathlib import Path
import sys
import tempfile

os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QObject, QPoint, QPointF, Qt, QUrl, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtQuick import QQuickItem, QQuickView  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402


class Context(QObject):
    @Slot(str, result=str)
    def i18n(self, text):
        return text

    @Slot(str, str, result=str)
    def i18nc(self, context, text):
        return text



UI = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.quicksettings/contents/ui"
if not (UI / "components/FusionMetrics.qml").exists():
    raise SystemExit("Build the quick settings package into the stage first: " + str(UI))

# The profiles the stand-in daemon offers, the active one and the inhibition, as Backend.profile
# shows them (the row logic itself is contents/code/power.js, tests/power.test.js).
PROFILES = """
import QtQuick
import "%(ui)s"
import "%(ui)s/components"
import "%(ui)s/../code/power.js" as Power

Item {
    id: root
    width: 356
    height: 560
    // What the page asked the backend for, "; "-separated.
    property string calls: ""
    property var list: ["performance", "balanced", "power-saver"]
    property string active: "balanced"
    property string reason: "lap-detected"
    FusionPalette { id: pal }
    FusionMetrics { id: metrics }
    QtObject {
        id: backend
        property QtObject profile: QtObject {
            readonly property var list: root.list
            readonly property string active: root.active
            readonly property string inhibitionReason: root.reason
            property string failedProfile: ""
            readonly property var options: Power.options(list, active, inhibitionReason)
            readonly property string inhibitionNote: inhibitionReason ? "Performance mode has been disabled" : ""
            readonly property string note: [inhibitionNote, "Steam has requested Power saver"].filter(t => t !== "").join("\\n")
            function profileName(p: string): string { return p; }
            function setProfile(p: string) { root.calls += (root.calls ? "; " : "") + "set " + p; }
            function openSettings() { root.calls += (root.calls ? "; " : "") + "settings"; }
        }
    }
    ProfilesPage {
        id: page
        width: root.width
        backend: backend
        pal: pal
        metrics: metrics
    }
}
"""

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


def items(item: QQuickItem):
    yield item
    for child in item.childItems():
        yield from items(child)


def find(root, name):
    return next((i for i in items(root) if i.objectName() == name and i.isVisible()), None)


def click(view, item):
    point = item.mapToScene(QPointF(item.width() / 2, item.height() / 2))
    QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(round(point.x()), round(point.y())))
    QTest.qWait(50)


def load(text):
    tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
    tmp.write(text % {"ui": UI.as_uri()})
    tmp.close()
    view = QQuickView()
    view.rootContext().setContextObject(context)
    view.setSource(QUrl.fromLocalFile(tmp.name))
    os.unlink(tmp.name)
    if view.status() == QQuickView.Error:
        raise SystemExit("page failed to load: " + "; ".join(e.toString() for e in view.errors()))
    root = view.rootObject()
    view.resize(round(root.width()), round(root.height()))
    view.show()
    QTest.qWait(100)
    return view, root


app = QGuiApplication(sys.argv[:1])
context = Context()

# ---- Power mode chooser (P7)
view, root = load(PROFILES)
rows = [find(root, "profile-" + p) for p in ("power-saver", "balanced", "performance")]
check(all(rows), "the chooser lists the three profiles the daemon offers")
check(rows[1].property("selected") and rows[1].property("trailingPath") and not rows[0].property("trailingPath"),
      "the active profile is marked")
check(not rows[2].isEnabled() and rows[2].property("status") == "Unavailable",
      "inhibited Performance is listed as unavailable and cannot be chosen")
note = find(root, "profile-note")
check(note is not None and "disabled" in note.property("text") and "Steam has requested" in note.property("text"),
      "the reason and the holders show under the list")
click(view, rows[2])
check(root.property("calls") == "", "a click on inhibited Performance switches nothing")
click(view, rows[0])
check(root.property("calls") == "set power-saver", "a click on Power saver chooses it directly")
root.setProperty("reason", "")
QTest.qWait(50)
rows = [find(root, "profile-" + p) for p in ("power-saver", "balanced", "performance")]
check(rows[2].isEnabled() and find(root, "profile-note").property("text") == "Steam has requested Power saver",
      "without the inhibition Performance can be chosen and only the holder is named")
click(view, rows[2])
check(root.property("calls").endswith("set performance"), "a click on Performance chooses it")
root.setProperty("list", ["balanced", "power-saver"])
QTest.qWait(50)
check(find(root, "profile-performance") is None, "a profile the daemon does not offer is not listed")
view.close()

print(f"Quick settings pages: {checks} checks, 0 failures")
