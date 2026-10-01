// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.dbus as DBus

import "components"

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
    property real maxPopupHeight: 820

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
            backend.page = ["main", "wifi", "bluetooth", "audio"].indexOf(start) !== -1 ? start : "main";
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
        function onActivated() {
            root.togglePopup();
        }
    }

    // ---- openRequest: "<mode>:<nonce>[:<output>]" (or "<mode> <nonce>"), written by other shell
    // parts through desktop scripting (the tablet script's right edge, Meta+N). Without an
    // output only the widget on KWin's active screen acts.
    Connections {
        target: Plasmoid.configuration
        function onOpenRequestChanged() {
            const parts = String(Plasmoid.configuration.openRequest || "").split(/[: ]/);
            if (parts[0] === "") {
                return;
            }
            const output = parts.length > 2 ? parts.slice(2).join(":") : "";
            if (output !== "") {
                root.runRequest(parts[0], output);
                return;
            }
            DBus.SessionBus.asyncCall({
                "service": "org.kde.KWin",
                "path": "/KWin",
                "iface": "org.kde.KWin",
                "member": "activeOutputName",
                "arguments": []
            }, reply => root.runRequest(parts[0], String(reply.value || "")), () => root.runRequest(parts[0], ""));
        }
    }
    function runRequest(mode: string, output: string) {
        const mine = String(root.Screen.name || "");
        if (output !== "" && mine !== "" && output !== mine) {
            return;
        }
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
        case "close":
            if (popupOpen) {
                setPopupOpen(false);
            }
            break;
        }
    }

    // ---- Testing hook (config key debugAction, cleared after use): "dump:TAG".
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
        }
    }
    // Every visible target (a button, a slider, a mouse area) under `item`, as
    // "name x,y wxh" with the centre in screen coordinates (window origin ox, oy).
    function targets(item: Item, ox: real, oy: real, out: var) {
        if (!item || !item.visible || item.opacity === 0) {
            return;
        }
        // qmllint disable missing-property
        const interactive = typeof item.clicked === "function" || (item.moved !== undefined && item.value !== undefined);
        if (interactive && item.width > 0 && item.height > 0 && item.enabled !== false && item.Accessible.ignored !== true) {
            const c = item.mapToItem(null, item.width / 2, item.height / 2);
            const name = item.objectName || item.text || item.Accessible.name || "?";
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
                     + ", policy " + (policy ? "im " + (policy.inputMethod === "" ? "off" : "on") + " window " + policy.windowMode + " rotation "
                                      + (policy.rotationLocked ? "locked" : "free") + " mode " + policy.tabletModeSetting + " osk "
                                      + (policy.oskAvailable ? "available" : "none") : "-")
                     + ", under 44: " + small.length);
        // qmllint enable missing-property
        console.info("quicksettings: dump " + tag + " bar: " + bar.join("; "));
        console.info("quicksettings: dump " + tag + " sheet: " + sheet.join("; "));
    }

    readonly property Backend qsBackend: backend
    Backend {
        id: backend
        popupOpen: root.popupOpen
        showKeyboardLayout: Plasmoid.configuration.showKeyboardLayout
        keyboardLayoutAlways: Plasmoid.configuration.keyboardLayoutAlways
        showKdeConnect: Plasmoid.configuration.showKdeConnect
        showClipboard: Plasmoid.configuration.showClipboard
        showBatteryPercent: Plasmoid.configuration.showBatteryPercent
        showNotifications: Plasmoid.configuration.showNotifications
        lightLookAndFeel: Plasmoid.configuration.lightLookAndFeel
        darkLookAndFeel: Plasmoid.configuration.darkLookAndFeel
        keyboardPolicy: Plasmoid.configuration.keyboardPolicy
        tablet: tabletState.tablet
        postureKnown: tabletState.fromKWin
        tabletAvailable: tabletState.available
        screenName: String(root.Screen.name || "")
        barCompact: tabletState.tablet || root.budgetLevel >= 2
        penPresent: root.penPresent
        notificationsApart: root.notificationsApart
        onPenRequested: root.openPenMenu()
        onCloseRequested: root.setPopupOpen(false)
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

    onPopupOpenChanged: {
        if (!popupOpen) {
            backend.notif.markRead();
            resetPage.restart();
        }
    }
    Timer {
        id: resetPage
        interval: 300
        onTriggered: {
            if (!root.popupOpen) {
                backend.page = "main";
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
                framePaddingLeft: popup.leftPadding
                framePaddingRight: popup.rightPadding
                framePaddingTop: popup.topPadding
                framePaddingBottom: popup.bottomPadding
                maxOuterHeight: root.maxPopupHeight
                focus: true
            }
        }
        Connections {
            target: popup
            enabled: root.openStarted > 0
            function onFrameSwapped() {
                if (!popup.visible) {
                    return;
                }
                console.info("quicksettings: sheet " + (root.contentShown ? "open" : "first open") + ", first frame after "
                             + (Date.now() - root.openStarted) + " ms");
                root.openStarted = 0;
                root.contentShown = true;
            }
        }
    }
}
