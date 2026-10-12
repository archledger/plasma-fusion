/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound
// The widget's root (`host`) is read through its own members (texts, levels), which the linter
// cannot see on a plain var.
// qmllint disable missing-property

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "../code/memory.js" as Memory
import "../code/meters.js" as Meters

// The meters' pop-up: a few more values than the bar has room for, in the style of the desktop
// system card (labels 12 px 700 in the secondary colour, figures 12 px 700, 5 px bars in #3cc4b0
// and #5b9dff on a .10 track) inside the frosted pop-up surface of the Plasma style, and a button
// for System Monitor. It shows every value its sensors give, whichever meters are in the bar.
//
// Keys: Tab reaches the button (it has the focus when the pop-up opens), Esc closes.
FocusScope {
    id: card

    required property Readings readings
    // The widget (main.qml): texts, warning levels and the region's temperature unit.
    required property var host

    signal closeRequested()
    signal openMonitorRequested()

    // Text scale and pixel grid of the pop-up window.
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    Motion {
        id: motion
    }
    FusionAccent {
        id: accent
    }

    // The pop-up's own colour set (it may differ from the panel's): text, secondary text drawn
    // from it (the High Contrast scheme stays high contrast), the card's bars.
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color secondary: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.72)
    readonly property color ink: dark ? "#ffffff" : "#141827"
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }
    function levelColor(level: int): color {
        return level >= 2 ? Kirigami.Theme.negativeTextColor : level === 1 ? Kirigami.Theme.neutralTextColor : textColor;
    }

    readonly property real contentWidth: m.px(260)
    implicitWidth: contentWidth + 2 * m.px(4)
    implicitHeight: column.implicitHeight + 2 * m.px(4)
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    Keys.onEscapePressed: card.closeRequested()

    // "6.1 / 15.3 GiB" in binary units, as System Monitor and the system card show it (memory.js).
    readonly property var memoryValue: Memory.memory(readings.memoryUsed, readings.memoryTotal)
    function memoryUnitText(unit: string): string {
        switch (unit) {
        case "KiB":
            return i18nc("@label memory unit, kibibytes", "KiB");
        case "MiB":
            return i18nc("@label memory unit, mebibytes", "MiB");
        case "GiB":
            return i18nc("@label memory unit, gibibytes", "GiB");
        case "TiB":
            return i18nc("@label memory unit, tebibytes", "TiB");
        case "PiB":
            return i18nc("@label memory unit, pebibytes", "PiB");
        }
        return i18nc("@label memory unit, bytes", "B");
    }
    readonly property string memoryText: memoryValue
        ? i18nc("@label used / total memory and its unit, e.g. 6.1 / 15.3 GiB", "%1 / %2 %3",
                Qt.locale().toString(memoryValue.used, "f", memoryValue.decimals),
                Qt.locale().toString(memoryValue.total, "f", memoryValue.decimals), memoryUnitText(memoryValue.unit))
        : "–"

    component Label: FusionText {
        metrics: m
        px: 12
        weight: 700
        color: card.secondary
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
    component Figure: FusionText {
        metrics: m
        px: 12
        weight: 700
        color: card.textColor
        font.features: { "tnum": 1 }
    }
    component Note: FusionText {
        metrics: m
        px: 11.5
        weight: 600
        color: card.secondary
        Layout.fillWidth: true
        elide: Text.ElideRight
    }
    // A 5 px bar, radius 2.5, on a .10 track (the system card's); a whole-pixel width, stepped.
    component Bar: Rectangle {
        id: track
        property real fraction: 0
        property color barColor
        Layout.fillWidth: true
        Layout.preferredHeight: 5
        radius: 2.5
        antialiasing: true
        color: card.tint(0.10)
        Rectangle {
            width: track.fraction > 0 ? Math.max(track.height, Math.round(track.width * Math.min(1, track.fraction))) : 0
            height: parent.height
            radius: 2.5
            antialiasing: true
            color: track.barColor
        }
    }
    // A label and its value on one row, read as one by a screen reader.
    component ValueRow: RowLayout {
        id: row
        property string label
        property string value
        property color valueColor: card.textColor
        Layout.fillWidth: true
        spacing: m.px(8)
        Accessible.role: Accessible.StaticText
        Accessible.name: label + " " + value
        Label {
            text: row.label
        }
        Figure {
            text: row.value
            color: row.valueColor
        }
    }

    ColumnLayout {
        id: column
        x: m.px(4)
        y: m.px(4)
        width: card.contentWidth
        spacing: m.px(12)

        FusionText {
            Layout.fillWidth: true
            metrics: m
            px: 15
            weight: 800
            color: card.textColor
            text: i18nc("@title the meters' pop-up", "System")
            Accessible.role: Accessible.Heading
            Accessible.name: text
        }

        // Processor
        ColumnLayout {
            Layout.fillWidth: true
            spacing: m.px(5)
            ValueRow {
                label: i18nc("@label processor load", "CPU")
                value: card.host.percentText(card.host.cpuPercent)
                valueColor: card.levelColor(card.host.cpuLevel)
                Accessible.name: card.host.accessibleName("cpu")
            }
            Bar {
                fraction: isNaN(card.host.cpuPercent) ? 0 : card.host.cpuPercent / 100
                barColor: card.host.cpuLevel > 0 ? card.levelColor(card.host.cpuLevel) : "#3cc4b0"
            }
            // (the row is kept while the count is not there yet, so the pop-up keeps its height)
            Note {
                text: Meters.valid(card.readings.cores) && card.readings.cores > 0
                    ? i18ncp("@info number of processor cores", "%1 core", "%1 cores", Math.round(card.readings.cores)) : " "
            }
        }

        // Memory
        ColumnLayout {
            Layout.fillWidth: true
            spacing: m.px(5)
            ValueRow {
                label: i18nc("@label", "Memory")
                value: card.memoryText
                valueColor: card.levelColor(card.host.memoryLevel)
                Accessible.name: card.host.accessibleName("memory") + (card.memoryValue ? ", " + card.memoryText : "")
            }
            Bar {
                fraction: isNaN(card.host.memoryPercent) ? 0 : card.host.memoryPercent / 100
                barColor: card.host.memoryLevel > 0 ? card.levelColor(card.host.memoryLevel) : "#5b9dff"
            }
            Note {
                text: isNaN(card.host.memoryPercent) ? " " : i18nc("@info memory in use in percent", "%1% in use", card.host.memoryPercent)
            }
        }

        // Network
        ColumnLayout {
            Layout.fillWidth: true
            spacing: m.px(5)
            ValueRow {
                label: i18nc("@label network download rate", "Download")
                value: card.host.rateText(card.host.downRate, false)
            }
            ValueRow {
                label: i18nc("@label network upload rate", "Upload")
                value: card.host.rateText(card.host.upRate, false)
            }
        }

        // Temperature: only where the machine has a CPU sensor (once a reading came, as in the
        // bar).
        ColumnLayout {
            Layout.fillWidth: true
            visible: card.host.temperatureSeen
            spacing: m.px(5)
            ValueRow {
                label: i18nc("@label", "CPU temperature")
                value: isNaN(card.host.degrees) ? "–" : card.host.degreesText(card.host.degrees)
                valueColor: card.levelColor(card.host.temperatureLevel)
                Accessible.name: card.host.accessibleName("temperature")
            }
            Note {
                text: i18nc("@info the temperature shown is the hottest core's", "Hottest core")
            }
        }

        T.AbstractButton {
            id: monitorButton
            Layout.fillWidth: true
            implicitHeight: m.px(32)
            focus: true
            focusPolicy: Qt.StrongFocus
            hoverEnabled: true
            text: i18nc("@action:button", "Open System Monitor")
            Accessible.name: text
            Accessible.role: Accessible.Button
            Keys.onReturnPressed: monitorButton.clicked()
            Keys.onEnterPressed: monitorButton.clicked()
            onClicked: card.openMonitorRequested()

            background: Rectangle {
                radius: height / 2
                color: card.tint(monitorButton.down ? 0.16 : monitorButton.hovered ? 0.12 : 0.08)
                Behavior on color {
                    enabled: motion.animate
                    ColorAnimation { duration: motion.hover }
                }
                // Keyboard focus: 2 px, 2 px outside.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: height / 2
                    color: "transparent"
                    border.width: 2
                    border.color: accent.focusRing
                    visible: monitorButton.visualFocus
                }
            }
            contentItem: FusionText {
                metrics: m
                px: 13
                weight: 700
                color: card.textColor
                horizontalAlignment: Text.AlignHCenter
                text: monitorButton.text
                elide: Text.ElideRight
            }
        }
    }
}
