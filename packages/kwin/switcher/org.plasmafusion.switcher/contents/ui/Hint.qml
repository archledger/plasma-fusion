/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

// One item of the hint bar: optional text, key caps joined by "+", then the action
// (board: gap 6 inside an item). Every piece is one key cap tall and centred on it; sizes
// follow the user's text size.
Row {
    id: hint

    property string before: ""
    property string after: ""
    property var keys: []
    property FusionPalette pal
    property FusionMetrics metrics
    readonly property real rowHeight: metrics.px(22)

    spacing: metrics.px(6)
    height: rowHeight

    component HintText: Text {
        height: hint.rowHeight
        verticalAlignment: Text.AlignVCenter
        font.family: hint.metrics.family
        font.pointSize: hint.metrics.font(12) * 0.75
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
            spacing: hint.metrics.px(6)

            HintText {
                visible: keyRow.index > 0
                text: "+"
            }

            Kbd {
                pal: hint.pal
                metrics: hint.metrics
                text: keyRow.modelData
            }
        }
    }

    HintText {
        visible: hint.after.length > 0
        text: hint.after
    }
}
