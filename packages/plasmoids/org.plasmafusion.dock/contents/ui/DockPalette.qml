/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick

// Colours of the dock content, taken from the Main and MainLight boards
// (<nav aria-label="Dock">) and the Launcher/Overview boards for the pressed state.
QtObject {
    property bool dark: true

    readonly property color ink: dark ? "#e8ebf4" : "#141827"
    readonly property color buttonFill: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.08)
    readonly property color buttonHover: dark ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.13)
    readonly property color buttonPressed: dark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.05)
    // aria-pressed="true" (launcher open, Overview active)
    readonly property color activeFill: Qt.rgba(91 / 255, 157 / 255, 1, 0.3)
    // The Launcher and LauncherLight boards (Start pressed, the only pressed state the dock
    // shows) use the same ring in both variants; OverviewLight's would be rgba(47,111,223,.5).
    readonly property color activeRing: Qt.rgba(138 / 255, 184 / 255, 1, 0.5)
    readonly property color activeInk: dark ? "#ffffff" : "#1d4fb0"
    readonly property color separator: dark ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.16)
    readonly property color runningDot: dark ? Qt.rgba(1, 1, 1, 0.6) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.6)
    readonly property color activePill: dark ? "#8ab8ff" : "#2f6fdf"
    readonly property color attention: "#f2a65a"
    // drop-shadow colour. MultiEffect blends shadowColor as a premultiplied colour, so the
    // tinted light-mode colour is premultiplied here (rgb * alpha).
    readonly property color iconShadow: dark ? Qt.rgba(0, 0, 0, 0.35)
                                             : Qt.rgba(0.14 * 20 / 255, 0.14 * 24 / 255, 0.14 * 39 / 255, 0.14)
    // Name pill above the hovered item: dark in both variants.
    readonly property color tipFill: Qt.rgba(12 / 255, 15 / 255, 28 / 255, 0.92)
    readonly property color tipBorder: dark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, 0.12)
    readonly property color tipText: dark ? "#e8ebf4" : "#ffffff"
    // Downloads stack
    readonly property color cardBack: "#f2a65a"
    readonly property color cardMiddle: "#5b9dff"
    readonly property color cardFront: dark ? "#e8ebf4" : "#ffffff"
    readonly property color cardArrow: dark ? "#1b2031" : "#2f6fdf"
    // Keyboard focus ring (Controls board: 2 px accent ring with a 2 px gap)
    readonly property color focusRing: "#2f6fdf"
}
