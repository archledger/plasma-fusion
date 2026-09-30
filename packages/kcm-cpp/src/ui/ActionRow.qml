/*
    An action at the end of the page: a title, a short explanation and a button (the button opens
    a confirmation first). Same rhythm and colours as the setting rows.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2

Item {
    id: row

    required property FusionPalette pal
    property string text
    property string description
    property string buttonText
    property string buttonIcon
    property bool last: false
    signal triggered

    readonly property bool stacked: Math.max(title.implicitWidth, 200) + 16 + button.implicitWidth > width
    readonly property real textWidth: stacked ? width : width - button.implicitWidth - 16

    implicitWidth: Math.max(title.implicitWidth, 200) + 16 + button.implicitWidth
    implicitHeight: (stacked ? details.y + details.implicitHeight + pal.m.px(8) + button.implicitHeight
                             : Math.max(details.y + details.implicitHeight, button.implicitHeight)) + pal.m.px(10) + (last ? 0 : 1)

    Text {
        id: title
        y: row.pal.m.px(10)
        width: row.textWidth
        wrapMode: Text.WordWrap
        text: row.text
        font.family: row.pal.family
        font.pixelSize: row.pal.m.font(13)
        color: row.pal.text
        Accessible.ignored: true
    }
    Text {
        id: details
        y: title.y + title.implicitHeight + row.pal.m.px(2)
        width: row.textWidth
        wrapMode: Text.WordWrap
        text: row.description
        font.family: row.pal.family
        font.pointSize: 8.625 * row.pal.m.ts // 11.5 px (pixelSize is an integer)
        color: row.pal.section
        Accessible.ignored: true
    }
    QQC2.Button {
        id: button
        x: row.stacked ? 0 : row.width - width
        y: row.stacked ? details.y + details.implicitHeight + row.pal.m.px(8) : row.pal.m.px(8)
        text: row.buttonText
        icon.name: row.buttonIcon
        enabled: row.enabled
        Accessible.description: row.description
        onClicked: row.triggered()
    }

    Rectangle {
        visible: !row.last
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: row.pal.rowLine
    }
}
