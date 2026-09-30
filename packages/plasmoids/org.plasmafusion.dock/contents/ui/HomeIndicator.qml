/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.plasma.core as PlasmaCore

// The home indicator (TABLET 4.4, P2): a 120 x 5 pill, radius 2.5, 8 px above the bottom edge,
// centred on the dock's screen, shown over a maximized app in tablet posture (the dock hides
// there; a swipe up from the bottom edge brings it back). Its own window, which takes no input
// and no focus; it renders once when it appears (a short fade) and then stays still.
PlasmaCore.Dialog {
    id: indicator

    required property DockPalette pal
    required property Motion motion
    property rect screenGeometry

    type: PlasmaCore.Dialog.Dock
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    outputOnly: true
    flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
    x: screenGeometry.x + Math.round((screenGeometry.width - 120) / 2)
    y: screenGeometry.y + screenGeometry.height - 8 - 5
    visible: screenGeometry.width > 0

    mainItem: Item {
        width: 120
        height: 5

        Rectangle {
            anchors.fill: parent
            radius: 2.5
            color: indicator.pal.homeIndicator
            opacity: 0
            NumberAnimation on opacity {
                to: 1
                duration: indicator.motion.toggle
                running: true
            }
        }
    }
}
