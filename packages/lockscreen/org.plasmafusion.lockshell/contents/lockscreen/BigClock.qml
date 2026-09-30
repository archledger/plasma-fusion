// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Effects

// Lock board: the date (Manrope 20 px, 700) over a 148 px Space Grotesk clock (600,
// letter-spacing -0.02 em, line-height 1), 6 px apart, with a soft text shadow.
Item {
    id: clock

    required property FusionMetrics metrics
    property date dateTime: new Date()
    // The clock's size against the Lock board (148 px at 1440 x 900; ADAPTIVE 5.10: the screen's
    // proportion, 0.7 to 1.4). The date line follows the text scale instead.
    property real sizeScale: 1

    readonly property bool softwareRendering: GraphicsInfo.api === GraphicsInfo.Software
    readonly property var timeParts: PfStyle.timeParts(Qt.locale(), dateTime)
    readonly property string dateText: Qt.locale().toString(dateTime, PfStyle.dateFormatWithoutYear(Qt.locale()))

    // CSS line boxes: the date line is 27 px (Manrope's normal line height at 20 px), the
    // clock line exactly 148 px; glyphs sit centred in their line box as in the browser. The
    // date follows the user's text size; the clock does not.
    readonly property real dateLine: metrics.px(27)
    readonly property real clockLine: Math.round(148 * sizeScale)

    implicitWidth: Math.max(dateLabel.implicitWidth, timeRow.implicitWidth)
    implicitHeight: dateLine + 6 + clockLine

    Accessible.role: Accessible.StaticText
    Accessible.name: dateText + ", " + timeParts.main + (timeParts.suffix ? " " + timeParts.suffix : "")

    Item {
        id: content
        anchors.fill: parent

        layer.enabled: !clock.softwareRendering
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.35)
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
            blurMax: 20
            shadowBlur: 1.0
            autoPaddingEnabled: true
        }

        FontMetrics {
            id: dateMetrics
            font: dateLabel.font
        }
        FontMetrics {
            id: clockMetrics
            font: timeLabel.font
        }

        Text {
            id: dateLabel
            anchors.horizontalCenter: parent.horizontalCenter
            y: (clock.dateLine - (dateMetrics.ascent + dateMetrics.descent)) / 2
            text: clock.dateText
            color: PfStyle.text
            font.family: PfStyle.uiFont
            font.pixelSize: clock.metrics.font(20)
            font.weight: Font.DemiBold
            font.styleName: PfStyle.bold
            textFormat: Text.PlainText
        }

        Row {
            id: timeRow
            anchors.horizontalCenter: parent.horizontalCenter
            y: clock.dateLine + 6 + (clock.clockLine - (clockMetrics.ascent + clockMetrics.descent)) / 2
            spacing: Math.round(12 * clock.sizeScale)

            Text {
                id: timeLabel
                text: clock.timeParts.main
                color: PfStyle.text
                font.family: PfStyle.displayFont
                font.pixelSize: clock.clockLine
                font.weight: Font.DemiBold
                font.letterSpacing: -0.02 * clock.clockLine
                textFormat: Text.PlainText
                renderType: Text.QtRendering
            }
            Text {
                id: suffixLabel
                visible: text.length > 0
                anchors.baseline: timeLabel.baseline
                text: clock.timeParts.suffix
                color: PfStyle.text
                font.family: PfStyle.displayFont
                font.pixelSize: Math.round(44 * clock.sizeScale)
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
            }
        }
    }
}
