// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Login board, top left: 28 px Space Grotesk time (600) and the date (Manrope 14 px, 700,
// #cdd3e4) on a shared baseline, 12 px apart.
Row {
    id: clock

    property date dateTime: new Date()

    readonly property var timeParts: PfStyle.timeParts(Qt.locale(), dateTime)
    readonly property string dateText: Qt.locale().toString(dateTime, PfStyle.dateFormatWithoutYear(Qt.locale()))

    spacing: 12

    Accessible.role: Accessible.StaticText
    Accessible.name: dateText + ", " + timeParts.main + (timeParts.suffix ? " " + timeParts.suffix : "")

    Text {
        id: timeLabel
        text: clock.timeParts.main + (clock.timeParts.suffix ? " " + clock.timeParts.suffix : "")
        color: PfStyle.text
        font.family: PfStyle.displayFont
        font.pixelSize: 28
        font.weight: Font.DemiBold
        textFormat: Text.PlainText
    }
    Text {
        anchors.baseline: timeLabel.baseline
        text: clock.dateText
        color: PfStyle.textMuted
        font.family: PfStyle.uiFont
        font.pixelSize: 14
        font.weight: Font.DemiBold
        font.styleName: PfStyle.bold
        textFormat: Text.PlainText
    }
}
