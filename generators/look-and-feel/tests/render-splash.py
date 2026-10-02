#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed): render a built splash offscreen on the build machine.
#   QT_QPA_PLATFORM=offscreen FONTCONFIG_FILE=<conf with fonts/> render-splash.py Splash.qml STAGE OUT.png [ms]
import sys
from PySide6.QtCore import QUrl, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

app = QGuiApplication(sys.argv)
qml, stage, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
view = QQuickView()
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.resize(1440, 900)
view.setInitialProperties({"stage": stage})
view.setSource(QUrl.fromLocalFile(qml))
for error in view.errors():
    print("error:", error.toString())
view.show()


def grab():
    view.grabWindow().save(out)
    app.quit()


QTimer.singleShot(int(sys.argv[4]) if len(sys.argv) > 4 else 2500, grab)
app.exec()
