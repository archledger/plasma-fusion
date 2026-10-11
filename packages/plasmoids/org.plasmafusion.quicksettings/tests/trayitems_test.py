#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Drive services/TrayItems.qml (hidden tray items while active, P1) on Plasma's own types.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 tests/trayitems_test.py
A stand-in panel holds a stand-in system tray with stock item ids and a writable configuration,
as Plasma::Containment, Plasma::Applet and the tray's KConfigPropertyMap expose them to QML.
Requires PySide6 and Plasma's org.kde.plasma.core QML module.
"""

import os
from pathlib import Path
import sys
import tempfile

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtTest import QTest

SERVICES = (Path(__file__).resolve().parent.parent / "contents/ui/services").as_uri()
FIXTURE = """
import QtQuick
import org.kde.plasma.core as PlasmaCore
import "%s"

Item {
    id: root
    // PlasmaCore.Types.ItemStatus of each stock item; the tests set them.
    property int vault: PlasmaCore.Types.PassiveStatus
    property int printers: PlasmaCore.Types.HiddenStatus
    property int inputMethod: PlasmaCore.Types.PassiveStatus
    property bool tablet: false
    readonly property string shown: (config.shownItems || []).join(",")
    readonly property string revealed: service.revealed.join(",")
    function setDisabled(list) { config.disabledStatusNotifiers = list; }

    QtObject {
        id: config
        property var shownItems: ["org.example.app"]
        property var disabledStatusNotifiers: ["org.kde.plasma.vault", "org.kde.plasma.devicenotifier", "org.kde.kscreen",
            "org.kde.plasma.printmanager", "org.kde.plasma.manage-inputmethod", "org.kde.plasma.volume"]
    }
    QtObject { id: vaultApplet; readonly property string pluginName: "org.kde.plasma.vault"; readonly property int status: root.vault }
    QtObject { id: printApplet; readonly property string pluginName: "org.kde.plasma.printmanager"; readonly property int status: root.printers }
    QtObject { id: imApplet; readonly property string pluginName: "org.kde.plasma.manage-inputmethod"; readonly property int status: root.inputMethod }
    QtObject { id: displayApplet; readonly property string pluginName: "org.kde.kscreen"; readonly property int status: PlasmaCore.Types.PassiveStatus }
    QtObject { id: volumeApplet; readonly property string pluginName: "org.kde.plasma.volume"; readonly property int status: PlasmaCore.Types.ActiveStatus }
    QtObject {
        id: tray
        readonly property string pluginName: "org.kde.plasma.systemtray"
        readonly property var applets: [vaultApplet, printApplet, imApplet, displayApplet, volumeApplet]
        readonly property QtObject configuration: config
    }
    QtObject { id: clock; readonly property string pluginName: "org.plasmafusion.clockpill" }
    QtObject { id: panel; readonly property var applets: [clock, tray] }

    TrayItems {
        id: service
        containment: panel
        tablet: root.tablet
    }
}
""" % SERVICES

checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print("PASS", message)


app = QGuiApplication(sys.argv[:1])
engine = QQmlEngine()
tmp = tempfile.NamedTemporaryFile("w", suffix=".qml", delete=False)
tmp.write(FIXTURE)
tmp.close()
component = QQmlComponent(engine, QUrl.fromLocalFile(tmp.name))
root = component.create()
os.unlink(tmp.name)
if root is None:
    raise SystemExit("fixture did not load: " + "; ".join(e.toString() for e in component.errors()))
ACTIVE, PASSIVE, HIDDEN, ATTENTION = 2, 1, 6, 3


def settle():
    QTest.qWait(50)


settle()
check(root.property("shown") == "org.example.app" and root.property("revealed") == "",
      "all passive (one screen): the tray's shownItems stay the user's")
root.setProperty("vault", ACTIVE)
settle()
check(root.property("shown") == "org.example.app,org.kde.plasma.vault" and root.property("revealed") == "org.kde.plasma.vault",
      "an open vault (the applet's Active status) is put into shownItems")
root.setProperty("printers", ATTENTION)
settle()
check(root.property("revealed") == "org.kde.plasma.vault,org.kde.plasma.printmanager", "printers needing attention as well")
root.setProperty("vault", PASSIVE)
root.setProperty("printers", PASSIVE)
settle()
check(root.property("shown") == "org.example.app" and root.property("revealed") == "", "passive again: taken out, the user's entry kept")
root.setProperty("inputMethod", ACTIVE)
settle()
check(root.property("revealed") == "org.kde.plasma.manage-inputmethod", "the input-method switch while active")
root.setProperty("tablet", True)
settle()
check(root.property("revealed") == "" and root.property("shown") == "org.example.app", "but not in tablet posture")
root.setProperty("tablet", False)
root.setProperty("inputMethod", PASSIVE)
root.setProperty("vault", ACTIVE)
settle()
root.setProperty("printers", HIDDEN)
settle()
check(root.property("revealed") == "org.kde.plasma.vault" and "org.kde.plasma.volume" not in root.property("shown"),
      "an item that is not one of the hidden four (Volume, active) is never put into shownItems")
# The user chose a visibility for Vaults in the tray's settings: it left disabledStatusNotifiers.
root.setDisabled(["org.kde.kscreen", "org.kde.plasma.printmanager"])
root.setProperty("vault", PASSIVE)
settle()
check("org.kde.plasma.vault" in root.property("shown").split(","), "a vault the user shows (out of the hidden list) is left in shownItems")
print(f"Tray items: {checks} checks, 0 failures")
