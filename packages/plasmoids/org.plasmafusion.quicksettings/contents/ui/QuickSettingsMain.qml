// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore

import "components"
import "components/Icons.js" as Icons

// Main page of the pop-up (Quick Settings board): battery chip and header
// buttons, volume and brightness sliders, six tiles and the media card.
ColumnLayout {
    id: page

    required property var backend
    required property FusionPalette pal

    signal openPage(string name, Item opener)

    readonly property alias firstFocusItem: screenshotButton
    readonly property alias wifiDetails: wifiTile.detailsButton
    readonly property alias bluetoothDetails: bluetoothTile.detailsButton
    readonly property alias audioDetails: audioChevron

    spacing: 14

    // ---------------------------------------------------------------- header row
    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 34
        spacing: 6

        Rectangle {
            id: batteryChip
            visible: page.backend.battery.present
            Layout.preferredHeight: 34
            Layout.preferredWidth: chipRow.implicitWidth + 24
            radius: 17
            color: chipHover.hovered ? page.pal.overlay(0.1) : page.pal.overlay(0.07)

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 6
                BatteryGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    pal: page.pal
                    size: 18
                    percent: page.backend.battery.percent
                    charging: page.backend.battery.charging
                }
                FText {
                    anchors.verticalCenter: parent.verticalCenter
                    pal: page.pal
                    text: i18nc("@info battery charge", "%1%", page.backend.battery.percent)
                    font.weight: Font.ExtraBold
                }
            }
            HoverHandler {
                id: chipHover
            }
            TapHandler {
                onTapped: page.backend.battery.openSettings()
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                location: PlasmaCore.Types.Floating
                mainText: i18nc("@info:tooltip", "Battery %1%", page.backend.battery.percent)
                subText: {
                    const b = page.backend.battery;
                    if (b.charging) {
                        return i18nc("@info:tooltip", "Charging");
                    }
                    if (b.full) {
                        return i18nc("@info:tooltip", "Fully charged");
                    }
                    if (b.pluggedIn) {
                        return i18nc("@info:tooltip", "Plugged in, not charging");
                    }
                    if (b.remainingMsec > 0) {
                        const minutes = Math.round(b.remainingMsec / 60000);
                        return i18nc("@info:tooltip %1 hours %2 minutes", "About %1 h %2 min left",
                                     Math.floor(minutes / 60), minutes % 60);
                    }
                    return "";
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }

        IconButton {
            id: screenshotButton
            pal: page.pal
            iconPath: Icons.screenshot
            text: i18nc("@action:button", "Take a screenshot")
            onClicked: page.backend.session.screenshot()
        }
        IconButton {
            pal: page.pal
            iconPath: Icons.settings
            text: i18nc("@action:button", "System Settings")
            onClicked: page.backend.session.openSystemSettings()
        }
        IconButton {
            pal: page.pal
            iconPath: Icons.lock
            text: i18nc("@action:button", "Lock the screen")
            enabled: page.backend.session.canLock
            onClicked: page.backend.session.lock()
        }
        IconButton {
            pal: page.pal
            iconPath: Icons.power
            text: i18nc("@action:button", "Shut down, restart or log out…")
            onClicked: page.backend.session.leave()
        }
    }

    // ---------------------------------------------------------------- sliders
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 10
        visible: page.backend.audio.available || page.backend.display.brightnessAvailable

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 12
            visible: page.backend.audio.available

            IconButton {
                id: muteButton
                pal: page.pal
                size: 28
                fill: "transparent"
                hoverFill: "transparent"
                pressFill: "transparent"
                iconSize: 18
                iconPath: ""
                text: page.backend.audio.muted ? i18nc("@action:button", "Unmute") : i18nc("@action:button", "Mute")
                onClicked: page.backend.audio.toggleMute()
                Layout.preferredWidth: 18
                Layout.preferredHeight: 28

                VolumeGlyph {
                    anchors.centerIn: parent
                    pal: page.pal
                    size: 18
                    baseColor: page.pal.controlText
                    volume: page.backend.audio.volume
                    muted: page.backend.audio.muted
                }
            }
            FusionSlider {
                id: volumeSlider
                Layout.fillWidth: true
                pal: page.pal
                dimmed: page.backend.audio.muted
                Accessible.name: i18nc("@label:slider", "Volume")
                value: Math.min(1, page.backend.audio.volume)
                onMoved: page.backend.audio.setVolume(value)
                onPressedChanged: {
                    if (!pressed) {
                        value = Qt.binding(() => Math.min(1, page.backend.audio.volume));
                    }
                }
                PlasmaCore.ToolTipArea {
                    anchors.fill: parent
                    location: PlasmaCore.Types.Floating
                    mainText: page.backend.audio.deviceName
                    subText: page.backend.audio.muted ? i18nc("@info:tooltip", "Muted")
                                                      : i18nc("@info:tooltip", "%1%", Math.round(page.backend.audio.volume * 100))
                }
            }
            IconButton {
                id: audioChevron
                pal: page.pal
                size: 28
                iconSize: 14
                iconPath: Icons.chevronRight
                text: i18nc("@action:button", "Choose audio output")
                onClicked: page.openPage("audio", audioChevron)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            spacing: 12
            visible: page.backend.display.brightnessAvailable

            LineIcon {
                Layout.preferredWidth: 18
                size: 18
                path: Icons.brightness
                color: page.pal.controlText
            }
            FusionSlider {
                id: brightnessSlider
                Layout.fillWidth: true
                pal: page.pal
                from: 0.01
                Accessible.name: i18nc("@label:slider", "Screen brightness")
                value: page.backend.display.brightness
                onMoved: page.backend.display.setBrightness(value)
                onPressedChanged: {
                    if (!pressed) {
                        value = Qt.binding(() => page.backend.display.brightness);
                    }
                }
            }
            Item {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
            }
        }
    }

    // ---------------------------------------------------------------- tiles
    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: 10
        columnSpacing: 10
        uniformCellWidths: true

        Tile {
            id: wifiTile
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Wi‑Fi")
            subtitle: page.backend.net.subtitle
            iconPath: Icons.wifi
            checked: page.backend.net.checked
            available: page.backend.net.available && page.backend.net.wifiDevice
            hasDetails: page.backend.net.available && page.backend.net.wifiDevice
            detailsText: i18nc("@action:button", "Show Wi‑Fi networks")
            onToggled: {
                if (available) {
                    page.backend.net.toggle();
                } else {
                    page.backend.net.openSettings();
                }
            }
            onDetailsRequested: page.openPage("wifi", wifiTile.detailsButton)
        }
        Tile {
            id: bluetoothTile
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Bluetooth")
            subtitle: page.backend.bt.subtitle
            iconPath: Icons.bluetooth
            checked: page.backend.bt.checked
            available: page.backend.bt.available
            hasDetails: page.backend.bt.available
            detailsText: i18nc("@action:button", "Show Bluetooth devices")
            onToggled: {
                if (available) {
                    page.backend.bt.toggle();
                } else {
                    page.backend.bt.openSettings();
                }
            }
            onDetailsRequested: page.openPage("bluetooth", bluetoothTile.detailsButton)
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Night light")
            subtitle: page.backend.night.subtitle
            iconPath: Icons.moon
            checked: page.backend.night.checked
            available: page.backend.night.available
            toolTip: page.backend.night.enabled ? i18nc("@info:tooltip", "Click to pause or resume Night Light")
                                                : i18nc("@info:tooltip", "Click to turn on Night Light")
            onToggled: page.backend.night.toggle()
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Do not disturb")
            subtitle: page.backend.dnd.subtitle
            iconPath: Icons.bellOff
            checked: page.backend.dnd.active
            available: page.backend.dnd.available
            onToggled: page.backend.dnd.toggle()
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Power mode")
            subtitle: page.backend.profile.subtitle
            iconPath: Icons.gauge
            checked: page.backend.profile.checked
            available: page.backend.profile.available
            toolTip: i18nc("@info:tooltip", "Click to switch between Power saver, Balanced and Performance")
            onToggled: page.backend.profile.cycle()
        }
        Tile {
            Layout.fillWidth: true
            pal: page.pal
            title: i18nc("@title tile", "Dark style")
            subtitle: page.backend.darkStyle.subtitle
            iconPath: Icons.contrast
            iconFillPath: Icons.contrastFill
            checked: page.backend.darkStyle.checked
            onToggled: page.backend.darkStyle.toggle()
        }
    }

    // ---------------------------------------------------------------- media card
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 64
        visible: page.backend.media.available
        radius: 16
        color: page.pal.overlay(0.06)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            spacing: 12

            Item {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44

                Kirigami.ShadowedImage {
                    id: albumArt
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: page.backend.media.artUrl
                    sourceSize.width: 88
                    sourceSize.height: 88
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    radius: 10
                }
                Kirigami.Icon {
                    anchors.fill: parent
                    visible: !albumArt.visible
                    source: page.backend.media.iconName || "emblem-music-symbolic"
                    fallback: "emblem-music-symbolic"
                }
                TapHandler {
                    enabled: page.backend.media.canRaise
                    onTapped: page.backend.media.raise()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    text: page.backend.media.title
                    font.weight: Font.ExtraBold
                }
                FText {
                    Layout.fillWidth: true
                    pal: page.pal
                    text: page.backend.media.subtitle
                    visible: text.length > 0
                    color: page.pal.secondary
                    px: 11.5
                }
            }

            IconButton {
                pal: page.pal
                size: 32
                iconSize: 16
                fill: "transparent"
                iconPath: Icons.previous
                enabled: page.backend.media.canPrevious
                text: i18nc("@action:button", "Previous track")
                onClicked: page.backend.media.previous()
            }
            IconButton {
                pal: page.pal
                size: 36
                iconSize: 16
                fill: page.pal.playFill
                hoverFill: Qt.lighter(page.pal.playFill, page.pal.dark ? 1.08 : 1.6)
                pressFill: Qt.darker(page.pal.playFill, 1.1)
                iconColor: page.pal.playGlyph
                iconFillPath: page.backend.media.playing ? Icons.pauseFill : Icons.play
                enabled: page.backend.media.canPlayPause
                text: page.backend.media.playing ? i18nc("@action:button", "Pause") : i18nc("@action:button", "Play")
                onClicked: page.backend.media.playPause()
            }
            IconButton {
                pal: page.pal
                size: 32
                iconSize: 16
                fill: "transparent"
                iconPath: Icons.next
                enabled: page.backend.media.canNext
                text: i18nc("@action:button", "Next track")
                onClicked: page.backend.media.next()
            }
        }
    }
}
