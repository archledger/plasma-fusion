/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    The app-open zoom in tablet posture (TABLET2 M1): when an app is started from the home screen,
    the launcher sheet or the dock, a card in the tile's colour with the app's icon grows from the
    tapped icon to the whole screen, as on iPadOS and Android. The card's window is an ordinary
    window under the panels, so the app's window, which KWin opens above it, covers it: no
    "app is ready" signal is needed. It goes after 4 s (an app that takes longer shows its window
    over the home screen, as without the zoom) or on a tap, and it is unloaded then (a full-screen
    window costs about 37 MiB of GPU memory while it exists). With reduced motion (Plasma's
    animation speed at instant) nothing is shown.

      FusionLaunchZoom { id: launchZoom; dark: ... }
      launchZoom.play(iconItem, source, iconName)   // iconItem: the tapped FusionIconTile

    The source is packages/common/FusionLaunchZoom.qml; tools/build-lib/shared-qml.sh copies it into
    every package that uses it (do not edit the copies).
*/
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore

Item {
    id: zoom

    // The surface colour: the tile's dark or light board neutral.
    property bool dark: true
    readonly property color surface: dark ? "#1b2031" : "#f4f6fb"

    property var iconSource
    property string iconName: ""
    // The icon's rectangle and the screen, in global coordinates.
    property rect from: Qt.rect(0, 0, 72, 72)
    property rect area: Qt.rect(0, 0, 1440, 900)
    property real progress: 0
    readonly property bool playing: loader.active

    Motion {
        id: motion
    }

    function play(iconItem: Item, source: var, name: string): void {
        if (!motion.animate || !iconItem || !iconItem.Window.window) {
            return;
        }
        const p = iconItem.mapToGlobal(0, 0);
        from = Qt.rect(p.x, p.y, iconItem.width, iconItem.height);
        const screen = iconItem.Screen;
        area = Qt.rect(screen.virtualX, screen.virtualY, screen.width, screen.height);
        iconSource = source;
        iconName = name;
        progress = 0;
        holdTimer.stop();
        loader.active = true;
        grow.restart();
        console.info("launch zoom: " + name + " from " + Math.round(from.x) + "," + Math.round(from.y) + " " + Math.round(from.width) + " px");
    }
    function finish(): void {
        holdTimer.stop();
        grow.stop();
        fade.restart();
    }

    NumberAnimation {
        id: grow
        target: zoom
        property: "progress"
        from: 0
        to: 1
        duration: motion.scaled(motion.surface, 1.2)
        easing.type: Easing.Bezier
        easing.bezierCurve: motion.decelerate
        onFinished: holdTimer.restart()
    }
    Timer {
        id: holdTimer
        interval: 4000
        onTriggered: zoom.finish()
    }
    SequentialAnimation {
        id: fade
        NumberAnimation {
            target: loader.item ? loader.item.mainItem : null
            property: "opacity"
            to: 0
            duration: motion.popupOut
        }
        ScriptAction {
            script: loader.active = false
        }
    }

    Loader {
        id: loader
        active: false
        sourceComponent: PlasmaCore.Dialog {
            type: PlasmaCore.Dialog.Normal
            location: PlasmaCore.Types.Floating
            backgroundHints: PlasmaCore.Dialog.NoBackground
            flags: Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
            hideOnWindowDeactivate: false
            x: zoom.area.x
            y: zoom.area.y
            visible: true
            mainItem: Item {
                Accessible.role: Accessible.Animation
                Accessible.name: i18ndc("plasmafusion", "@info accessible name of the app-open animation", "Opening app")
                width: zoom.area.width
                height: zoom.area.height
                Layout.minimumWidth: width
                Layout.maximumWidth: width
                Layout.minimumHeight: height
                Layout.maximumHeight: height
                readonly property real p: zoom.progress
                Rectangle {
                    id: card
                    x: (zoom.from.x - zoom.area.x) * (1 - parent.p)
                    y: (zoom.from.y - zoom.area.y) * (1 - parent.p)
                    width: zoom.from.width + (parent.width - zoom.from.width) * parent.p
                    height: zoom.from.height + (parent.height - zoom.from.height) * parent.p
                    radius: 0.234 * zoom.from.width * (1 - parent.p)
                    color: zoom.surface
                    FusionIconTile {
                        anchors.centerIn: parent
                        size: Math.min(card.width, card.height, zoom.from.width + (128 - zoom.from.width) * card.parent.p)
                        source: zoom.iconSource
                        iconName: zoom.iconName
                    }
                }
                TapHandler {
                    onTapped: zoom.finish()
                }
            }
        }
    }
}
