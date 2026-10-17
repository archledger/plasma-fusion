// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

import "components"
import "global"
import "../code/tiles.js" as Tiles
import "../code/requests.js" as Requests
import "../code/shared.js" as Shared
import "../code/clipboard.js" as Clip

// Plasma Fusion quick settings: the right side of the top bar (keyboard layout,
// phone, clipboard, status pill, notification bell) and a floating pop-up with
// quick settings and the notification list.
//
// The widget has no fullRepresentation: the bar is shown directly in the panel
// and the pop-up is an own AppletPopup with a margin, so it floats 10 px below the
// top bar and 16 px from the screen edge with all four corners rounded (the stock
// pop-up of a non-floating panel is glued to the panel and the screen edge).
//
// Tablet posture (TABLET 4.3 and 4.6): the bar's tablet sizes (TopBar.qml), and the sheet is
// 400 px wide 8 px under the bar and 12 px from the edge, in portrait min(W - 32, 560) and
// centred. The pop-up's content is built in the background after start (BACKLOG S2) or when
// the pointer reaches the bar. Other shell parts open it with the config key openRequest.
PlasmoidItem {
    id: root

    readonly property bool inPanel: [PlasmaCore.Types.TopEdge, PlasmaCore.Types.RightEdge,
        PlasmaCore.Types.BottomEdge, PlasmaCore.Types.LeftEdge].includes(Plasmoid.location)
    readonly property bool tablet: tabletState.tablet

    // ---- One quick settings per top bar (every screen's bar has one, owner decision 2026-10-09) ----
    // The widgets know each other through Instances (global/). The leader runs the session-wide
    // jobs (the tablet posture's settings, the new-device sheet); the sheet and Meta+A open on the
    // screen in use (KWin's active output); the settings are the same in every widget: a change in
    // one is copied to the others, and a new widget takes the leader's.
    readonly property int screenIndex: Plasmoid.containment ? Plasmoid.containment.screen : -1
    // The output this widget's bar is on: the screen at its containment's screen geometry (right
    // as soon as the bar is placed; the window's Screen attached property named the first screen
    // for a while in a bar made for another screen, so Meta+A went to the wrong widget).
    readonly property string screenFromGeometry: {
        const g = Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0);
        if (g.width > 0) {
            for (const screen of Qt.application.screens) {
                if (screen.virtualX === g.x && screen.virtualY === g.y && screen.width === g.width) {
                    return screen.name;
                }
            }
        }
        return "";
    }
    readonly property string screenName: screenFromGeometry || String(root.Screen.name || "")
    // Whether screenName is the bar's own output, not yet the window's guess (requests wait for it).
    readonly property bool screenSettled: screenFromGeometry !== ""
    readonly property bool leader: Instances.leader === root
    readonly property var sharedKeys: ["showKeyboardLayout", "keyboardLayoutAlways", "showKdeConnect", "showClipboard",
        "showCopyText", "showBatteryPercent", "popupOnNewDevice", "showNotifications", "popupGap",
        "popupScreenMargin", "startPage", "keyboardPolicy", "tabletNotifications",
        "lightLookAndFeel", "darkLookAndFeel", "tileOrder", "hiddenTiles"]
    readonly property var sharedSettings: sharedKeys.map(key => Plasmoid.configuration[key])
    function sharedValue(key: string): var {
        return Plasmoid.configuration[key];
    }
    // When the shared settings last changed (ms; 0 before 0.5.0), so the newest set wins when the
    // widgets meet again after a restart (code/shared.js).
    readonly property double sharedRevision: Number(Plasmoid.configuration.sharedRevision) || 0
    // The shared settings as last seen once this widget joined.
    property var lastShared: null
    function setSharedRevision(revision: double): void {
        if (sharedRevision !== revision) {
            Plasmoid.configuration.sharedRevision = revision;
        }
    }
    // A list (the tiles' order) is compared by its entries: each read gives a new array, which
    // `!==` always takes for a change, so an equal order would be written to every widget again.
    function setShared(key: string, value: var): void {
        const current = Plasmoid.configuration[key];
        const list = typeof value === "object" && value !== null;
        if (list ? !Tiles.same(current, value) : current !== value) {
            Plasmoid.configuration[key] = list ? Tiles.list(value) : value;
        }
    }
    onSharedSettingsChanged: {
        // Not before this widget has taken the leader's settings (Component.onCompleted): a new
        // widget's settings change while it loads, and pushing those defaults reset the others.
        if (Instances.items.indexOf(root) === -1) {
            return;
        }
        // The list is made again whenever any key of the configuration changes (the revision's
        // own write too): only a changed value is a change.
        const changed = !lastShared || sharedKeys.some((key, i) => {
            const value = sharedSettings[i];
            const list = typeof value === "object" && value !== null;
            return list ? !Tiles.same(lastShared[i], value) : lastShared[i] !== value;
        });
        lastShared = sharedSettings;
        if (!changed) {
            return;
        }
        for (const other of Instances.items) {
            if (other !== root) {
                sharedKeys.forEach((key, i) => other.setShared(key, sharedSettings[i]));
            }
        }
        Qt.callLater(stampSharedRevision);
    }
    // Every widget's revision to now, a moment after the change: a change written by desktop
    // scripting (writeConfig) is read back into the configuration after this handler ran, which
    // put this widget's revision back as it was. Never below the revision they hold, also when the
    // clock was set back (code/shared.js nextRevision).
    function stampSharedRevision(): void {
        const now = Shared.nextRevision(Date.now(), Instances.items.map(widget => widget.sharedRevision));
        Instances.items.forEach(widget => widget.setSharedRevision(now));
    }
    // Airplane mode's radio record (Backend.qml) survives a plasmashell restart: every widget keeps
    // a copy in its settings, and the first to start after a restart gives it back, once the
    // network service says airplane mode is still on; off (ended while the shell was down), the
    // record is stale and dropped.
    Connections {
        target: Instances
        function onAirplaneRestoreChanged() {
            Plasmoid.configuration.airplaneRestore = Instances.airplaneRestore ? JSON.stringify(Instances.airplaneRestore) : "";
        }
    }
    function adoptAirplaneRecord(): void {
        if (!backend.net.available || !Plasmoid.configuration.airplaneRestore) {
            return;
        }
        if (!backend.net.airplane) {
            Plasmoid.configuration.airplaneRestore = "";
            return;
        }
        if (!Instances.airplaneRestore) {
            try {
                Instances.airplaneRestore = JSON.parse(Plasmoid.configuration.airplaneRestore);
            } catch (e) {
                Plasmoid.configuration.airplaneRestore = "";
            }
        }
    }
    Connections {
        target: backend.net
        function onAvailableChanged() { root.adoptAirplaneRecord(); }
        function onAirplaneChanged() { root.adoptAirplaneRecord(); }
    }
    Component.onCompleted: {
        // The newest shared settings among the widgets there before this one joins, else the
        // leader's (equal revisions): a widget on a lower screen number (the primary screen's bar
        // made again) leads at once and still takes the others' first. A bar whose screen was away
        // after a restart kept its old settings; loaded first, it no longer gives them to the
        // others. When this widget's own are the newest, it gives them on.
        const others = Instances.items;
        const from = Shared.adoptFrom(sharedRevision, others.map(w => w.sharedRevision), others.indexOf(Instances.leader));
        if (from >= 0) {
            const source = others[from];
            sharedKeys.forEach(key => setShared(key, source.sharedValue(key)));
            setSharedRevision(source.sharedRevision);
        } else if (others.length > 0) {
            const revision = sharedRevision;
            for (const other of others) {
                sharedKeys.forEach((key, i) => other.setShared(key, sharedSettings[i]));
                other.setSharedRevision(revision);
            }
        }
        lastShared = sharedSettings;
        Instances.adopt(root);
        adoptAirplaneRecord();
        console.info("quicksettings: widget on " + (screenName || "?") + " (screen " + screenIndex + "), "
                     + Instances.items.length + " in this shell");
    }
    Component.onDestruction: Instances.forget(root)
    // The widget was removed (Plasma's undo notification is shown) or the removal undone: the bar's
    // tray items it shows are given back to the tray (Backend.qml, services/TrayItems.qml).
    property bool removed: false
    Connections {
        target: Plasmoid
        function onDestroyedChanged(destroyed: bool) {
            root.removed = destroyed;
        }
    }
    // Runs action(widget) for the widget on KWin's active screen (this one when that is unknown).
    function onActiveScreen(action: var): void {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.KWin",
            "path": "/KWin",
            "iface": "org.kde.KWin",
            "member": "activeOutputName",
            "arguments": []
        }, reply => action(Instances.onScreen(String(reply.value || "")) ?? root), () => action(root));
    }

    FusionTablet {
        id: tabletState
    }
    // Text scale and pixel grid of the panel window (docs/parts/shell-quicksettings.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }
    // The pop-up window's metrics once it is built, else the panel's.
    readonly property PopupContent popupContent: contentLoader.item as PopupContent
    readonly property FusionMetrics popupMetrics: popupContent ? popupContent.metrics : m
    readonly property rect screenArea: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
    // Width of the pop-up card: 356 px on the board (400 in tablet posture), scaled with the
    // text, at most the screen less 32 px; portrait tablet min(W - 32, 560). Whole device pixels.
    readonly property bool portraitSheet: tablet && m.portrait
    readonly property real outerWidth: {
        const pm = popupMetrics;
        const screenWidth = screenArea.width;
        if (portraitSheet) {
            return pm.windowSize(Math.min(screenWidth - 32, 560));
        }
        return pm.windowSize(Math.min(pm.px(tablet ? 400 : 356), screenWidth - 32));
    }
    readonly property int popupGap: tablet ? 8 : Plasmoid.configuration.popupGap
    readonly property int popupScreenMargin: tablet ? 12 : Plasmoid.configuration.popupScreenMargin

    property bool popupOpen: false
    property bool openOnPress: false
    // A page the next opening shows instead of the start page (the clipboard sheet, Keep awake).
    property string requestedPage: ""
    // The end of a timed Keep awake (ms since the epoch), else 0: the live chips widget in the same
    // bar reads it from this item (its sources/KeepAwake.qml) for its time-left chip.
    readonly property double keepAwakeUntil: backend.keepAwake.timed ? backend.keepAwake.until : 0
    property real maxPopupHeight: 820

    // The Plasma style's frame padding of the sheet's window, which the content subtracts from the
    // card's outer size. The window's leftPadding... properties are 0 until it is first shown and
    // then become the style's margins (14 px with Plasma Fusion's style) without their change
    // signal (paddingChanged), so a binding to them stayed 0: the content asked for the outer size
    // as its own, the window took it without the padding, and the content was drawn 14 px too low
    // and right with its last 28 px cut off. They are read again whenever the window sets its frame
    // borders (each time it is placed) or reports a change, and the content follows; the window
    // then sizes itself from the content's new size hints and the real padding. The read waits for
    // the window's own handler to return: the content's new size resizes the window, which sets
    // its borders again, and a nested update lost one of the four values.
    property real framePaddingLeft: 0
    property real framePaddingTop: 0
    property real framePaddingRight: 0
    property real framePaddingBottom: 0
    function readFramePadding(): void {
        framePaddingLeft = popup.leftPadding;
        framePaddingTop = popup.topPadding;
        framePaddingRight = popup.rightPadding;
        framePaddingBottom = popup.bottomPadding;
    }

    // The window's size follows the content's size hints (AppletPopup sets its minimum and maximum
    // size to them, which are equal here, and resizes it), but a size set while the sheet is hidden
    // did not reach the Wayland window: after a scale change, or a notification that came or went
    // with the sheet closed, it opened at its old height with the content cut off or a gap below.
    // Once shown, the window takes the size its own limits name.
    function fitWindow(): void {
        const width = popup.minimumWidth;
        const height = popup.minimumHeight;
        if (!popup.visible || width <= 0 || height <= 0 || width !== popup.maximumWidth || height !== popup.maximumHeight
                || (popup.width === width && popup.height === height)) {
            return;
        }
        console.info("quicksettings: sheet window " + popup.width + "x" + popup.height + " -> " + width + "x" + height);
        popup.width = width;
        popup.height = height;
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // The whole bar height is the hit area (TABLET 4.3, corrected in review).
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    Plasmoid.status: popupOpen ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.ActiveStatus
    activationTogglesExpanded: false
    hideOnWindowDeactivate: true
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: topBar.implicitWidth
    Layout.preferredWidth: topBar.implicitWidth
    Layout.maximumWidth: topBar.implicitWidth
    Layout.minimumHeight: 26
    Layout.preferredHeight: m.px(34)

    // ---- The top bar's width budget (the clock pill's coordinator, ADAPTIVE 5.1)
    property int budgetLevel: 0
    function budgetSaving(level: int): real {
        return topBar.budgetSaving(level);
    }

    // ---- Right edge: the board's 6 px from the screen edge (12 in tablet posture), whatever
    // margin the panel has (6, 4 with the north frame's side margins at 0, 10 in a 44 px bar).
    property real windowRightGap: 6
    function updateWindowGap() {
        const window = root.Window.window;
        if (window) {
            windowRightGap = Math.round(window.width - root.mapToItem(null, root.width, 0).x);
        }
    }
    onXChanged: Qt.callLater(updateWindowGap)
    onWidthChanged: Qt.callLater(updateWindowGap)
    onHeightChanged: Qt.callLater(updateWindowGap)
    Connections {
        target: root.parent
        ignoreUnknownSignals: true
        function onXChanged() {
            Qt.callLater(root.updateWindowGap);
        }
    }
    Connections {
        target: root.Window.window
        function onWidthChanged() {
            Qt.callLater(root.updateWindowGap);
        }
    }

    // ---- The pen widget in the same bar (its menu opens from the tablet row)
    readonly property Item penApplet: {
        let layout = root.parent;
        while (layout && !(layout instanceof GridLayout)) {
            layout = layout.parent;
        }
        if (!layout) {
            return null;
        }
        for (const child of layout.children) {
            // qmllint disable missing-property
            if (child.applet?.plasmoid?.pluginName === "org.plasmafusion.pen") {
                return child.applet;
            }
            // qmllint enable missing-property
        }
        return null;
    }
    // qmllint disable missing-property
    readonly property bool penPresent: penApplet !== null && penApplet.hasPen === true
    function openPenMenu() {
        if (penApplet) {
            setPopupOpen(false);
            penApplet.plasmoid.configuration.openRequest = "open:" + Date.now();
        }
    }
    // qmllint enable missing-property

    function togglePopup() {
        setPopupOpen(!popupOpen);
    }
    // The clipboard sheet (the clipboard button, Meta+V): the pop-up on its clipboard page, or
    // closed; Klipper's own pop-up where Plasma's clipboard module is missing. A request while the
    // clipboard service is still loading (just after the shell started) waits for it.
    readonly property bool clipboardShown: popupOpen && backend.page === "clipboard"
    property bool clipboardWaiting: false
    function showClipboard(open: bool): void {
        switch (Clip.opening(backend.clipboard.available, backend.clipboard.loading)) {
        case "wait":
            clipboardWaiting = open;
            return;
        case "legacy":
            clipboardWaiting = false;
            backend.clipboard.legacyPopup();
            return;
        }
        clipboardWaiting = false;
        if (!open) {
            setPopupOpen(false);
            return;
        }
        const wasOpen = popupOpen && popup.visible;
        requestedPage = "clipboard";
        setPopupOpen(true);
        if (wasOpen && popupContent) {
            // Already open on another page: the focus moves to the clipboard at once.
            Qt.callLater(() => root.popupContent.focusFirst());
        }
    }
    // Decided once the loader has settled (its item and status change one after the other).
    Connections {
        target: backend.clipboard
        function onLoadingChanged() {
            root.clipboardLoaded();
        }
        function onAvailableChanged() {
            root.clipboardLoaded();
        }
    }
    function clipboardLoaded(): void {
        if (clipboardWaiting && (backend.clipboard.available || !backend.clipboard.loading)) {
            Qt.callLater(() => {
                if (root.clipboardWaiting) {
                    root.showClipboard(true);
                }
            });
        }
    }
    // A device was plugged in (popupOnNewDevice): the sheet on the device list, unless the user is
    // busy on another page or in the Notification Centre.
    function showNewDevice(): void {
        if (centreOpen) {
            return;
        }
        if (!popupOpen) {
            setPopupOpen(true);
            backend.page = "devices";
        } else if (backend.page === "main") {
            backend.page = "devices";
        }
    }
    function setPopupOpen(open: bool) {
        if (open && centreOpen) {
            // after the Notification Centre's window is gone (see onHidden)
            centre.controlsNext = true;
            closeNotificationCentre(false);
            return;
        }
        if (open) {
            if (!popupOpen && openStarted === 0) {
                openStarted = Date.now();
            }
            contentWanted = true;
            placeAnchor();
            const start = String(Plasmoid.configuration.startPage || "main");
            backend.page = requestedPage !== "" ? requestedPage
                         : ["main", "wifi", "bluetooth", "audio", "power"].indexOf(start) !== -1 ? start : "main";
            backend.pageDirect = requestedPage !== "";
            requestedPage = "";
            // The settings are read again after the sheet's first frame (policyRefresh).
            policyRefresh.restart();
        }
        popupOpen = open;
    }
    // Places the pop-up's anchor so that the card ends popupScreenMargin px
    // from the screen edge (or at the widget's own edge when it sits further in);
    // in portrait tablet posture the card is centred on the screen.
    function placeAnchor() {
        const screen = Plasmoid.containment ? Plasmoid.containment.screenGeometry : null;
        const global = root.mapToGlobal(0, 0);
        if (!screen || screen.width <= 0) {
            popupAnchor.x = root.width - outerWidth;
            return;
        }
        const widgetRight = global.x + root.width;
        const popupRight = portraitSheet ? screen.x + (screen.width + outerWidth) / 2
                                         : Math.min(screen.x + screen.width - popupScreenMargin, widgetRight);
        popupAnchor.x = popupRight - outerWidth - global.x;

        popupAnchor.width = outerWidth;
        if (Plasmoid.location === PlasmaCore.Types.LeftEdge || Plasmoid.location === PlasmaCore.Types.RightEdge) {
            // Beside a vertical panel the pop-up opens next to the widget itself.
            popupAnchor.x = 0;
            popupAnchor.width = root.width;
        }

        // A pop-up of a non-floating panel is placed against the panel window's edge
        // (not the widget's), so measure from there to keep popupScreenMargin exact. The
        // height comes from the available area (the dock's reserve excluded, ADAPTIVE 5.3).
        const windowTop = global.y - root.mapToItem(null, 0, 0).y;
        const windowHeight = root.Window.height > 0 ? root.Window.height : root.height;
        const area = screenArea.height > 0 ? screenArea : screen;
        let available = area.height - popupGap - popupScreenMargin;
        if (Plasmoid.location === PlasmaCore.Types.TopEdge) {
            const panelBottom = Math.max(global.y + root.height, windowTop + windowHeight, area.y);
            available = area.y + area.height - panelBottom - popupGap - popupScreenMargin;
        } else if (Plasmoid.location === PlasmaCore.Types.BottomEdge) {
            const panelTop = Math.min(global.y, windowTop, area.y + area.height);
            available = panelTop - area.y - popupGap - popupScreenMargin;
        }
        maxPopupHeight = Math.max(320, available);
    }

    Connections {
        target: Plasmoid
        // The global shortcut (Meta+A) belongs to one widget: the one on the screen in use opens.
        function onActivated() {
            root.onActiveScreen(widget => widget.togglePopup());
        }
    }

    // ---- openRequest: "<mode>:<nonce>[:<output>]" (or "<mode> <nonce>"), written by other shell
    // parts through desktop scripting (the tablet script's right edge, Meta+N, Meta+V) and by the
    // live chips widget (keepawake: its Keep awake chip, with this widget's output). Without an
    // output only the widget on KWin's active screen acts, and only the leader when that is not
    // known either (code/requests.js).
    Connections {
        target: Plasmoid.configuration
        function onOpenRequestChanged() {
            const request = Requests.parse(Plasmoid.configuration.openRequest);
            if (request.mode === "") {
                return;
            }
            if (request.output !== "") {
                root.runRequest(request.mode, request.output);
                return;
            }
            DBus.SessionBus.asyncCall({
                "service": "org.kde.KWin",
                "path": "/KWin",
                "iface": "org.kde.KWin",
                "member": "activeOutputName",
                "arguments": []
            }, reply => root.runRequest(request.mode, String(reply.value || "")), () => root.runRequest(request.mode, ""));
        }
    }
    function runRequest(mode: string, output: string) {
        switch (Requests.decide(output, root.screenName, root.screenSettled, root.leader, false)) {
        case "wait":
            // Kept until the bar's output is known (2 s at most, then the guess decides): the
            // request is written once, and Meta+N, Meta+V or the edge swipe did nothing.
            waitingRequest = { "mode": mode, "output": output };
            requestWait.restart();
            return;
        case "skip":
            return;
        }
        performRequest(mode, output);
    }
    property var waitingRequest: null
    function runWaitingRequest(final: bool): void {
        const request = waitingRequest;
        if (!request || (!final && !screenSettled)) {
            return;
        }
        waitingRequest = null;
        requestWait.stop();
        if (Requests.decide(request.output, screenName, screenSettled, leader, true) === "act") {
            performRequest(request.mode, request.output);
        }
    }
    onScreenSettledChanged: runWaitingRequest(false)
    Timer {
        id: requestWait
        interval: 2000
        onTriggered: root.runWaitingRequest(true)
    }
    function performRequest(mode: string, output: string): void {
        console.info("quicksettings: openRequest " + mode + (output !== "" ? " on " + output : ""));
        switch (mode) {
        case "sheet":
        case "main":
            backend.showEmptyNotifications = false;
            setPopupOpen(true);
            break;
        case "notifications":
            if (openNotificationCentre()) {
                break;
            }
            backend.showEmptyNotifications = true;
            setPopupOpen(true);
            break;
        case "toggle":
            togglePopup();
            break;
        case "clipboard":
            showClipboard(!clipboardShown);
            break;
        case "keepawake":
            // The Keep awake page (the tile's chevron), opened on its own.
            requestedPage = "power";
            setPopupOpen(true);
            break;
        case "close":
            if (popupOpen) {
                setPopupOpen(false);
            }
            break;
        }
    }

    // ---- Testing hook (config key debugAction, cleared after use): "dump:TAG", or "keepawake:SECONDS"
    // for a timed Keep awake that ends after so many seconds (the scenario of a timer running out,
    // which the sheet offers only in hours).
    readonly property string debugAction: Plasmoid.configuration.debugAction
    onDebugActionChanged: Qt.callLater(runDebugAction)
    function runDebugAction(): void {
        const action = Plasmoid.configuration.debugAction;
        if (!action) {
            return;
        }
        Plasmoid.configuration.debugAction = "";
        const parts = action.split(":");
        if (parts[0] === "dump") {
            dump(parts.slice(1).join(":"));
        } else if (parts[0] === "keepawake") {
            backend.keepAwake.forSeconds(Math.min(86400, parseInt(parts[1]) || 0));
        }
    }
    // Every visible target (a button, a slider, a mouse area) under `item`, as
    // "name x,y wxh" with the centre in screen coordinates (window origin ox, oy).
    function targets(item: Item, ox: real, oy: real, out: var) {
        if (!item || !item.visible || item.opacity === 0) {
            return;
        }
        // qmllint disable missing-property
        const interactive = typeof item.clicked === "function" || typeof item.editingFinished === "function"
            || (item.moved !== undefined && item.value !== undefined);
        if (interactive && item.width > 0 && item.height > 0 && item.enabled !== false && item.Accessible.ignored !== true) {
            const c = item.mapToItem(null, item.width / 2, item.height / 2);
            const name = item.objectName || item.Accessible.name || item.text || "?";
            out.push(String(name).replace(/[;,]/g, " ") + " " + Math.round(ox + c.x) + "," + Math.round(oy + c.y) + " "
                     + Math.round(item.width) + "x" + Math.round(item.height));
        }
        // qmllint enable missing-property
        for (let i = 0; i < item.children.length; ++i) {
            targets(item.children[i], ox, oy, out);
        }
    }
    function dump(tag: string) {
        const bar = [];
        const window = root.Window.window;
        targets(topBar, window ? window.x : 0, window ? window.y : 0, bar);
        const sheet = [];
        const content = popupContent;
        if (content && popup.visible) {
            targets(content, popup.x, popup.y, sheet);
        }
        const small = sheet.concat(bar).filter(t => {
            const size = t.split(" ").pop().split("x").map(Number);
            return size[0] < 44 || size[1] < 44;
        });
        const policy = backend.tabletPolicy;
        // qmllint disable missing-property
        const scroller = content ? content.scroller : null;
        console.info("quicksettings: dump " + tag + ": tablet " + tablet + ", sheet " + (popup.visible ? popup.x + "," + popup.y + " "
                     + popup.width + "x" + popup.height : "closed") + ", max " + Math.round(maxPopupHeight) + ", outer " + Math.round(outerWidth)
                     + ", scroll " + (scroller ? Math.round(scroller.contentHeight) + "/" + Math.round(scroller.height) + (scroller.interactive ? " interactive at " + Math.round(scroller.contentY) : "") : "-")
                     + ", bt model " + (backend.bt.devicesModel ? "created" : "none")
                     + ", dnd " + backend.dnd.subtitle
                     + ", keep awake " + backend.keepAwake.subtitle
                     + ", power " + backend.profile.subtitle + (backend.profile.note ? " [" + backend.profile.note.replace(/\n/g, " | ") + "]" : "")
                     + ", hotspot " + backend.net.hotspotSubtitle
                     + ", devices " + backend.devices.count
                     + ", notifications " + backend.notif.count + " (" + backend.notif.unread + " unread"
                     + (backend.notif.available ? ")" : ", off)")
                     + ", tray " + (backend.trayRevealed.length > 0 ? backend.trayRevealed.join("+") : "-")
                     + ", screen " + (root.screenName || "?") + (root.screenSettled ? "" : " (guess)")
                     + (root.leader ? " leader" : "") + " of " + Instances.items.length
                     + ", page " + backend.page + (backend.pageDirect ? " (direct)" : "")
                     + (content && content.pageItem && backend.page === "clipboard"
                        ? " [" + content.pageItem.mode + ", " + content.pageItem.count + " shown of "
                          + (backend.clipboard.service ? backend.clipboard.service.sourceCount + ", "
                             + backend.clipboard.service.starredCount + " starred" : "-")
                          + ", current " + content.pageItem.list.currentIndex + ", query '" + content.pageItem.searchField.text + "']" : "")
                     + ", focus " + (popup.activeFocusItem ? popup.activeFocusItem.Accessible.name : "-")
                     + ", policy " + (policy ? "im " + (policy.inputMethod === "" ? "off" : "on") + " window " + policy.windowMode + " rotation "
                                      + (policy.rotationLocked ? "locked" : "free") + " mode " + policy.tabletModeSetting + " osk "
                                      + (policy.oskAvailable ? "available" : "none") : "-")
                     + ", under 44: " + small.length);
        // qmllint enable missing-property
        console.info("quicksettings: dump " + tag + " bar: " + bar.join("; "));
        console.info("quicksettings: dump " + tag + " sheet: " + sheet.join("; "));
        // The sheet's window against its content: the content item's place and size in the
        // window, the size the content asks for and the Plasma style's frame padding.
        // qmllint disable missing-property
        console.info("quicksettings: dump " + tag + " frame: " + (content && popup.visible
            ? "window " + popup.width + "x" + popup.height + ", padding " + [popup.leftPadding, popup.topPadding, popup.rightPadding, popup.bottomPadding].join(",")
              + ", item " + Math.round(contentLoader.x) + "," + Math.round(contentLoader.y) + " " + Math.round(contentLoader.width) + "x" + Math.round(contentLoader.height)
              + ", wanted " + Math.round(content.implicitWidth) + "x" + Math.round(content.implicitHeight)
              + ", page " + Math.round(content.scroller.contentHeight)
              + ", screen " + root.screenArea.x + "," + root.screenArea.y + " " + root.screenArea.width + "x" + root.screenArea.height
              + " at " + root.Screen.devicePixelRatio
            : "closed"));
        // qmllint enable missing-property
    }

    readonly property Backend qsBackend: backend
    Backend {
        id: backend
        popupOpen: root.popupOpen
        containment: Plasmoid.containment
        removed: root.removed
        showKeyboardLayout: Plasmoid.configuration.showKeyboardLayout
        keyboardLayoutAlways: Plasmoid.configuration.keyboardLayoutAlways
        showKdeConnect: Plasmoid.configuration.showKdeConnect
        showClipboard: Plasmoid.configuration.showClipboard
        showCopyText: Plasmoid.configuration.showCopyText
        showBatteryPercent: Plasmoid.configuration.showBatteryPercent
        showNotifications: Plasmoid.configuration.showNotifications
        tileOrder: Plasmoid.configuration.tileOrder
        hiddenTiles: Plasmoid.configuration.hiddenTiles
        onTileLayoutRequested: (order, hidden) => {
            Plasmoid.configuration.tileOrder = order;
            Plasmoid.configuration.hiddenTiles = hidden;
        }
        // Stock Disks & Devices opens its pop-up on a new device (popupOnNewDevice, default on).
        // Every bar's widget sees the device: the leader opens the sheet on the screen in use.
        onDeviceAdded: udi => {
            if (root.leader && Plasmoid.configuration.popupOnNewDevice) {
                root.onActiveScreen(widget => widget.showNewDevice());
            }
        }
        lightLookAndFeel: Plasmoid.configuration.lightLookAndFeel
        darkLookAndFeel: Plasmoid.configuration.darkLookAndFeel
        keyboardPolicy: Plasmoid.configuration.keyboardPolicy
        tablet: tabletState.tablet
        postureKnown: tabletState.fromKWin
        tabletAvailable: tabletState.available
        screenName: root.screenName
        leader: root.leader
        barCompact: tabletState.tablet || root.budgetLevel >= 2
        penPresent: root.penPresent
        notificationsApart: root.notificationsApart
        onPenRequested: root.openPenMenu()
        onCloseRequested: root.setPopupOpen(false)
        onNotificationCentreRequested: root.openNotificationCentre()
    }
    Binding {
        target: backend.pal
        property: "touch"
        value: m.touch
    }
    Binding {
        target: backend.pal
        property: "tablet"
        value: tabletState.tablet
    }

    TopBar {
        id: topBar
        anchors.fill: parent
        backend: backend
        metrics: m
        popupOpen: root.popupOpen
        tablet: tabletState.tablet
        budgetLevel: root.budgetLevel
        endPadding: Math.max(0, (tabletState.tablet ? 12 : 6) - root.windowRightGap)
        onPillPressed: {
            root.contentWanted = true;
            root.openOnPress = !root.popupOpen;
        }
        onPillClicked: {
            backend.showEmptyNotifications = false;
            root.setPopupOpen(root.openOnPress);
        }
        onBellPressed: {
            root.contentWanted = true;
            root.openOnPress = !root.popupOpen;
        }
        onClipboardPressed: {
            root.contentWanted = true;
            root.openOnPress = !root.clipboardShown;
        }
        onClipboardClicked: root.showClipboard(root.openOnPress)
        // Copy text from the screen, as quick settings' header button (the sheet closes first).
        onCopyTextClicked: backend.session.copyText()
        onBellClicked: {
            if (root.notificationsApart) {
                if (root.centreOpen) {
                    root.closeNotificationCentre(false);
                } else {
                    root.openNotificationCentre();
                }
                return;
            }
            backend.showEmptyNotifications = root.openOnPress;
            root.setPopupOpen(root.openOnPress);
        }
        onPulled: fromBell => {
            if (fromBell && root.notificationsApart) {
                console.info("quicksettings: pull-down on the bell opens the notification centre");
                root.openNotificationCentre();
                return;
            }
            if (!root.popupOpen) {
                console.info("quicksettings: pull-down opens the sheet");
                backend.showEmptyNotifications = fromBell;
                root.setPopupOpen(true);
            }
        }
    }
    HoverHandler {
        onHoveredChanged: if (hovered) root.contentWanted = true
    }

    // ---- The Notification Centre (tablet posture, TABLET2 S1): the bell, a pull-down on the bell
    // or on the clock pill (the clock pill calls openNotificationCentre()) and Meta+N open it; the
    // status pill opens the controls without the list. kcfg tabletNotifications "together" keeps
    // one sheet as on the laptop.
    readonly property bool notificationsApart: tabletState.tablet && Plasmoid.configuration.tabletNotifications !== "together"
    property bool centreOpen: false
    function openNotificationCentre(): bool {
        if (!notificationsApart || !backend.notif.available) {
            return false;
        }
        if (popupOpen) {
            setPopupOpen(false);
        }
        const screen = Plasmoid.containment ? Plasmoid.containment.screenGeometry : null;
        if (screen && screen.width > 0) {
            centre.area = Qt.rect(screen.x, screen.y, screen.width, screen.height);
        }
        const window = root.Window.window;
        centre.topBar = window ? window.height : 44;
        centre.screenNumber = Plasmoid.containment ? Plasmoid.containment.screen : 0;
        centre.wanted = true;
        centre.openStarted = Date.now();
        centreOpen = true;
        console.info("quicksettings: notification centre opens");
        return true;
    }
    function closeNotificationCentre(immediate: bool): void {
        if (!centreOpen) {
            return;
        }
        centreOpen = false;
        backend.notif.markRead();
        if (immediate && centre.content) {
            centre.content.snapClosed();
        }
    }
    onNotificationsApartChanged: {
        if (!notificationsApart) {
            closeNotificationCentre(true);
        }
    }
    NotificationCentre {
        id: centre
        backend: root.qsBackend
        open: root.centreOpen
        glass: Plasmoid.configuration.glass
        onCloseRequested: root.closeNotificationCentre(false)
        onDeactivated: root.closeNotificationCentre(true)
        // The controls open once the sheet's window is gone and KWin has activated the next window
        // (200 ms): opened earlier, the pop-up lost the activation at once and closed (s1h D1, F1).
        property bool controlsNext: false
        onControlsRequested: {
            controlsNext = true;
            root.closeNotificationCentre(false);
        }
        onHidden: {
            if (controlsNext) {
                controlsNext = false;
                controlsTimer.restart();
            }
        }
    }
    Timer {
        id: controlsTimer
        interval: 200
        onTriggered: {
            backend.showEmptyNotifications = false;
            root.setPopupOpen(true);
        }
    }

    // Invisible item the pop-up is placed under (see placeAnchor()).
    Item {
        id: popupAnchor
        y: 0
        width: root.outerWidth
        height: root.height
    }

    // After the pop-up closed itself (focus moved elsewhere), follow its state a
    // little later, so that a click on the pill closes rather than reopens it.
    Timer {
        id: closeSync
        interval: 150
        onTriggered: {
            if (!popup.visible) {
                root.popupOpen = false;
            }
        }
    }

    // Whether the notification list was on the sheet while it was open: closing it marks the
    // notifications read only then. Opened on the clipboard page (Meta+V) and closed there, it
    // cleared the unread count and the bell though no notification had been shown.
    property bool notificationsSeen: false
    // The list's own condition: with Show notifications off it is hidden, and so nothing is seen.
    readonly property bool notificationListShown: popupOpen && backend.notif.listShown
    onNotificationListShownChanged: {
        if (notificationListShown) {
            notificationsSeen = true;
        }
    }
    onPopupOpenChanged: {
        if (!popupOpen) {
            if (notificationsSeen) {
                backend.notif.markRead();
            }
            notificationsSeen = false;
            resetPage.restart();
        }
    }
    Timer {
        id: resetPage
        interval: 300
        onTriggered: {
            if (!root.popupOpen) {
                backend.page = "main";
                backend.pageDirect = false;
                backend.showEmptyNotifications = false;
            }
        }
    }

    // The pop-up's content is built in the background a few seconds after start, or at once
    // when the pointer reaches the bar or anything asks for it (BACKLOG S2).
    property bool contentWanted: false
    Timer {
        interval: 4000
        running: !root.contentWanted
        onTriggered: root.contentWanted = true
    }
    property real openStarted: 0
    property bool contentShown: false
    // Frames swapped in the 500 ms after the open's first frame (the "sheet settled" line; survey
    // 4: the sheet had no frame count, only the first-frame latency). -1 while not counting.
    property int openSettleFrames: -1
    // Reads the tablet settings again once the sheet is up (processes and D-Bus calls would
    // delay its first frame).
    Timer {
        id: policyRefresh
        interval: 250
        onTriggered: {
            if (root.popupOpen) {
                // the charge limit can change in Energy Saving too
                backend.charge.refresh();
            }
            if (root.popupOpen && backend.tabletPolicy) {
                backend.tabletPolicy.refresh();
                if (root.tablet) {
                    backend.tabletPolicy.checkRotationLock();
                }
            }
        }
    }

    PlasmaCore.AppletPopup {
        id: popup

        visualParent: popupAnchor
        popupDirection: {
            switch (Plasmoid.location) {
            case PlasmaCore.Types.BottomEdge:
                return Qt.TopEdge;
            case PlasmaCore.Types.LeftEdge:
                return Qt.RightEdge;
            case PlasmaCore.Types.RightEdge:
                return Qt.LeftEdge;
            default:
                return Qt.BottomEdge;
            }
        }
        margin: root.popupGap
        floating: !root.inPanel
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        visible: root.popupOpen && contentLoader.status === Loader.Ready

        onVisibleChanged: {
            const content = contentLoader.item as PopupContent;
            if (visible) {
                Qt.callLater(root.fitWindow);
            }
            if (visible && content) {
                popup.requestActivate();
                content.forceActiveFocus();
                content.focusFirst();
            } else if (!visible) {
                closeSync.restart();
            }
        }

        mainItem: Loader {
            id: contentLoader
            active: root.contentWanted
            asynchronous: true
            focus: true
            Layout.minimumWidth: root.popupContent ? root.popupContent.Layout.minimumWidth : root.outerWidth
            Layout.maximumWidth: root.popupContent ? root.popupContent.Layout.maximumWidth : root.outerWidth
            Layout.preferredWidth: root.popupContent ? root.popupContent.Layout.preferredWidth : root.outerWidth
            Layout.minimumHeight: root.popupContent ? root.popupContent.Layout.minimumHeight : 0
            Layout.maximumHeight: root.popupContent ? root.popupContent.Layout.maximumHeight : 0
            Layout.preferredHeight: root.popupContent ? root.popupContent.Layout.preferredHeight : 0
            sourceComponent: PopupContent {
                // Qualified: inside a component an unqualified `backend` is the property itself.
                backend: root.qsBackend
                open: root.popupOpen
                tablet: tabletState.tablet
                touch: tabletState.tablet || m.touch
                outerWidth: root.outerWidth
                framePaddingLeft: root.framePaddingLeft
                framePaddingRight: root.framePaddingRight
                framePaddingTop: root.framePaddingTop
                framePaddingBottom: root.framePaddingBottom
                maxOuterHeight: root.maxPopupHeight
                focus: true
            }
        }
        Connections {
            target: popup
            function onBordersChanged() {
                Qt.callLater(root.readFramePadding);
            }
            function onPaddingChanged() {
                Qt.callLater(root.readFramePadding);
            }
        }
        Connections {
            target: popup
            enabled: root.openStarted > 0 || root.openSettleFrames >= 0
            function onFrameSwapped() {
                if (!popup.visible) {
                    return;
                }
                if (root.openStarted === 0) {
                    root.openSettleFrames++;
                    return;
                }
                console.info("quicksettings: sheet " + (root.contentShown ? "open" : "first open") + ", first frame after "
                             + (Date.now() - root.openStarted) + " ms");
                root.openStarted = 0;
                root.contentShown = true;
                root.openSettleFrames = 0;
                openSettle.restart();
            }
        }
        // The open animation runs 200-250 ms (Motion popupIn/surface): 500 ms of frames cover it.
        Timer {
            id: openSettle
            interval: 500
            onTriggered: {
                console.info("quicksettings: sheet settled, " + root.openSettleFrames + " frames in 500 ms");
                root.openSettleFrames = -1;
            }
        }
    }
}
