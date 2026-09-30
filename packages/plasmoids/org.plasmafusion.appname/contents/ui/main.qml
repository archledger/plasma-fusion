/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.workspace.dbus as DBus

// Top-left of the Plasma Fusion top bar (Main / MainLight boards): a 32x26 button with the
// Fusion logo that opens the launcher, then the active application's name in Manrope 13 px
// ExtraBold ("Desktop" when no window is focused). The global menu is the stock
// org.kde.plasma.appmenu widget placed after this one.
//
// In tablet posture (TABLET 4.3) the button and the name become the window pill: 32 px tall,
// radius 16, the app icon (20 px) and the name (14 px 800); only the icon in portrait or on a
// narrow screen. A tap or a pull-down opens the window card (WindowCard.qml) for the active
// window; with no active window it opens the launcher, as the logo does.
//
// The top bar's width budget (ADAPTIVE 5.1, run by the clock pill) sets `budgetLevel`; from
// step 3 only the logo (tablet: the app icon) is shown.
PlasmoidItem {
    id: root

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool tablet: tabletState.tablet && !vertical

    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    FusionAccent {
        id: accent
    }
    // Text scale and pixel grid of the panel window (docs/parts/shell-topbar.md, "Text scale").
    FusionMetrics {
        id: m
        area: Plasmoid.containment ? Plasmoid.containment.availableScreenRect : Qt.rect(0, 0, 1440, 900)
        tablet: tabletState.tablet
    }

    // Board geometry (px): header padding-left 10, button 32x26 radius 8, gap 2, name padding
    // 0 10 0 6, all scaled with the text except the radius. The logo lands 10 px from the
    // screen edge: `startPadding` (default 4) is the space before it behind the panel's own
    // 6 px margin, and the padding follows the margin the panel really has (4 px with the
    // north frame's side margins at 0, 10 px in a 44 px tablet bar). The button is never
    // taller than the panel row (a bar built for a smaller text size).
    readonly property int startPadding: Plasmoid.configuration.startPadding
    readonly property real buttonWidth: m.px(32)
    readonly property real buttonHeight: vertical ? m.px(26) : Math.min(m.px(26), Math.max(1, height - m.px(8)))
    readonly property real nameGap: m.px(2 + 6)
    readonly property real nameEndPadding: m.px(Plasmoid.configuration.endPadding)
    // 220 px, 140 px on a narrow screen (ADAPTIVE 5.1), scaled with the text.
    readonly property real nameMaxWidth: m.px(m.compactWidth ? Math.min(140, Plasmoid.configuration.maximumNameWidth)
                                                           : Plasmoid.configuration.maximumNameWidth)

    // x of this widget in the panel window (the panel's left margin for the first widget).
    property real windowX: 6
    readonly property real leadingPadding: vertical ? 0
        : windowX < 16 ? Math.max(0, startPadding + 6 - windowX) : startPadding
    function updateWindowX() {
        if (root.Window.window) {
            windowX = Math.round(root.mapToItem(null, 0, 0).x);
        }
    }
    onXChanged: Qt.callLater(updateWindowX)
    onHeightChanged: Qt.callLater(updateWindowX)
    Connections {
        target: root.parent
        ignoreUnknownSignals: true
        function onXChanged() {
            Qt.callLater(root.updateWindowX);
        }
    }
    Connections {
        target: root.Window.window
        function onWidthChanged() {
            Qt.callLater(root.updateWindowX);
        }
    }

    // ---- Width budget (ADAPTIVE 5.1): written by the clock pill's coordinator.
    property int budgetLevel: 0
    // Tablet posture in portrait or on a narrow screen always shows only the icon (TABLET 4.3).
    readonly property bool forcedIconOnly: tablet && (m.portrait || m.compactWidth)
    readonly property bool iconOnly: forcedIconOnly || budgetLevel >= 3
    readonly property real nameSpan: (tablet ? m.px(8) : nameGap) + Math.min(nameLabel.implicitWidth, nameMaxWidth)
    // Width this widget gives up at a budget step, against step 0 (the coordinator's question).
    function budgetSaving(level: int): real {
        return !vertical && !forcedIconOnly && level >= 3 ? nameSpan : 0;
    }

    // Colours follow the colour scheme: dark boards use white tints, light boards the text ink.
    readonly property bool dark: {
        const c = Kirigami.Theme.backgroundColor;
        return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
    }
    readonly property color ink: dark ? "#ffffff" : Kirigami.Theme.textColor
    function tint(alpha: real): color {
        return Qt.rgba(ink.r, ink.g, ink.b, alpha);
    }

    // The active application: name ("" while no window is active), icon and window id.
    property string appName: ""
    property var appIcon: ""
    property string appIconName: ""
    property var appWindowIds: []
    readonly property bool hasWindow: appWindowIds.length > 0
    readonly property string shownName: appName !== ""
        ? appName
        : i18nc("@label top bar title when no window is focused", "Desktop")

    // The board draws the logo button filled while the launcher is open. The launcher lives in
    // another panel, so its state cannot be read; it is followed through window focus instead:
    // a toggle request (this button, its shortcut, or the shell's "Activate Application
    // Launcher" action on Alt+F1) flips the state and expects one focus change as its result
    // (the launcher taking focus, or giving it back). Any later focus change means the launcher
    // closed by itself (Esc, Meta, a click outside, an application started), also when the focus
    // goes back to the desktop and no application window becomes active. The Meta key reaches
    // the shell through KWin directly, so a launcher opened with it does not light the button.
    // TasksModel reports activation changes of every window, the shell's own included, through
    // activeTaskChanged, even when the active task itself stays invalid.
    property bool launcherOpen: false
    property bool requestPending: false
    // activeTaskChanged signals in the current burst. A focus change sends at least two (one
    // window loses the focus, another gets it); one alone is a window of the shell going away
    // (a tooltip, a notification) and says nothing about the launcher.
    property int focusSignals: 0

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    // The whole bar height is the hit area (TABLET 4.3, corrected in review); the button and
    // the pill are drawn centred in it.
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    Plasmoid.status: cardOpen ? PlasmaCore.Types.RequiresAttentionStatus : PlasmaCore.Types.ActiveStatus
    activationTogglesExpanded: false
    toolTipMainText: ""
    toolTipSubText: ""

    Layout.minimumWidth: vertical ? -1 : row.implicitWidth
    Layout.preferredWidth: vertical ? -1 : row.implicitWidth
    Layout.maximumWidth: vertical ? Infinity : row.implicitWidth
    Layout.minimumHeight: vertical ? buttonHeight : -1
    Layout.preferredHeight: vertical ? buttonHeight : -1
    Layout.maximumHeight: vertical ? buttonHeight : Infinity

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            text: i18nc("@action:inmenu", "Open Launcher")
            icon.name: "start-here-kde-symbolic"
            onTriggered: root.openLauncher()
        }
    ]

    // The shell's "Activate Application Launcher" action: it toggles the first launcher widget
    // (X-Plasma-Provides org.kde.plasma.launchermenu: the Plasma Fusion launcher, or Kickoff)
    // in a panel of the active screen, exactly as the Meta key does.
    function openLauncher() {
        noteLauncherToggle();
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell",
            "path": "/PlasmaShell",
            "iface": "org.kde.PlasmaShell",
            "member": "activateLauncherMenu",
            "arguments": []
        }, () => {}, () => {
            root.launcherOpen = false;
            root.requestPending = false;
        });
    }

    // The pill in tablet posture: the window card for the active window, else the launcher.
    function activatePill() {
        if (cardOpen) {
            setCardOpen(false);
        } else if (hasWindow) {
            setCardOpen(true);
        } else {
            openLauncher();
        }
    }

    // A toggle of the launcher was requested: flip the shown state and wait for its result.
    function noteLauncherToggle() {
        launcherOpen = !launcherOpen;
        requestPending = true;
        // A focus change noticed just before the request is not its result.
        focusSettle.stop();
        focusSignals = 0;
        requestTimeout.restart();
    }

    // A burst of focus changes has settled.
    function focusMoved() {
        const signals = focusSignals;
        focusSignals = 0;
        if (tasksModel.activeTask.valid || Application.state !== Qt.ApplicationActive) {
            // An application window is active, or no shell window is: the launcher is closed.
            launcherOpen = false;
            requestPending = false;
        } else if (signals < 2) {
            // No focus change.
            return;
        } else if (requestPending) {
            // The result of the last request (the launcher opened or closed).
            requestPending = false;
        } else {
            // The shell's focus moved without a request: the launcher closed by itself.
            launcherOpen = false;
        }
    }

    // Folds the several activation signals of one focus change into one.
    Timer {
        id: focusSettle
        interval: 200
        onTriggered: root.focusMoved()
    }

    // A request that caused no focus change within this time (no launcher, or it failed to
    // open) no longer waits for one.
    Timer {
        id: requestTimeout
        interval: 3000
        onTriggered: root.requestPending = false
    }

    // The shell's own launcher action (its Alt+F1 shortcut): the same toggle, requested elsewhere.
    readonly property QtObject launcherAction: {
        const containment = Plasmoid.containment;
        const corona = containment ? containment.corona : null;
        return corona && typeof corona.action === "function"
            ? corona.action("activate application launcher") : null;
    }
    Connections {
        target: root.launcherAction
        ignoreUnknownSignals: true
        function onTriggered() {
            root.noteLauncherToggle();
        }
    }

    // Reads the active task's name, icon and window ids. Called on changes instead of being a
    // binding, so the model's frequent data updates can never form a binding loop.
    function refresh() {
        // While the panel itself has keyboard focus (Tab navigation, a text field in a panel
        // widget) or the window card is open, no application window is active; keep the last
        // window, as the global menu does.
        const containment = Plasmoid.containment;
        if (cardOpen || (containment && containment.status === PlasmaCore.Types.AcceptingInputStatus)) {
            return;
        }
        const index = tasksModel.activeTask;
        if (!index || !index.valid) {
            appName = "";
            appIcon = "";
            appIconName = "";
            appWindowIds = [];
            return;
        }
        let name = tasksModel.data(index, TaskManager.AbstractTasksModel.AppName);
        if (!name) {
            name = tasksModel.data(index, TaskManager.AbstractTasksModel.GenericName);
        }
        if (!name) {
            name = tasksModel.data(index, Qt.DisplayRole);
        }
        appName = name ? String(name) : "";
        // Only the pill shows the icon; the laptop row needs the name alone.
        if (tablet) {
            appIcon = tasksModel.data(index, Qt.DecorationRole) ?? "";
            appIconName = String(tasksModel.data(index, TaskManager.AbstractTasksModel.AppId) ?? "").replace(/\.desktop$/, "");
        }
        const ids = tasksModel.data(index, TaskManager.AbstractTasksModel.WinIdList);
        appWindowIds = ids ? Array.from(ids).map(String) : [];
    }
    onTabletChanged: Qt.callLater(refresh)

    TaskManager.TasksModel {
        id: tasksModel
        // Only the active task matters: no grouping, sorting or filtering work.
        groupMode: TaskManager.TasksModel.GroupDisabled
        sortMode: TaskManager.TasksModel.SortDisabled
        filterByVirtualDesktop: false
        filterByActivity: false
        filterByScreen: false

        onActiveTaskChanged: {
            root.focusSignals++;
            focusSettle.restart();
            Qt.callLater(root.refresh);
            root.activeTaskMoved();
        }
        // Names rarely change, but the model has no per-role signal in QML; refresh() only
        // reads a few roles of one row and Qt.callLater folds bursts (window moves) into one.
        onDataChanged: Qt.callLater(root.refresh)
        onCountChanged: Qt.callLater(root.refresh)
    }

    Connections {
        target: Application
        function onStateChanged() {
            focusSettle.restart();
        }
    }

    Connections {
        target: Plasmoid.containment
        function onStatusChanged() {
            Qt.callLater(root.refresh);
        }
    }

    Connections {
        target: Plasmoid
        // The widget's own global shortcut opens the launcher as well.
        function onActivated() {
            root.openLauncher();
        }
    }

    Component.onCompleted: {
        refresh();
        Qt.callLater(updateWindowX);
    }

    // ---- The window card's actions (TABLET 4.3; Windowed per window, LEAD-1 resolution 11)

    // The row of the card's window, looked up by its window id when an action runs (rows move
    // as windows open and close).
    function cardRow(): int {
        const id = cardWindow.length > 0 ? cardWindow[0] : "";
        for (let row = 0; id !== "" && row < tasksModel.count; ++row) {
            const ids = tasksModel.data(tasksModel.makeModelIndex(row), TaskManager.AbstractTasksModel.WinIdList);
            if (ids && Array.from(ids).map(String).indexOf(id) >= 0) {
                return row;
            }
        }
        return -1;
    }
    function cardData(role: int): var {
        const row = cardRow();
        return row >= 0 ? tasksModel.data(tasksModel.makeModelIndex(row), role) : undefined;
    }

    property bool cardOpen: false
    property bool cardWanted: false
    property var cardWindow: []
    property string cardTitle: ""
    property bool cardMaximized: false
    property real openStarted: 0
    property bool cardShown: false

    function setCardOpen(open: bool) {
        if (open) {
            cardWindow = appWindowIds;
            cardTitle = String(cardData(Qt.DisplayRole) ?? "");
            cardMaximized = cardData(TaskManager.AbstractTasksModel.IsMaximized) === true;
            if (openStarted === 0) {
                openStarted = Date.now();
            }
            cardWanted = true;
        }
        cardOpen = open;
    }

    // Split waits for the window to be active: KWin's quick tile shortcut acts on the active
    // window, and the card itself had the focus.
    property string pendingTile: ""
    function cardAction(action: string) {
        const row = cardRow();
        console.info("appname: window card action " + action + (row < 0 ? " (window gone)" : ""));
        setCardOpen(false);
        if (row < 0) {
            return;
        }
        const index = tasksModel.makeModelIndex(row);
        switch (action) {
        case "windowed":
        case "fullscreen":
            // Un-maximizing gives the title bar back (KWin's borderless maximized option); the
            // tablet script then leaves this window alone until the next fold.
            tasksModel.requestToggleMaximized(index);
            break;
        case "left":
        case "right":
            pendingTile = action === "left" ? "Window Quick Tile Left" : "Window Quick Tile Right";
            tasksModel.requestActivate(index);
            tileTimeout.restart();
            Qt.callLater(activeTaskMoved);
            break;
        case "minimize":
            tasksModel.requestToggleMinimized(index);
            break;
        case "close":
            tasksModel.requestClose(index);
            break;
        }
    }
    function activeTaskMoved() {
        if (pendingTile === "") {
            return;
        }
        const index = tasksModel.activeTask;
        const ids = index && index.valid ? tasksModel.data(index, TaskManager.AbstractTasksModel.WinIdList) : null;
        if (!ids || Array.from(ids).map(String).indexOf(cardWindow[0]) < 0) {
            return;
        }
        const shortcut = pendingTile;
        pendingTile = "";
        tileTimeout.stop();
        console.info("appname: invokeShortcut " + shortcut);
        DBus.SessionBus.asyncCall({
            "service": "org.kde.kglobalaccel",
            "path": "/component/kwin",
            "iface": "org.kde.kglobalaccel.Component",
            "member": "invokeShortcut",
            "arguments": [shortcut]
        }, () => {}, () => {});
    }
    Timer {
        id: tileTimeout
        interval: 1500
        onTriggered: {
            if (root.pendingTile !== "") {
                console.info("appname: split dropped, the window did not become active");
                root.pendingTile = "";
            }
        }
    }

    // After the card closed itself (focus moved elsewhere), follow its state a little later,
    // so that the tap on the pill that caused the close does not reopen it.
    Timer {
        id: closeSync
        interval: 150
        onTriggered: {
            if (!cardPopup.visible) {
                root.cardOpen = false;
                Qt.callLater(root.refresh);
            }
        }
    }
    property bool openOnPress: false

    // ---- The row: padding, the logo button or the window pill, the name
    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        anchors.left: root.vertical ? undefined : parent.left
        LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
        LayoutMirroring.childrenInherit: true
        spacing: 0

        Item {
            width: root.leadingPadding
            height: 1
        }

        // Laptop: the logo button. The tooltip area is the outer item: a hover-enabled item on
        // top of a MouseArea would take the hover from it.
        PlasmaCore.ToolTipArea {
            visible: !root.tablet
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? root.buttonWidth : 0
            height: root.buttonHeight
            mainText: i18nc("@info:tooltip", "Open the launcher")
            location: Plasmoid.location
            active: !root.launcherOpen

            MouseArea {
                id: logoButton
                anchors.fill: parent
                // The whole bar height, and out to the screen edge (Fitts), stay clickable.
                anchors.topMargin: root.vertical ? 0 : -Math.max(0, (root.height - parent.height) / 2)
                anchors.bottomMargin: anchors.topMargin
                anchors.leftMargin: root.vertical ? 0 : -(root.leadingPadding + (root.windowX < 16 ? root.windowX : 0))
                hoverEnabled: true
                activeFocusOnTab: true
                acceptedButtons: Qt.LeftButton

                Accessible.role: Accessible.Button
                Accessible.name: i18nc("@action:button", "Open launcher")
                Accessible.onPressAction: root.openLauncher()

                onClicked: root.openLauncher()
                Keys.onPressed: event => {
                    if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                        root.openLauncher();
                        event.accepted = true;
                    }
                }

                Rectangle {
                    x: -logoButton.anchors.leftMargin
                    y: -logoButton.anchors.topMargin
                    width: root.buttonWidth
                    height: root.buttonHeight
                    radius: 8
                    antialiasing: true
                    color: logoButton.pressed || root.launcherOpen ? root.tint(0.16)
                         : logoButton.containsMouse ? root.tint(0.10) : "transparent"
                    Behavior on color {
                        enabled: motion.animate
                        ColorAnimation { duration: motion.hover }
                    }

                    FusionLogo {
                        anchors.centerIn: parent
                        size: m.px(18)
                    }

                    // Keyboard focus: the Controls board's 2 px ring with a 2 px gap.
                    Rectangle {
                        visible: logoButton.activeFocus
                        anchors.fill: parent
                        anchors.margins: -4
                        radius: 12
                        color: "transparent"
                        border.width: 2
                        border.color: accent.focusRing
                    }
                }
            }
        }

        Item {
            visible: !root.tablet
            width: visible && !root.vertical && !root.iconOnly ? root.nameGap : 0
            height: 1
        }

        // Tablet: the window pill.
        Loader {
            id: pillLoader
            active: root.tablet
            visible: active
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: windowPill
        }

        FusionText {
            id: nameLabel
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && !root.tablet && !root.iconOnly
            metrics: m
            px: root.tablet ? 14 : 13
            weight: 800
            color: Kirigami.Theme.textColor
            text: root.shownName
            elide: Text.ElideRight
            width: Math.min(implicitWidth, root.nameMaxWidth)
            Accessible.role: Accessible.StaticText
            Accessible.name: text
        }

        Item {
            width: root.vertical ? 0 : root.nameEndPadding
            height: 1
        }
    }

    Component {
        id: windowPill

        // 32 px tall, radius 16, padding 0 14 (TABLET 4.3); the hit area is the whole bar
        // height, at least 44 wide and out to the screen edge. Icon only: a 44 x 44 target.
        Item {
            id: pill
            readonly property real drawnHeight: Math.min(m.px(32), Math.max(1, root.height - m.px(4)))
            readonly property real padding: root.iconOnly ? 0 : m.px(14)
            readonly property real iconSize: m.px(20)
            implicitWidth: root.iconOnly ? Math.max(m.px(44), drawnHeight) : pillRow.implicitWidth + 2 * padding
            implicitHeight: drawnHeight

            Rectangle {
                anchors.centerIn: parent
                width: root.iconOnly ? pill.drawnHeight : parent.width
                height: pill.drawnHeight
                radius: height / 2
                antialiasing: true
                color: root.cardOpen ? accent.soft(0.35)
                     : root.tint(pillArea.pressed ? 0.16 : pillArea.containsMouse ? 0.12 : 0.08)
                border.width: root.cardOpen ? 1 : 0
                border.color: Qt.rgba(accent.focusRing.r, accent.focusRing.g, accent.focusRing.b, 0.5)
                scale: pillArea.pressed ? 0.96 : 1
                Behavior on color {
                    enabled: motion.animate
                    ColorAnimation { duration: motion.hover }
                }
                Behavior on scale {
                    enabled: motion.animate
                    NumberAnimation { duration: motion.pressScale; easing.type: motion.standardEasing }
                }

                Row {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: m.px(8)

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: pill.iconSize
                        height: pill.iconSize
                        FusionLogo {
                            anchors.centerIn: parent
                            visible: !root.hasWindow
                            size: m.px(18)
                        }
                        FusionIconTile {
                            anchors.fill: parent
                            visible: root.hasWindow
                            size: pill.iconSize
                            source: root.appIcon
                            iconName: root.appIconName
                        }
                    }
                    FusionText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.iconOnly
                        metrics: m
                        px: 14
                        weight: 800
                        color: Kirigami.Theme.textColor
                        text: root.shownName
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, root.nameMaxWidth)
                    }
                }

                // Keyboard focus ring.
                Rectangle {
                    visible: pillArea.activeFocus
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: height / 2
                    color: "transparent"
                    border.width: 2
                    border.color: accent.focusRing
                }
            }

            MouseArea {
                id: pillArea
                objectName: "windowPill"
                anchors.fill: parent
                anchors.topMargin: -Math.max(0, (root.height - pill.height) / 2)
                anchors.bottomMargin: anchors.topMargin
                anchors.leftMargin: -(root.leadingPadding + (root.windowX < 16 ? root.windowX : 0))
                hoverEnabled: true
                activeFocusOnTab: true
                acceptedButtons: Qt.LeftButton

                Accessible.role: root.hasWindow ? Accessible.ButtonDropDown : Accessible.Button
                Accessible.name: root.hasWindow ? root.shownName : i18nc("@action:button", "Open launcher")
                Accessible.description: root.hasWindow ? i18nc("@info:whatsthis", "Window actions") : ""
                Accessible.onPressAction: root.activatePill()

                onPressed: {
                    if (root.hasWindow) {
                        root.cardWanted = true;
                    }
                    root.openOnPress = !root.cardOpen;
                }
                onClicked: {
                    if (!root.openOnPress && !root.cardOpen) {
                        return; // the press closed the card (it lost the focus)
                    }
                    root.activatePill();
                }
                Keys.onPressed: event => {
                    if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space, Qt.Key_Select].indexOf(event.key) !== -1) {
                        root.activatePill();
                        event.accepted = true;
                    }
                }
            }

            // Pull-down of 24 px opens the card too (TABLET 4.3). A layer above the mouse area:
            // it holds only a passive grab until the finger has moved 24 px, so taps still
            // reach the pill.
            Item {
                anchors.fill: pillArea
                z: 10
                DragHandler {
                    acceptedDevices: PointerDevice.TouchScreen
                    target: null
                    xAxis.enabled: false
                    dragThreshold: 24
                    onActiveChanged: {
                        // (translation is still 0 when `active` turns true: use the press position)
                        const dy = centroid.position.y - centroid.pressPosition.y;
                        if (active && dy > 0 && !root.cardOpen) {
                            console.info("appname: pull-down opens the " + (root.hasWindow ? "window card" : "launcher"));
                            root.activatePill();
                        }
                    }
                }
            }
        }
    }

    // ---- The window card (built on first use, TABLET 4.3 "Cost")
    PlasmaCore.AppletPopup {
        id: cardPopup

        visualParent: pillLoader.status === Loader.Ready ? pillLoader.item as Item : root
        popupDirection: Plasmoid.location === PlasmaCore.Types.BottomEdge ? Qt.TopEdge : Qt.BottomEdge
        margin: m.px(10)
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        visible: root.cardOpen && cardLoader.status === Loader.Ready

        onVisibleChanged: {
            if (visible) {
                cardPopup.requestActivate();
                (cardLoader.item as Item)?.forceActiveFocus();
            } else {
                closeSync.restart();
            }
        }

        mainItem: Loader {
            id: cardLoader
            active: root.cardWanted
            asynchronous: true
            focus: true
            sourceComponent: WindowCard {
                metrics: m
                motion: motion
                appName: root.shownName
                title: root.cardTitle
                icon: root.appIcon
                iconName: root.appIconName
                maximized: root.cardMaximized
                focus: true
                onActionRequested: action => root.cardAction(action)
                onCloseRequested: root.setCardOpen(false)
            }
        }
        Connections {
            target: cardPopup
            enabled: root.openStarted > 0
            function onFrameSwapped() {
                if (!cardPopup.visible) {
                    return;
                }
                console.info("appname: window card " + (root.cardShown ? "open" : "first open") + ", first frame after "
                             + (Date.now() - root.openStarted) + " ms");
                const card = cardLoader.item as WindowCard;
                const pill = pillLoader.item as Item;
                if (card && pill) {
                    const hit = pill.mapToItem(null, pill.childrenRect.x, pill.childrenRect.y);
                    console.info("appname: window card at " + cardPopup.x + "," + cardPopup.y + ", rows " + card.rowCentres(cardPopup.x, cardPopup.y)
                                 + "; pill " + Math.round(hit.x) + "," + Math.round(hit.y) + " " + Math.round(pill.childrenRect.width)
                                 + "x" + Math.round(pill.childrenRect.height));
                }
                root.openStarted = 0;
                root.cardShown = true;
            }
        }
    }
}
