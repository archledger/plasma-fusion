// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick

// Colours of the Quick Settings and Popups boards, dark and light. The accent
// colours come from the colour scheme so a user accent colour still applies.
QtObject {
    id: pal

    // Set from the colour scheme: true when the background is dark.
    property bool dark: true
    // Accent fill (Selection background, #2F6FDF in both Fusion schemes).
    property color accent: "#2f6fdf"
    // Lighter accent used for slider fills (DecorationHover, #5B9DFF).
    property color accentSoft: "#5b9dff"
    // Focus ring (DecorationFocus).
    property color focus: dark ? "#8ab8ff" : "#2f6fdf"
    property color link: dark ? "#8ab8ff" : "#2359c4"
    property string fontFamily: ""

    // Base of all translucent overlays: white on dark, #141827 on light.
    readonly property color overlayBase: dark ? "#ffffff" : "#141827"
    function overlay(alpha) {
        return Qt.rgba(overlayBase.r, overlayBase.g, overlayBase.b, alpha);
    }
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    readonly property color text: dark ? "#e8ebf4" : "#141827"
    readonly property color controlText: dark ? "#dfe3ee" : "#2a3044"
    readonly property color secondary: dark ? "#a3abc2" : "#5b6278"
    readonly property color tertiary: dark ? "#8f98b3" : "#6b7288"
    readonly property color body: dark ? "#cdd3e4" : "#3a4157"
    readonly property color accentText: "#ffffff"
    readonly property color accentTextSecondary: dark ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.9)

    readonly property color playFill: dark ? "#e8ebf4" : "#141827"
    readonly property color playGlyph: dark ? "#1b2031" : "#ffffff"

    readonly property color knob: "#ffffff"
    readonly property color knobShadow: dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.14)

    readonly property color dimIcon: dark ? Qt.rgba(232 / 255, 235 / 255, 244 / 255, 0.28) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.22)
    readonly property color danger: dark ? "#ff8a8f" : "#b3262e"
    readonly property color warning: dark ? "#f2c38a" : "#8f4f12"
    readonly property color charging: dark ? "#f7c948" : "#b7791f"
    readonly property color unreadDot: "#f2a65a"

    // Status pill while its pop-up is open (same in both boards).
    readonly property color pillOpen: Qt.rgba(91 / 255, 157 / 255, 1, 0.35)
    readonly property color pillOpenEdge: Qt.rgba(138 / 255, 184 / 255, 1, 0.5)

    // Wi-Fi panel: the connected network card.
    readonly property color activeCard: Qt.rgba(91 / 255, 157 / 255, 1, 0.16)
    readonly property color activeCardText: dark ? "#cfe0ff" : "#1d4fb0"
    readonly property color activeCardTitle: dark ? "#ffffff" : "#141827"
    readonly property color activeCardStats: dark ? "#b8cdf0" : "#1d4fb0"

    // "Clear all" pill of the notification list.
    readonly property color clearAllFill: dark ? Qt.rgba(14 / 255, 18 / 255, 34 / 255, 0.7) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.07)
}
