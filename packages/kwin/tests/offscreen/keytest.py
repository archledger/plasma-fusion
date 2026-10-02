#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen check: a key sent the way KWin sends it (to the first QQuickWindow below the
switcher object) right after the switcher is shown, before any frame, reaches the switcher.

    QT_QPA_PLATFORM=offscreen python3 keytest.py [PACKAGES_KWIN_DIR]

PACKAGES_KWIN_DIR defaults to packages/kwin of this checkout (test use only).
"""
import os, sys
from PySide6.QtCore import QTimer, QUrl, QEvent, Qt, QCoreApplication
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
OFF = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, OFF)
from render import I18n  # noqa: E402

pkgroot = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(REPO, "packages", "kwin")
app = QGuiApplication(sys.argv[:1])
engine = QQmlApplicationEngine()
engine.addImportPath(os.path.join(OFF, "stubs"))
i18n = I18n()
engine.rootContext().setContextObject(i18n)
for k, v in dict(count=5, otherDesktop=2, allDesktops=True, current=1, dark=True).items():
    engine.rootContext().setContextProperty(k, v)
engine.rootContext().setContextProperty("packagesRoot", pkgroot)
engine.load(QUrl.fromLocalFile(os.path.join(OFF, "switcher-harness.qml")))
root = engine.rootObjects()[0]
sw = root.property("switcher")
item = sw.property("item")


def send(label):
    w = sw.findChild(QQuickWindow)
    before = item.property("showAll")
    QCoreApplication.sendEvent(w, QKeyEvent(QEvent.KeyPress, Qt.Key_A, Qt.NoModifier, "a"))
    QCoreApplication.sendEvent(w, QKeyEvent(QEvent.KeyRelease, Qt.Key_A, Qt.NoModifier, "a"))
    after = item.property("showAll")
    print(f"{label}: key went to {w.title()!r}; showAll {before} -> {after}: {'handled' if after != before else 'LOST'}")


send("before the first frame")
QTimer.singleShot(1500, lambda: (send("card shown"), app.quit()))
app.exec()
