#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the shipped avatar inside a disc, as the login card and the account tiles show it.

QT_QPA_PLATFORM=offscreen python3 packages/sddm-theme/tests/avatar_test.py           (CI)
xvfb-run -a env PF_AVATAR_GL=1 python3 packages/sddm-theme/tests/avatar_test.py    (OpenGL)

The tile is a disc on the wallpaper, so nothing may be drawn outside the disc: the photo's square
corners showed on a real greeter (Debian testing, 2026-10-21). By default the software scene
graph renders, where Qt's effects draw nothing, so the photo must not be drawn at all (the tile
keeps its fill and initial). With PF_AVATAR_GL=1 and an X server with OpenGL (Mesa's llvmpipe
under Xvfb will do) the hardware scene graph renders and the photo must show inside the disc only.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

GL = os.environ.get("PF_AVATAR_GL") == "1"
if not GL:
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ["QT_QUICK_BACKEND"] = "software"
else:
    # Qt's render thread destroys a removed mask's layer; PySide6's QObject destruction hook then
    # waits for Python's GIL, which this thread holds while it waits for that render thread to sync:
    # a deadlock of the test harness only (the greeter is C++). The basic render loop has no thread.
    os.environ.setdefault("QSG_RENDER_LOOP", "basic")

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtGui import QColor, QGuiApplication, QImage  # noqa: E402
from PySide6.QtQuick import QQuickView, QSGRendererInterface  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402

HERE = Path(__file__).resolve().parent.parent


def main():
    app = QGuiApplication(sys.argv)
    checks = []

    def check(condition, message):
        checks.append(bool(condition))
        print(("PASS " if condition else "FAIL ") + message)

    with tempfile.TemporaryDirectory(prefix="sddm-avatar-") as tmp:
        root = Path(tmp)
        image = QImage(100, 100, QImage.Format_RGB32)
        image.fill(QColor("#aabbcc"))
        image.save(str(root / "photo.png"))
        subprocess.run(["bash", str(HERE / "build.sh"), tmp], check=True)
        harness = root / "avatar.qml"
        # The login card's avatar: a 100 px disc in the tile fill, the photo 4 px inside it, on a
        # black wallpaper stand-in.
        harness.write_text('''import QtQuick 2.15
import "plasmafusion" as Theme
Rectangle {
    width: 160; height: 160; color: "black"
    property url icon: ""
    property alias ready: photo.ready
    Rectangle {
        x: 20; y: 20; width: 100; height: 100; radius: 50; color: "#785bd4"
        Theme.CircularImage {
            id: photo
            anchors.fill: parent
            anchors.margins: 4
            source: parent.parent.icon
        }
    }
}
''')
        view = QQuickView()
        warnings = []
        view.engine().warnings.connect(lambda errors: warnings.extend(e.toString() for e in errors))
        view.setResizeMode(QQuickView.SizeRootObjectToView)
        view.setSource(QUrl.fromLocalFile(str(harness)))
        check(view.status() == QQuickView.Ready, "the staged avatar component loads")
        if view.status() != QQuickView.Ready:
            return 1
        view.resize(160, 160)
        view.show()
        QTest.qWait(150)
        software = view.rendererInterface().graphicsApi() == QSGRendererInterface.GraphicsApi.Software
        check(software != GL, f"the {'OpenGL' if GL else 'software'} scene graph renders")

        def near(color, want, tolerance=6):
            return all(abs(a - b) <= tolerance for a, b in zip(color.getRgb()[:3], QColor(want).getRgb()[:3]))

        # (26, 26) lies inside the photo's square but outside the disc (62 px from its centre)
        corner, centre = (26, 26), (70, 70)
        frame = view.grabWindow()
        check(near(frame.pixelColor(*centre), "#785bd4"), "an account without a photo keeps its tile fill")
        check(near(frame.pixelColor(*corner), "black"), "  and nothing is drawn outside the disc")

        view.rootObject().setProperty("icon", QUrl.fromLocalFile(str(root / "photo.png")))
        QTest.qWait(300)
        frame = view.grabWindow()
        check(near(frame.pixelColor(*corner), "black"),
              "with a photo, nothing is drawn outside the disc (no square corners)")
        if GL:
            check(view.rootObject().property("ready"), "the photo is ready through the circular mask")
            check(near(frame.pixelColor(*centre), "#aabbcc"), "the photo shows inside the disc")
        else:
            check(not view.rootObject().property("ready"),
                  "without effects (software scene graph) the photo is not ready, so the initial stays")
            check(near(frame.pixelColor(*centre), "#785bd4"), "  and the photo is not drawn at all")

        view.rootObject().setProperty("icon", QUrl())
        QTest.qWait(150)
        frame = view.grabWindow()
        check(near(frame.pixelColor(*centre), "#785bd4") and not view.rootObject().property("ready"),
              "removing the photo shows the tile fill again")
        check(not warnings, "avatar changes emit no QML warnings")
        for warning in warnings:
            print("QML", warning)
        view.close()
        view.setSource(QUrl())
        app.processEvents()
    print(f"SDDM avatar: {sum(checks)}/{len(checks)} passed")
    return 0 if all(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
