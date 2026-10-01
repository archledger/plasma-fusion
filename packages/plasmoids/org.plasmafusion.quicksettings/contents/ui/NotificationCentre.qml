// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "components"

// The Notification Centre's window (TABLET2 S1): full screen, frameless, a normal-layer dialog
// without the style's background, as the tablet launcher's sheet (the panels stay above it, so
// the top bar keeps working). Built the first time it is wanted, then kept.
PlasmaCore.Dialog {
    id: window

    property var backend
    property rect area: Qt.rect(0, 0, 1, 1)
    property real topBar: 44
    property int screenNumber: 0
    property bool wanted: false
    property bool open: false
    readonly property NotificationCentreContent content: loader.item as NotificationCentreContent

    signal closeRequested()
    signal controlsRequested()
    // KWin hid the window (another window became active): close without the animation.
    signal deactivated()
    // The window is gone (after the close animation).
    signal hidden()
    // Open latency (log): set by the widget when it asks to open.
    property real openStarted: 0

    type: PlasmaCore.Dialog.Normal
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    flags: Qt.FramelessWindowHint
    // Closed by the widget when another window becomes active, not while the sheet's own card
    // menu has the focus (as the tablet launcher's sheet).
    hideOnWindowDeactivate: false
    property bool wasActive: false
    onActiveChanged: {
        if (active) {
            wasActive = true;
        } else if (visible && wasActive && !(content && content.menuOpen)) {
            deactivated();
        }
    }
    x: area.x
    y: area.y
    // Stays up while the close animation runs.
    visible: (open || (content !== null && content.progress > 0)) && loader.status === Loader.Ready
    onVisibleChanged: {
        if (visible) {
            requestActivate();
            if (content) {
                content.forceActiveFocus();
            }
        } else {
            wasActive = false;
            hidden();
        }
    }
    onFrameSwapped: {
        if (openStarted > 0 && visible) {
            console.info("quicksettings: notification centre first frame after " + (Date.now() - openStarted) + " ms");
            openStarted = 0;
        }
    }

    mainItem: Item {
        width: Math.max(1, window.area.width)
        height: Math.max(1, window.area.height)
        Layout.minimumWidth: width
        Layout.maximumWidth: width
        Layout.minimumHeight: height
        Layout.maximumHeight: height
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false
        FusionMetrics {
            id: centreMetrics
            area: window.area
            tablet: true
        }
        Motion {
            id: centreMotion
        }
        Loader {
            id: loader
            anchors.fill: parent
            focus: true
            active: window.wanted
            asynchronous: true
            sourceComponent: NotificationCentreContent {
                focus: true
                backend: window.backend
                metrics: centreMetrics
                motion: centreMotion
                topBar: window.topBar
                screenNumber: window.screenNumber
                shown: window.open
                onCloseRequested: window.closeRequested()
                onMenuClosed: window.requestActivate()
                onControlsRequested: window.controlsRequested()
            }
        }
    }
}
