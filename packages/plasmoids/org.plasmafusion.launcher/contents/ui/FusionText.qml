/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Text in the design's type scale: size in CSS pixels and CSS weight (400-800).
// Plasma Fusion installs Manrope as one static file per weight (the build's fonts/*/static),
// so the CSS weight is the font weight: Qt picks the matching file and draws no synthetic bold
// (it only emboldens files lighter than 700).
Text {
    id: label

    property string family
    property real px: 13
    property int weight: 400

    font.family: family
    // CSS px to points at the 96 dpi logical resolution Plasma uses on Wayland.
    font.pointSize: px * 0.75
    font.weight: weight
}
