// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.layershell 1.0 as LayerShell

// Split from the dock (SPLIT.md item 1; Android's taskbar drag, iPadOS's dock drag): while an app's
// icon is dragged up out of the dock in tablet posture, this full-screen overlay shows the two
// halves the app can go to and the icon under the finger. It takes no input (the dock keeps the
// touch), sits above the apps ("on-screen-display": KWin's tablet policy leaves it alone) and exists
// only during the drag.
Window {
    id: overlay

    required property DockPalette pal
    required property Motion motion
    // The screen the dock is on, and the finger in its coordinates.
    property rect screenGeometry
    property point finger: Qt.point(0, 0)
    property var iconSource
    // The work area's top (below the top bar) and bottom (above the dock strip), in this window.
    property real topInset: 0
    property real bottomInset: 0
    // "left", "right" or "" (the middle: dropping there does nothing).
    readonly property string side: finger.x < width / 3 ? "left" : finger.x > width * 2 / 3 ? "right" : ""

    // A top-level surface (see BottomStrip.qml) that never takes input.
    transientParent: null
    flags: Qt.FramelessWindowHint | Qt.WindowTransparentForInput | Qt.WindowDoesNotAcceptFocus
    color: "transparent"

    screen: {
        const screens = Qt.application.screens;
        for (let i = 0; i < screens.length; ++i) {
            const s = screens[i];
            if (s.virtualX === screenGeometry.x && s.virtualY === screenGeometry.y) {
                return s;
            }
        }
        return screens.length > 0 ? screens[0] : null;
    }

    LayerShell.Window.scope: "on-screen-display"
    LayerShell.Window.layer: LayerShell.Window.LayerOverlay
    LayerShell.Window.anchors: LayerShell.Window.AnchorTop | LayerShell.Window.AnchorBottom
                               | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: -1
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    component Zone: Rectangle {
        required property string name
        readonly property bool target: overlay.side === name
        y: overlay.topInset + 6
        width: overlay.width / 2 - 9
        height: overlay.height - overlay.topInset - overlay.bottomInset - 12
        radius: 14
        color: Qt.rgba(overlay.pal.accent.r, overlay.pal.accent.g, overlay.pal.accent.b, target ? 0.28 : 0.08)
        border.width: 2
        border.color: Qt.rgba(overlay.pal.accent.r, overlay.pal.accent.g, overlay.pal.accent.b, target ? 1 : 0.35)
        Behavior on color {
            enabled: overlay.motion.animate
            ColorAnimation { duration: overlay.motion.toggle }
        }
    }
    Zone {
        name: "left"
        x: 6
    }
    Zone {
        name: "right"
        x: overlay.width / 2 + 3
    }

    // The app under the finger, a little above it so that the finger does not cover it.
    Kirigami.Icon {
        width: 72
        height: 72
        x: overlay.finger.x - width / 2
        y: overlay.finger.y - height - 24
        source: overlay.iconSource
        opacity: 0.92
    }
}
