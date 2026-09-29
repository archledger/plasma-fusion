/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

// One item of the hint bar: optional text, key caps joined by "+", then the action
// (board: gap 6 inside an item). Every piece is one key cap tall and centred on it.
Row {
    id: hint

    property string before: ""
    property string after: ""
    property var keys: []
    property FusionPalette pal
    property string fontFamily: "Manrope"
    readonly property int rowHeight: 22

    spacing: 6
    height: rowHeight

    component HintText: Text {
        height: hint.rowHeight
        verticalAlignment: Text.AlignVCenter
        font.family: hint.fontFamily
        font.pointSize: 9
        color: hint.pal.textMuted
        renderType: Text.QtRendering
    }

    HintText {
        visible: hint.before.length > 0
        text: hint.before
    }

    Repeater {
        model: hint.keys
        delegate: Row {
            id: keyRow
            required property int index
            required property string modelData
            height: hint.rowHeight
            spacing: 6

            HintText {
                visible: keyRow.index > 0
                text: "+"
            }

            Kbd {
                pal: hint.pal
                fontFamily: hint.fontFamily
                text: keyRow.modelData
            }
        }
    }

    HintText {
        visible: hint.after.length > 0
        text: hint.after
    }
}
