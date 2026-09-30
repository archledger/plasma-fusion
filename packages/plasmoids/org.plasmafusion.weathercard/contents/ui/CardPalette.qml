/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Colours of the desktop cards (Main.dc.html / MainLight.dc.html, "Plasma desktop
// widgets"); the fonts come from FusionMetrics. The card itself is the Plasma style's widget background (StandardBackground, the
// "blurred" frame over the wallpaper blur); this item only picks the dark or light text set for
// it. Shared by the three card widgets: the same file is in each package (the build checks that
// the copies are identical).
Item {
    visible: false

    // The card follows the Window colour set of the colour scheme (BasicAppletContainer).
    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark

    readonly property color text: dark ? "#e8ebf4" : "#141827"
    // Card labels ("Local weather", "CPU", the month arrows).
    readonly property color label: dark ? "#a3abc2" : "#5b6278"
    // Secondary body text ("Partly cloudy · 21° / 12°").
    readonly property color body: dark ? "#cdd3e4" : "#3a4157"
    // Calendar days, weekday initials and weekend days.
    readonly property color day: dark ? "#dfe3ee" : "#2a3044"
    readonly property color tertiary: dark ? "#8f98b3" : "#6b7288"
    readonly property color weatherIcon: dark ? "#f2c38a" : "#c77a1e"
    // Accent (Selection background, #2f6fdf in both Fusion schemes; a user accent still applies).
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color accentText: "#ffffff"
    readonly property color focusRing: dark ? "#8ab8ff" : "#2f6fdf"
    readonly property color cpu: "#3cc4b0"
    readonly property color memory: "#5b9dff"

    // White on dark cards, the light boards' ink (#141827) on light cards.
    function tint(alpha: real): color {
        return dark ? Qt.rgba(1, 1, 1, alpha) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, alpha);
    }
}
