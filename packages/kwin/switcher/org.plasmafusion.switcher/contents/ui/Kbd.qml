/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// A key cap of the hint bar: padding 2 x 7, radius 6, 1 px edge, 12 px ExtraBold.
Rectangle {
    id: cap

    property alias text: label.text
    property FusionPalette pal
    property string fontFamily: "Manrope"

    implicitWidth: Math.round(label.implicitWidth) + 14
    implicitHeight: 22
    radius: 6
    color: pal.kbdFill
    border.width: 1
    border.color: pal.kbdEdge

    Text {
        id: label
        anchors.centerIn: parent
        font.family: cap.fontFamily
        font.pointSize: 9
        font.weight: Font.ExtraBold
        color: cap.pal.text
        renderType: Text.QtRendering
    }
}
