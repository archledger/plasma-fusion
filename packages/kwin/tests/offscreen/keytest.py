#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offscreen check: a key sent the way KWin sends it (to the first QQuickWindow below the
switcher object) right after the switcher is shown, before any frame, reaches the switcher.

    QT_QPA_PLATFORM=offscreen python3 keytest.py PACKAGES_KWIN_DIR

PACKAGES_KWIN_DIR is a staged harness directory whose switcher entry points to
STAGE/.local/share/kwin/tabbox. The source tree does not contain the shared QML blocks.
"""
import argparse
from pathlib import Path
import sys

from PySide6.QtCore import QCoreApplication, QEvent, QTimer, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow

from render import I18n

parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
parser.add_argument("packages_kwin_dir", type=Path, help="staged harness directory (switcher/<id>)")
pkgroot = parser.parse_args().packages_kwin_dir.resolve()
ui = pkgroot / "switcher/org.plasmafusion.switcher/contents/ui"
if not (ui / "main.qml").is_file() or not (ui / "FusionMetrics.qml").is_file():
    parser.error("expected a staged switcher; build kwin with tools/build.sh and point "
                 "PACKAGES_KWIN_DIR/switcher at STAGE/.local/share/kwin/tabbox")
here = Path(__file__).resolve().parent
app = QGuiApplication(sys.argv[:1])
engine = QQmlApplicationEngine()
engine.addImportPath(str(here / "stubs"))
i18n = I18n()
engine.rootContext().setContextObject(i18n)
for k, v in dict(count=5, otherDesktop=2, allDesktops=True, current=1, dark=True).items():
    engine.rootContext().setContextProperty(k, v)
engine.rootContext().setContextProperty("packagesRoot", str(pkgroot))
engine.load(QUrl.fromLocalFile(str(here / "switcher-harness.qml")))
roots = engine.rootObjects()
if not roots:
    raise SystemExit("switcher harness did not load")
sw = roots[0].property("switcher")
if sw is None:
    raise SystemExit("staged switcher did not instantiate")
item = sw.property("item")


def send(label):
    w = sw.findChild(QQuickWindow)
    if w is None or item is None:
        print(f"{label}: switcher window or focus item is missing", file=sys.stderr)
        return False
    before = item.property("showAll")
    QCoreApplication.sendEvent(w, QKeyEvent(QEvent.KeyPress, Qt.Key_A, Qt.NoModifier, "a"))
    QCoreApplication.sendEvent(w, QKeyEvent(QEvent.KeyRelease, Qt.Key_A, Qt.NoModifier, "a"))
    after = item.property("showAll")
    handled = after != before
    print(f"{label}: key went to {w.title()!r}; showAll {before} -> {after}: {'handled' if handled else 'LOST'}")
    return handled


def finish():
    second = send("card shown")
    app.exit(0 if first and second else 1)


first = send("before the first frame")
QTimer.singleShot(1500, finish)
sys.exit(app.exec())
