// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// "Notifications | Controls": the switch between the tablet posture's two sheets (TABLET2 S1;
// research E-phone 4.2: move between the two without closing). Shown on top of the Notification
// Centre and of the controls sheet while the notifications have their own sheet; `current` is the
// sheet it sits on, a tap on the other one emits its request.
Rectangle {
    id: sheetSwitch

    required property FusionPalette pal
    required property var metrics
    // 0 = Notifications, 1 = Controls
    property int current: 0
    property color edge: pal.dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.10)

    signal notificationsRequested()
    signal controlsRequested()

    width: 2 * 132 + 8
    height: 44
    radius: 22
    color: pal.dark ? Qt.rgba(12 / 255, 15 / 255, 28 / 255, 0.72) : Qt.rgba(1, 1, 1, 0.78)
    border.width: 1
    border.color: edge

    Rectangle {
        x: 4 + sheetSwitch.current * 132
        y: 4
        width: 132
        height: 36
        radius: 18
        color: sheetSwitch.pal.dark ? "#2a3150" : "#e2e8f5"
    }
    Row {
        x: 4
        y: 4
        Repeater {
            model: [i18nc("@action:button tablet sheet switch", "Notifications"),
                    i18nc("@action:button tablet sheet switch", "Controls")]
            delegate: T.AbstractButton {
                id: segmentButton
                required property int index
                required property string modelData
                width: 132
                height: 36
                text: modelData
                Accessible.role: Accessible.PageTab
                Accessible.name: modelData
                Accessible.selected: index === sheetSwitch.current
                contentItem: Text {
                    text: segmentButton.modelData
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    color: segmentButton.index === sheetSwitch.current ? sheetSwitch.pal.text : sheetSwitch.pal.secondary
                    font.pixelSize: sheetSwitch.metrics.font(14)
                    font.weight: Font.DemiBold
                }
                onClicked: {
                    if (segmentButton.index === sheetSwitch.current) {
                        return;
                    }
                    if (segmentButton.index === 0) {
                        sheetSwitch.notificationsRequested();
                    } else {
                        sheetSwitch.controlsRequested();
                    }
                }
            }
        }
    }
}
