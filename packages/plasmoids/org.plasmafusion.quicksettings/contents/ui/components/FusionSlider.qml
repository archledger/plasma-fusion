// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Effects
import QtQuick.Templates as T

// Slider of the Quick Settings board: 8 px track, accent fill, 20 px white knob.
T.Slider {
    id: slider

    required property FusionPalette pal
    property bool dimmed: false

    from: 0
    to: 1
    stepSize: 0.01
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    implicitWidth: 200
    implicitHeight: 28
    wheelEnabled: false

    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            const step = event.key === Qt.Key_PageUp ? 0.1 : -0.1;
            slider.value = Math.max(slider.from, Math.min(slider.to, slider.value + step));
            slider.moved();
            event.accepted = true;
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const delta = (event.angleDelta.y || -event.angleDelta.x) * (event.inverted ? -1 : 1);
            const next = Math.max(slider.from, Math.min(slider.to, slider.value + (delta / 120) * 0.05));
            if (next !== slider.value) {
                slider.value = next;
                slider.moved();
            }
        }
    }

    background: Rectangle {
        x: slider.leftPadding
        y: slider.topPadding + (slider.availableHeight - height) / 2
        width: slider.availableWidth
        height: 8
        radius: 4
        color: slider.pal.overlay(0.14)

        Rectangle {
            width: Math.max(height, slider.handle.x - slider.leftPadding + slider.handle.width / 2)
            height: parent.height
            radius: 4
            color: slider.pal.accentSoft
            opacity: slider.dimmed ? 0.5 : 1
        }
    }

    handle: Item {
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + (slider.availableHeight - height) / 2
        width: 20
        height: 20

        RectangularShadow {
            anchors.fill: knob
            offset.y: 2
            blur: 6
            radius: knob.radius
            color: slider.pal.knobShadow
        }
        Rectangle {
            id: knob
            anchors.fill: parent
            radius: 10
            color: slider.pal.knob
            scale: slider.pressed ? 1.08 : 1
            Behavior on scale { NumberAnimation { duration: 100 } }
        }
        FocusRing {
            baseRadius: 10
            ringColor: slider.pal.focus
            shown: slider.visualFocus
        }
    }
}
