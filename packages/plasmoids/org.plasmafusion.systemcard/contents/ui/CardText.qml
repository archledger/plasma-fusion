/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Text in the boards' type scale: size in board pixels (fractions allowed, 10.5 and 11.5 are
// used), scaled by the user's text size, and CSS weight. Shared by the three card widgets
// (identical copies). The families come resolved from the card's FusionMetrics.
Text {
    required property CardPalette pal
    // The card's metrics (one per card, passed down from its root).
    required property FusionMetrics metrics
    property bool display: false
    property real px: 13
    property int weight: 400
    // Tabular figures, for numbers that change in place (BACKLOG M8).
    property bool tabular: false

    color: pal.text
    font.family: display ? metrics.displayFamily : metrics.family
    // Logical pixels to points at Qt's 96 dpi logical resolution.
    font.pointSize: metrics.font(px) * 0.75
    font.weight: weight
    font.features: tabular ? { "tnum": 1 } : ({})
    textFormat: Text.PlainText
    maximumLineCount: 1
    elide: Text.ElideRight
}
