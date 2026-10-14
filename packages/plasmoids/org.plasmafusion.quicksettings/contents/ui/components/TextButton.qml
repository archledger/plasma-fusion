// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Templates as T

// Rounded text button ("Clear all", "Disconnect", notification actions). Height, paddings and
// text follow the user's text size (`metrics`); callers pass board values.
T.AbstractButton {
    id: button

    required property FusionPalette pal
    required property FusionMetrics metrics
    property bool primary: false
    // The drawn shape keeps the text size's height while the target may be 44 px tall in touch
    // mode; the radius follows the shape, so an enlarged target does not turn a button into a pill
    // (IconButton keeps its circle the same way).
    readonly property real drawnHeight: metrics.px(26)
    // The caller's target height (the drawn shape keeps `drawnHeight`): callers pass their board
    // value here instead of overriding `implicitHeight`, so the touch floor below always applies.
    property real targetHeight: drawnHeight
    property real radius: drawnHeight / 2
    property real sidePadding: metrics.px(12)
    property real fontSize: 12
    property int fontWeight: Font.Bold
    property color fill: primary ? pal.accent : pal.overlay(0.1)
    property color textColor: primary ? pal.accentText : pal.text
    property string iconPath: ""
    // The ring also when an owner moves a keyboard selection over the button without focusing it
    // (the clipboard sheet's row actions, chosen with the arrow keys on the list).
    property bool highlighted: false

    // In touch mode the target is at least 44 px (ADAPTIVE 5.3), the drawn shape keeps the text
    // size's height: IconButton and the sheet's other controls grow the same way.
    implicitHeight: Math.max(targetHeight, pal.touch ? 44 : 0)
    implicitWidth: label.implicitWidth + 2 * sidePadding + (iconPath.length > 0 ? metrics.px(20) : 0)
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    Accessible.name: text
    Accessible.role: Accessible.Button
    opacity: enabled ? 1 : 0.5

    Keys.onReturnPressed: button.clicked()
    Keys.onEnterPressed: button.clicked()

    background: Rectangle {
        // The drawing, not the target: touch mode's 44 px box keeps a text-height pill inside.
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: button.drawnHeight
        radius: button.radius
        color: {
            if (button.primary) {
                return button.down ? Qt.darker(button.fill, 1.12) : (button.hovered ? Qt.lighter(button.fill, 1.1) : button.fill);
            }
            if (button.down) {
                return Qt.rgba(button.fill.r, button.fill.g, button.fill.b, Math.min(1, button.fill.a + 0.08));
            }
            return button.hovered ? Qt.rgba(button.fill.r, button.fill.g, button.fill.b, Math.min(1, button.fill.a + 0.05)) : button.fill;
        }
        Behavior on color {
            enabled: button.pal.motion.animate
            ColorAnimation { duration: button.pal.motion.hover }
        }

        FocusRing {
            baseRadius: button.radius
            ringColor: button.pal.focus
            shown: button.visualFocus || button.highlighted
        }
    }

    contentItem: Item {
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight
        Row {
            id: row
            anchors.centerIn: parent
            spacing: button.metrics.px(6)
            LineIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: button.iconPath.length > 0
                size: button.metrics.px(14)
                path: button.iconPath
                color: button.textColor
            }
            FText {
                id: label
                pal: button.pal
                metrics: button.metrics
                anchors.verticalCenter: parent.verticalCenter
                text: button.text
                color: button.textColor
                px: button.fontSize
                font.weight: button.fontWeight
                width: Math.min(implicitWidth, button.width - 2 * button.sidePadding - (button.iconPath.length > 0 ? button.metrics.px(20) : 0))
            }
        }
    }
}
