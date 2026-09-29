// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// 40 x 22 switch with an 18 px white knob (accent track when on).
T.Switch {
    id: control

    required property FusionPalette pal

    implicitWidth: 40
    implicitHeight: 22
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
        width: 40
        height: 22
        radius: 11
        color: control.checked ? control.pal.accent : control.pal.overlay(control.hovered ? 0.26 : 0.2)
        Behavior on color { ColorAnimation { duration: 140 } }

        Rectangle {
            x: control.checked ? parent.width - width - 2 : 2
            y: 2
            width: 18
            height: 18
            radius: 9
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        FocusRing {
            baseRadius: 11
            ringColor: control.pal.focus
            shown: control.visualFocus
        }
    }
    contentItem: Item {}
}
