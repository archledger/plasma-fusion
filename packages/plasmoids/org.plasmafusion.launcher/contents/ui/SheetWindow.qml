/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// The tablet launcher's window (TABLET 4.5): a full-screen, frameless normal-layer dialog without
// the style's background (no KWin blur; the panels stay above it). Unlike the dim layer it takes
// the focus, so the search pill can get the keyboard; it does not hide by itself, the launcher
// closes it when another window becomes active. The sheet is built in the background the first
// time it is wanted and then kept.
PlasmaCore.Dialog {
    id: window

    property var launcher
    property rect area: Qt.rect(0, 0, 1, 1)
    property real topBar: 44
    property int screenNumber: 0
    property bool sheetWanted: false
    readonly property TabletSheet sheet: sheetLoader.item as TabletSheet

    signal sheetReady()
    signal closeRequested()

    type: PlasmaCore.Dialog.Normal
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    flags: Qt.FramelessWindowHint
    hideOnWindowDeactivate: false
    x: area.x
    y: area.y

    mainItem: Item {
        id: holder
        width: Math.max(1, window.area.width)
        height: Math.max(1, window.area.height)
        Layout.minimumWidth: width
        Layout.maximumWidth: width
        Layout.minimumHeight: height
        Layout.maximumHeight: height

        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        FusionMetrics {
            id: fusionMetrics
            area: window.launcher ? window.launcher.availableScreenRect : Qt.rect(0, 0, 1440, 900)
            tablet: true
        }
        FusionColors {
            id: colors
            dark: {
                const c = Kirigami.Theme.backgroundColor;
                return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
            }
            accent: Kirigami.Theme.highlightColor
        }
        Motion {
            id: motionTokens
        }

        Loader {
            id: sheetLoader
            anchors.fill: parent
            focus: true
            active: window.sheetWanted
            asynchronous: true
            onLoaded: window.sheetReady()
            sourceComponent: TabletSheet {
                focus: true
                launcher: window.launcher
                pal: colors
                metrics: fusionMetrics
                motion: motionTokens
                topBar: window.topBar
                screenNumber: window.screenNumber
                shown: window.visible
                onCloseRequested: window.closeRequested()
            }
        }
    }
}
