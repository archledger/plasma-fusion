/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.components as PC3

// Footer session button: 38 px circle with an 18 px glyph (`size`: 44 in the tablet sheet); the
// power button is red.
T.AbstractButton {
    id: button

    property FusionColors pal
    property string glyph
    property bool danger: false
    property real size: 38

    implicitWidth: size
    implicitHeight: size
    hoverEnabled: true
    focusPolicy: Qt.TabFocus

    Accessible.role: Accessible.Button
    Accessible.name: text

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    PC3.ToolTip.text: text
    PC3.ToolTip.visible: hovered && text.length > 0
    PC3.ToolTip.delay: 600

    background: Rectangle {
        radius: button.size / 2
        antialiasing: true
        opacity: button.enabled ? 1 : 0.45
        color: button.danger ? (button.hovered || button.down ? button.pal.dangerHover : button.pal.danger)
                             : (button.hovered || button.down ? button.pal.roundHover : button.pal.round)

        FocusRing {
            visible: button.visualFocus
            baseRadius: button.size / 2
            ringColor: button.pal.focusRing
        }
    }

    contentItem: Item {
        opacity: button.enabled ? 1 : 0.45

        Glyph {
            anchors.centerIn: parent
            name: button.glyph
            size: 18
            color: button.danger ? "#ffffff" : button.pal.tileText
        }
    }
}
