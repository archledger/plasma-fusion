// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

import "components"
import "components/Icons.js" as Icons

// Right side of the top bar: EN badge, phone, clipboard, the status pill and
// the notification bell (Main and Quick Settings boards). Heights, paddings, gaps and the
// icons in the row follow the user's text size (`metrics`), never taller than the panel row;
// radii and the unread dot do not. Every target reaches over the bar's whole height.
//
// Tablet posture (TABLET 4.3): the pill is 32 px (padding 16, gap 12, icons 18, battery % 14 px
// 800), the bell 44 x 44 (32 drawn, an 8 px unread dot), a keyboard button (44 x 44, 32 drawn)
// shows while the on-screen keyboard is available, the EN badge, phone and clipboard leave the
// bar (phone and clipboard get rows in the sheet), and in portrait the pill shows Wi-Fi and
// battery only. A 24 px pull-down (TouchScreen) on the pill or the bell opens the sheet (4.1).
// The top bar's width budget (the clock pill, ADAPTIVE 5.1) moves phone and clipboard at step 2
// and hides the battery % at step 6 (`budgetLevel`).
Item {
    id: bar

    required property var backend
    required property FusionMetrics metrics
    readonly property FusionPalette pal: backend.pal
    property bool popupOpen: false
    property bool tablet: false
    property int budgetLevel: 0
    // Space after the bell, before the panel's own margin (the board's distance to the edge).
    property real endPadding: 0
    // Drawn height of the pills and buttons: 26 px on the board, 32 in tablet posture.
    readonly property real rowHeight: Math.min(metrics.px(tablet ? 32 : 26), Math.max(1, height - (tablet ? 4 : 0)))
    // Hit height: the whole bar.
    readonly property real hitHeight: Math.max(rowHeight, height)
    readonly property bool phoneShown: backend.phone.shown && !backend.barCompact
    readonly property bool clipboardShown: backend.showClipboard && !backend.barCompact
    readonly property bool percentShown: backend.showBatteryPercent && budgetLevel < 6

    readonly property alias pill: pill
    readonly property alias bell: bellButton

    signal pillPressed()
    signal pillClicked()
    signal bellPressed()
    signal bellClicked()
    // A pull-down on the pill or the bell (touch).
    signal pulled(bool fromBell)

    implicitWidth: row.implicitWidth
    implicitHeight: metrics.px(34)

    // Width the bar gives up at a budget step, against step 0 (the clock pill's question).
    function budgetSaving(level: int): real {
        let saving = 0;
        if (level >= 2 && !tablet) {
            if (backend.phone.shown) {
                saving += phoneButton.implicitWidth + row.spacing;
            }
            if (backend.showClipboard) {
                saving += clipboardButton.implicitWidth + row.spacing;
            }
        }
        if (level >= 6 && backend.showBatteryPercent && backend.battery.present) {
            saving += percentMetrics.advanceWidth + batteryRow.spacing;
        }
        return Math.ceil(saving);
    }
    TextMetrics {
        id: percentMetrics
        font: percentLabel.font
        text: percentLabel.text
    }

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
        spacing: bar.metrics.px(bar.tablet ? 8 : 6)

        // ---- Keyboard layout badge
        T.AbstractButton {
            id: layoutBadge
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.kbd.shown && !bar.tablet
            implicitHeight: Math.min(bar.metrics.px(22), bar.rowHeight)
            implicitWidth: layoutLabel.implicitWidth + bar.metrics.px(16)
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
                metrics: bar.metrics
                text: layoutBadge.text
                horizontalAlignment: Text.AlignHCenter
                px: 11
                font.weight: Font.ExtraBold
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                // Touch synthesises hover: no tooltips in tablet posture (TABLET2 S1).
                active: !bar.tablet
                mainText: bar.backend.kbd.longName || bar.backend.kbd.label
                subText: bar.backend.kbd.count > 1 ? i18nc("@info:tooltip", "Click to switch to the next layout") : ""
            }
        }

        // ---- KDE Connect phone
        BarIconButton {
            id: phoneButton
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.phoneShown
            pal: bar.pal
            metrics: bar.metrics
            implicitHeight: bar.rowHeight
            iconPath: Icons.phone
            text: bar.backend.phone.deviceName
                  ? i18nc("@action:button %1 phone name", "%1 connected", bar.backend.phone.deviceName)
                  : i18nc("@action:button", "Phone connected")
            onClicked: bar.backend.phone.open()
        }

        // ---- Clipboard
        BarIconButton {
            id: clipboardButton
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.clipboardShown
            pal: bar.pal
            metrics: bar.metrics
            implicitHeight: bar.rowHeight
            iconPath: Icons.clipboard
            text: i18nc("@action:button", "Clipboard")
            onClicked: bar.backend.session.openClipboard()
        }

        // ---- On-screen keyboard (tablet posture, TABLET 4.3)
        T.AbstractButton {
            id: keyboardButton
            objectName: "keyboardButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.tablet && bar.backend.tabletPolicy !== null && bar.backend.tabletPolicy.oskAvailable
            implicitWidth: Math.max(44, bar.rowHeight)
            implicitHeight: bar.hitHeight
            focusPolicy: Qt.TabFocus
            hoverEnabled: true
            text: bar.backend.tabletPolicy && bar.backend.tabletPolicy.oskVisible ? i18nc("@action:button", "Hide the keyboard")
                                                                                   : i18nc("@action:button", "Show the keyboard")
            Accessible.name: text
            Keys.onReturnPressed: keyboardButton.clicked()
            Keys.onEnterPressed: keyboardButton.clicked()
            onClicked: bar.backend.tabletPolicy.toggleOsk()
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: bar.rowHeight
                    height: bar.rowHeight
                    radius: height / 2
                    color: bar.backend.tabletPolicy && bar.backend.tabletPolicy.oskVisible ? bar.pal.accent
                         : bar.pal.overlay(keyboardButton.down ? 0.16 : keyboardButton.hovered ? 0.12 : 0.08)
                    FocusRing {
                        baseRadius: parent.radius
                        ringColor: bar.pal.focus
                        shown: keyboardButton.visualFocus
                    }
                }
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    size: 18
                    path: Icons.keyboard
                    color: bar.backend.tabletPolicy && bar.backend.tabletPolicy.oskVisible ? bar.pal.accentText : bar.pal.text
                }
            }
        }

        // ---- System status pill
        T.AbstractButton {
            id: pill
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: bar.hitHeight
            implicitWidth: pillRow.implicitWidth + bar.metrics.px(bar.tablet ? 32 : 24)
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

            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width
                    height: bar.rowHeight
                    radius: height / 2
                    color: bar.popupOpen ? bar.pal.pillOpen : bar.pal.overlay(pill.down ? 0.16 : (pill.hovered ? 0.12 : 0.08))
                    border.width: bar.popupOpen ? 1 : 0
                    border.color: bar.pal.pillOpenEdge
                    Behavior on color {
                        enabled: bar.pal.motion.animate
                        ColorAnimation { duration: bar.pal.motion.hover }
                    }
                    FocusRing {
                        baseRadius: parent.radius
                        ringColor: bar.pal.focus
                        shown: pill.visualFocus
                    }
                }
            }

            contentItem: Item {}

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: bar.metrics.px(bar.tablet ? 12 : 10)

                NetworkGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.backend.net.available && bar.backend.net.kind !== "none"
                    pal: bar.pal
                    size: bar.metrics.px(bar.tablet ? 18 : 16)
                    kind: bar.backend.net.kind
                    level: bar.backend.net.level
                }
                VolumeGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    // Portrait tablet: Wi-Fi and battery only.
                    visible: bar.backend.audio.available && !(bar.tablet && bar.metrics.portrait)
                    pal: bar.pal
                    size: bar.metrics.px(bar.tablet ? 18 : 16)
                    volume: bar.backend.audio.volume
                    muted: bar.backend.audio.muted
                }
                Row {
                    id: batteryRow
                    anchors.verticalCenter: parent.verticalCenter
                    visible: bar.backend.battery.present
                    spacing: bar.metrics.px(5)
                    BatteryGlyph {
                        anchors.verticalCenter: parent.verticalCenter
                        pal: bar.pal
                        size: bar.metrics.px(bar.tablet ? 20 : 18)
                        percent: bar.backend.battery.percent
                        charging: bar.backend.battery.charging
                    }
                    FText {
                        id: percentLabel
                        anchors.verticalCenter: parent.verticalCenter
                        visible: bar.percentShown
                        pal: bar.pal
                        metrics: bar.metrics
                        text: i18nc("@info battery charge", "%1%", bar.backend.battery.percent)
                        px: bar.tablet ? 14 : 12
                        font.weight: bar.tablet ? Font.ExtraBold : Font.Bold
                        font.features: { "tnum": 1 }
                    }
                }
                LineIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !(bar.backend.net.available && bar.backend.net.kind !== "none")
                             && !bar.backend.audio.available && !bar.backend.battery.present
                    size: bar.metrics.px(16)
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
            PullDown {
                onPulled: bar.pulled(false)
            }

            PlasmaCore.ToolTipArea {
                id: pillToolTip
                anchors.fill: parent
                active: !bar.popupOpen && !bar.tablet
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
            // The drawn button, and in tablet posture the strip up to the board's end: the bell's
            // target runs on to the screen corner (E-phone 4.2: 56 px at the edges; a corner target).
            readonly property real core: bar.tablet ? Math.max(44, bar.rowHeight) : bar.metrics.px(30)
            readonly property real corner: bar.tablet ? row.spacing + bar.endPadding : 0
            anchors.verticalCenter: parent.verticalCenter
            visible: bar.backend.notif.available
            implicitWidth: core + corner
            implicitHeight: bar.hitHeight
            rightPadding: corner
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

            background: Item {
                Rectangle {
                    id: bellCircle
                    x: (bellButton.core - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: bar.tablet ? bar.rowHeight : parent.width
                    height: bar.rowHeight
                    radius: height / 2
                    color: bellButton.hovered || (bar.tablet && bellButton.down) ? bar.pal.overlay(bellButton.down ? 0.14 : 0.08) : "transparent"
                    FocusRing {
                        baseRadius: parent.radius
                        ringColor: bar.pal.focus
                        shown: bellButton.visualFocus
                    }
                }
            }
            contentItem: Item {
                LineIcon {
                    anchors.centerIn: parent
                    size: bar.metrics.px(bar.tablet ? 18 : 16)
                    path: bar.backend.dnd.active ? Icons.bellOff : Icons.bell
                    color: bar.pal.text
                }
                // The unread dot, at the drawn circle's top right.
                Rectangle {
                    readonly property real dot: bar.tablet ? 8 : 7
                    x: (parent.width + (bar.tablet ? bar.rowHeight : parent.width)) / 2 - (bar.tablet ? 4 : 6) - width
                    y: (parent.height - bar.rowHeight) / 2 + (bar.tablet ? 3 : 4)
                    width: dot
                    height: dot
                    radius: dot / 2
                    color: bar.pal.unreadDot
                    visible: bar.backend.notif.unread > 0 && !bar.backend.dnd.active
                }
            }
            PullDown {
                onPulled: bar.pulled(true)
            }
            PlasmaCore.ToolTipArea {
                anchors.fill: parent
                active: !bar.popupOpen && !bar.tablet
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

        // The board's distance to the screen edge behind the panel's own margin (part of the
        // bell's target in tablet posture).
        Item {
            visible: !bar.tablet || !bellButton.visible
            width: bar.endPadding
            height: 1
        }
    }

    // A pull-down of 24 px (TouchScreen) over a target (TABLET 4.1): a layer above the
    // button that holds only a passive grab until then, so taps still reach the button.
    component PullDown: Item {
        signal pulled()
        anchors.fill: parent
        z: 10
        DragHandler {
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            xAxis.enabled: false
            dragThreshold: 24
            onActiveChanged: {
                // (translation is still 0 when `active` turns true: use the press position)
                const dy = centroid.position.y - centroid.pressPosition.y;
                if (active && dy > 0) {
                    parent.pulled();
                }
            }
        }
    }

    component BarIconButton: T.AbstractButton {
        id: iconButton
        required property FusionPalette pal
        required property FusionMetrics metrics
        property string iconPath: ""
        implicitWidth: metrics.px(28)
        implicitHeight: metrics.px(26)
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
                size: iconButton.metrics.px(16)
                path: iconButton.iconPath
                color: iconButton.pal.text
            }
        }
        PlasmaCore.ToolTipArea {
            anchors.fill: parent
            active: !iconButton.pal.tablet
            mainText: iconButton.text
        }
    }
}
