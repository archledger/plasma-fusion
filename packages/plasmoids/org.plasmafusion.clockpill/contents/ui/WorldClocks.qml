// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.clock
import org.kde.plasma.private.digitalclock

ColumnLayout {
    id: clocks
    required property FusionMetrics metrics
    required property color textColor
    required property color secondaryColor
    property var zones: ["Local"]
    property string timeFormat: "HH:mm"
    property bool showSeconds: false
    spacing: metrics.px(6)
    FusionText {
        Layout.fillWidth: true
        metrics: clocks.metrics
        color: clocks.textColor
        px: 13
        weight: 800
        text: i18nc("@title:group", "Time zones")
        Accessible.role: Accessible.Heading
    }
    Repeater {
        model: clocks.zones
        delegate: RowLayout {
            id: row
            required property string modelData
            readonly property string zoneId: modelData
            readonly property date currentTime: zoneClock.dateTime
            Layout.fillWidth: true
            Clock {
                id: zoneClock
                timeZone: row.zoneId
                trackSeconds: clocks.showSeconds
            }
            FusionText {
                Layout.fillWidth: true
                metrics: clocks.metrics
                color: clocks.textColor
                px: 12
                text: row.zoneId === "Local" ? i18nc("@info time zone", "Local time") : TimeZonesI18n.i18nCity(row.zoneId)
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            ColumnLayout {
                spacing: 0
                FusionText {
                    metrics: clocks.metrics
                    color: clocks.textColor
                    px: 12
                    text: Qt.locale().toString(row.currentTime, clocks.timeFormat)
                }
                FusionText {
                    metrics: clocks.metrics
                    color: clocks.secondaryColor
                    px: 10.5
                    text: Qt.formatDate(row.currentTime, Qt.locale().dateFormat(Locale.ShortFormat))
                }
            }
        }
    }
}
