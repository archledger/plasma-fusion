// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// 40 x 22 switch with an 18 px white knob (accent track when on); 48 x 28 with a 24 px knob in
// touch mode (ADAPTIVE 5.3).
T.Switch {
    id: control

    required property FusionPalette pal

    readonly property real trackWidth: pal.touch ? 48 : 40
    readonly property real trackHeight: pal.touch ? 28 : 22
    implicitWidth: pal.touch ? 48 : 40
    implicitHeight: pal.touch ? 44 : 22
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text

    Keys.onReturnPressed: {
        control.toggle();
        control.toggled();
    }
    Keys.onEnterPressed: {
        control.toggle();
        control.toggled();
    }

    indicator: Rectangle {
        // Centred in a 44 px tall control in touch mode (the hit area).
        y: (control.height - height) / 2
        width: control.trackWidth
        height: control.trackHeight
        radius: height / 2
        color: control.checked ? control.pal.accent : control.pal.overlay(control.hovered ? 0.26 : 0.2)
        Behavior on color {
            enabled: control.pal.motion.animate
            ColorAnimation { duration: control.pal.motion.hover }
        }

        Rectangle {
            x: control.checked ? parent.width - width - 2 : 2
            y: 2
            width: parent.height - 4
            height: width
            radius: width / 2
            color: "#ffffff"
            Behavior on x {
                enabled: control.pal.motion.animate
                NumberAnimation { duration: control.pal.motion.toggle; easing.type: control.pal.motion.standardEasing }
            }
        }

        FocusRing {
            baseRadius: parent.radius
            ringColor: control.pal.focus
            shown: control.visualFocus
        }
    }
    contentItem: Item {}
}
