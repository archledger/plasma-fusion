// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import org.kde.layershell 1.0 as LayerShell

import "../code/drop.js" as Drop

// The window pill's drag in tablet posture (board TabletSnap.dc.html): while the app's pill is held
// and dragged down, this full-screen overlay shows the two halves the app can take, the whole
// screen when the finger is over the middle third, the way home at the bottom, and the app's icon
// under the finger, as the dock's split drag does (its SplitDropOverlay.qml). It takes no input
// (the pill keeps the touch), sits above the apps ("on-screen-display": KWin's tablet policy
// leaves it alone) and exists only during the drag.
Window {
    id: overlay

    required property color accent
    required property bool dark
    required property Motion motion
    // The pill's screen, and the finger in its coordinates.
    property rect screenGeometry
    property point finger: Qt.point(0, 0)
    property var iconSource
    // The work area's top (below the top bar) and bottom (above the dock strip), in this window.
    property real topInset: 0
    property real bottomInset: 0
    // "" (back in the top bar), "home", "left", "right" or "full" (drop.js).
    readonly property string target: Drop.target(finger, width, topInset, height - bottomInset)

    // A top-level surface that never takes input (as the dock's overlay).
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

    function tint(alpha: real): color {
        return Qt.rgba(accent.r, accent.g, accent.b, alpha);
    }

    // A half (the board: accent 8 %, the target 28 % with a full edge, radius 14); over the middle
    // third both halves light up as one, the whole screen.
    component Zone: Rectangle {
        required property string name
        required property string label
        readonly property bool lit: overlay.target === name || overlay.target === "full"
        y: overlay.topInset + 6
        width: overlay.width / 2 - 9
        height: overlay.height - overlay.topInset - overlay.bottomInset - 12
        radius: 14
        color: overlay.tint(lit ? 0.28 : 0.08)
        border.width: 2
        border.color: overlay.tint(lit ? 1 : 0.35)
        Behavior on color {
            enabled: overlay.motion.animate
            ColorAnimation { duration: overlay.motion.toggle }
        }
        Text {
            anchors.centerIn: parent
            text: overlay.target === "full" ? i18nc("@info the drop zone of the pill's drag", "Full screen") : parent.label
            textFormat: Text.PlainText
            color: parent.lit ? (overlay.dark ? "#ffffff" : "#141827") : (overlay.dark ? "#a3abc2" : "#5b6278")
            font.pixelSize: 15
            font.weight: Font.ExtraBold
        }
    }
    Zone {
        name: "left"
        label: i18nc("@info the drop zone of the pill's drag", "Left half")
        x: 6
    }
    Zone {
        name: "right"
        label: i18nc("@info the drop zone of the pill's drag", "Right half")
        x: overlay.width / 2 + 3
    }

    // What the three places do, in the island's black, 22 px below the top bar.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.topInset + 22
        width: hint.implicitWidth + 36
        height: 40
        radius: 20
        color: "#0b0e1b"
        Text {
            id: hint
            anchors.centerIn: parent
            text: i18nc("@info what the drop zones of the pill's drag do", "A side splits · the middle is full screen · the bottom goes home")
            textFormat: Text.PlainText
            color: "#ffffff"
            font.pixelSize: 14
            font.weight: Font.Bold
        }
    }

    // Home: the bottom 96 px of the work area.
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        y: overlay.height - overlay.bottomInset - 34 - height
        width: homeLabel.implicitWidth + 36
        height: 36
        radius: 18
        color: overlay.tint(overlay.target === "home" ? 0.28 : 0.08)
        border.width: 2
        border.color: overlay.tint(overlay.target === "home" ? 1 : 0.45)
        Text {
            id: homeLabel
            anchors.centerIn: parent
            text: i18nc("@info the drop zone of the pill's drag", "Home")
            textFormat: Text.PlainText
            color: overlay.target === "home" ? (overlay.dark ? "#ffffff" : "#141827") : (overlay.dark ? "#a3abc2" : "#5b6278")
            font.pixelSize: 13
            font.weight: Font.ExtraBold
        }
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
