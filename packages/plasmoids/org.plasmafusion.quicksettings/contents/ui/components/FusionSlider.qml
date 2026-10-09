// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// Slider of the Quick Settings board: 8 px track, accent fill, 20 px white knob (28 px in touch
// mode, ADAPTIVE 5.3). In tablet posture (TABLET 4.6) it is a 44 px tall bar, radius 22, filled
// up to the value, and it moves relatively: a drag adds dx / width to the value and a tap does not
// jump.
T.Slider {
    id: slider

    required property FusionPalette pal
    property bool dimmed: false

    readonly property bool bar: pal.tablet
    readonly property real knobSize: pal.touch ? 28 : 20

    from: 0
    to: 1
    stepSize: 0.01
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    implicitWidth: 200
    implicitHeight: bar ? 44 : Math.max(28, knobSize)
    wheelEnabled: false

    Keys.onPressed: event => {
        if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            // At least one step: a slider of a few levels (keyboard backlight) moves by one.
            const step = (event.key === Qt.Key_PageUp ? 1 : -1) * Math.max(slider.stepSize, 0.1);
            slider.value = Math.max(slider.from, Math.min(slider.to, slider.value + step));
            slider.moved();
            event.accepted = true;
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const delta = (event.angleDelta.y || -event.angleDelta.x) * (event.inverted ? -1 : 1);
            const next = Math.max(slider.from, Math.min(slider.to, slider.value + (delta / 120) * Math.max(slider.stepSize, 0.05)));
            if (next !== slider.value) {
                slider.value = next;
                slider.moved();
            }
        }
    }

    // Tablet bar: relative drag over the whole bar; the template's own jump-to-press is covered.
    MouseArea {
        id: barDrag
        anchors.fill: parent
        // The slider itself is the accessible control; this is only its pointer surface.
        Accessible.ignored: true
        enabled: slider.bar
        visible: slider.bar
        preventStealing: true
        property real startX: 0
        property real startValue: 0
        onPressed: mouse => {
            startX = mouse.x;
            startValue = slider.value;
            slider.forceActiveFocus(Qt.MouseFocusReason);
        }
        onPositionChanged: mouse => {
            const span = slider.to - slider.from;
            const next = Math.max(slider.from, Math.min(slider.to, startValue + (mouse.x - startX) / Math.max(1, width) * span));
            if (Math.abs(next - slider.value) >= slider.stepSize / 2) {
                slider.value = next;
                slider.moved();
            }
        }
    }
    // The owners act on moved() and take `value` back from their model when `dragging` ends. The
    // bar's drag counts as pressed, and wheel and key steps count until the input pauses (600 ms):
    // they set `value` themselves, so without that the owner's binding would stay broken.
    readonly property bool dragging: pressed || barDrag.pressed || nudge.running
    Timer {
        id: nudge
        interval: 600
    }
    onMoved: {
        if (!pressed && !barDrag.pressed) {
            nudge.restart();
        }
    }

    background: Item {
        x: slider.leftPadding
        y: slider.topPadding + (slider.availableHeight - height) / 2
        width: slider.availableWidth
        height: slider.bar ? 44 : 8

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: slider.pal.overlay(slider.bar ? 0.10 : 0.14)
        }
        Rectangle {
            width: slider.bar ? Math.max(parent.height, slider.visualPosition * parent.width)
                              : Math.max(parent.height, slider.handle.x - slider.leftPadding + slider.handle.width / 2)
            height: parent.height
            radius: height / 2
            color: slider.bar ? slider.pal.accent : slider.pal.accentSoft
            opacity: slider.dimmed ? 0.5 : 1
        }
        FocusRing {
            visible: slider.bar
            baseRadius: parent.height / 2
            ringColor: slider.pal.focus
            shown: slider.bar && slider.visualFocus
        }
    }

    handle: Item {
        visible: !slider.bar
        x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
        y: slider.topPadding + (slider.availableHeight - height) / 2
        width: slider.bar ? 0 : slider.knobSize
        height: slider.bar ? 0 : slider.knobSize

        FusionShadow {
            anchors.fill: knob
            offset.y: 2
            blur: 6
            radius: knob.radius
            color: slider.pal.knobShadow
        }
        Rectangle {
            id: knob
            anchors.fill: parent
            radius: width / 2
            color: slider.pal.knob
            scale: slider.pressed ? 1.08 : 1
            Behavior on scale {
                enabled: slider.pal.motion.animate
                NumberAnimation { duration: slider.pal.motion.pressScale }
            }
        }
        FocusRing {
            baseRadius: parent.width / 2
            ringColor: slider.pal.focus
            shown: slider.visualFocus
        }
    }
}
