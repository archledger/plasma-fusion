/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// "All apps >" / "More >" / "< Back": 26 px pill, 12 px bold text and a 14 px chevron.
T.AbstractButton {
    id: pill

    property FusionColors pal
    property FusionMetrics metrics
    property bool back: false

    implicitWidth: row.implicitWidth + metrics.px(18)
    implicitHeight: metrics.px(26)
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    Accessible.role: Accessible.Button
    Accessible.name: text

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    background: Rectangle {
        radius: height / 2
        color: pill.hovered || pill.down ? pill.pal.pillHover : pill.pal.pill
        antialiasing: true

        FocusRing {
            visible: pill.visualFocus
            baseRadius: pill.height / 2
            ringColor: pill.pal.focusRing
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: pill.metrics.px(26)

        Row {
            id: row
            x: pill.metrics.px(pill.back ? 6 : 12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: pill.metrics.px(4)
            layoutDirection: pill.back ? Qt.RightToLeft : Qt.LeftToRight

            FusionText {
                anchors.verticalCenter: parent.verticalCenter
                text: pill.text
                color: pill.pal.textSecondary
                metrics: pill.metrics
                px: 12
                weight: 700
            }

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                name: pill.back ? "chevronLeft" : "chevronRight"
                size: pill.metrics.px(14)
                color: pill.pal.textSecondary
            }
        }
    }
}
