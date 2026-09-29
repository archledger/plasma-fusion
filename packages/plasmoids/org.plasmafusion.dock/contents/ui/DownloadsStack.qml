/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Fanned cards of the Downloads button (Main board): three 22x28 cards with a 4 px radius,
// the front one carrying a download arrow. Coordinates are relative to the 48 px button.
Item {
    id: stack

    required property DockPalette pal

    width: 48
    height: 48

    component Card: Rectangle {
        width: 22
        height: 28
        radius: 4
        antialiasing: true
    }

    Card { x: 12; y: 9; rotation: -10; color: stack.pal.cardBack }
    Card { x: 15; y: 10; rotation: 6; color: stack.pal.cardMiddle }
    Card {
        x: 13
        y: 11
        color: stack.pal.cardFront

        Glyph {
            anchors.centerIn: parent
            size: 14
            color: stack.pal.cardArrow
            path: "M12 4v11M7 10l5 5 5-5M5 20h14"
        }
    }
}
