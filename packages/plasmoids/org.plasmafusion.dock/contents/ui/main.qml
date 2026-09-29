/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtCore
import Qt.labs.folderlistmodel

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus
import org.kde.taskmanager as TaskManager
import org.kde.kirigami as Kirigami

// The whole content of the Plasma Fusion dock: Start, Search, Overview | pinned apps |
// running apps that are not pinned, Downloads, Trash. It fills the full panel thickness
// (88 px: 16 px transparent headroom + the 72 px dock drawn by the Plasma style), so
// magnified icons can grow into the headroom.
PlasmoidItem {
    id: root

    // ---- Board metrics (logical px, Main.dc.html <nav aria-label="Dock">) ----
    readonly property int tile: 48
    readonly property int gap: 8
    readonly property int sepSlot: 9            // 1 px line + 4 px margin on each side
    readonly property int sidePad: 12
    readonly property int bottomPad: 14
    readonly property int zoomSize: Plasmoid.configuration.magnify
        ? Math.max(tile, Math.min(Plasmoid.configuration.magnifiedSize, Math.floor(height) - bottomPad))
        : tile
    // App icons shrink below 48 px only when the dock would otherwise be wider than the screen.
    readonly property int minTaskTile: 24
    // Floating panel margins (Plasma style: 8 px left and right of the dock).
    readonly property int screenMargin: 8
    readonly property real screenWidth: {
        const g = Plasmoid.containment ? Plasmoid.containment.screenGeometry : undefined;
        return g && g.width > 0 ? g.width : Screen.width;
    }

    // ---- State ----
    property var taskVisible: []
    property var taskPinned: []
    property var geo: ({ taskX: [], taskSize: [], restCenter: [], start: 0, search: 0, overview: 0,
                         sep1: 0, sep2: -1, downloads: 0, trash: 0, width: 0, restWidth: 0, taskTile: 48 })
    property real pointerGlobalX: NaN
    property bool pointerOverTasks: false
    property real zoom: (Plasmoid.configuration.magnify && (pointerOverTasks || debugHover) && dragRow < 0) ? 1 : 0
    property real leftInset: 0
    property real rightInset: 0
    // Distance from this item's edges to the first/last button so that the row starts 12 px
    // from the visible dock edge; negative when the containment's own margin is larger.
    readonly property real padLeft: sidePad - leftInset
    readonly property real padRight: sidePad - rightInset
    property Item hoveredItem: null
    property int dragRow: -1
    property bool menuOpen: false
    property Item launcherApplet: null
    // The Plasma Fusion launcher shows its menu in its own window and reports it in menuOpen;
    // other launchers (Kickoff, Kicker) use the applet's expanded state.
    readonly property bool launcherOpen: {
        if (!launcherApplet) {
            return false;
        }
        const menuOpen = launcherApplet["menuOpen"];
        return menuOpen !== undefined ? menuOpen === true : launcherApplet["expanded"] === true;
    }
    readonly property bool debugHover: Plasmoid.configuration.debugHoverIndex >= 0
    readonly property bool debugPointer: Plasmoid.configuration.debugPointerX >= 0
    property bool fallbacksApplied: false

    Behavior on zoom {
        NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
    }

    DockPalette {
        id: dockPal
        dark: {
            switch (Plasmoid.configuration.colorVariant) {
            case 1: return true;
            case 2: return false;
            default: return Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark;
            }
        }
    }

    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.status: tasksModel.anyTaskDemandsAttention ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus

    Layout.fillWidth: false
    Layout.fillHeight: true
    Layout.minimumWidth: Math.max(tile, Math.ceil(geo.width + padLeft + padRight))
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: Layout.minimumWidth

    // ---- Tasks ----
    TaskManager.VirtualDesktopInfo { id: virtualDesktopInfo }
    TaskManager.ActivityInfo { id: activityInfo }

    TaskManager.TasksModel {
        id: tasksModel

        screenGeometry: Plasmoid.containment.screenGeometry
        activity: activityInfo.currentActivity
        filterByCurrentVirtualDesktop: Plasmoid.configuration.showOnlyCurrentDesktop
        filterByActivity: Plasmoid.configuration.showOnlyCurrentActivity
        filterByScreen: Plasmoid.configuration.showOnlyCurrentScreen

        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        sortMode: TaskManager.TasksModel.SortManual
        separateLaunchers: true
        launchInPlace: true
        hideActivatedLaunchers: true

        onLauncherListChanged: {
            if (JSON.stringify(Plasmoid.configuration.launchers) !== JSON.stringify(launcherList)) {
                Plasmoid.configuration.launchers = launcherList;
            }
            root.scheduleRescan();
        }
        onCountChanged: root.scheduleRescan()
        onDataChanged: (topLeft, bottomRight, roles) => {
            const atm = TaskManager.AbstractTasksModel;
            const relevant = [atm.AppId, atm.AppName, atm.IsLauncher, atm.IsStartup, atm.IsWindow, atm.LauncherUrlWithoutIcon, atm.HasLauncher];
            if (!roles || roles.length === 0 || roles.some(r => relevant.indexOf(r) !== -1)) {
                root.scheduleRescan();
            }
        }
        onRowsMoved: root.scheduleRescan()
        onModelReset: root.scheduleRescan()

        Component.onCompleted: {
            launcherList = Plasmoid.configuration.launchers;
            taskRepeater.model = tasksModel;
            root.scheduleRescan();
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onLaunchersChanged(): void {
            if (JSON.stringify(tasksModel.launcherList) !== JSON.stringify(Plasmoid.configuration.launchers)) {
                tasksModel.launcherList = Plasmoid.configuration.launchers;
            }
        }
        function onDebugHoverIndexChanged(): void { root.relayout(); }
        function onDebugPointerXChanged(): void {
            if (!root.debugPointer) {
                root.hoveredItem = null;
            }
            root.relayout();
        }
        function onDebugActionChanged(): void { Qt.callLater(root.runDebugAction); }
        function onMagnifiedSizeChanged(): void { root.relayout(); }
    }

    Timer {
        id: rescanTimer
        interval: 0
        onTriggered: root.rescan()
    }

    function scheduleRescan(): void {
        rescanTimer.restart();
    }

    function role(row: int, roleId: int): var {
        return tasksModel.data(tasksModel.makeModelIndex(row), roleId);
    }

    // A launcher whose app is not installed: libtaskmanager then leaves AppId empty (and
    // shows the .desktop file name as AppName).
    function isMissingLauncher(row: int): bool {
        return role(row, TaskManager.AbstractTasksModel.IsLauncher) === true
            && !role(row, TaskManager.AbstractTasksModel.AppId);
    }

    // Which rows are shown (launchers of apps that are not installed are hidden) and
    // which belong to pinned apps (they come first; the rest follow the second separator).
    function rescan(): void {
        const n = tasksModel.count;
        const visible = [];
        const pinned = [];
        for (let i = 0; i < n; ++i) {
            const isLauncher = role(i, TaskManager.AbstractTasksModel.IsLauncher) === true;
            const url = role(i, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
            visible.push(!isMissingLauncher(i));
            pinned.push(isLauncher || (url ? tasksModel.launcherPosition(url) !== -1 : false));
        }
        if (JSON.stringify(visible) !== JSON.stringify(taskVisible) || JSON.stringify(pinned) !== JSON.stringify(taskPinned)) {
            taskVisible = visible;
            taskPinned = pinned;
        }
        relayout();
        if (!fallbacksApplied && n > 0) {
            fallbacksApplied = true;
            Qt.callLater(applyLauncherFallbacks);
        }
        publishTimer.restart();
    }

    // Replace pinned launchers whose app is missing by the configured fallback (for
    // example Kate -> KWrite), once, so the default pin set works on more systems.
    function applyLauncherFallbacks(): void {
        const pairs = Plasmoid.configuration.launcherFallbacks || [];
        if (pairs.length === 0) {
            return;
        }
        const fallback = {};
        for (const pair of pairs) {
            const parts = String(pair).split("=");
            if (parts.length === 2) {
                fallback[parts[0]] = parts[1];
            }
        }
        const missing = new Set();
        for (let i = 0; i < tasksModel.count; ++i) {
            if (isMissingLauncher(i)) {
                missing.add(String(role(i, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon)));
            }
        }
        const current = Plasmoid.configuration.launchers.slice();
        let changed = false;
        const next = current.map(url => {
            const replacement = fallback[url];
            if (replacement && missing.has(url) && current.indexOf(replacement) === -1) {
                changed = true;
                return replacement;
            }
            return url;
        });
        if (changed) {
            Plasmoid.configuration.launchers = next;
        }
    }

    // ---- Layout: rest geometry, then magnified sizes around the pointer ----
    function relayout(): void {
        const n = taskRepeater.count;
        const slots = [];
        const push = (kind, row) => slots.push({ kind: kind, row: row, w: (kind === "sep1" || kind === "sep2") ? sepSlot : tile });
        push("start"); push("search"); push("overview"); push("sep1");
        let anyPinned = false;
        let sep2 = false;
        for (let i = 0; i < n; ++i) {
            if (!taskVisible[i]) {
                continue;
            }
            const pinned = !!taskPinned[i];
            if (!pinned && anyPinned && !sep2) {
                push("sep2");
                sep2 = true;
            }
            anyPinned = anyPinned || pinned;
            push("task", i);
        }
        if (anyPinned && !sep2) {
            push("sep2");
        }
        push("downloads"); push("trash");

        // Too many apps for the screen: shrink the app icons (not the fixed buttons) so that
        // Downloads and Trash stay reachable, keeping room for the magnified icons.
        const taskCount = slots.filter(s => s.kind === "task").length;
        let taskTile = tile;
        if (taskCount > 0) {
            const fixed = slots.reduce((sum, s) => sum + (s.kind === "task" ? 0 : s.w + gap), 0) - gap;
            const growth = zoomSize > tile ? 2 * (zoomSize - tile) : 0;
            const budget = screenWidth - 2 * screenMargin - 2 * sidePad - growth - fixed;
            const fit = Math.floor(budget / taskCount) - gap;
            if (fit < tile) {
                taskTile = Math.max(minTaskTile, fit);
                for (const s of slots) {
                    if (s.kind === "task") {
                        s.w = taskTile;
                    }
                }
            }
        }
        // Parabolic falloff 1 - (d/R)^2; with 56 px between icon centres R = 74 gives 62 / 54 / 48.
        const falloffRadius = (taskTile + gap) / Math.sqrt(1 - 3 / 7);

        let x = 0;
        let firstTask = -1;
        let lastTask = -1;
        for (const s of slots) {
            s.rx = x;
            x += s.w + gap;
            if (s.kind === "task") {
                if (firstTask < 0) {
                    firstTask = s.rx;
                }
                lastTask = s.rx + s.w;
            }
        }
        const restWidth = x - gap;

        // Pointer position in rest coordinates. The row is centred on the dock, whose centre
        // does not move when the panel grows, so this does not feed back into itself.
        let cursor = NaN;
        const forced = Plasmoid.configuration.debugHoverIndex;
        if (forced >= 0) {
            const s = slots.find(t => t.kind === "task" && t.row === forced);
            if (s) {
                cursor = s.rx + s.w / 2;
            }
        } else {
            const globalX = debugPointer ? Plasmoid.configuration.debugPointerX : pointerGlobalX;
            if (!isNaN(globalX)) {
                const local = root.mapFromGlobal(globalX, 0).x;
                cursor = local - (root.width / 2 + (padLeft - padRight) / 2) + restWidth / 2;
            }
        }
        const over = (hoverHandler.hovered || debugPointer) && !isNaN(cursor) && firstTask >= 0
            && cursor >= firstTask - gap / 2 && cursor <= lastTask + gap / 2;
        if (over !== pointerOverTasks) {
            pointerOverTasks = over;
        }

        const amplitude = (zoomSize - tile) * zoom;
        const out = { taskX: [], taskSize: [], restCenter: [], sep2: -1, taskTile: taskTile };
        x = 0;
        for (const s of slots) {
            let size = s.w;
            if (s.kind === "task") {
                if (amplitude > 0 && !isNaN(cursor)) {
                    const d = (s.rx + s.w / 2 - cursor) / falloffRadius;
                    size = Math.round(taskTile + amplitude * Math.max(0, 1 - d * d));
                }
                out.taskX[s.row] = x;
                out.taskSize[s.row] = size;
                out.restCenter[s.row] = s.rx + s.w / 2;
            } else {
                out[s.kind] = x;
            }
            x += size + gap;
        }
        out.width = x - gap;
        out.restWidth = restWidth;
        if (JSON.stringify(out) !== JSON.stringify(geo)) {
            geo = out;
        }
        if (debugPointer) {
            Qt.callLater(pickDebugPointerItem);
        }
    }

    // Geometry changes come from the panel layout; relayout after it has settled so the
    // new preferred width never feeds back into the layout pass that produced it.
    onZoomChanged: relayout()
    onWidthChanged: {
        Qt.callLater(relayout);
        insetTimer.restart();
    }
    onHeightChanged: Qt.callLater(relayout)
    onPadLeftChanged: Qt.callLater(relayout)
    onPadRightChanged: Qt.callLater(relayout)
    onZoomSizeChanged: Qt.callLater(relayout)
    onScreenWidthChanged: Qt.callLater(relayout)

    HoverHandler {
        id: hoverHandler
        onPointChanged: {
            if (hovered) {
                root.pointerGlobalX = root.mapToGlobal(point.position.x, point.position.y).x;
                root.relayout();
            }
        }
        onHoveredChanged: {
            if (!hovered) {
                root.pointerOverTasks = false;
                root.hoveredItem = null;
                root.relayout();
            }
        }
    }

    // The containment adds its own margins around applets; measure them once the panel
    // has settled so that the outer padding matches the board's 12 px.
    Timer {
        id: insetTimer
        interval: 400
        onTriggered: root.measureInsets()
    }

    function measureInsets(): void {
        if (zoom > 0) {
            insetTimer.restart();
            return;
        }
        const top = root.Window.contentItem;
        let item = root;
        while (item.parent && item.parent.parent && item.parent.parent !== top) {
            item = item.parent;
        }
        if (!top || !item.parent || item.parent.parent !== top || item === root) {
            return;
        }
        const p = root.mapToItem(item, 0, 0);
        const left = Math.round(p.x);
        const right = Math.round(item.width - p.x - root.width);
        if (left >= 0 && left <= 40 && right >= 0 && right <= 40) {
            leftInset = left;
            rightInset = right;
        }
    }

    // ---- Minimize animation targets ----
    Timer {
        id: publishTimer
        interval: 500
        onTriggered: {
            if (root.zoom > 0) {
                restart();
                return;
            }
            for (let i = 0; i < taskRepeater.count; ++i) {
                const item = taskRepeater.itemAt(i) as TaskItem;
                if (item && item.visible && item.isRunning) {
                    const p = item.iconItem.mapToGlobal(0, 0);
                    tasksModel.requestPublishDelegateGeometry(tasksModel.makeModelIndex(i),
                        Qt.rect(p.x, p.y, item.iconItem.width, item.iconItem.height), item);
                }
            }
        }
    }

    // ---- Launcher, KRunner, Overview ----
    function findLauncherApplet(): Item {
        const layout = root.parent ? root.parent.parent : null;
        if (!layout) {
            return null;
        }
        const ids = ["org.plasmafusion.launcher", "org.kde.plasma.kickoff", "org.kde.plasma.kicker", "org.kde.plasma.kickerdash"];
        for (const child of layout.children) {
            const applet = child ? child["applet"] : null;
            if (applet && applet !== root && applet["plasmoid"] && ids.indexOf(applet["plasmoid"].pluginName) !== -1) {
                return applet;
            }
        }
        return null;
    }

    Connections {
        target: Plasmoid.containment
        function onAppletsChanged(): void {
            Qt.callLater(() => { root.launcherApplet = root.findLauncherApplet(); });
        }
    }

    // True while the launcher is open or was closed a moment ago: pressing Start deactivates
    // (and so closes) an open launcher before the click arrives.
    function launcherRecentlyOpen(): bool {
        const applet = findLauncherApplet();
        if (applet && typeof applet["recentlyOpen"] === "function") {
            return applet["recentlyOpen"]();
        }
        return launcherOpen;
    }

    // Opens or closes the launcher. A launcher applet in the dock's own panel is driven
    // directly (open/close functions of the Plasma Fusion launcher, else its expanded state);
    // otherwise plasmashell's "Activate Application Launcher" action finds one in any panel.
    function toggleLauncher(wasOpen: var, mode: string): void {
        launcherApplet = findLauncherApplet();
        const applet = launcherApplet;
        if (!applet) {
            DBus.SessionBus.asyncCall({ service: "org.kde.plasmashell", path: "/PlasmaShell",
                                        iface: "org.kde.PlasmaShell", member: "activateLauncherMenu" });
            return;
        }
        const open = wasOpen === undefined ? launcherOpen : wasOpen === true;
        if (open) {
            if (typeof applet["close"] === "function") {
                applet["close"]();
            } else {
                applet["expanded"] = false;
            }
        } else if (typeof applet["open"] === "function") {
            applet["open"](mode || "home", "");
        } else {
            applet["expanded"] = true;
        }
    }

    function toggleSearch(): void {
        if (Plasmoid.configuration.searchAction === 1) {
            toggleLauncher(searchButton.clickFromPointer ? searchButton.launcherWasOpen : undefined, "home");
            return;
        }
        DBus.SessionBus.asyncCall({ service: "org.kde.krunner", path: "/App",
                                    iface: "org.kde.krunner.App", member: "toggleDisplay" });
    }

    function toggleOverview(): void {
        DBus.SessionBus.asyncCall({ service: "org.kde.kglobalaccel", path: "/component/kwin",
                                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                                    arguments: ["Overview"], signature: "(s)" });
    }

    // Testing hook (config key debugPointerX): the task under that screen x counts as hovered.
    function pickDebugPointerItem(): void {
        const x = row0.mapFromGlobal(Plasmoid.configuration.debugPointerX, 0).x;
        let found = null;
        for (let i = 0; i < taskRepeater.count; ++i) {
            if (taskVisible[i] && x >= geo.taskX[i] - gap / 2 && x < geo.taskX[i] + geo.taskSize[i] + gap / 2) {
                found = taskRepeater.itemAt(i);
            }
        }
        hoveredItem = found;
    }

    // Testing hook (config key debugAction): lets a scripted session open the menus and press
    // buttons without a pointer. The key is cleared after use.
    function runDebugAction(): void {
        const action = Plasmoid.configuration.debugAction;
        if (!action) {
            return;
        }
        Plasmoid.configuration.debugAction = "";
        const parts = action.split(":");
        const row = parts.length > 1 ? parseInt(parts[1]) : -1;
        const item = row >= 0 ? taskRepeater.itemAt(row) as TaskItem : null;
        switch (parts[0]) {
        case "start": toggleLauncher(undefined, "home"); break;
        case "search": toggleSearch(); break;
        case "overview": toggleOverview(); break;
        case "downloads-menu": showDownloadsMenu(); break;
        case "trash-menu": showTrashMenu(); break;
        case "close-menu": if (lastMenu) lastMenu.close(); break;
        case "menu": if (item) showTaskMenu(item); break;
        case "activate": if (item) activateTask(row, 0); break;
        case "new": if (item) tasksModel.requestNewInstance(tasksModel.makeModelIndex(row)); break;
        case "configure": {
            const configure = Plasmoid.internalAction("configure");
            if (configure) {
                configure.trigger();
            }
            break;
        }
        }
    }

    // ---- Task actions (same rules as the stock task manager) ----
    function activateTask(row: int, modifiers: int): void {
        const index = tasksModel.makeModelIndex(row);
        const atm = TaskManager.AbstractTasksModel;
        if (modifiers & Qt.ShiftModifier) {
            tasksModel.requestNewInstance(index);
            return;
        }
        if (tasksModel.data(index, atm.IsGroupParent) === true) {
            const children = [];
            for (let j = 0; j < tasksModel.rowCount(index); ++j) {
                children.push(tasksModel.makeModelIndex(row, j));
            }
            const active = children.findIndex(child => tasksModel.data(child, atm.IsActive) === true);
            if (active >= 0) {
                tasksModel.requestActivate(children[(active + 1) % children.length]);
                return;
            }
            let best = children[0];
            let bestTime = -1;
            for (const child of children) {
                const t = tasksModel.data(child, atm.LastActivated);
                if (t !== undefined && t > bestTime) {
                    bestTime = t;
                    best = child;
                }
            }
            tasksModel.requestActivate(best);
            return;
        }
        if (tasksModel.data(index, atm.IsLauncher) === true) {
            tasksModel.requestActivate(index);
        } else if (tasksModel.data(index, atm.IsMinimized) === true) {
            tasksModel.requestToggleMinimized(index);
            tasksModel.requestActivate(index);
        } else if (tasksModel.data(index, atm.IsActive) === true && Plasmoid.configuration.minimizeActiveTaskOnClick) {
            tasksModel.requestToggleMinimized(index);
        } else {
            tasksModel.requestActivate(index);
        }
    }

    // Plasmashell calls this for Meta+1 ... Meta+9.
    function activateTaskAtIndex(index: var): void {
        if (typeof index !== "number") {
            return;
        }
        let seen = -1;
        for (let i = 0; i < taskRepeater.count; ++i) {
            if (taskVisible[i] && ++seen === index) {
                activateTask(i, 0);
                return;
            }
        }
    }

    function isPinned(row: int): bool {
        const url = role(row, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
        return url ? tasksModel.launcherPosition(url) !== -1 : false;
    }

    function setPinned(row: int, pinned: bool): void {
        const url = role(row, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
        if (!url || Plasmoid.immutability === PlasmaCore.Types.SystemImmutable) {
            return;
        }
        if (pinned) {
            tasksModel.requestAddLauncher(url);
        } else {
            tasksModel.requestRemoveLauncher(url);
        }
    }

    // Drag a task sideways to reorder it within its group (pinned or running).
    function reorderTo(row: int, sceneX: real): void {
        dragRow = row;
        const x = row0.mapFromItem(null, sceneX, 0).x;
        let target = row;
        for (let i = 0; i < taskRepeater.count; ++i) {
            if (!taskVisible[i] || !!taskPinned[i] !== !!taskPinned[row]) {
                continue;
            }
            const left = geo.taskX[i];
            const size = geo.taskSize[i];
            if (x >= left - gap / 2 && x < left + size + gap / 2) {
                target = i;
                break;
            }
        }
        if (target !== row) {
            tasksModel.move(row, target);
        }
    }

    function finishReorder(): void {
        dragRow = -1;
        tasksModel.syncLaunchers();
    }

    // ---- Context menus ----
    Component {
        id: menuComponent
        DockMenu {}
    }

    property DockMenu lastMenu: null

    function openMenu(visualParent: Item): DockMenu {
        const menu = menuComponent.createObject(root, { visualParent: visualParent }) as DockMenu;
        menu.statusChanged.connect(() => { root.menuOpen = menu.status !== PlasmaExtras.Menu.Closed; });
        lastMenu = menu;
        return menu;
    }

    function showTaskMenu(item: TaskItem): void {
        const row = item.index;
        const index = tasksModel.makeModelIndex(row);
        const atm = TaskManager.AbstractTasksModel;
        const menu = openMenu(item.iconItem);
        const name = item.name;
        if (name) {
            menu.addHeader(name);
        }
        if (tasksModel.data(index, atm.IsGroupParent) === true) {
            for (let j = 0; j < tasksModel.rowCount(index); ++j) {
                const child = tasksModel.makeModelIndex(row, j);
                const title = tasksModel.data(child, Qt.DisplayRole) || name;
                menu.addAction(title, "", () => tasksModel.requestActivate(child),
                               { checkable: true, checked: tasksModel.data(child, atm.IsActive) === true });
            }
            menu.addSeparator();
        }
        if (item.isLauncher) {
            menu.addAction(i18nc("@action:inmenu", "Open"), "document-open-symbolic", () => tasksModel.requestActivate(index), {});
        } else if (tasksModel.data(index, atm.CanLaunchNewInstance) !== false) {
            menu.addAction(i18nc("@action:inmenu", "New Window"), "window-new-symbolic", () => tasksModel.requestNewInstance(index), {});
        }
        if (!item.isLauncher && !item.isStartup) {
            const minimized = tasksModel.data(index, atm.IsMinimized) === true;
            menu.addAction(minimized ? i18nc("@action:inmenu", "Restore") : i18nc("@action:inmenu", "Minimize"),
                           minimized ? "window-restore-symbolic" : "window-minimize-symbolic",
                           () => tasksModel.requestToggleMinimized(index), {});
        }
        menu.addSeparator();
        const pinned = isPinned(row);
        if (role(row, atm.LauncherUrlWithoutIcon)) {
            menu.addAction(i18nc("@action:inmenu", "Keep in Dock"), "window-pin-symbolic",
                           () => root.setPinned(row, !pinned), { checkable: true, checked: pinned });
        }
        if (!item.isLauncher && !item.isStartup) {
            const count = tasksModel.rowCount(index);
            menu.addAction(count > 1 ? i18nc("@action:inmenu", "Close All %1 Windows", count) : i18nc("@action:inmenu", "Close"),
                           "window-close-symbolic", () => tasksModel.requestClose(index), {});
        }
        menu.openRelative();
    }

    // ---- Downloads ----
    readonly property url downloadsUrl: Plasmoid.configuration.downloadsFolder !== ""
        ? (Plasmoid.configuration.downloadsFolder.indexOf("://") > 0 ? Plasmoid.configuration.downloadsFolder
                                                                     : "file://" + Plasmoid.configuration.downloadsFolder)
        : StandardPaths.writableLocation(StandardPaths.DownloadLocation)

    FolderListModel {
        id: downloadsModel
        folder: root.downloadsUrl
        showDirs: true
        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Time
    }

    function iconForFile(name: string, isDir: bool): string {
        if (isDir) {
            return "folder";
        }
        const ext = name.slice(name.lastIndexOf(".") + 1).toLowerCase();
        const map = {
            pdf: "application-pdf", png: "image-x-generic", jpg: "image-x-generic", jpeg: "image-x-generic",
            gif: "image-x-generic", webp: "image-x-generic", svg: "image-svg+xml", zip: "application-zip",
            gz: "application-x-archive", xz: "application-x-archive", tar: "application-x-archive",
            "7z": "application-x-archive", rar: "application-x-archive", iso: "application-x-cd-image",
            mp3: "audio-x-generic", flac: "audio-x-generic", ogg: "audio-x-generic", wav: "audio-x-generic",
            mp4: "video-x-generic", mkv: "video-x-generic", webm: "video-x-generic", mov: "video-x-generic",
            rpm: "application-x-rpm", odt: "x-office-document", docx: "x-office-document",
            ods: "x-office-spreadsheet", xlsx: "x-office-spreadsheet", odp: "x-office-presentation",
            pptx: "x-office-presentation", txt: "text-plain", ttf: "font-ttf", otf: "font-otf"
        };
        return map[ext] || "text-x-generic";
    }

    function showDownloadsMenu(): void {
        const menu = openMenu(downloadsButton.face);
        menu.addAction(i18nc("@action:inmenu", "Open Downloads Folder"), "folder-download",
                       () => Qt.openUrlExternally(root.downloadsUrl), {});
        const count = Math.min(10, downloadsModel.count);
        if (count > 0) {
            menu.addHeader(i18nc("@title:group", "Recent Downloads"));
            for (let i = 0; i < count; ++i) {
                const fileName = downloadsModel.get(i, "fileName");
                const fileUrl = downloadsModel.get(i, "fileUrl");
                menu.addAction(fileName, iconForFile(fileName, downloadsModel.get(i, "fileIsDir")),
                               () => Qt.openUrlExternally(fileUrl), {});
            }
        }
        menu.openRelative();
    }

    // ---- Trash ----
    readonly property string trashFilesUrl: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/Trash/files"

    FolderListModel {
        id: trashFiles
        folder: root.trashFilesUrl
        showDirs: true
        showHidden: true
        showDotAndDotDot: false
        showOnlyReadable: false
    }
    // FolderListModel keeps its previous folder when the new one does not exist, so only
    // trust the count while it really lists the trash.
    readonly property bool trashWatched: String(trashFiles.folder) === trashFilesUrl && trashFiles.status === FolderListModel.Ready
    readonly property bool trashFull: trashWatched && trashFiles.count > 0

    // The trash folder may not exist yet; look again now and then until it does.
    Timer {
        interval: 15000
        repeat: true
        running: !root.trashWatched
        onTriggered: {
            trashFiles.folder = "";
            trashFiles.folder = root.trashFilesUrl;
        }
    }

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => disconnectSource(sourceName)
        function run(command: string): void {
            connectSource(command);
        }
    }

    function shellQuote(text: string): string {
        return "'" + String(text).replace(/'/g, "'\\''") + "'";
    }

    function moveToTrash(urls: var): void {
        const list = [];
        for (const url of urls) {
            const s = String(url);
            if (s && !s.startsWith("trash:")) {
                list.push(shellQuote(s));
            }
        }
        if (list.length > 0) {
            executable.run("kioclient move " + list.join(" ") + " trash:/");
        }
    }

    function showTrashMenu(): void {
        const menu = openMenu(trashButton.face);
        menu.addAction(i18nc("@action:inmenu", "Open Trash"), "document-open-folder-symbolic",
                       () => Qt.openUrlExternally("trash:/"), {});
        menu.addAction(i18nc("@action:inmenu", "Empty Trash…"), "trash-empty-symbolic",
                       () => Qt.callLater(root.confirmEmptyTrash), { enabled: root.trashFull });
        menu.openRelative();
    }

    function confirmEmptyTrash(): void {
        const menu = openMenu(trashButton.face);
        menu.addHeader(i18nc("@title:menu", "Delete everything in the Trash?"));
        menu.addAction(i18nc("@action:inmenu", "Empty Trash"), "edit-delete-symbolic",
                       () => executable.run("ktrash6 --empty"), {});
        menu.addAction(i18nc("@action:inmenu", "Cancel"), "dialog-cancel-symbolic", null, {});
        menu.openRelative();
    }

    // ---- Drops: .desktop files pin apps, other files open in the app under the pointer ----
    DropArea {
        id: taskDrop
        anchors.fill: parent
        keys: ["text/uri-list"]
        onEntered: drag => { drag.accepted = drag.hasUrls; }
        onDropped: drop => {
            if (!drop.hasUrls) {
                return;
            }
            const urls = Array.from(drop.urls).map(u => String(u));
            if (urls.every(u => u.endsWith(".desktop"))) {
                urls.forEach(u => tasksModel.requestAddLauncher(u));
                drop.acceptProposedAction();
                return;
            }
            const x = row0.mapFromItem(taskDrop, drop.x, drop.y).x;
            for (let i = 0; i < taskRepeater.count; ++i) {
                if (root.taskVisible[i] && x >= root.geo.taskX[i] && x < root.geo.taskX[i] + root.geo.taskSize[i]) {
                    tasksModel.requestOpenUrls(tasksModel.makeModelIndex(i), drop.urls);
                    drop.acceptProposedAction();
                    return;
                }
            }
        }
    }

    // ---- Content ----
    Item {
        id: row0
        x: Math.round((root.width - root.geo.width) / 2 + (root.padLeft - root.padRight) / 2)
        width: root.geo.width
        height: root.height

        DockButton {
            id: startButton
            x: root.geo.start
            height: row0.height
            pal: dockPal
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Start")
            description: i18nc("@info:tooltip", "Open the application launcher")
            active: root.launcherOpen
            showIndicator: root.launcherOpen
            onPressedChanged: if (pressed) launcherWasOpen = root.launcherRecentlyOpen()
            onClicked: root.toggleLauncher(clickFromPointer ? launcherWasOpen : undefined, "home")
            onHoveredChanged: root.trackHover(startButton, hovered)

            FusionLogo {
                anchors.centerIn: parent
                size: 28
            }
        }

        DockButton {
            id: searchButton
            x: root.geo.search
            height: row0.height
            pal: dockPal
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Search")
            description: i18nc("@info:tooltip", "Search apps, files and settings")
            onPressedChanged: if (pressed) launcherWasOpen = root.launcherRecentlyOpen()
            onClicked: root.toggleSearch()
            onHoveredChanged: root.trackHover(searchButton, hovered)

            Glyph {
                anchors.centerIn: parent
                size: 24
                color: dockPal.ink
                path: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4"
            }
        }

        DockButton {
            id: overviewButton
            x: root.geo.overview
            height: row0.height
            pal: dockPal
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Overview")
            description: i18nc("@info:tooltip", "Show all windows and workspaces")
            onClicked: root.toggleOverview()
            onHoveredChanged: root.trackHover(overviewButton, hovered)

            Glyph {
                anchors.centerIn: parent
                size: 24
                color: overviewButton.active ? dockPal.activeInk : dockPal.ink
                path: "M4 5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM8 19h12a1 1 0 0 0 1-1V9"
            }
        }

        Rectangle {
            x: root.geo.sep1 + 4
            y: row0.height - root.bottomPad - 6 - 36
            width: 1
            height: 36
            color: dockPal.separator
        }

        Repeater {
            id: taskRepeater

            onCountChanged: root.scheduleRescan()

            delegate: TaskItem {
                id: taskItem
                pal: dockPal
                x: root.geo.taskX[taskItem.index] ?? 0
                iconSize: root.geo.taskSize[taskItem.index] ?? root.tile
                height: row0.height
                bottomPad: root.bottomPad
                onActivated: modifiers => root.activateTask(taskItem.index, modifiers)
                onNewInstanceRequested: tasksModel.requestNewInstance(tasksModel.makeModelIndex(taskItem.index))
                onMenuRequested: root.showTaskMenu(taskItem)
                onDragMoved: sceneX => root.reorderTo(taskItem.index, sceneX)
                onDragFinished: root.finishReorder()
                onHoveredChanged: root.trackHover(taskItem, hovered)
            }
        }

        Rectangle {
            x: root.geo.sep2 + 4
            y: row0.height - root.bottomPad - 6 - 36
            width: 1
            height: 36
            color: dockPal.separator
            visible: root.geo.sep2 >= 0
        }

        DockButton {
            id: downloadsButton
            x: root.geo.downloads
            height: row0.height
            pal: dockPal
            bottomPad: root.bottomPad
            acceptsMenu: true
            text: i18nc("@action:button", "Downloads")
            description: i18nc("@info:tooltip", "Open the Downloads folder")
            onClicked: Qt.openUrlExternally(root.downloadsUrl)
            onMenuRequested: root.showDownloadsMenu()
            onHoveredChanged: root.trackHover(downloadsButton, hovered)

            DownloadsStack {
                anchors.fill: parent
                pal: dockPal
            }
        }

        DockButton {
            id: trashButton
            x: root.geo.trash
            height: row0.height
            pal: dockPal
            bottomPad: root.bottomPad
            acceptsMenu: true
            text: root.trashFull ? i18nc("@action:button", "Trash (full)") : i18nc("@action:button", "Trash")
            description: i18nc("@info:tooltip", "Open the Trash; drop files here to move them to the Trash")
            onClicked: Qt.openUrlExternally("trash:/")
            onMenuRequested: root.showTrashMenu()
            onHoveredChanged: root.trackHover(trashButton, hovered)

            Glyph {
                anchors.centerIn: parent
                size: 24
                color: dockPal.ink
                path: "M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13M10 11v5M14 11v5"
            }

            // Items in the trash: the board's orange badge dot.
            Rectangle {
                x: parent.width - 6 - width
                y: 4
                width: 7
                height: 7
                radius: 3.5
                color: dockPal.attention
                visible: root.trashFull
            }

            DropArea {
                anchors.fill: parent
                keys: ["text/uri-list"]
                onEntered: drag => {
                    drag.accepted = drag.hasUrls;
                    trashButton.dropHighlight = drag.accepted ? 1 : 0;
                }
                onExited: trashButton.dropHighlight = 0
                onDropped: drop => {
                    trashButton.dropHighlight = 0;
                    if (drop.hasUrls) {
                        root.moveToTrash(Array.from(drop.urls));
                        drop.accept(Qt.MoveAction);
                    }
                }
            }
        }

        // Where the name pill sits: its bottom edge 12 px above the hovered item (Main board).
        Item {
            id: pillAnchor
            readonly property Item target: root.pillTarget
            readonly property bool isTask: target instanceof TaskItem
            x: target ? target.x : 0
            y: target ? (isTask ? (target as TaskItem).iconTop : (target as DockButton).face.y) - 12 : 0
            width: target ? target.width : 0
            height: 1
            onXChanged: if (pill.item) (pill.item as NamePill).reposition()
            onYChanged: if (pill.item) (pill.item as NamePill).reposition()
        }
    }

    function trackHover(item: Item, hovered: bool): void {
        if (hovered) {
            hoveredItem = item;
        } else if (hoveredItem === item) {
            hoveredItem = null;
        }
    }

    readonly property Item pillTarget: {
        if (debugHover) {
            const forced = taskRepeater.itemAt(Plasmoid.configuration.debugHoverIndex);
            return forced && forced.visible ? forced : null;
        }
        if (!hoveredItem || menuOpen || dragRow >= 0) {
            return null;
        }
        if (hoveredItem instanceof TaskItem && (hoveredItem as TaskItem).pressed) {
            return null;
        }
        return hoveredItem;
    }
    readonly property string pillText: {
        const t = pillTarget;
        if (!t) {
            return "";
        }
        return t instanceof TaskItem ? (t as TaskItem).name : (t as DockButton).text;
    }

    Loader {
        id: pill
        active: Plasmoid.configuration.showTooltips
        sourceComponent: NamePill {
            pal: dockPal
            anchorItem: pillAnchor
            text: root.pillText
            visible: root.pillText !== "" && root.visible
        }
    }

    Component.onCompleted: {
        launcherApplet = findLauncherApplet();
        insetTimer.start();
        relayout();
    }
}
