/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as P5Support
import org.kde.ksysguard.sensors as Sensors
import org.kde.kirigami as Kirigami

// CPU and memory card of the Main board's desktop widgets: two labelled 5 px bars, CPU in teal
// (#3cc4b0) with its load in percent, memory in blue (#5b9dff) as "used / total GB". Values from
// ksystemstats through org.kde.ksysguard.sensors, as the stock system monitor widget reads them.
PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.StandardBackground
    preferredRepresentation: fullRepresentation
    // Text scale and pixel grid of the card (docs/parts/desktop-cards.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    }
    // Board card 192 x 92 minus the style's 14 px frame margins (the desktop's 16 px grid makes
    // the card 192 x 96), scaled with the text (the layout script sizes the card the same way).
    // Always the card itself: switchWidth/switchHeight would show the icon whenever the card is
    // not larger than them (libplasma appletShouldBeExpanded).
    readonly property int boardWidth: 164
    readonly property int boardHeight: 64
    readonly property real contentWidth: m.px(boardWidth)
    readonly property real contentHeight: m.px(boardHeight)

    readonly property int updateInterval: Math.max(1000, Plasmoid.configuration.updateInterval)

    Sensors.Sensor {
        id: cpuSensor
        sensorId: "cpu/all/usage"
        updateRateLimit: root.updateInterval
    }
    Sensors.Sensor {
        id: memUsed
        sensorId: "memory/physical/used"
        updateRateLimit: root.updateInterval
    }
    Sensors.Sensor {
        id: memTotal
        sensorId: "memory/physical/total"
        updateRateLimit: root.updateInterval
    }

    readonly property bool cpuValid: typeof cpuSensor.value === "number" && isFinite(cpuSensor.value)
    readonly property real cpu: cpuValid ? Math.max(0, Math.min(100, cpuSensor.value)) : 0
    readonly property bool memValid: typeof memUsed.value === "number" && typeof memTotal.value === "number"
                                     && memTotal.value > 0
    readonly property real memFraction: memValid ? Math.max(0, Math.min(1, memUsed.value / memTotal.value)) : 0

    readonly property real gib: 1024 * 1024 * 1024
    readonly property string cpuText: cpuValid ? i18nc("@label CPU load in percent", "%1%", Math.round(cpu)) : "–"
    readonly property string memoryText: {
        if (!memValid) {
            return "–";
        }
        const used = memUsed.value / gib;
        // The installed size: the kernel reports a little less than the modules hold (firmware
        // and graphics reservations), so the total is rounded up to whole GB.
        const total = memTotal.value / gib;
        const totalText = total >= 2 ? Math.ceil(total - 0.05).toString() : Qt.locale().toString(total, "f", 1);
        return i18nc("@label used / total memory in GB, e.g. 6.1 / 16 GB", "%1 / %2 GB",
                     Qt.locale().toString(used, "f", 1), totalText);
    }

    Plasmoid.icon: "utilities-system-monitor"
    toolTipMainText: i18nc("@title", "CPU and memory")

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        onNewData: sourceName => disconnectSource(sourceName)
    }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action", "Open System Monitor")
            icon.name: "utilities-system-monitor"
            // kstart hands the application to KIO and exits, so nothing stays a child of the shell.
            onTriggered: launcher.connectSource("kstart --application org.kde.plasma-systemmonitor")
        }
    ]

    fullRepresentation: FocusScope {
        id: card

        // The minimum never exceeds the board size: the desktop keeps a widget at least as large
        // as its minimum and stores the enlarged geometry, so a text size seen only for a moment
        // (the shell's font while a Global Theme is being applied) would grow the card for good.
        // The layout script gives the card the scaled size (docs/parts/desktop-cards.md).
        Layout.minimumWidth: Math.min(root.contentWidth, root.boardWidth)
        Layout.minimumHeight: Math.min(root.contentHeight, root.boardHeight)
        Layout.preferredWidth: root.contentWidth
        Layout.preferredHeight: root.contentHeight
        // 1 px of slack: the snapped sizes at fractional scales are a fraction of a pixel larger.
        readonly property real fitScale: Math.min(1, (width + 1) / root.contentWidth, (height + 1) / root.contentHeight)

        CardPalette { id: cardPalette }

        component Meter: ColumnLayout {
            id: meter
            property string label
            property string value
            property real fraction: 0
            property color barColor

            Layout.fillWidth: true
            spacing: m.px(5)
            Accessible.role: Accessible.ProgressBar
            Accessible.name: label + " " + value

            RowLayout {
                Layout.fillWidth: true
                spacing: m.px(8)
                CardText {
                    pal: cardPalette
                    metrics: m
                    Layout.fillWidth: true
                    px: 12
                    weight: 700
                    color: cardPalette.label
                    text: meter.label
                }
                CardText {
                    pal: cardPalette
                    metrics: m
                    px: 12
                    weight: 700
                    text: meter.value
                }
            }
            // 5 px track and bar, radius 3 (board), the bar glides to each new value.
            Rectangle {
                id: track
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 2.5
                antialiasing: true
                color: cardPalette.tint(0.10)

                // Whole pixels, so a change too small to see changes nothing.
                readonly property real target: meter.fraction > 0 ? Math.max(height, Math.round(width * meter.fraction)) : 0
                // Every animation frame redraws the whole desktop (wallpaper and blurred cards),
                // also under windows: a 600 ms glide every 2 s kept plasmashell at 3-5 % of a core
                // (0.6 % without animation). So the glide takes one standard duration and only
                // changes of 3 px or more glide; the idle load's small jitter just steps.
                onTargetChanged: {
                    glide.stop();
                    if (Kirigami.Units.longDuration > 0 && bar.width > 0 && Math.abs(target - bar.width) >= 3) {
                        glide.to = target;
                        glide.start();
                    } else {
                        bar.width = target;
                    }
                }
                // A new width of the card (edit mode) applies at once.
                onWidthChanged: {
                    glide.stop();
                    bar.width = target;
                }

                Rectangle {
                    id: bar
                    width: 0
                    height: parent.height
                    radius: 2.5
                    antialiasing: true
                    color: meter.barColor
                }
                NumberAnimation {
                    id: glide
                    target: bar
                    property: "width"
                    duration: Kirigami.Units.longDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        ColumnLayout {
            // Board: 16 px padding + 1 px edge from the card side (the style's frame gives 14).
            // Laid out across the card; when the desktop gave the card less than this text size
            // needs (the text size was raised after the layout was made), laid out at the size
            // it needs and scaled down to fit, so nothing is cut off.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: (card.fitScale < 1 ? root.contentWidth : parent.width) - 2 * 3
            scale: card.fitScale
            spacing: m.px(10)

            Meter {
                label: i18nc("@label processor load", "CPU")
                value: root.cpuText
                fraction: root.cpu / 100
                barColor: cardPalette.cpu
            }
            Meter {
                label: i18nc("@label", "Memory")
                value: root.memoryText
                fraction: root.memFraction
                barColor: cardPalette.memory
            }
        }
    }
}
