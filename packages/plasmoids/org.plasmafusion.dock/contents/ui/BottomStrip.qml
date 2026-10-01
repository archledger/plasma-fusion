// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Window
import org.kde.layershell 1.0 as LayerShell

// The tablet bottom strip (TABLET2 N1; replaces the floating home indicator of TABLET 4.4): in
// tablet posture a 20 px band along the bottom edge of the dock's screen, a layer-shell surface with
// a 20 px exclusive zone, so KWin ends maximized apps above it, like iPadOS keeps app controls out
// of its home-indicator area. The band is the 20 px bottom touch zone of the navigation gestures
// (kwinrc [ScreenEdges] TouchTarget=20 in tablet posture), where KWin keeps every touch; without the
// strip, apps' status bars sat under the indicator and lost their taps there (private session
// hd2t, LibreOffice). Over a maximized app: the top bar's solid tone with the 120 x 5 pill;
// otherwise transparent. It exists for the whole tablet posture, so the work area stays the same
// while apps open and close. It takes no input and sits on the bottom layer, under the dock.
Window {
    id: strip

    // A top-level surface, not a transient of the dock's panel: Qt makes a Window declared inside
    // an item a transient of that item's window, and Plasma keeps a dodging or auto-hiding panel
    // shown while a transient of it is visible (PanelView::restoreAutoHide), so the always-shown
    // strip kept the dock over every app in tablet posture.
    transientParent: null

    required property DockPalette pal
    required property Motion motion
    // A maximized app is active: solid band with the pill.
    property bool overApp: false
    // The settings module's home indicator switch (dock config homeIndicator): the pill only.
    property bool showIndicator: true
    property rect screenGeometry

    // 20 px snapped to whole device pixels at the screen's scale (21 at 4/3), so the app area above
    // ends on a pixel edge (research H-hidpi 3.6). The plasmafusion-tablet KWin script writes it
    // (dock config tabletStripHeight): plasmashell's QML only sees Wayland's rounded integer scale.
    property int stripHeight: 20

    // The QScreen the dock is on (the containment gives its geometry).
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

    // "dock": KWin treats it as a panel (any other scope makes a normal window: Overview, tablet policy)
    LayerShell.Window.scope: "dock"
    LayerShell.Window.layer: LayerShell.Window.LayerBottom
    LayerShell.Window.anchors: LayerShell.Window.AnchorBottom | LayerShell.Window.AnchorLeft | LayerShell.Window.AnchorRight
    LayerShell.Window.exclusionZone: stripHeight
    LayerShell.Window.keyboardInteractivity: LayerShell.Window.KeyboardInteractivityNone

    flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus | Qt.WindowTransparentForInput
    color: "transparent"
    width: screenGeometry.width
    height: stripHeight
    visible: screenGeometry.width > 0

    Rectangle {
        anchors.fill: parent
        // The top bar's solid fill (widgets/panel-background of plasma-fusion-dark / -light).
        color: strip.pal.dark ? "#090c18" : "#fafbff"
        opacity: strip.overApp ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: strip.motion.toggle }
        }
    }

    // The home indicator: 120 x 5, radius 2.5, 8 px above the bottom edge.
    Rectangle {
        width: 120
        height: 5
        radius: 2.5
        anchors.horizontalCenter: parent.horizontalCenter
        y: strip.stripHeight - 8 - height
        color: strip.pal.homeIndicator
        opacity: strip.overApp && strip.showIndicator ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: strip.motion.toggle }
        }
    }
}
