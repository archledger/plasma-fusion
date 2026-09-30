/*
    Colours of the Appearance page, dark (Main board) and light (MainLight board).

    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// An invisible Item (not a QtObject) so that Kirigami.Theme follows the page's colour set.
// It also carries the page's FusionMetrics (packages/common, compiled into the module): board
// text sizes go through m.font(), text-holding control heights through m.px(), so the page
// follows the user's font size like every other Plasma Fusion surface (exact at the default).
Item {
    visible: false
    width: 0
    height: 0

    readonly property FusionMetrics m: metrics

    FusionMetrics {
        id: metrics
    }

    readonly property bool dark: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
    readonly property string family: Kirigami.Theme.defaultFont.family

    // The session's accent: Selection (fills), DecorationHover / DecorationFocus (rings, borders).
    // The Plasma Fusion default is #2f6fdf with #5b9dff hover and #8ab8ff (dark) / #2f6fdf (light)
    // focus; an accent colour replaces them all (Colors page rules).
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property color accentText: Kirigami.Theme.highlightedTextColor
    readonly property bool defaultAccent: Qt.colorEqual(accent, "#2f6fdf")

    readonly property color pageBackground: Kirigami.Theme.backgroundColor
    readonly property color text: dark ? "#e8ebf4" : "#141827"
    readonly property color section: dark ? "#a3abc2" : "#5b6278"
    readonly property color label: dark ? "#cdd3e4" : "#3a4157"
    readonly property color labelSelected: dark
        ? (defaultAccent ? "#cfe0ff" : Kirigami.ColorUtils.tintWithAlpha("#ffffff", Kirigami.Theme.hoverColor, 0.3))
        : (defaultAccent ? "#1d4fb0" : Qt.darker(Kirigami.Theme.focusColor, 1.45))
    readonly property color cardBorder: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.10)
    readonly property color cardHover: dark ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.24)
    readonly property color cardSelected: dark ? Kirigami.Theme.hoverColor : Kirigami.Theme.focusColor
    readonly property color pillBorder: dark ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.30)
    readonly property color segmentBackground: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.06)
    readonly property color segmentHover: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.06)
    readonly property color rowLine: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.06)
    readonly property color switchOff: dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.18)
    readonly property color knobOff: dark ? "#e8ebf4" : "#ffffff"
    readonly property color focusRing: Kirigami.Theme.focusColor
}
