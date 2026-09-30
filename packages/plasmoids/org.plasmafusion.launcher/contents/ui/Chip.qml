/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// Category chip: 30 px pill, 14 px side padding, 12 px text (800 when selected, 700 otherwise),
// scaled with the user's text size.
T.AbstractButton {
    id: chip

    property FusionColors pal
    property FusionMetrics metrics
    property bool selected: false
    property bool showFocus: visualFocus

    implicitWidth: label.implicitWidth + metrics.px(28)
    implicitHeight: metrics.px(30)
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.checked: selected

    background: Rectangle {
        radius: height / 2
        color: chip.selected ? chip.pal.accent : (chip.hovered ? chip.pal.chipHover : chip.pal.chip)
        antialiasing: true

        FocusRing {
            visible: chip.showFocus
            baseRadius: chip.height / 2
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
