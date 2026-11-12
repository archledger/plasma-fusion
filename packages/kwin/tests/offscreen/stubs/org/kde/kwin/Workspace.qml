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
    property var screens: [activeScreen]
    // The last sendClientToScreen's screen (the harness checks it).
    property var sentTo: null
    property var screenTransfer: null
    property var quickTileRequest: null
    property rect maximizeArea: Qt.rect(0, 34, 1440, 866)
    property var outlineScreen: null
    property var outputDesktops: ({})
    property var desktopAreas: ({})
    property var outputAreas: ({})
    property var customRoots: ({})
    property point cursorPos: Qt.point(700, 400)
    property string currentActivity: "a"
    // The fork's TransientTilingApi facade (a null impl is a stock KWin: no facade). The
    // harness installs its mock here; the placement script and the tiler probe it through
    // transientTiling().
    property var transientTilingImpl: null
    // The explicit restore (Meta+Backspace's path) the tiler's untoggle asks for; counted.
    // onSlotRestore lets a harness emulate KWin's activation side effects during the restore
    // (activating the old master can carry the current desktop and screen to its view).
    property int slotWindowRestoreCalls: 0
    property var onSlotRestore: null

    signal windowAdded(var window)
    signal windowRemoved(var window)
    signal windowActivated(var window)
    // screensChanged() comes with the screens property.
    signal virtualScreenGeometryChanged()

    function transientTiling() {
        return transientTilingImpl ? transientTilingImpl() : null;
    }

    function screenAt(p) {
        return outlineScreen || screens.find(s => s.geometry && p.x >= s.geometry.x
            && p.x < s.geometry.x + s.geometry.width && p.y >= s.geometry.y
            && p.y < s.geometry.y + s.geometry.height) || activeScreen;
    }
    function currentDesktopForScreen(o) { return (o && outputDesktops[o.name]) || currentDesktop; }
    function clientArea(option, a, b) {
        const output = b ? a : (a ? a.output : null);
        return (output && outputAreas[output.name]) || (b && desktopAreas[b.id]) || maximizeArea;
    }
    function raiseWindow(w) {}
    function showOutline(r) { console.log("showOutline", JSON.stringify(r)); }
    function hideOutline() { console.log("hideOutline"); }
    function quickTile(role) { if (quickTileRequest) quickTileRequest(role); }
    function slotWindowQuickTileLeft() { quickTile(0); }
    function slotWindowQuickTileRight() { quickTile(1); }
    function slotWindowQuickTileTop() { quickTile(2); }
    function slotWindowQuickTileBottom() { quickTile(3); }
    function slotWindowQuickTileTopLeft() { quickTile(4); }
    function slotWindowQuickTileTopRight() { quickTile(5); }
    function slotWindowQuickTileBottomLeft() { quickTile(6); }
    function slotWindowQuickTileBottomRight() { quickTile(7); }
    function rootTile(o, d) { return (o && d && customRoots[o.name + "|" + d.id]) || null; }
    function slotToggleShowDesktop() {}
    function sendClientToScreen(w, o) {
        sentTo = o;
        if (screenTransfer) screenTransfer(w, o);
        w.output = o;
    }
    function slotWindowRestore() {
        slotWindowRestoreCalls++;
        if (onSlotRestore) {
            onSlotRestore();
        }
    }
}
