#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the shipped avatar through source/fill changes, without a live greeter.

QT_QPA_PLATFORM=offscreen python3 packages/sddm-theme/tests/avatar_test.py
Uses the software scene graph so pixel assertions need no GPU or display server.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile

os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_QUICK_BACKEND"] = "software"

from PySide6.QtCore import QUrl  # noqa: E402
from PySide6.QtGui import QColor, QGuiApplication, QImage  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402
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
        harness.write_text('''import QtQuick 2.15
import "plasmafusion" as Theme
Rectangle {
    width: 160; height: 160; color: "black"
    property url icon: ""
    property color maskFill: "#785bd4"
    Rectangle {
        x: 20; y: 20; width: 100; height: 100; color: parent.maskFill
        Theme.CircularImage {
            anchors.fill: parent
            source: parent.parent.icon
            fill: parent.parent.maskFill
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
        QTest.qWait(80)
        check(view.grabWindow().pixelColor(24, 24) == QColor("#785bd4"),
              "an account without a photo keeps its tile fill")

        view.rootObject().setProperty("icon", QUrl.fromLocalFile(str(root / "photo.png")))
        QTest.qWait(80)
        frame = view.grabWindow()
        check(frame.pixelColor(70, 70) == QColor("#aabbcc"), "the new account photo is displayed")
        check(frame.pixelColor(24, 24) == QColor("#785bd4"),
              "switching from no photo repaints the circular mask")

        view.rootObject().setProperty("maskFill", QColor("#112233"))
        QTest.qWait(80)
        check(view.grabWindow().pixelColor(24, 24) == QColor("#112233"),
              "a changed tile fill repaints the mask corners")
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
