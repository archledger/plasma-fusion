/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Text in the design's type scale: size in CSS pixels and CSS weight (400-800).
// Manrope is a variable font. Qt adds a synthetic bold on top of its named Bold/ExtraBold
// instances, which makes 700/800 text far too heavy, so for Manrope the weight is set on the
// "wght" axis and the font weight stays Normal. Other families use the regular font weight.
Text {
    id: label

    property string family
    property real px: 13
    property int weight: 400
    readonly property bool variableWeight: family === "Manrope"

    font.family: family
    // CSS px to points at the 96 dpi logical resolution Plasma uses on Wayland.
    font.pointSize: px * 0.75
    font.weight: variableWeight ? Font.Normal : weight
    font.variableAxes: variableWeight ? { "wght": weight } : ({})
}
