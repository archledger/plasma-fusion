/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Colours of the Launcher boards (dark: Launcher.dc.html, light: LauncherLight.dc.html).
// The surface itself comes from the Plasma style; these are the tints drawn on top of it.
QtObject {
    id: pal

    property bool dark: true
    property color accent: "#2f6fdf"

    // Overlay ink: white on the dark card, the light scheme's text colour (20,24,39) on the light card.
    readonly property color ink: dark ? "#ffffff" : "#141827"

    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    readonly property color text: dark ? "#e8ebf4" : "#141827"
    readonly property color textSecondary: dark ? "#cdd3e4" : "#3a4157"
    readonly property color tileText: dark ? "#dfe3ee" : "#2a3044"
    readonly property color muted: dark ? "#a3abc2" : "#5b6278"
    readonly property color placeholder: dark ? "#8f98b3" : "#6b7288"

    readonly property color fieldBorder: "#5b9dff"
    readonly property color fieldBorderIdle: tint(0.14)
    readonly property color focusRing: dark ? "#8ab8ff" : "#2f6fdf"
    readonly property color danger: "#d9434b"
    readonly property color dangerHover: "#e2555d"
    readonly property color avatar: "#7b5cd6"

    readonly property color field: tint(0.07)
    readonly property color badge: tint(0.08)
    readonly property color chip: tint(0.06)
    readonly property color chipHover: tint(0.10)
    readonly property color pill: tint(0.06)
    readonly property color pillHover: tint(0.10)
    readonly property color tileHover: tint(0.09)
    readonly property color rowHover: tint(0.06)
    readonly property color round: tint(0.07)
    readonly property color roundHover: tint(0.12)
    readonly property color footer: dark ? Qt.rgba(0, 0, 0, 0.18) : tint(0.04)
    readonly property color footerEdge: tint(0.07)
    readonly property color iconShadow: Qt.rgba(0, 0, 0, 0.30)
}
