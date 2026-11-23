#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Run the real staged width budget with a stand-in clock and app-name widget.

QT_QPA_PLATFORM=offscreen dbus-run-session -- python3 width_budget_test.py STAGE_HOME
"""

import os
from pathlib import Path
import sys

os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

FIXTURE = """import QtQuick
import QtQuick.Layouts
Item {
    width: 1440
    height: 34
    property alias nameSpan: appName.nameSpan
    property alias partialSaving: appName.partialSaving
    readonly property int level: budget.level
    readonly property real nameHint: nameCell.sizeHint
    component Spacer: Item {
        property bool isAppletContainer: true
        property QtObject applet: QtObject {
            property QtObject plasmoid: QtObject {
                property string pluginName: "org.kde.plasma.panelspacer"
                property QtObject configuration: QtObject {
                    property bool expanding: true
                }
            }
        }
        Layout.fillWidth: true
    }
    GridLayout {
        anchors.fill: parent
        rows: 1
        columnSpacing: 0
        Item {
            id: nameCell
            property bool isAppletContainer: true
            property Item applet: Item {
                id: appName
                property int budgetLevel: 0
                property real nameSpan: 100
                property real partialSaving: 100
                function budgetSaving(at: int): real {
                    return at >= 7 ? nameSpan : at >= 3 ? Math.min(nameSpan, partialSaving) : 0;
                }
            }
            readonly property real sizeHint: 460 + appName.nameSpan - appName.budgetSaving(appName.budgetLevel)
            Layout.minimumWidth: sizeHint
            Layout.preferredWidth: sizeHint
            Layout.maximumWidth: sizeHint
        }
        Spacer {}
        Item {
            id: clock
            property int budgetLevel: 0
            property real pillWidth: 400
            function budgetSaving(at: int): real { return 0; }
            Layout.preferredWidth: pillWidth
        }
        Spacer {}
    }
    FusionMetrics { id: metrics }
    WidthBudget {
        id: budget
        clock: clock
        cell: clock
        metrics: metrics
        tablet: false
    }
}
"""

app = QGuiApplication(sys.argv[:1])
view = QQuickView()
view.resize(1440, 34)
ui = Path(sys.argv[1]).resolve() / ".local/share/plasma/plasmoids/org.plasmafusion.clockpill/contents/ui"
component = QQmlComponent(view.engine())
component.setData(FIXTURE.encode(), QUrl.fromLocalFile(str(ui / "WidthBudgetFixture.qml")))
bar = component.create()
assert bar is not None, "; ".join(error.toString() for error in component.errors())
bar.setParentItem(view.contentItem())
view.show()


def expect_level(level, reason):
    for _ in range(100):
        if bar.property("level") == level:
            break
        QTest.qWait(10)
    assert bar.property("level") == level, f"{reason}: expected {level}, got {bar.property('level')}"
    print("PASS", reason)


expect_level(3, "the long name does not fit and folds to the app icon")
before = bar.property("nameHint")
bar.setProperty("nameSpan", 25)
assert bar.property("nameHint") == before == 460, "the hidden name must not change the width hint"
expect_level(0, "the shorter name returns without a width-hint change")
bar.setProperty("nameSpan", 100)
expect_level(3, "a long name still folds again")

# A change to an earlier step must be noticed even if the saving at the current step is fixed.
bar.setProperty("partialSaving", 0)
expect_level(7, "the fully collapsed step is used when step 3 no longer fits")
before = bar.property("nameHint")
bar.setProperty("partialSaving", 80)
assert bar.property("nameHint") == before == 460, "step 7 keeps the same hint and saving"
expect_level(3, "an earlier step returns when only its hypothetical saving changes")
