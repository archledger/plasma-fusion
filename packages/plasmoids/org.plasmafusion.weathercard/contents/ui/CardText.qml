/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Text in the boards' type scale: size in board pixels (fractions allowed, 10.5 and 11.5 are
// used) and CSS weight. Shared by the three card widgets (identical copies).
Text {
    required property CardPalette pal
    property bool display: false
    property real px: 13
    property int weight: 400

    color: pal.text
    font.family: display ? pal.displayFont : pal.uiFont
    // Logical pixels to points at Qt's 96 dpi logical resolution.
    font.pointSize: px * 0.75
    font.weight: weight
    textFormat: Text.PlainText
    maximumLineCount: 1
    elide: Text.ElideRight
}
