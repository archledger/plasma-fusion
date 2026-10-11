/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Text in the design's type scale: size in board pixels, scaled by the user's text size
// (FusionMetrics.font), and CSS weight (400-800).
// Plasma Fusion installs Manrope and Space Grotesk as one static file per weight (the build's
// fonts/*/static), so the CSS weight is the font weight: Qt picks the matching file and draws
// no synthetic bold (it only emboldens files lighter than 700). The families come resolved
// from the window's FusionMetrics (the Plasma UI font when they are not installed).
Text {
    id: label

    // The window's metrics (one per window, passed down from its root).
    required property FusionMetrics metrics
    // Space Grotesk (display figures) instead of Manrope.
    property bool display: false
    property real px: 13
    property int weight: 400

    font.family: display ? metrics.displayFamily : metrics.family
    font.pixelSize: metrics.font(px)
    font.weight: weight
    textFormat: Text.PlainText
    verticalAlignment: Text.AlignVCenter
}
