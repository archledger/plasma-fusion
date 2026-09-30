// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// The top-bar pen button (PEN.md 3.1): a round fill (32 px in tablet posture, the bar's 26 px row
// otherwise) with an 18 px pen glyph, inside a 44 px hit area in touch mode (FusionMetrics.hit).
// While the menu is open it takes the quick-settings pill's open look (accent at 35 % with a
// 1 px edge).
T.AbstractButton {
    id: button

    required property FusionMetrics metrics
    required property FusionAccent tint
    required property color ink
    property bool open: false

    readonly property real fill: metrics.px(metrics.tablet ? 32 : 26)

    implicitWidth: metrics.hit(fill)
    implicitHeight: metrics.hit(fill)
    hoverEnabled: true
    focusPolicy: Qt.TabFocus
    text: i18nc("@action:button", "Pen menu")
    Accessible.name: text
    Accessible.role: Accessible.Button

    background: Item {
        Rectangle {
            anchors.centerIn: parent
            width: button.fill
            height: width
            radius: width / 2
            color: button.open ? button.tint.soft(0.35)
                               : Qt.rgba(button.ink.r, button.ink.g, button.ink.b, button.down ? 0.16 : button.hovered ? 0.12 : 0.08)
            border.width: button.open ? 1 : 0
            border.color: Qt.rgba(button.tint.focusRing.r, button.tint.focusRing.g, button.tint.focusRing.b, 0.5)

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: button.tint.focusRing
                visible: button.visualFocus
            }
        }
    }
    contentItem: Item {
        LineIcon {
            anchors.centerIn: parent
            size: button.metrics.px(18)
            path: "M4 20l4.2-1 11-11a2.1 2.1 0 0 0-3-3l-11 11zM14.5 6.5l3 3"
            color: button.ink
        }
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
