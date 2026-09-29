/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T

// Category chip: 30 px pill, 14 px side padding, 12 px text (800 when selected, 700 otherwise).
T.AbstractButton {
    id: chip

    property FusionColors pal
    property string fontFamily
    property bool selected: false
    property bool showFocus: visualFocus

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 30
    focusPolicy: Qt.NoFocus
    hoverEnabled: true

    Accessible.role: Accessible.PageTab
    Accessible.name: text
    Accessible.checked: selected

    background: Rectangle {
        radius: 15
        color: chip.selected ? chip.pal.accent : (chip.hovered ? chip.pal.chipHover : chip.pal.chip)
        antialiasing: true

        FocusRing {
            visible: chip.showFocus
            baseRadius: 15
            ringColor: chip.pal.focusRing
        }
    }

    contentItem: FusionText {
        id: label
        text: chip.text
        color: chip.selected ? "#ffffff" : chip.pal.textSecondary
        family: chip.fontFamily
        px: 12
        weight: chip.selected ? 800 : 700
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
