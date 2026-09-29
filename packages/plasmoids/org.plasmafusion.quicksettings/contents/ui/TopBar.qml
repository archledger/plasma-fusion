// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

import "components"
import "components/Icons.js" as Icons

// Right side of the top bar: EN badge, phone, clipboard, the status pill and
// the notification bell (Main and Quick Settings boards).
Item {
    id: bar

    required property var backend
    readonly property FusionPalette pal: backend.pal
    property bool popupOpen: false

    readonly property alias pill: pill
    readonly property alias bell: bellButton

    signal pillPressed()
    signal pillClicked()
    signal bellPressed()
    signal bellClicked()

    implicitWidth: row.implicitWidth
    implicitHeight: 34

    function formatDuration(ms) {
        const minutes = Math.round(ms / 60000);
        const h = Math.floor(minutes / 60);
        const m = minutes % 60;
        return h > 0 ? i18nc("@info remaining time, hours and minutes", "%1 h %2 min", h, m)
                     : i18nc("@info remaining time, minutes", "%1 min", m);
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        spacing: 6

        // ---- Keyboard layout badge
        T.AbstractButton {
            id: layoutBadge
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.kbd.shown
            implicitHeight: 22
            implicitWidth: layoutLabel.implicitWidth + 16
            focusPolicy: Qt.TabFocus
            hoverEnabled: true
            text: bar.backend.kbd.label
            Accessible.name: i18nc("@action:button %1 keyboard layout name", "Keyboard layout: %1", bar.backend.kbd.longName || bar.backend.kbd.label)
            Keys.onReturnPressed: bar.backend.kbd.next()
            onClicked: bar.backend.kbd.next()

            background: Rectangle {
                radius: 6
                color: layoutBadge.hovered ? bar.pal.overlay(0.08) : "transparent"
                border.width: 1
                border.color: bar.pal.overlay(0.18)
                FocusRing {
                    baseRadius: 6
                    ringColor: bar.pal.focus
                    shown: layoutBadge.visualFocus
                }
            }
            contentItem: FText {
                id: layoutLabel
                pal: bar.pal
                text: layoutBadge.text
                horizontalAlignment: Text.AlignHCenter
                px: 11
                font.weight: Font.ExtraBold
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                mainText: bar.backend.kbd.longName || bar.backend.kbd.label
                subText: bar.backend.kbd.count > 1 ? i18nc("@info:tooltip", "Click to switch to the next layout") : ""
            }
        }

        // ---- KDE Connect phone
        BarIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.phone.shown
            pal: bar.pal
            iconPath: Icons.phone
            text: bar.backend.phone.deviceName
                  ? i18nc("@action:button %1 phone name", "%1 connected", bar.backend.phone.deviceName)
                  : i18nc("@action:button", "Phone connected")
            onClicked: bar.backend.phone.open()
        }

        // ---- Clipboard
        BarIconButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.showClipboard
            pal: bar.pal
            iconPath: Icons.clipboard
            text: i18nc("@action:button", "Clipboard")
            onClicked: bar.backend.session.openClipboard()
        }

        // ---- System status pill
        T.AbstractButton {
            id: pill
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 26
            implicitWidth: pillRow.implicitWidth + 24
            focusPolicy: Qt.TabFocus
            hoverEnabled: true
            text: i18nc("@action:button", "System status")
            Accessible.name: text
            Accessible.description: pillToolTip.subText
            Accessible.role: Accessible.ButtonDropDown
            Keys.onReturnPressed: {
                bar.pillPressed();
                bar.pillClicked();
            }
            Keys.onEnterPressed: {
                bar.pillPressed();
                bar.pillClicked();
            }
            onPressed: bar.pillPressed()
            onClicked: bar.pillClicked()

            background: Rectangle {
                radius: 13
                color: bar.popupOpen ? bar.pal.pillOpen : bar.pal.overlay(pill.down ? 0.16 : (pill.hovered ? 0.12 : 0.08))
                border.width: bar.popupOpen ? 1 : 0
                border.color: bar.pal.pillOpenEdge
                Behavior on color { ColorAnimation { duration: 140 } }
                FocusRing {
                    baseRadius: 13
                    ringColor: bar.pal.focus
                    shown: pill.visualFocus
                }
            }

            contentItem: Item {}

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 10

                NetworkGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.backend.net.available && bar.backend.net.kind !== "none"
                    pal: bar.pal
                    size: 16
                    kind: bar.backend.net.kind
                    level: bar.backend.net.level
                }
                VolumeGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.backend.audio.available
                    pal: bar.pal
                    size: 16
                    volume: bar.backend.audio.volume
                    muted: bar.backend.audio.muted
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.backend.battery.present
                    spacing: 5
                    BatteryGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        pal: bar.pal
                        size: 18
                        percent: bar.backend.battery.percent
                        charging: bar.backend.battery.charging
                    }
                    FText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bar.backend.showBatteryPercent
                        pal: bar.pal
                        text: i18nc("@info battery charge", "%1%", bar.backend.battery.percent)
                        px: 12
                        font.weight: Font.Bold
                    }
                }
                LineIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !(bar.backend.net.available && bar.backend.net.kind !== "none")
                             && !bar.backend.audio.available && !bar.backend.battery.present
                    size: 16
                    path: Icons.settingsSmall
                    color: bar.pal.text
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                enabled: bar.backend.audio.available
                property real accumulated: 0
                onWheel: event => {
                    accumulated += (event.angleDelta.y || -event.angleDelta.x) * (event.inverted ? -1 : 1);
                    while (Math.abs(accumulated) >= 120) {
                        const step = accumulated > 0 ? 0.05 : -0.05;
                        bar.backend.audio.setVolume(Math.round((bar.backend.audio.volume + step) * 20) / 20);
                        accumulated -= accumulated > 0 ? 120 : -120;
                    }
                }
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: bar.backend.audio.toggleMute()
            }

            PlasmaCore.ToolTipArea {
                id: pillToolTip
                anchors.fill: parent
                active: !bar.popupOpen
                mainText: i18nc("@info:tooltip", "Quick settings")
                subText: {
                    const lines = [];
                    const net = bar.backend.net;
                    if (net.available) {
                        if (net.kind === "wired") {
                            lines.push(i18nc("@info:tooltip", "Wired connection"));
                        } else if (net.wifiDevice) {
                            lines.push(i18nc("@info:tooltip %1 Wi-Fi state or network", "Wi‑Fi: %1", net.subtitle));
                        }
                    }
                    const audio = bar.backend.audio;
                    if (audio.available) {
                        lines.push(audio.muted ? i18nc("@info:tooltip", "Volume: muted")
                                               : i18nc("@info:tooltip", "Volume: %1%", Math.round(audio.volume * 100)));
                    }
                    const battery = bar.backend.battery;
                    if (battery.present) {
                        let line = i18nc("@info:tooltip", "Battery: %1%", battery.percent);
                        if (battery.charging) {
                            line = i18nc("@info:tooltip", "Battery: %1%, charging", battery.percent);
                        } else if (!battery.pluggedIn && battery.remainingMsec > 0) {
                            line = i18nc("@info:tooltip %1 percent, %2 time", "Battery: %1%, %2 left", battery.percent,
                                         bar.formatDuration(battery.remainingMsec));
                        }
                        lines.push(line);
                    }
                    if (audio.available) {
                        lines.push(i18nc("@info:tooltip", "Scroll to change the volume, middle-click to mute"));
                    }
                    return lines.join("\n");
                }
            }
        }

        // ---- Notifications bell
        T.AbstractButton {
            id: bellButton
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.notif.available
            implicitWidth: 30
            implicitHeight: 26
            focusPolicy: Qt.TabFocus
            hoverEnabled: true
            text: bar.backend.notif.unread > 0
                  ? i18ncp("@action:button", "Notifications, %1 unread", "Notifications, %1 unread", bar.backend.notif.unread)
                  : i18nc("@action:button", "Notifications")
            Accessible.name: text
            Keys.onReturnPressed: {
                bar.bellPressed();
                bar.bellClicked();
            }
            Keys.onEnterPressed: {
                bar.bellPressed();
                bar.bellClicked();
            }
            onPressed: bar.bellPressed()
            onClicked: bar.bellClicked()

            background: Rectangle {
                radius: 13
                color: bellButton.hovered ? bar.pal.overlay(bellButton.down ? 0.14 : 0.08) : "transparent"
                FocusRing {
                    baseRadius: 13
                    ringColor: bar.pal.focus
                    shown: bellButton.visualFocus
                }
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    size: 16
                    path: bar.backend.dnd.active ? Icons.bellOff : Icons.bell
                    color: bar.pal.text
                }
                Rectangle {
                    x: parent.width - 6 - width
                    y: 4 - (bellButton.height - parent.height) / 2
                    width: 7
                    height: 7
                    radius: 3.5
                    color: bar.pal.unreadDot
                    visible: bar.backend.notif.unread > 0 && !bar.backend.dnd.active
                }
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                active: !bar.popupOpen
                mainText: i18nc("@info:tooltip", "Notifications")
                subText: {
                    if (bar.backend.dnd.active) {
                        return i18nc("@info:tooltip", "Do not disturb is on");
                    }
                    return bar.backend.notif.unread > 0
                        ? i18ncp("@info:tooltip", "%1 unread notification", "%1 unread notifications", bar.backend.notif.unread)
                        : i18nc("@info:tooltip", "No unread notifications");
                }
            }
        }
    }

    component BarIconButton: T.AbstractButton {
        id: iconButton
        required property FusionPalette pal
        property string iconPath: ""
        implicitWidth: 28
        implicitHeight: 26
        focusPolicy: Qt.TabFocus
        hoverEnabled: true
        Accessible.name: text
        Keys.onReturnPressed: iconButton.clicked()
        Keys.onEnterPressed: iconButton.clicked()
        background: Rectangle {
            radius: 8
            color: iconButton.hovered ? iconButton.pal.overlay(iconButton.down ? 0.14 : 0.08) : "transparent"
            FocusRing {
                baseRadius: 8
                ringColor: iconButton.pal.focus
                shown: iconButton.visualFocus
            }
        }
        contentItem: Item {
            LineIcon {
                anchors.centerIn: parent
                size: 16
                path: iconButton.iconPath
                color: iconButton.pal.text
            }
        }
        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            mainText: iconButton.text
        }
    }
}
