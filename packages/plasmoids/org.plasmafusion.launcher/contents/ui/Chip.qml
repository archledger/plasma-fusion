/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// Category chip: a 30 px pill, 14 px side padding, 12 px text (800 when selected, 700 otherwise),
// scaled with the user's text size. In touch mode the target is at least 44 x 44 (ADAPTIVE 5.3)
// while the drawn pill keeps the text size's size, as IconButton keeps its circle.
T.AbstractButton {
    id: chip

    property FusionColors pal
    property FusionMetrics metrics
    property bool selected: false
    property bool showFocus: visualFocus

    readonly property real drawnWidth: Math.max(label.implicitWidth + metrics.px(28), drawnHeight)
    readonly property real drawnHeight: metrics.px(30)

    implicitWidth: Math.max(drawnWidth, metrics.touch ? 44 : 0)
    implicitHeight: Math.max(drawnHeight, metrics.touch ? 44 : 0)
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.checked: selected

    background: Rectangle {
        // The drawing, not the target: touch mode's 44 px box keeps the text-sized pill inside.
        anchors.centerIn: parent
        width: chip.drawnWidth
        height: chip.drawnHeight
        radius: chip.drawnHeight / 2
        color: chip.selected ? chip.pal.accent : (chip.hovered ? chip.pal.chipHover : chip.pal.chip)
        antialiasing: true

        FocusRing {
            visible: chip.showFocus
            baseRadius: chip.drawnHeight / 2
            ringColor: chip.pal.focusRing
        }
    }

    contentItem: FusionText {
        id: label
        text: chip.text
        color: chip.selected ? "#ffffff" : chip.pal.textSecondary
        metrics: chip.metrics
        px: 12
        weight: chip.selected ? 800 : 700
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
