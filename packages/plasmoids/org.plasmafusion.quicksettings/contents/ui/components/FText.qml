// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Text in the design's UI font (the system UI font, Manrope in Plasma Fusion), scaled by the
// user's text size.
Text {
    required property FusionPalette pal
    // The window's metrics (one per window, passed down from its root).
    required property FusionMetrics metrics
    // Size in logical pixels as on the boards (11.5, 12.5 ... are allowed).
    property real px: 13

    color: pal.text
    font.family: pal.fontFamily
    font.pointSize: metrics.font(px) * 0.75
    elide: Text.ElideRight
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
