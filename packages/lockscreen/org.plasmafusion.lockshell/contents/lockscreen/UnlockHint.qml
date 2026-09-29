// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Lock board: "Press any key or click to unlock", a 320 x 48 glass pill with a lock icon.
// It is only a hint: a key press or click anywhere shows the prompt.
GlassPanel {
    id: hint

    property alias text: label.text

    implicitWidth: Math.max(320, row.implicitWidth + 48)
    implicitHeight: 48
    radius: 24
    fill: PfStyle.glassFillPill
    borderColor: PfStyle.glassBorderPill

    Accessible.role: Accessible.StaticText
    Accessible.name: label.text

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 10

        LineIcon {
            anchors.verticalCenter: parent.verticalCenter
            size: 18
            path: PfStyle.iconLock
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: PfStyle.text
            font.family: PfStyle.uiFont
            font.pixelSize: 14
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
            textFormat: Text.PlainText
        }
    }
}
