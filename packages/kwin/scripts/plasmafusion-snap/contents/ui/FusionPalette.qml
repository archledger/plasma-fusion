/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// Colours of the snap boards (QuickSettings/QuickSettingsLight "Snap layouts", TabsSnap "Fill
// the other half"). Dark or light follows the colour scheme; the accent follows it as well.
Item {
    id: palette

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color accent: Kirigami.Theme.highlightColor
    readonly property bool fusionAccent: Math.abs(accent.r - 47 / 255) < 0.04
        && Math.abs(accent.g - 111 / 255) < 0.04 && Math.abs(accent.b - 223 / 255) < 0.04
    // #5b9dff on the boards: the zone highlight, rings and the selected card.
    readonly property color zone: fusionAccent ? "#5b9dff" : Qt.lighter(accent, 1.25)

    readonly property color text: dark ? "#e8ebf4" : "#141827"
    readonly property color heading: dark ? "#cdd3e4" : "#3a4157"
    readonly property color pickerHeading: dark ? "#dfe3ee" : "#141827"
    readonly property color shortcut: dark ? "#8f98b3" : "#6b7288"
    readonly property color muted: dark ? "#a3abc2" : "#5b6278"
    readonly property color cardFill: tint(0.06)
    readonly property color zoneFill: tint(0.20)
    readonly property color hoverFill: tint(0.10)
    readonly property color selectedFill: Qt.rgba(zone.r, zone.g, zone.b, 0.22)
    readonly property color thumbFill: dark ? "#1b2031" : "#ffffff"
    readonly property color thumbEdge: tint(0.10)
    // The empty half: rgba(8,11,24,.55) on the dark board; a light frost on light schemes.
    readonly property color pickerFill: dark ? Qt.rgba(8 / 255, 11 / 255, 24 / 255, 0.55)
                                             : Qt.rgba(250 / 255, 251 / 255, 1, 0.62)
    readonly property color flyoutFill: dark ? Qt.rgba(22 / 255, 27 / 255, 46 / 255, 0.9)
                                             : Qt.rgba(1, 1, 1, 0.9)

    function tint(alpha) {
        return dark ? Qt.rgba(1, 1, 1, alpha) : Qt.rgba(20 / 255, 24 / 255, 39 / 255, alpha);
    }
}
