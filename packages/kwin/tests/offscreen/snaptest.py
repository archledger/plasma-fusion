#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the built snap script and outline in Qt, with stand-in KWin objects.

QT_QPA_PLATFORM=offscreen python3 snaptest.py STAGE_HOME
"""
import os
import sys
import tempfile

from PySide6.QtCore import QObject, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from render import I18n


class Config(QObject):
    def __init__(self):
        super().__init__()
        self.settings = {"FillOtherHalf": False}

    @Slot(str, "QVariant", result="QVariant")
    def readConfig(self, key, fallback):
        return self.settings.get(key, fallback)

    @Slot(str, "QVariant")
    def setConfig(self, key, value):
        self.settings[key] = value


class TestFiles(QObject):
    """Writes the private kwinrc the outline's settings reader sees."""

    @Slot(str)
    def writeKwinrc(self, text):
        with open(os.path.join(config_home.name, "kwinrc"), "w") as f:
            f.write(text)


here = os.path.dirname(os.path.abspath(__file__))
config_home = tempfile.TemporaryDirectory(prefix="plasmafusion-snap-config-")
os.environ["XDG_CONFIG_HOME"] = config_home.name
app = QGuiApplication(sys.argv[:1])
engine = QQmlApplicationEngine()
engine.addImportPath(os.path.join(here, "stubs"))
i18n = I18n()
engine.rootContext().setContextObject(i18n)
config = Config()
engine.rootContext().setContextProperty("KWin", config)
test_files = TestFiles()
engine.rootContext().setContextProperty("testFiles", test_files)
engine.rootContext().setContextProperty("stageHome", os.path.abspath(sys.argv[1]))
engine.load(QUrl.fromLocalFile(os.path.join(here, "snap-geometry-harness.qml")))
if not engine.rootObjects():
    raise SystemExit("snap geometry harness failed to load")
root = engine.rootObjects()[0]
QTimer.singleShot(25000, app.quit)
getattr(root, "doneChanged").connect(app.quit)
app.exec()
if not root.property("done"):
    raise SystemExit("snap geometry harness timed out")
for line in root.property("results").toVariant():
    print(line)
print(f"snap geometry: {root.property('checks')} checks, {root.property('failures')} failures")
if not root.property("checks"):
    raise SystemExit("snap geometry harness ran no checks")
raise SystemExit(1 if root.property("failures") else 0)
