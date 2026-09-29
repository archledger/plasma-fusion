/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Colours of the window switcher boards (AltTab.dc.html dark, AltTabLight.dc.html light).
// The accent follows the colour scheme; the ring keeps the board's lighter blue for the
// Fusion accent #2f6fdf and is derived from any other accent.
QtObject {
    id: palette

    property bool dark: true
    property color accent: "#2f6fdf"

    readonly property bool fusionAccent: Math.abs(accent.r - 47 / 255) < 0.04
        && Math.abs(accent.g - 111 / 255) < 0.04 && Math.abs(accent.b - 223 / 255) < 0.04
    readonly property color ring: fusionAccent ? "#5b9dff" : Qt.lighter(accent, 1.25)
    readonly property color selectedFill: Qt.rgba(ring.r, ring.g, ring.b, 0.16)

    readonly property color text: dark ? "#e8ebf4" : "#141827"
    readonly property color textMuted: dark ? "#a3abc2" : "#5b6278"
    readonly property color tabText: "#ffffff"
    readonly property color tabTextInactive: dark ? "#cdd3e4" : "#3a4157"
    readonly property color tabTrack: tint(0.07)
    readonly property color thumbEdge: tint(0.10)
    readonly property color thumbFill: dark ? "#1b2031" : "#ffffff"
    readonly property color thumbBar: dark ? "#222840" : "#eceff6"
    readonly property color kbdFill: tint(0.10)
    readonly property color kbdEdge: tint(0.14)
    readonly property color hoverFill: tint(dark ? 0.05 : 0.04)
    readonly property color dim: dark ? Qt.rgba(6 / 255, 8 / 255, 18 / 255, 0.55)
                                      : Qt.rgba(221 / 255, 230 / 255, 244 / 255, 0.5)
    // Used only when the Plasma style has no frame for the card (never with Plasma Fusion).
    readonly property color cardFill: dark ? Qt.rgba(22 / 255, 27 / 255, 46 / 255, 0.86)
                                           : Qt.rgba(1, 1, 1, 0.86)

    // White on dark boards, the light boards' ink rgb(20,24,39) on light ones.
    function tint(alpha) {
        return dark ? Qt.rgba(1, 1, 1, alpha) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, alpha);
    }
}
