// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.core as PlasmaCore

// Round button with a line icon (header buttons, chevrons, media controls). In touch mode the
// target is at least 44 x 44 (ADAPTIVE 5.3); the drawn circle keeps `size`.
T.AbstractButton {
    id: button

    required property FusionPalette pal
    property string iconPath: ""
    property string iconFillPath: ""
    property real iconSize: 17
    property real size: 34
    property color fill: pal.overlay(0.07)
    property color hoverFill: pal.overlay(0.12)
    property color pressFill: pal.overlay(0.16)
    property color iconColor: pal.controlText
    property string toolTip: text
    // A toggle drawn with the accent fill while on (the tablet row).
    property bool toggleOn: false
    // Smallest target (44 in touch mode).
    property real hitSize: pal.touch ? 44 : 0

    implicitWidth: Math.max(size, hitSize)
    implicitHeight: Math.max(size, hitSize)
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Accessible.role: Accessible.Button
    opacity: enabled ? 1 : 0.45

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()

    background: Rectangle {
        x: (button.width - width) / 2
        y: (button.height - height) / 2
        width: Math.min(button.width, button.size)
        height: Math.min(button.height, button.size)
        radius: height / 2
        color: button.toggleOn ? (button.down ? Qt.darker(button.pal.accent, 1.12) : button.pal.accent)
             : button.down ? button.pressFill : (button.hovered ? button.hoverFill : button.fill)
        Behavior on color {
            enabled: button.pal.motion.animate
            ColorAnimation { duration: button.pal.motion.hover }
        }

        FocusRing {
            baseRadius: parent.radius
            ringColor: button.pal.focus
            shown: button.visualFocus
        }
    }

    contentItem: Item {
        LineIcon {
            anchors.centerIn: parent
            size: button.iconSize
            path: button.iconPath
            fillPath: button.iconFillPath
            fillStroked: true
            color: button.toggleOn ? button.pal.accentText : button.iconColor
        }
    }

    // Touch: the label on a long press (there is no hover).
    onPressAndHold: buttonToolTip.showToolTip()

    PlasmaCore.ToolTipArea {
        id: buttonToolTip
        anchors.fill: parent
        mainText: button.toolTip
        active: button.toolTip.length > 0
        location: PlasmaCore.Types.Floating
    }
}
