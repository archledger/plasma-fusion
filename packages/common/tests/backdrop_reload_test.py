#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""FusionBackdrop keeps its blur layer while its picture loads again.

  QT_QPA_PLATFORM=offscreen python3 packages/common/tests/backdrop_reload_test.py

Qt reloads an Image when the window's device pixel ratio changes, from inside the walk over the
window's items that tells each of them (QQuickWindow::physicalDpiChanged ->
updatePixelRatioHelper, which walks a copy of each item's children). The backdrop switched its
blur's layer on and off with the picture's readiness, so the reload switched the layer off in the
middle of the walk; the layer deleted its effect item, a sibling the walk still had to visit, and
plasmashell crashed (QQuickItem::flags on a deleted item) when the tablet launcher sheet or the
Notification Centre opened at the ThinkPad's 4/3 scale, or the scale changed while one was open.
A new size reloads the picture the same way: this checks that the layer is on with a picture and
does not change while the picture loads again, and that Solid glass still has no layer.
Needs PySide6 (Qt Quick, offscreen).
"""
import shutil
import sys
import tempfile
from pathlib import Path

from PySide6.QtCore import QObject, QUrl
from PySide6.QtGui import QColor, QGuiApplication, QImage
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[3]
COMMON = ROOT / "packages" / "common"
checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


ui = Path(tempfile.mkdtemp(prefix="pf-backdrop-reload-"))
shutil.copy(COMMON / "FusionBackdrop.qml", ui / "FusionBackdrop.qml")
picture = QImage(160, 100, QImage.Format.Format_RGB32)
picture.fill(QColor("#3b56a0"))
picture.save(str(ui / "wall.png"))
(ui / "Reload.qml").write_text("""import QtQuick
Item {
    id: root
    width: 1280
    height: 800
    property int layerChanges: 0
    FusionBackdrop { id: picked; objectName: "picked"; width: 640; height: 400; source: "wall.png"; dark: true }
    FusionBackdrop { id: solid; objectName: "solid"; y: 400; width: 640; height: 400; source: "wall.png"; glass: "solid" }
    function blurOf(backdrop: Item): Item {
        for (const child of backdrop.children) {
            if (child.objectName === "backdropBlur") {
                return child;
            }
        }
        return null;
    }
    readonly property bool layered: blurOf(picked) ? blurOf(picked).layer.enabled : false
    readonly property bool solidLayered: blurOf(solid) ? blurOf(solid).layer.enabled : true
    onLayeredChanged: layerChanges++
}
""")

app = QGuiApplication(sys.argv[:1])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(str(ui / "Reload.qml")))
if view.status() == QQuickView.Status.Error:
    print("FAIL Reload.qml did not load: " + "; ".join(e.toString() for e in view.errors()))
    sys.exit(1)
view.show()
root = view.rootObject()
picked = root.findChild(QObject, "picked")


def wait_ready(minimum_ms=0):
    waited = 0
    while waited < 4000:
        QTest.qWait(50)
        waited += 50
        if picked.property("ready") and waited >= minimum_ms:
            return True
    return False


check(wait_ready() and root.property("layered"), "a picture: the blur is drawn in its layer")
before = root.property("layerChanges")
picked.setProperty("width", 900)
QTest.qWait(30)
picked.setProperty("width", 1100)
wait_ready(500)
changes = root.property("layerChanges") - before
check(changes == 0 and root.property("layered"),
      "the layer stays on while the picture loads again at a new size (%d changes)" % changes)
check(root.property("solidLayered") is False, "Solid glass: no layer")
print(f"Backdrop reload: {checks} checks, {len(failures)} failures")
sys.exit(1 if failures else 0)
