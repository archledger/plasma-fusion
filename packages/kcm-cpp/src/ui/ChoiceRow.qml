/*
    A setting row with a label on the left and the board's segmented control on the right, in the
    rhythm of the switch rows (1 px line under every row but the last). In a narrow window the
    control moves under the label. An optional note wraps under both.

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: row

    required property FusionPalette pal
    property string text
    property string note
    property bool last: false
    property alias model: control.model
    property alias currentIndex: control.currentIndex
    signal activated(int index)

    readonly property real rowHeight: pal.m.px(44)
    // Label and control side by side when both fit at their natural widths.
    readonly property bool stacked: label.implicitWidth + 16 + control.implicitWidth > width
    readonly property real controlTop: stacked ? label.y + label.implicitHeight + pal.m.px(6) : (rowHeight - control.height) / 2

    implicitWidth: label.implicitWidth + 16 + control.implicitWidth
    implicitHeight: (stacked ? controlTop + control.height + pal.m.px(8) : rowHeight)
        + (noteLabel.visible ? noteLabel.implicitHeight + pal.m.px(6) : 0) + (last ? 0 : 1)
    opacity: enabled ? 1 : 0.5

    Text {
        id: label
        anchors.left: parent.left
        width: row.stacked ? row.width : Math.max(0, row.width - control.width - 16)
        y: row.stacked ? row.pal.m.px(10) : (row.rowHeight - height) / 2
        elide: Text.ElideRight
        text: row.text
        font.family: row.pal.family
        font.pixelSize: row.pal.m.font(13)
        color: row.pal.text
        Accessible.ignored: true
    }

    Segmented {
        id: control
        pal: row.pal
        accessibleName: row.text
        anchors.right: parent.right
        width: row.stacked ? row.width : implicitWidth
        y: row.controlTop
        enabled: row.enabled
        onActivated: index => row.activated(index)
    }

    Text {
        id: noteLabel
        visible: row.note !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        y: (row.stacked ? row.controlTop + control.height + row.pal.m.px(4) : row.rowHeight - row.pal.m.px(4))
        wrapMode: Text.WordWrap
        text: row.note
        font.family: row.pal.family
        font.pointSize: 8.625 * row.pal.m.ts // 11.5 px (pixelSize is an integer)
        color: row.pal.section
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
