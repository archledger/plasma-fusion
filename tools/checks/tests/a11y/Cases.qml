// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture for tools/checks/a11y-lint.py: "expect: RULE" marks each line the lint must report;
// every other line must stay silent. Not a working component.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Item {
    QQC2.Button { text: "OK" }
    QQC2.ToolButton { icon.name: "edit" } // expect: control-name
    QQC2.ToolButton { icon.name: "edit"; Accessible.name: "Edit" }
    QQC2.Slider { from: 0 } // expect: control-name
    QQC2.Slider { Accessible { name: "Volume" } }
    QQC2.SpinBox { Kirigami.FormData.label: "Size:" }
    QQC2.TextField { placeholderText: "Search" }
    QQC2.TextField { text: "x" } // expect: control-name
    TextInput { readOnly: true }
    Rectangle {
        MouseArea { anchors.fill: parent } // expect: pointer-name
    }
    Rectangle {
        Accessible.name: "Card"
        MouseArea { anchors.fill: parent }
    }
    Rectangle { MouseArea { acceptedButtons: Qt.NoButton; hoverEnabled: true } }
    Rectangle { Accessible.ignored: true; MouseArea { anchors.fill: parent } }
    Item { TapHandler { onTapped: parent.forceActiveFocus() } } // expect: pointer-name
    Item { activeFocusOnTab: true } // expect: focus-name
    Item { activeFocusOnTab: true; Accessible.name: "Grid" }
    QQC2.Button { enabled: false }
    QQC2.Button { text: "Open"; MouseArea { anchors.fill: parent } }
    function make(): QQC2.MenuItem { return null; }
    FixtureButton { } // expect: component-name
    FixtureButton { text: "Go" }
    FixtureRow { }
    // QQC2.ToolButton { } in a comment is not code
}
