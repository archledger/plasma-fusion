// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// An action tile of the pen menu (PEN.md 3.3): 96 px tall, radius 16, a 36 px icon well at 12/12,
// the label (14 px, 800) at 12/53 and the subtitle (12 px, 70 %) at 12/72. The primary tile is
// filled with the accent.
T.AbstractButton {
    id: tile

    required property FusionMetrics metrics
    required property FusionAccent tint
    required property color ink
    property string iconPath: ""
    property string subtitle: ""
    property bool primary: false

    readonly property color fg: primary ? tint.fillText : ink

    implicitHeight: metrics.px(96)
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus

    Accessible.name: text
    Accessible.description: subtitle

    background: Rectangle {
        radius: tile.metrics.px(16)
        color: tile.primary ? tile.tint.fill : Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, tile.down ? 0.16 : tile.hovered ? 0.12 : 0.08)
        opacity: tile.primary && tile.down ? 0.85 : 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            color: "transparent"
            border.width: 2
            border.color: tile.tint.focusRing
            visible: tile.visualFocus
        }
    }

    contentItem: Item {
        Rectangle {
            x: tile.metrics.px(12)
            y: tile.metrics.px(12)
            width: tile.metrics.px(36)
            height: width
            radius: tile.metrics.px(10)
            color: tile.primary ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(tile.ink.r, tile.ink.g, tile.ink.b, 0.10)

            LineIcon {
                anchors.centerIn: parent
                size: tile.metrics.px(20)
                path: tile.iconPath
                color: tile.fg
            }
        }
        Text {
            x: tile.metrics.px(12)
            y: tile.metrics.px(53)
            width: parent.width - 2 * tile.metrics.px(12)
            text: tile.text
            color: tile.fg
            font.pixelSize: tile.metrics.font(14)
            font.weight: Font.ExtraBold
            // A long label or translation shrinks a little before it is cut.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.round(tile.metrics.font(12))
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Text {
            x: tile.metrics.px(12)
            y: tile.metrics.px(72)
            width: parent.width - 2 * tile.metrics.px(12)
            text: tile.subtitle
            color: tile.fg
            opacity: 0.7
            font.pixelSize: tile.metrics.font(12)
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.round(tile.metrics.font(10.5))
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()
}
