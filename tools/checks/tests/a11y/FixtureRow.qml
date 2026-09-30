// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Fixture for tools/checks/a11y-lint.py: a control that names itself from a bound property.
import QtQuick

Item {
    id: row
    readonly property string title: "Row"
    MouseArea {
        anchors.fill: parent
        Accessible.name: row.title
        Accessible.role: Accessible.Button
    }
}
