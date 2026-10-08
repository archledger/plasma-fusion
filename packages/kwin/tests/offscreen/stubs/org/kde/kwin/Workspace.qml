// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
// Offscreen test stand-in for KWin's Workspace singleton (test use only). The harness fills
// windows, desktops and the current desktop.
pragma Singleton
import QtQuick

QtObject {
    enum ClientAreaOption { PlacementArea, MovementArea, MaximizeArea, MaximizeFullArea, FullScreenArea, WorkArea, FullArea, ScreenArea }

    property var windows: []
    property var stackingOrder: windows
    property var desktops: []
    property var currentDesktop: null
    property var activeWindow: null
    property var activeScreen: ({ name: "Virtual-1", geometry: Qt.rect(0, 0, 1440, 900) })
    property rect maximizeArea: Qt.rect(0, 34, 1440, 866)
    property var outlineScreen: null
    property var outputDesktops: ({})
    property var desktopAreas: ({})
    property var customRoots: ({})
    property point cursorPos: Qt.point(700, 400)
    property string currentActivity: "a"

    signal windowAdded(var window)
    signal windowRemoved(var window)
    signal windowActivated(var window)
    signal screensChanged()
    signal virtualScreenGeometryChanged()

    function screenAt(p) { return outlineScreen || activeScreen; }
    function currentDesktopForScreen(o) { return (o && outputDesktops[o.name]) || currentDesktop; }
    function clientArea(option, a, b) { return (b && desktopAreas[b.id]) || maximizeArea; }
    function raiseWindow(w) {}
    function showOutline(r) { console.log("showOutline", JSON.stringify(r)); }
    function hideOutline() { console.log("hideOutline"); }
    function slotWindowQuickTileLeft() { console.log("quickTileLeft"); }
    function slotWindowQuickTileRight() { console.log("quickTileRight"); }
    function slotWindowQuickTileTop() {}
    function slotWindowQuickTileBottom() {}
    function slotWindowQuickTileTopLeft() {}
    function slotWindowQuickTileTopRight() {}
    function slotWindowQuickTileBottomLeft() {}
    function slotWindowQuickTileBottomRight() {}
    function rootTile(o, d) { return (o && d && customRoots[o.name + "|" + d.id]) || null; }
    function slotToggleShowDesktop() {}
}
