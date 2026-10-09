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
import org.kde.notificationmanager as NotificationManager
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.kicker as Kicker
import org.kde.kitemmodels as KItemModels

import "../code/pins.js" as Pins
import "../code/date-timer.js" as DateTimer

// The whole content of the Plasma Fusion dock: Start, Search, Overview | pinned apps |
// running apps that are not pinned, Downloads, Trash. It fills the full panel thickness
// (88 px: 16 px transparent headroom + the 72 px dock drawn by the Plasma style; with the plain
// south frame the 72 px plate, and the headroom above the panel), and magnified icons grow into
// the headroom. In tablet posture (FusionTablet, TABLET 4.4) the tiles are 56 px, Search moves
// into the launcher sheet, touch never magnifies, a long press opens the menu and a swipe up
// opens the launcher.
PlasmoidItem {
    id: root

    FusionTablet {
        id: tabletState
    }
    Motion {
        id: motion
    }
    // The app-open zoom in tablet posture (TABLET2 M1).
    FusionLaunchZoom {
        id: launchZoom
        dark: {
            const c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }
    }
    FusionAccent {
        id: tint
    }

    // ---- Board metrics (logical px, Main.dc.html <nav aria-label="Dock">; TABLET 4.4) ----
    readonly property bool tablet: tabletState.tablet
    readonly property bool portraitScreen: {
        const g = Plasmoid.containment ? Plasmoid.containment.screenGeometry : undefined;
        return g !== undefined && g.height > g.width;
    }
    readonly property int tile: tablet ? Plasmoid.configuration.tabletTile : 48
    readonly property int gap: tablet ? 12 : 8
    readonly property int sepLength: tablet ? 40 : 36
    readonly property int sepSlot: tablet ? 13 : 9   // 1 px line + 6 (laptop 4) px margin on each side
    readonly property int sidePad: 12
    readonly property int bottomPad: tablet ? 12 : 14
    // Room above the panel that magnified icons may use: with the plain south frame (STYLE-1) the
    // dock's 16 px headroom is above the panel; with the headroom frame it is inside it.
    readonly property int headroomAbove: height <= tile + bottomPad + 20 ? 16 : 0
    readonly property int zoomTarget: tablet ? tile + 14 : Plasmoid.configuration.magnifiedSize
    readonly property int zoomSize: Plasmoid.configuration.magnify
        ? Math.max(tile, Math.min(zoomTarget, Math.floor(height) - bottomPad + headroomAbove))
        : tile
    // App icons shrink below their size only when the dock would otherwise be wider than the
    // screen (in tablet posture never below 44 px, the touch minimum).
    readonly property int minTaskTile: tablet ? 44 : 24
    // Fixed buttons: in tablet posture Search is in the launcher sheet, and in portrait only
    // Start and Overview stay (TABLET 4.4).
    readonly property bool showSearch: !tablet
    readonly property bool showDownloadsTrash: !tablet || (!portraitScreen && Plasmoid.configuration.tabletShowDownloadsTrash)
    // Start-up pulse cycles by battery tier (plasma-fusion-powerfx writes powerTier).
    readonly property int pulseCycles: [3, 1, 0][Math.max(0, Math.min(2, Plasmoid.configuration.powerTier))]
    // Floating panel margins (Plasma style: 8 px left and right of the dock).
    readonly property int screenMargin: 8
    readonly property real screenWidth: {
        const g = Plasmoid.containment ? Plasmoid.containment.screenGeometry : undefined;
        return g && g.width > 0 ? g.width : Screen.width;
    }

    // ---- State ----
    property var taskVisible: []
    property var taskPinned: []
    // Rest geometry in row coordinates. It is computed only when the tasks, pins, screen, insets
    // or tile size change, never while the pointer moves, so the panel keeps its size while the
    // icons magnify (EFFECTS.md 4.1).
    property var rest: ({ slots: [], taskX: [], taskW: [], taskC: [], start: 0, search: 0, overview: 0,
                          sep1: 0, sep2: -1, downloads: 0, trash: 0, width: 0, taskTile: 48,
                          firstTask: -1, lastTask: -1, cFirst: 0, cLast: 0, maxDc: 0, radius: 74 })
    // Magnification of this frame: horizontal offset per fixed slot (EFFECTS.md 4.2). The task
    // items get their growth and offset set directly by updateMagnification().
    property var mag: ({ fixed: {} })
    // Row of the task under the pointer (-1: none), from the magnified geometry.
    property int hoverTaskRow: -1
    // Pointer position in row coordinates (NaN: none): stored by the hover handler; one
    // magnification update follows per event-loop pass (Qt.callLater), and nothing runs while the
    // pointer rests. A FrameAnimation would make the window render every frame while it runs,
    // even with nothing changed (measured: plasmashell 44 % instead of 23 % of a core for a
    // pointer sweep with magnification off).
    property real pendingX: NaN
    property real pendingY: NaN
    property real cursorX: NaN
    property bool magDirty: false
    property bool pointerOverTasks: false
    // A touchscreen press turns magnification off until a mouse, touchpad or pen hovers again.
    property bool touchSuppress: false
    // The crisp magnified icons are loaded after the first hover, not at start.
    property bool zoomIconsReady: false
    property real zoom: (Plasmoid.configuration.magnify && !touchSuppress && (pointerOverTasks || debugHover)
                         && dragRow < 0 && !launcherOpen && !menuOpen) ? 1 : 0
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
        enabled: motion.animate
        NumberAnimation { duration: motion.popupIn; easing.type: motion.standardEasing }
    }

    DockPalette {
        id: dockPal
        accent: tint.hoverAccent
        accentRing: dark ? (tint.schemeAccent ? "#8ab8ff" : Qt.tint(tint.hoverAccent, Qt.rgba(1, 1, 1, 0.35))) : tint.fill
        accentFill: tint.fill
        accentText: tint.fillText
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
    Layout.minimumWidth: Math.max(tile, Math.ceil(rest.width + padLeft + padRight))
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
        // Tablet posture (TABLET2 N2): the apps that are not pinned in strict recency, the latest
        // first (libtaskmanager keeps pinned apps in their pinned order before them); rescan()
        // shows the first tabletRecents of them. The laptop keeps them in the order they started.
        sortMode: root.tablet ? TaskManager.TasksModel.SortLastActivated : TaskManager.TasksModel.SortManual
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
        onRowsMoved: {
            root.closeTaskMenu();
            root.scheduleRescan();
        }
        onModelReset: {
            root.closeTaskMenu();
            root.scheduleRescan();
        }
        onRowsInserted: {
            root.closeTaskMenu();
            Qt.callLater(root.refreshAudio);
        }
        onRowsRemoved: {
            root.closeTaskMenu();
            Qt.callLater(root.refreshAudio);
        }
        onLayoutChanged: root.closeTaskMenu()

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
        function onDebugHoverIndexChanged(): void { root.markMagnification(); }
        function onDebugPointerXChanged(): void {
            if (!root.debugPointer) {
                root.hoveredItem = null;
            }
            root.markMagnification();
        }
        function onDebugActionChanged(): void { Qt.callLater(root.runDebugAction); }
        function onTabletRecentsChanged(): void { root.scheduleRescan(); }
        function onMagnifiedSizeChanged(): void { root.markMagnification(); }
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

    // Which rows are shown (launchers of apps that are not installed are hidden, and a pinned
    // app that two pins resolve to keeps one row) and which belong to pinned apps (they come
    // first; the rest follow the second separator).
    function rescan(): void {
        const n = tasksModel.count;
        const visible = [];
        const pinned = [];
        // Pinned rows come in configured pin order, one per pin (a running app's window replaces
        // its launcher row in place), so the k-th of them comes from the k-th raw pin. Its
        // preferred:// scheme tells a role pin from an explicit one (Pins.isRolePin).
        const rawPins = tasksModel.launcherList || [];
        const dupRows = [];
        let pinIdx = 0;
        let recents = 0;
        for (let i = 0; i < n; ++i) {
            const isLauncher = role(i, TaskManager.AbstractTasksModel.IsLauncher) === true;
            const url = role(i, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon);
            const isPinned = isLauncher || (url ? tasksModel.launcherPosition(url) !== -1 : false);
            let shown = !isMissingLauncher(i);
            if (isPinned) {
                if (isLauncher) {
                    dupRows.push({ row: i, app: String(role(i, TaskManager.AbstractTasksModel.AppId) || ""),
                                   rolePin: Pins.isRolePin(rawPins[pinIdx]) });
                }
                pinIdx++;
            }
            // Tablet posture: only the most recent apps that are not pinned (the rows come in
            // recency order there); the App Switcher has the rest.
            if (shown && !isPinned && tablet && ++recents > Plasmoid.configuration.tabletRecents) {
                shown = false;
            }
            visible.push(shown);
            pinned.push(isPinned);
        }
        // The Ubuntu 2026-10-03 defect: preferred://browser resolved to the pinned Kate on a
        // machine without a browser and the dock showed two identical Kate tiles.
        const dup = Pins.hiddenDuplicates(dupRows.map(r => ({ app: r.app, rolePin: r.rolePin })));
        for (const j of dup) {
            visible[dupRows[j].row] = false;
        }
        if (JSON.stringify(visible) !== JSON.stringify(taskVisible) || JSON.stringify(pinned) !== JSON.stringify(taskPinned)) {
            taskVisible = visible;
            taskPinned = pinned;
        }
        // Rows may have moved (a launcher became a starting app, an app closed): find the
        // hovered task again from the pointer instead of keeping the old row.
        setTaskHover(-1);
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

    // ---- Layout: rest geometry (only on structural changes) ----
    function relayout(): void {
        const n = taskRepeater.count;
        const slots = [];
        const push = (kind, row) => slots.push({ kind: kind, row: row, w: (kind === "sep1" || kind === "sep2") ? sepSlot : tile });
        push("start");
        if (showSearch) {
            push("search");
        }
        push("overview"); push("sep1");
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
        if (showDownloadsTrash) {
            push("downloads"); push("trash");
        }

        // Too many apps for the screen: shrink the app icons (not the fixed buttons) so that
        // Downloads and Trash stay reachable. Magnification needs no room of its own: the icons
        // grow into the headroom and the gaps absorb their growth.
        const taskCount = slots.filter(s => s.kind === "task").length;
        let taskTile = tile;
        if (taskCount > 0) {
            const fixed = slots.reduce((sum, s) => sum + (s.kind === "task" ? 0 : s.w + gap), 0) - gap;
            const budget = screenWidth - 2 * screenMargin - 2 * sidePad - fixed;
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

        const out = { slots: [], taskX: [], taskW: [], taskC: [], sep2: -1, taskTile: taskTile,
                      firstTask: -1, lastTask: -1, cFirst: 0, cLast: 0, maxDc: 0,
                      // Parabolic falloff 1 - (d/R)^2; with 56 px between icon centres R = 74
                      // gives 62 / 54 / 48.
                      radius: (taskTile + gap) / Math.sqrt(1 - 3 / 7) };
        let x = 0;
        let prevC = NaN;
        for (const s of slots) {
            const c = x + s.w / 2;
            out.slots.push({ kind: s.kind, row: s.kind === "task" ? s.row : -1, c: c });
            if (s.kind === "task") {
                out.taskX[s.row] = x;
                out.taskW[s.row] = s.w;
                out.taskC[s.row] = c;
                if (out.firstTask < 0) {
                    out.firstTask = x;
                }
                out.lastTask = x + s.w;
            } else {
                out[s.kind] = x;
            }
            if (!isNaN(prevC)) {
                out.maxDc = Math.max(out.maxDc, c - prevC);
            }
            prevC = c;
            x += s.w + gap;
        }
        out.width = x - gap;
        out.cFirst = out.slots.length ? out.slots[0].c : 0;
        out.cLast = out.slots.length ? out.slots[out.slots.length - 1].c : 0;
        if (!sameRest(out, rest)) {
            rest = out;
        }
        markMagnification();
    }

    function sameList(a: var, b: var): bool {
        if (!a || !b || a.length !== b.length) {
            return false;
        }
        for (let i = 0; i < a.length; ++i) {
            if (a[i] !== b[i]) {
                return false;
            }
        }
        return true;
    }

    function sameRest(a: var, b: var): bool {
        if (!b || a.width !== b.width || a.taskTile !== b.taskTile || a.sep2 !== b.sep2 || a.slots.length !== b.slots.length) {
            return false;
        }
        for (const k of ["start", "search", "overview", "sep1", "downloads", "trash"]) {
            if (a[k] !== b[k]) {
                return false;
            }
        }
        return sameList(a.taskX, b.taskX) && sameList(a.taskW, b.taskW);
    }

    // ---- Magnification (per frame, arithmetic only; EFFECTS.md 4.2) ----
    function markMagnification(): void {
        if (!magDirty) {
            magDirty = true;
            Qt.callLater(updateMagnification);
        }
    }

    // Growth of every task under the pointer, then offsets so that the growth pushes the icons
    // apart like a Mac dock while Start and Trash stay where they are: every gap of the row gives
    // up the same share (never below 3 px).
    function updateMagnification(): void {
        magDirty = false;
        const r = rest;
        let cursor = pendingX;
        const forced = Plasmoid.configuration.debugHoverIndex;
        if (forced >= 0 && r.taskC[forced] !== undefined) {
            cursor = r.taskC[forced];
        } else if (debugPointer) {
            cursor = row0.mapFromGlobal(Plasmoid.configuration.debugPointerX, 0).x;
        }
        const over = (hoverHandler.hovered || debugPointer || forced >= 0) && !isNaN(cursor) && r.firstTask >= 0
            && cursor >= r.firstTask - gap / 2 && cursor <= r.lastTask + gap / 2;
        if (over !== pointerOverTasks) {
            pointerOverTasks = over;
        }
        if (over) {
            cursorX = cursor;
            zoomIconsReady = true;
        }

        const amplitude = (zoomSize - r.taskTile) * zoom;
        const n = r.slots.length;
        const g = new Array(n).fill(0);
        const offsets = new Array(n).fill(0);
        if (amplitude > 0.01 && !isNaN(cursorX)) {
            let total = 0;
            for (let j = 0; j < n; ++j) {
                const s = r.slots[j];
                if (s.kind === "task") {
                    const d = (s.c - cursorX) / r.radius;
                    g[j] = amplitude * Math.max(0, 1 - d * d);
                    total += g[j];
                }
            }
            const span = r.cLast - r.cFirst;
            // Gap floor: no gap below 3 px.
            if (total > 0 && span > 0 && total * r.maxDc / span > gap - 3) {
                const k = (gap - 3) * span / (total * r.maxDc);
                for (let j = 0; j < n; ++j) {
                    g[j] *= k;
                }
                total *= k;
            }
            let before = 0;
            for (let j = 0; j < n; ++j) {
                const s = r.slots[j];
                offsets[j] = (span > 0 ? before + (s.kind === "task" ? g[j] / 2 : 0) - total * (s.c - r.cFirst) / span : 0);
                if (s.kind === "task") {
                    before += g[j];
                }
            }
        } else if (zoom === 0 && !over) {
            cursorX = NaN;
        }

        // Apply: task items directly, fixed slots through `mag`. Then find the slot under the
        // pointer in the magnified geometry (the icon plus half of each neighbouring gap, from
        // 10 px above the icon to the bottom of the panel), for tasks and buttons alike.
        const fixed = {};
        let hoverRow = -1;
        let hoverKind = "";
        const live = hoverHandler.hovered || debugPointer;
        const pointer = live ? cursor : NaN;
        const pointerY = hoverHandler.hovered ? pendingY : row0.height - bottomPad - tile / 2;
        const restTop = row0.height - bottomPad - tile - 10;
        for (let j = 0; j < n; ++j) {
            const s = r.slots[j];
            const w = s.kind === "task" ? r.taskW[s.row] : (s.kind === "sep1" || s.kind === "sep2" ? sepSlot : tile);
            const hit = !isNaN(pointer) && Math.abs(pointer - (s.c + offsets[j])) <= (w + g[j]) / 2 + gap / 2
                && pointerY >= restTop - g[j];
            if (s.kind !== "task") {
                fixed[s.kind] = offsets[j];
                if (hit && s.kind !== "sep1" && s.kind !== "sep2") {
                    hoverKind = s.kind;
                }
                continue;
            }
            const item = taskRepeater.itemAt(s.row) as TaskItem;
            if (item) {
                item.grow = g[j];
                item.shift = offsets[j];
            }
            if (hit) {
                hoverRow = s.row;
            }
        }
        if (!sameOffsets(fixed, mag.fixed)) {
            mag = { fixed: fixed };
        }
        setFixedHover(hoverKind);
        setTaskHover(hoverRow);
    }

    function sameOffsets(a: var, b: var): bool {
        for (const k of ["start", "search", "overview", "sep1", "sep2", "downloads", "trash"]) {
            if ((a[k] ?? 0) !== (b[k] ?? 0)) {
                return false;
            }
        }
        return true;
    }

    // The fixed buttons by slot kind.
    function fixedButton(kind: string): DockButton {
        switch (kind) {
        case "start": return startButton;
        case "search": return searchButton;
        case "overview": return overviewButton;
        case "downloads": return downloadsButton;
        case "trash": return trashButton;
        }
        return null;
    }

    property string hoverFixedKind: ""
    function setFixedHover(kind: string): void {
        if (kind === hoverFixedKind) {
            return;
        }
        const previous = fixedButton(hoverFixedKind);
        if (previous) {
            previous.hovered = false;
            if (hoveredItem === previous) {
                hoveredItem = null;
            }
        }
        hoverFixedKind = kind;
        const button = fixedButton(kind);
        if (button) {
            button.hovered = true;
            hoveredItem = button;
        }
    }

    function setTaskHover(row: int): void {
        if (row === hoverTaskRow) {
            return;
        }
        const previous = hoverTaskRow >= 0 ? taskRepeater.itemAt(hoverTaskRow) as TaskItem : null;
        if (previous) {
            previous.hovered = false;
        }
        hoverTaskRow = row;
        const item = row >= 0 ? taskRepeater.itemAt(row) as TaskItem : null;
        if (item) {
            item.hovered = true;
            hoveredItem = item;
        } else if (hoveredItem instanceof TaskItem) {
            hoveredItem = null;
        }
    }

    // The panel only changes size when the rest layout does; relayout after the panel layout
    // has settled so the new width never feeds back into the pass that produced it.
    onZoomChanged: updateMagnification()
    onWidthChanged: {
        Qt.callLater(relayout);
        insetTimer.restart();
    }
    onHeightChanged: Qt.callLater(relayout)
    onPadLeftChanged: Qt.callLater(relayout)
    onPadRightChanged: Qt.callLater(relayout)
    onZoomSizeChanged: markMagnification()
    onScreenWidthChanged: Qt.callLater(relayout)
    onTabletChanged: {
        clearHover();
        // the recents limit applies in tablet posture only (rescan() relays out too)
        scheduleRescan();
        Qt.callLater(relayout);
        maybeShowGestureCard();
    }
    onPortraitScreenChanged: Qt.callLater(relayout)
    onShowDownloadsTrashChanged: Qt.callLater(relayout)
    // The launcher or a context menu opening ends the magnification (zoom binding) and the name
    // pill (pillTarget); the hover state is cleared too so it cannot stay behind.
    onLauncherOpenChanged: if (launcherOpen) clearHover()

    function clearHover(): void {
        pointerOverTasks = false;
        setTaskHover(-1);
        hoveredItem = null;
        pendingX = NaN;
        pendingY = NaN;
        setFixedHover("");
        markMagnification();
    }

    HoverHandler {
        id: hoverHandler
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus | PointerDevice.Airbrush
        onPointChanged: {
            if (!hovered) {
                return;
            }
            // Any hover from these devices ends a touch suppression.
            root.touchSuppress = false;
            const p = row0.mapFromItem(root, point.position.x, point.position.y);
            root.pendingX = p.x;
            root.pendingY = p.y;
            root.markMagnification();
            // A pen leaving range does not end a hover in Qt; a pen that stops reporting for a
            // moment has left (EFFECTS.md 4.4).
            if (point.device && (point.device.type === PointerDevice.Stylus || point.device.type === PointerDevice.Airbrush)) {
                stylusWatchdog.restart();
            }
        }
        onHoveredChanged: {
            if (!hovered) {
                stylusWatchdog.stop();
                root.clearHover();
            }
        }
    }

    // A pen held still (or lifted away) for 1 s ends the magnification (PEN.md 3.8, resolution 3).
    Timer {
        id: stylusWatchdog
        interval: 1000
        onTriggered: root.clearHover()
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

    function invokeKWinShortcut(name: string): void {
        DBus.SessionBus.asyncCall({ service: "org.kde.kglobalaccel", path: "/component/kwin",
                                    iface: "org.kde.kglobalaccel.Component", member: "invokeShortcut",
                                    arguments: [name], signature: "(s)" });
    }
    // Tablet posture (TABLET2 G1): the tablet app switcher of the navigation effect when it runs
    // (quick settings unloads KWin's Overview there); otherwise, and on the laptop, KWin's Overview.
    function toggleOverview(): void {
        if (!tablet) {
            invokeKWinShortcut("Overview");
            return;
        }
        DBus.SessionBus.asyncCall({ service: "org.kde.KWin", path: "/Effects", iface: "org.kde.kwin.Effects",
                                    member: "isEffectLoaded", arguments: [new DBus.string("plasmafusion_navigation")],
                                    signature: "(s)" },
                                  reply => root.invokeKWinShortcut(reply.value === true ? "Plasma Fusion App Switcher" : "Overview"),
                                  () => root.invokeKWinShortcut("Overview"));
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
        case "menu": if (item) { logNextMenu = true; showTaskMenu(item); } break;
        case "activate": if (item) activateTask(row, 0); break;
        case "new": if (item) tasksModel.requestNewInstance(tasksModel.makeModelIndex(row)); break;
        case "dump-targets": dumpTargets(); break;
        case "add-desktop": if (item && launcherPath(row) !== "") addToDesktop(launcherPath(row)); break;
        case "badge": if (item) {
            const next = Object.assign({}, launcherEntries);
            next[item.iconName] = { count: parseInt(parts[2] || "0"), countVisible: parseInt(parts[2] || "0") > 0,
                                    progress: parseFloat(parts[3] || "-1"), progressVisible: parseFloat(parts[3] || "-1") >= 0, urgent: false };
            launcherEntries = next;
        } break;
        case "configure": {
            const configure = Plasmoid.internalAction("configure");
            if (configure) {
                configure.trigger();
            }
            break;
        }
        }
    }

    // TABLET T6: every visible target's global rectangle and hit size, one log line.
    function dumpTargets(): void {
        const out = [];
        const add = (name, item, hitW, hitH) => {
            if (!item || !item.visible) {
                return;
            }
            const p = item.mapToGlobal(0, 0);
            out.push(name + "@" + Math.round(p.x) + "," + Math.round(p.y) + ":" + Math.round(hitW) + "x" + Math.round(hitH));
        };
        for (const b of [startButton, searchButton, overviewButton, downloadsButton, trashButton]) {
            add(b.text.replace(/ /g, "_"), b, b.width + root.gap, b.tile);
        }
        for (let i = 0; i < taskRepeater.count; ++i) {
            const t = taskRepeater.itemAt(i) as TaskItem;
            if (t && t.visible) {
                add("task" + i + "-" + t.iconName + (t.badgeCount > 0 ? "#" + t.badgeCount : "")
                    + (t.progress >= 0 ? "%" + t.progress.toFixed(2) : "") + (t.calendarTile ? "=" + t.dayText : "")
                    + (t.audioStreams.length > 0 ? (t.muted ? "+muted" : t.audioShown ? "+audio" : "+quiet") : ""),
                    t, t.width + root.gap, t.iconItem.height);
                if (t.audioShown) {
                    add("audio" + i, t.audioBadge, t.audioBadge.width, t.audioBadge.height);
                }
            }
        }
        // Preview cards: "*" the active window, "~" a live thumbnail; the close button apart.
        const shown = preview.item as WindowPreview;
        if (shown && shown.visible) {
            shown.cards().forEach((card, i) => {
                add("preview" + i + (card.modelData.active ? "*" : "") + (card.live ? "~" : ""), card, card.width, card.height);
                add("previewclose" + i, card.closeTarget, card.closeTarget.width, card.closeTarget.height);
            });
        }
        console.info("dock: targets tablet=" + root.tablet + " tile=" + root.tile
                     + " preview=" + (shown ? shown.row + "/" + shown.windows.length + (shown.visible ? "" : "(hidden)") : "none")
                     + " menu=" + (root.menuOpen ? "open" : "closed")
                     + " " + out.join(" "));
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
        } else if (tasksModel.data(index, atm.IsActive) === true && Plasmoid.configuration.minimizeActiveTaskOnClick && !tablet) {
            // (Not in tablet posture: apps are full screen there, minimizing would hide the only one.)
            tasksModel.requestToggleMinimized(index);
        } else {
            tasksModel.requestActivate(index);
        }
    }

    // Plasmashell calls this for its "activate task manager entry N" up to Plasma 6.7; the snap KWin
    // script's "Plasma Fusion: Activate Dock Entry N" asks for it through activateRequest.
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

    // Pins asked for by other shell parts: the launcher's "Keep in Dock" (it finds this applet in
    // its panel, as for the split request), by desktop file id; and the stock task manager's
    // hasLauncher/addLauncher, the names Kicker calls on task managers it knows.
    // `id`: an app's desktop id, with or without the applications: scheme (Pins.appLauncherUrl).
    function isAppPinned(id: string): bool {
        return id !== "" && tasksModel.launcherPosition(Pins.appLauncherUrl(id)) !== -1;
    }
    function setAppPinned(id: string, pinned: bool): void {
        if (id === "" || Plasmoid.immutability === PlasmaCore.Types.SystemImmutable) {
            return;
        }
        const url = Pins.appLauncherUrl(id);
        console.info("dock: " + (pinned ? "pin " : "unpin ") + url);
        if (pinned) {
            tasksModel.requestAddLauncher(url);
        } else {
            tasksModel.requestRemoveLauncher(url);
        }
    }
    function hasLauncher(url: url): bool {
        return tasksModel.launcherPosition(url) !== -1;
    }
    function addLauncher(url: url): void {
        if (Plasmoid.immutability !== PlasmaCore.Types.SystemImmutable) {
            tasksModel.requestAddLauncher(url);
        }
    }

    // ---- Desktop shortcuts (BACKLOG M3) ----
    // The app's .desktop file: a file URL, or an applications: URL looked up in the XDG data dirs.
    function launcherPath(row: int): string {
        const url = String(role(row, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "");
        if (url.startsWith("file://")) {
            return decodeURIComponent(url.slice(7));
        }
        if (url.startsWith("applications:")) {
            const found = String(StandardPaths.locate(StandardPaths.ApplicationsLocation, url.slice(13)));
            return found.startsWith("file://") ? decodeURIComponent(found.slice(7)) : "";
        }
        return "";
    }
    // "Add to Desktop": a symlink in ~/Desktop, which KDE trusts (no "untrusted program" prompt),
    // as Folder View's own "Add to Desktop" makes.
    function addToDesktop(path: string): void {
        const desktop = decodeURIComponent(String(StandardPaths.writableLocation(StandardPaths.DesktopLocation)).replace(/^file:\/\//, ""));
        const name = path.slice(path.lastIndexOf("/") + 1);
        executable.run("d=" + shellQuote(desktop) + "; mkdir -p \"$d\" && { [ -e \"$d\"/" + shellQuote(name) + " ] || ln -s "
                       + shellQuote(path) + " \"$d\"/" + shellQuote(name) + "; }");
    }
    // A pinned icon dragged upwards (48 px) starts a real drag of its launcher: the .desktop URL
    // as text/uri-list, through Kicker's drag helper. Over the desktop, Folder View offers "Link
    // Here" (KIO's drop menu); "Add to Desktop" in the icon's menu links without asking.
    Kicker.DragHelper {
        id: dragHelper
        dragIconSize: 48
    }
    function desktopDrag(item: TaskItem, active: bool): void {
        const path = launcherPath(item.index);
        if (!active || path === "" || dragHelper.dragging) {
            return;
        }
        console.info("dock: desktop drag of " + path);
        dragHelper.startDrag(root, "file://" + encodeURI(path), item.iconName);
    }

    // ---- Unread counts and progress (GAPS G17) ----
    // Per desktop id: {count, countVisible, progress, progressVisible, urgent}, drawn by TaskItem.
    // Apps broadcast them as com.canonical.Unity.LauncherEntry.Update signals from any object path;
    // the QML D-Bus watcher needs a fixed sender and path, so a live source needs a small compiled
    // helper (docs/parts/shell-dock.md). Until then only the test hook (debugAction badge:) sets them.
    property var launcherEntries: ({})

    // ---- Today, for the calendar tile ----
    property date today: new Date()
    readonly property string todayMonth: Qt.locale().toString(today, "MMM").toUpperCase().replace(".", "")
    readonly property string todayDay: String(today.getDate())
    // Re-arms to the next midnight, capped at CAP_MS: Qt timers count monotonic time, which
    // pauses across system suspend, so one long interval fired hours late and left the tile on
    // yesterday's date after a resume (2026-10-06). A tick only rechecks the date.
    Timer {
        id: midnight
        running: true
        repeat: true
        interval: DateTimer.intervalTo(new Date(), DateTimer.CAP_MS)
        onTriggered: {
            const now = new Date();
            if (DateTimer.changed(root.today, now))
                root.today = now;
            interval = DateTimer.intervalTo(now, DateTimer.CAP_MS);
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
            const left = rest.taskX[i];
            const size = rest.taskW[i];
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
    // A task's menu acts on model indexes taken when it opened: when tasks come, go or move, they
    // may name another task, so the menu closes (open it again for the task).
    function closeTaskMenu(): void {
        if (lastMenu && lastMenu.taskMenu && lastMenu.status !== PlasmaExtras.Menu.Closed) {
            lastMenu.close();
        }
    }

    function openMenu(visualParent: Item): DockMenu {
        const menu = menuComponent.createObject(root, { visualParent: visualParent }) as DockMenu;
        menu.statusChanged.connect(() => { root.menuOpen = menu.status !== PlasmaExtras.Menu.Closed; });
        lastMenu = menu;
        return menu;
    }

    // ---- The app's own actions and recent files (the stock task manager's jump list and recent
    // documents). Kicker's favourites model for the one app the menu is for: its action list holds
    // the desktop file's actions (_kicker_jumpListAction) and the app's recent files from the
    // activity manager (_kicker_recentDocument, _kicker_forgetRecentDocuments), and its trigger()
    // runs them as the launcher does.
    Kicker.SimpleFavoritesModel {
        id: appActionsModel
    }

    function storageId(row: int): string {
        const url = String(role(row, TaskManager.AbstractTasksModel.LauncherUrlWithoutIcon) || "");
        if (url.startsWith("applications:")) {
            return url.slice(13);
        }
        if (url.startsWith("file://") && url.endsWith(".desktop")) {
            return decodeURIComponent(url.slice(url.lastIndexOf("/") + 1));
        }
        return "";
    }
    function appActions(id: string): var {
        if (id === "") {
            return [];
        }
        appActionsModel.favorites = [id];
        if (appActionsModel.rowCount() < 1) {
            return [];
        }
        const list = appActionsModel.data(appActionsModel.index(0, 0), appActionsModel.KItemModels.KRoleNames.role("actionList"));
        return list ? Array.from(list) : [];
    }
    function runAppAction(id: string, action: var): void {
        appActionsModel.favorites = [id];
        appActionsModel.trigger(0, action.actionId, action.actionArgument);
    }
    function addAppActions(menu: DockMenu, row: int): void {
        const id = storageId(row);
        const actions = appActions(id);
        for (const action of actions.filter(a => a.actionId === "_kicker_jumpListAction")) {
            menu.addAction(action.text, action.icon, () => root.runAppAction(id, action), {});
        }
        const recent = actions.filter(a => a.actionId === "_kicker_recentDocument");
        if (recent.length > 0) {
            const sub = menu.addSubMenu(i18nc("@action:inmenu", "Recent Files"), "document-open-recent-symbolic");
            for (const action of recent) {
                menu.addSubAction(sub, action.text, action.icon, () => root.runAppAction(id, action), {});
            }
            const forget = actions.find(a => a.actionId === "_kicker_forgetRecentDocuments");
            if (forget) {
                menu.addSubSeparator(sub);
                menu.addSubAction(sub, forget.text, forget.icon, () => root.runAppAction(id, forget), {});
            }
        }
    }

    // ---- Moving a window (the stock task manager's "Move to Desktop", "Show in Activities", "More")
    function addWindowActions(menu: DockMenu, index: var, group: bool): void {
        const atm = TaskManager.AbstractTasksModel;
        if (virtualDesktopInfo.numberOfDesktops > 1) {
            const sub = menu.addSubMenu(i18nc("@action:inmenu", "Move to Desktop"), "virtual-desktops");
            const onAll = tasksModel.data(index, atm.IsOnAllVirtualDesktops) === true;
            menu.addSubAction(sub, i18nc("@action:inmenu", "All Desktops"), "", () => tasksModel.requestVirtualDesktops(index, []),
                              { checkable: true, checked: onAll });
            menu.addSubSeparator(sub);
            const on = tasksModel.data(index, atm.VirtualDesktops) || [];
            for (let i = 0; i < virtualDesktopInfo.desktopIds.length; ++i) {
                const desktop = virtualDesktopInfo.desktopIds[i];
                menu.addSubAction(sub, virtualDesktopInfo.desktopNames[i], "", () => tasksModel.requestVirtualDesktops(index, [desktop]),
                                  { checkable: true, checked: !onAll && Array.from(on).indexOf(desktop) !== -1 });
            }
            menu.addSubSeparator(sub);
            menu.addSubAction(sub, i18nc("@action:inmenu", "New Desktop"), "list-add-symbolic", () => tasksModel.requestNewVirtualDesktop(index), {});
        }
        if (activityInfo.numberOfRunningActivities > 1) {
            const sub = menu.addSubMenu(i18nc("@action:inmenu", "Show in Activities"), "activities");
            const current = Array.from(tasksModel.data(index, atm.Activities) || []);
            menu.addSubAction(sub, i18nc("@action:inmenu", "All Activities"), "", () => tasksModel.requestActivities(index, []),
                              { checkable: true, checked: current.length === 0 });
            menu.addSubSeparator(sub);
            for (const activity of activityInfo.runningActivities()) {
                const shown = current.indexOf(activity) !== -1;
                menu.addSubAction(sub, activityInfo.activityName(activity), activityInfo.activityIcon(activity), () => {
                    const next = shown ? current.filter(a => a !== activity) : current.concat(activity);
                    tasksModel.requestActivities(index, next.length > 0 ? next : [activityInfo.currentActivity]);
                }, { checkable: true, checked: shown });
            }
        }
        if (group) {
            return;
        }
        const more = menu.addSubMenu(i18nc("@action:inmenu", "More"), "view-more-symbolic");
        const flag = r => tasksModel.data(index, r) === true;
        menu.addSubAction(more, i18nc("@action:inmenu", "Move"), "transform-move", () => tasksModel.requestMove(index),
                          { enabled: flag(atm.IsMovable) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Resize"), "transform-scale", () => tasksModel.requestResize(index),
                          { enabled: flag(atm.IsResizable) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Maximize"), "window-maximize-symbolic", () => tasksModel.requestToggleMaximized(index),
                          { enabled: flag(atm.IsMaximizable), checkable: true, checked: flag(atm.IsMaximized) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Keep Above Others"), "window-keep-above", () => tasksModel.requestToggleKeepAbove(index),
                          { checkable: true, checked: flag(atm.IsKeepAbove) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Keep Below Others"), "window-keep-below", () => tasksModel.requestToggleKeepBelow(index),
                          { checkable: true, checked: flag(atm.IsKeepBelow) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Fullscreen"), "view-fullscreen", () => tasksModel.requestToggleFullScreen(index),
                          { enabled: flag(atm.IsFullScreenable), checkable: true, checked: flag(atm.IsFullScreen) });
        menu.addSubAction(more, i18nc("@action:inmenu", "Shade"), "window-shade", () => tasksModel.requestToggleShaded(index),
                          { enabled: flag(atm.IsShadeable), checkable: true, checked: flag(atm.IsShaded) });
        menu.addSubAction(more, i18nc("@action:inmenu", "No Titlebar and Frame"), "edit-none-border", () => tasksModel.requestToggleNoBorder(index),
                          { enabled: flag(atm.CanSetNoBorder), checkable: true, checked: flag(atm.HasNoBorder) });
    }

    // Testing: the next task menu logs its entries ("menu:ROW" debug action).
    property bool logNextMenu: false

    function showTaskMenu(item: TaskItem): void {
        const row = item.index;
        const index = tasksModel.makeModelIndex(row);
        const atm = TaskManager.AbstractTasksModel;
        const menu = openMenu(item.iconItem);
        menu.taskMenu = true;
        const name = item.name;
        if (name) {
            menu.addHeader(name);
        }
        addNotificationItems(menu, item);
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
        addAppActions(menu, row);
        if (item.audioStreams.length > 0) {
            menu.addAction(i18nc("@action:inmenu", "Mute"), "audio-volume-muted-symbolic", () => item.toggleMuted(),
                           { checkable: true, checked: item.muted });
        }
        // Tablet posture (SPLIT.md item 2, Android's "Split" in the app menu): the app opens in that
        // half and the app in use takes the other one, as with the dock's split drag.
        if (tablet && !item.isStartup) {
            menu.addAction(i18nc("@action:inmenu open the app in the left half", "Split Left"), "view-split-left-right",
                           () => root.startSplit(row, "left"), {});
            menu.addAction(i18nc("@action:inmenu open the app in the right half", "Split Right"), "view-split-left-right",
                           () => root.startSplit(row, "right"), {});
        }
        if (!item.isLauncher && !item.isStartup) {
            const minimized = tasksModel.data(index, atm.IsMinimized) === true;
            menu.addAction(minimized ? i18nc("@action:inmenu", "Restore") : i18nc("@action:inmenu", "Minimize"),
                           minimized ? "window-restore-symbolic" : "window-minimize-symbolic",
                           () => tasksModel.requestToggleMinimized(index), {});
            addWindowActions(menu, index, tasksModel.data(index, atm.IsGroupParent) === true);
        }
        menu.addSeparator();
        const pinned = isPinned(row);
        if (role(row, atm.LauncherUrlWithoutIcon)) {
            menu.addAction(i18nc("@action:inmenu", "Keep in Dock"), "window-pin-symbolic",
                           () => root.setPinned(row, !pinned), { checkable: true, checked: pinned });
            const desktopFile = launcherPath(row);
            if (desktopFile !== "") {
                menu.addAction(i18nc("@action:inmenu", "Add to Desktop"), "list-add-symbolic",
                               () => root.addToDesktop(desktopFile), {});
            }
        }
        if (!item.isLauncher && !item.isStartup) {
            const count = tasksModel.rowCount(index);
            menu.addAction(count > 1 ? i18nc("@action:inmenu", "Close All %1 Windows", count) : i18nc("@action:inmenu", "Close"),
                           "window-close-symbolic", () => tasksModel.requestClose(index), {});
        }
        if (logNextMenu) {
            logNextMenu = false;
            console.info("dock: menu " + item.iconName + ": " + menu.entries.join(" | "));
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

    // ---- Tent posture (TABLET2 N2/N9): tablet posture with the screen upside down puts the
    // bottom edge on the table, where no swipe can start. The tablet script keeps the dock visible
    // while kwinrc [Script-plasmafusion-tablet] TentPosture is true; written after the rotation has
    // been stable for 1 s, then the script re-reads its settings (its shortcut).
    readonly property bool tentPosture: root.tablet && Screen.orientation === Qt.InvertedLandscapeOrientation
    // -1 until the first write: a value left by a session that ended in tent posture is cleared.
    property int tentWritten: -1
    onTentPostureChanged: tentTimer.restart()
    Timer {
        id: tentTimer
        interval: 1000
        onTriggered: {
            if ((root.tentPosture ? 1 : 0) === root.tentWritten) {
                return;
            }
            root.tentWritten = root.tentPosture ? 1 : 0;
            console.info("dock: tent posture " + root.tentPosture);
            executable.run("kwriteconfig6 --notify --file kwinrc --group Script-plasmafusion-tablet --key TentPosture --type bool "
                           + (root.tentPosture ? "true" : "false")
                           + " && gdbus call --session --dest org.kde.kglobalaccel --object-path /component/kwin"
                           + " --method org.kde.kglobalaccel.Component.invokeShortcut 'Plasma Fusion: Tablet Window Mode' >/dev/null");
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
                if (root.taskVisible[i] && x >= root.rest.taskX[i] && x < root.rest.taskX[i] + root.rest.taskW[i]) {
                    tasksModel.requestOpenUrls(tasksModel.makeModelIndex(i), drop.urls);
                    drop.acceptProposedAction();
                    return;
                }
            }
        }
    }

    // ---- Touch (TABLET 4.4): above every icon, so it sees a touch before the icons' mouse areas do
    // (an item's own handlers come after its children's); it only takes passive grabs until a
    // swipe starts, so taps and long presses still reach the icons.
    Item {
        id: touchLayer
        anchors.fill: parent
        z: 100

        // A touchscreen press: no magnification and no name pill until the next real hover.
        PointHandler {
            acceptedDevices: PointerDevice.TouchScreen
            onActiveChanged: {
                if (active) {
                    root.touchSuppress = true;
                    root.clearHover();
                }
            }
        }

        // ---- Swipe up on the dock: the launcher (TABLET 4.4, TouchScreen only) ----
        // 24 px upwards opens it; a launcher that follows the finger (the Plasma Fusion launcher's
        // sheet, LAUNCH-2) gets the progress (dy / 240) and, on release, opens when it is at 0.3 or
        // more or the finger moved up at 800 px/s or faster.
        DragHandler {
            id: swipeUp
            enabled: !root.iconArmed
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            xAxis.enabled: false
            dragThreshold: 24
            property bool following: false
            // Active means 24 px upwards (the threshold): open at once; a following launcher gets
            // the progress while the finger moves and the decision on release (the travel is
            // already reset when `active` turns false, so it is kept here).
            property real lastProgress: 0
            onActiveChanged: {
                const applet = root.findLauncherApplet();
                root.launcherApplet = applet;
                if (active) {
                    root.clearHover();
                    lastProgress = Math.max(0, -translation.y) / 240;
                    following = applet !== null && typeof applet["beginReveal"] === "function";
                    if (following) {
                        applet["beginReveal"]();
                        applet["updateReveal"](lastProgress);
                    } else if (!root.launcherOpen) {
                        console.info("dock: swipe up opens the launcher");
                        root.toggleLauncher(false, "home");
                    }
                } else if (following) {
                    applet["endReveal"](lastProgress >= 0.3 || -centroid.velocity.y >= 800);
                    following = false;
                }
            }
            onTranslationChanged: {
                if (active && following && root.launcherApplet) {
                    lastProgress = Math.max(0, -translation.y) / 240;
                    root.launcherApplet["updateReveal"](lastProgress);
                }
            }
        }

    }

    // ---- Home indicator and the first tablet use (TABLET 4.4 and 5) ----
    // The active window on this screen, maximized (not full screen): the dock hides over it, and
    // the indicator shows where to swipe.
    property bool activeMaximized: false
    function updateActiveMaximized(): void {
        const index = tasksModel.activeTask;
        const atm = TaskManager.AbstractTasksModel;
        activeMaximized = index.valid && tasksModel.data(index, atm.IsMaximized) === true
            && tasksModel.data(index, atm.IsFullScreen) !== true;
    }
    Connections {
        target: tasksModel
        function onActiveTaskChanged(): void { root.updateActiveMaximized(); }
        function onDataChanged(): void { root.updateActiveMaximized(); }
    }
    // ---- App notification badges (owner 2026-10-01; Android's notification dots, with the number):
    // the notifications in the history from each app that are unread (the Notification Centre
    // was not opened since they came) and newer than the last time the app was in use. Opening the
    // app or the Notification Centre clears its badge. Tablet posture: the app's menu lists them.
    NotificationManager.Notifications {
        id: appNotifications
        showExpired: true
        showDismissed: true
        showJobs: false
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
        urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency
        onDataChanged: Qt.callLater(root.recountNotifications)
        // (shared with the Notification Centre, which resets it when it opens)
        onLastReadChanged: Qt.callLater(root.recountNotifications)
    }
    property var notificationCounts: ({})   // iconName (desktop entry) -> count
    property var notificationRows: ({})     // iconName -> rows in appNotifications, newest first
    property var appLastSeen: ({})          // iconName -> ms: the app was active until then
    property string lastActiveKey: ""
    function activeAppKey(): string {
        const active = tasksModel.activeTask;
        return active && active.valid ? String(tasksModel.data(active, TaskManager.AbstractTasksModel.AppId) || "").replace(/\.desktop$/, "") : "";
    }
    Connections {
        target: tasksModel
        function onActiveTaskChanged(): void {
            const key = root.activeAppKey();
            const now = Date.now();
            const seen = Object.assign({}, root.appLastSeen);
            if (root.lastActiveKey !== "") {
                seen[root.lastActiveKey] = now;
            }
            if (key !== "") {
                seen[key] = now;
            }
            root.appLastSeen = seen;
            root.lastActiveKey = key;
            Qt.callLater(root.recountNotifications);
        }
    }
    Instantiator {
        id: notificationRowsReader
        model: appNotifications
        delegate: QtObject {
            required property int index
            required property string desktopEntry
            required property var created
            required property var updated
            required property bool read
        }
        onObjectAdded: Qt.callLater(root.recountNotifications)
        onObjectRemoved: Qt.callLater(root.recountNotifications)
    }
    function recountNotifications(): void {
        const counts = {};
        const rows = {};
        const activeKey = activeAppKey();
        const lastRead = appNotifications.lastRead;
        const readUntil = lastRead && !isNaN(lastRead.getTime()) ? lastRead.getTime() : 0;
        for (let i = 0; i < notificationRowsReader.count; ++i) {
            const n = notificationRowsReader.objectAt(i);
            const key = n ? String(n.desktopEntry || "") : "";
            if (key === "" || n.read || key === activeKey) {
                continue;
            }
            const when = n.updated && !isNaN(n.updated.getTime()) ? n.updated : n.created;
            if (when && !isNaN(when.getTime()) && when.getTime() <= Math.max(readUntil, appLastSeen[key] || 0)) {
                continue;
            }
            counts[key] = (counts[key] || 0) + 1;
            (rows[key] = rows[key] || []).push(n.index);
        }
        notificationCounts = counts;
        notificationRows = rows;
    }
    function plainText(text: string): string {
        return String(text || "").replace(/<[^>]*>/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
            .replace(/\s+/g, " ").trim();
    }
    // The app's unseen notifications at the top of its menu (tablet posture): the newest three,
    // then "Clear N Notifications".
    function addNotificationItems(menu: DockMenu, item: TaskItem): void {
        const rows = (notificationRows[item.iconName] || []).slice();
        if (!tablet || rows.length === 0) {
            return;
        }
        const roles = NotificationManager.Notifications;
        for (const r of rows.slice(0, 3)) {
            const index = appNotifications.index(r, 0);
            const summary = plainText(appNotifications.data(index, roles.SummaryRole));
            const body = plainText(appNotifications.data(index, roles.BodyRole));
            let text = summary !== "" ? summary : body;
            if (summary !== "" && body !== "") {
                text += " \u2014 " + body;
            }
            if (text.length > 64) {
                text = text.slice(0, 63) + "\u2026";
            }
            const canAct = appNotifications.data(index, roles.HasDefaultActionRole) === true
                && appNotifications.data(index, roles.ExpiredRole) !== true;
            const row = item.index;
            menu.addAction(text, "preferences-desktop-notification-bell", () => {
                if (canAct) {
                    appNotifications.invokeDefaultAction(appNotifications.index(r, 0), roles.Close);
                } else {
                    root.activateTask(row, 0);
                }
            }, {});
        }
        menu.addAction(i18ncp("@action:inmenu", "Clear %1 Notification", "Clear %1 Notifications", rows.length), "edit-clear-all", () => {
            // newest first in the list: close from the last row up, so that the rows stay valid
            for (const r of rows.slice().sort((a, b) => b - a)) {
                const index = appNotifications.index(r, 0);
                if (appNotifications.data(index, roles.ClosableRole) !== false) {
                    appNotifications.close(index);
                }
            }
        }, {});
        menu.addSeparator();
    }

    // ---- Split from the dock (SPLIT.md item 1; Android's taskbar drag): an app's icon dragged up
    // and dropped on the left or right third of the screen goes into that half; the app in use
    // takes the other one (KWin's quick tiles, so the split divider and the snap pairs follow).
    property var splitDrag: null      // {row, icon, finger}
    // An icon held for a split drag: the swipe-up to the launcher steps aside.
    property bool iconArmed: false
    property var splitPlan: null      // {side, appId, step: "other" | "app", other}
    readonly property rect screenRect: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
    function splitDragMove(item: Item, globalPos: point): void {
        const local = Qt.point(globalPos.x - screenRect.x, globalPos.y - screenRect.y);
        if (!splitDrag) {
            console.info("dock: split drag starts: " + item.iconName);
        }
        splitDrag = { "row": item.index, "icon": item.model.decoration, "finger": local };
    }
    function splitDragEnd(item: Item, cancelled: bool): void {
        const side = splitOverlay.item ? splitOverlay.item.side : "";
        const row = splitDrag ? splitDrag.row : -1;
        splitDrag = null;
        if (cancelled || side === "" || row < 0) {
            console.info("dock: split drag ends without a split" + (cancelled ? " (cancelled)" : ""));
            return;
        }
        startSplit(row, side);
    }
    // (then `done` once kglobalaccel replied)
    P5Support.DataSource {
        id: splitLauncher
        engine: "executable"
        onNewData: (source, data) => disconnectSource(source)
    }
    // Two app ids name the same app. The home screen and the launcher send desktop file names
    // ("org.kde.dolphin.desktop"); the task model's AppId had that suffix up to Plasma 6.7 and has
    // none from Plasma 6.8 on (libtaskmanager uses the desktop entry name), so compare without it.
    function sameApp(a, b): bool {
        const bare = id => String(id || "").replace(/\.desktop$/, "");
        return bare(a) !== "" && bare(a) === bare(b);
    }
    // A split asked for by the home screen or the launcher: an app the dock has (running or
    // pinned) goes the dock's own way; any other app is started here once the app in use moved.
    function startSplitForApp(appId: string, side: string): void {
        const atm = TaskManager.AbstractTasksModel;
        for (let r = 0; r < tasksModel.count; ++r) {
            if (sameApp(tasksModel.data(tasksModel.makeModelIndex(r), atm.AppId), appId)) {
                startSplit(r, side);
                return;
            }
        }
        const active = tasksModel.activeTask;
        const activeApp = active && active.valid ? String(tasksModel.data(active, atm.AppId) || "") : "";
        const other = activeApp !== "" && !sameApp(activeApp, appId) && tasksModel.data(active, atm.IsWindow) === true
            && tasksModel.data(active, atm.IsMinimized) !== true;
        console.info("dock: split request: " + appId + " (not in the dock) to the " + side + (other ? ", " + activeApp + " to the other half" : ""));
        splitPlan = { "side": side, "appId": appId, "row": -1 };
        splitTimeout.restart();
        if (other) {
            invokeKWinShortcutThen(tileShortcut(side === "left" ? "right" : "left"), () => splitBringApp.restart());
        } else {
            splitBringApp.restart();
        }
    }
    Connections {
        target: Plasmoid.configuration
        function onActivateRequestChanged(): void {
            const n = parseInt(String(Plasmoid.configuration.activateRequest || "").split(":")[0], 10);
            if (n >= 1 && n <= 9) {
                root.activateTaskAtIndex(n - 1);
            }
        }
        function onSplitRequestChanged(): void {
            const parts = String(Plasmoid.configuration.splitRequest || "").split(":");
            if (parts.length >= 3 && (parts[0] === "left" || parts[0] === "right") && parts[2] !== "") {
                root.startSplitForApp(parts.slice(2).join(":"), parts[0]);
            }
        }
    }
    function invokeKWinShortcutThen(name: string, done): void {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.kglobalaccel",
            "path": "/component/kwin",
            "iface": "org.kde.kglobalaccel.Component",
            "member": "invokeShortcut",
            "arguments": [name]
        }, () => { if (done) done(); }, error => console.warn("dock: " + name + " failed: " + error));
    }
    function tileShortcut(side: string): string {
        return side === "left" ? "Window Quick Tile Left" : "Window Quick Tile Right";
    }
    function startSplit(row: int, side: string): void {
        const atm = TaskManager.AbstractTasksModel;
        const index = tasksModel.makeModelIndex(row);
        const appId = String(tasksModel.data(index, atm.AppId) || "");
        const active = tasksModel.activeTask;
        const activeApp = active && active.valid ? String(tasksModel.data(active, atm.AppId) || "") : "";
        // The app in use takes the other half first (it is the active window), unless it is the
        // dragged app itself or nothing is open (the home screen: the "fill the other half" picker
        // then offers the other half).
        const other = activeApp !== "" && activeApp !== appId && tasksModel.data(active, atm.IsWindow) === true
            && tasksModel.data(active, atm.IsMinimized) !== true;
        console.info("dock: split: " + appId + " to the " + side + (other ? ", " + activeApp + " to the other half" : ""));
        // (row -1: another part starts the app, the dock only waits for it)
        splitPlan = { "side": side, "appId": appId, "row": row };
        splitTimeout.restart();
        if (other) {
            invokeKWinShortcutThen(tileShortcut(side === "left" ? "right" : "left"), () => splitBringApp.restart());
        } else {
            splitBringApp.restart();
        }
    }
    // After the app in use has moved (KWin acts on the shortcut a moment after the reply).
    Timer {
        id: splitBringApp
        interval: 150
        onTriggered: {
            if (!root.splitPlan) {
                return;
            }
            const atm = TaskManager.AbstractTasksModel;
            const active = tasksModel.activeTask;
            if (active && active.valid && root.sameApp(tasksModel.data(active, atm.AppId), root.splitPlan.appId)) {
                root.splitActiveIsApp();
            } else if (root.splitPlan.row >= 0) {
                root.activateTask(root.splitPlan.row, 0);
            } else {
                // not in the dock: the launcher starts it (as a tap in its sheet does); without the
                // Plasma Fusion launcher, kstart (KDE's launcher tool) by its desktop file
                const launcher = root.findLauncherApplet();
                if (!(launcher && typeof launcher["launchApp"] === "function" && launcher["launchApp"](root.splitPlan.appId))) {
                    splitLauncher.connectSource("kstart --application " + root.splitPlan.appId.replace(/\.desktop$/, "").replace(/[^A-Za-z0-9._-]/g, ""));
                }
            }
        }
    }
    function splitActiveIsApp(): void {
        if (!splitPlan) {
            return;
        }
        const side = splitPlan.side;
        splitPlan = null;
        splitTimeout.stop();
        invokeKWinShortcutThen(tileShortcut(side), null);
    }
    Connections {
        target: tasksModel
        enabled: root.splitPlan !== null && !splitBringApp.running
        function onActiveTaskChanged(): void {
            const atm = TaskManager.AbstractTasksModel;
            const active = tasksModel.activeTask;
            if (active && active.valid && tasksModel.data(active, atm.IsWindow) === true
                    && root.sameApp(tasksModel.data(active, atm.AppId), root.splitPlan.appId)) {
                root.splitActiveIsApp();
            }
        }
    }
    Timer {
        id: splitTimeout
        interval: 10000
        onTriggered: {
            if (root.splitPlan) {
                console.info("dock: split dropped: " + root.splitPlan.appId + " did not become active");
                root.splitPlan = null;
            }
        }
    }
    Loader {
        id: splitOverlay
        active: root.tablet && root.splitDrag !== null
        sourceComponent: SplitDropOverlay {
            pal: dockPal
            motion: motion
            screenGeometry: root.screenRect
            finger: root.splitDrag ? root.splitDrag.finger : Qt.point(0, 0)
            iconSource: root.splitDrag ? root.splitDrag.icon : ""
            topInset: Plasmoid.containment ? Plasmoid.containment.availableScreenRect.y : 0
            bottomInset: Plasmoid.containment ? root.screenRect.height - Plasmoid.containment.availableScreenRect.y
                                                - Plasmoid.containment.availableScreenRect.height : 0
            visible: true
        }
    }

    // Tablet posture: the bottom strip (20 px reserved band with the home indicator over an app).
    Loader {
        active: root.tablet
        sourceComponent: BottomStrip {
            pal: dockPal
            motion: motion
            overApp: root.activeMaximized
            showIndicator: Plasmoid.configuration.homeIndicator
            stripHeight: Plasmoid.configuration.tabletStripHeight
            screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        }
    }
    // Shown once, the first time tablet mode turns on (plasmafusionrc [Tablet] GestureCardShown),
    // and once more for each new set of gestures: GestureCardVersion below the card's version
    // (TABLET2: home, switcher, previous app, the two pull-downs, home search) shows it again.
    property bool gestureCardShown: true
    readonly property int gestureCardVersion: 2
    property bool gestureCardOpen: false
    P5Support.DataSource {
        id: rcReader
        engine: "executable"
        connectedSources: ["kreadconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion --default 0"]
        onNewData: (sourceName, data) => {
            root.gestureCardShown = Number(String(data["stdout"] || "").trim()) >= root.gestureCardVersion;
            disconnectSource(sourceName);
            root.maybeShowGestureCard();
        }
    }
    // Leaving tablet mode closes a card not dismissed yet (its gestures are tablet ones); it shows
    // again the next time.
    function maybeShowGestureCard(): void {
        if (tablet && !gestureCardShown && !gestureCardOpen) {
            gestureCardOpen = true;
        } else if (!tablet && gestureCardOpen) {
            gestureCardOpen = false;
        }
    }
    function dismissGestureCard(): void {
        gestureCardOpen = false;
        gestureCardShown = true;
        executable.run("kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true"
                       + " && kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion " + gestureCardVersion);
    }
    Loader {
        active: root.gestureCardOpen
        sourceComponent: GestureCard {
            pal: dockPal
            motion: motion
            screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
            onDismissed: root.dismissGestureCard()
        }
    }

    // ---- Content ----
    Item {
        id: row0
        x: Math.round((root.width - root.rest.width) / 2 + (root.padLeft - root.padRight) / 2)
        width: root.rest.width
        height: root.height

        DockButton {
            id: startButton
            x: root.rest.start ?? 0
            transform: Translate { x: root.mag.fixed.start ?? 0 }
            height: row0.height
            pal: dockPal
            motion: motion
            tile: root.tile
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Start")
            description: i18nc("@info:tooltip", "Open the application launcher")
            active: root.launcherOpen
            showIndicator: root.launcherOpen
            onPressedChanged: if (pressed) launcherWasOpen = root.launcherRecentlyOpen()
            onClicked: root.toggleLauncher(clickFromPointer ? launcherWasOpen : undefined, "home")

            FusionLogo {
                anchors.centerIn: parent
                size: Math.round(28 * root.tile / 48)
            }
        }

        DockButton {
            id: searchButton
            visible: root.showSearch
            x: root.rest.search ?? 0
            transform: Translate { x: root.mag.fixed.search ?? 0 }
            height: row0.height
            pal: dockPal
            motion: motion
            tile: root.tile
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Search")
            description: i18nc("@info:tooltip", "Search apps, files and settings")
            onPressedChanged: if (pressed) launcherWasOpen = root.launcherRecentlyOpen()
            onClicked: root.toggleSearch()

            Glyph {
                anchors.centerIn: parent
                size: Math.round(24 * root.tile / 48)
                color: dockPal.ink
                path: "M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0M20 20l-4-4"
            }
        }

        DockButton {
            id: overviewButton
            x: root.rest.overview ?? 0
            transform: Translate { x: root.mag.fixed.overview ?? 0 }
            height: row0.height
            pal: dockPal
            motion: motion
            tile: root.tile
            bottomPad: root.bottomPad
            text: i18nc("@action:button", "Overview")
            description: i18nc("@info:tooltip", "Show all windows and workspaces")
            onClicked: root.toggleOverview()

            Glyph {
                anchors.centerIn: parent
                size: Math.round(24 * root.tile / 48)
                color: overviewButton.active ? dockPal.activeInk : dockPal.ink
                path: "M4 5h11a1 1 0 0 1 1 1v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1zM8 19h12a1 1 0 0 0 1-1V9"
            }
        }

        Rectangle {
            x: root.rest.sep1 + (root.sepSlot - 1) / 2
            transform: Translate { x: root.mag.fixed.sep1 ?? 0 }
            y: row0.height - root.bottomPad - (root.tile - root.sepLength) / 2 - root.sepLength
            width: 1
            height: root.sepLength
            color: dockPal.separator
        }

        Repeater {
            id: taskRepeater

            onCountChanged: root.scheduleRescan()

            delegate: TaskItem {
                id: taskItem
                pal: dockPal
                motion: motion
                tablet: root.tablet
                pulseCycles: root.pulseCycles
                gap: root.gap
                entry: root.launcherEntries[taskItem.iconName] ?? null
                audio: root.audio
                pidsFor: row => root.taskPids(row)
                monthText: root.todayMonth
                dayText: root.todayDay
                shown: root.taskVisible[taskItem.index] ?? true
                x: root.rest.taskX[taskItem.index] ?? 0
                iconSize: root.rest.taskW[taskItem.index] ?? root.tile
                zoomSize: root.zoomSize
                zoomReady: root.zoomIconsReady
                height: row0.height
                bottomPad: root.bottomPad
                onActivated: modifiers => {
                    // Tablet posture: starting a pinned app zooms from its tile (TABLET2 M1).
                    if (root.tablet && taskItem.isLauncher) {
                        launchZoom.play(taskItem.iconItem, taskItem.model.decoration, taskItem.iconName);
                    }
                    root.activateTask(taskItem.index, modifiers);
                }
                onNewInstanceRequested: tasksModel.requestNewInstance(tasksModel.makeModelIndex(taskItem.index))
                onMenuRequested: root.showTaskMenu(taskItem)
                onDragMoved: sceneX => root.reorderTo(taskItem.index, sceneX)
                onDragFinished: root.finishReorder()
                onDesktopDrag: active => root.desktopDrag(taskItem, active)
                onSplitDragMoved: globalPos => root.splitDragMove(taskItem, globalPos)
                onSplitDragFinished: cancelled => root.splitDragEnd(taskItem, cancelled)
                onSplitArmed: armed => root.iconArmed = armed
                notificationCount: root.notificationCounts[taskItem.iconName] ?? 0
            }
        }

        Rectangle {
            x: root.rest.sep2 + (root.sepSlot - 1) / 2
            transform: Translate { x: root.mag.fixed.sep2 ?? 0 }
            y: row0.height - root.bottomPad - (root.tile - root.sepLength) / 2 - root.sepLength
            width: 1
            height: root.sepLength
            color: dockPal.separator
            visible: root.rest.sep2 >= 0
        }

        DockButton {
            id: downloadsButton
            visible: root.showDownloadsTrash
            x: root.rest.downloads ?? 0
            transform: Translate { x: root.mag.fixed.downloads ?? 0 }
            height: row0.height
            pal: dockPal
            motion: motion
            tile: root.tile
            bottomPad: root.bottomPad
            acceptsMenu: true
            text: i18nc("@action:button", "Downloads")
            description: i18nc("@info:tooltip", "Open the Downloads folder")
            onClicked: Qt.openUrlExternally(root.downloadsUrl)
            onMenuRequested: root.showDownloadsMenu()

            DownloadsStack {
                anchors.fill: parent
                pal: dockPal
            }
        }

        DockButton {
            id: trashButton
            visible: root.showDownloadsTrash
            x: root.rest.trash ?? 0
            transform: Translate { x: root.mag.fixed.trash ?? 0 }
            height: row0.height
            pal: dockPal
            motion: motion
            tile: root.tile
            bottomPad: root.bottomPad
            acceptsMenu: true
            text: root.trashFull ? i18nc("@action:button", "Trash (full)") : i18nc("@action:button", "Trash")
            description: i18nc("@info:tooltip", "Open the Trash; drop files here to move them to the Trash")
            onClicked: Qt.openUrlExternally("trash:/")
            onMenuRequested: root.showTrashMenu()

            Glyph {
                anchors.centerIn: parent
                size: Math.round(24 * root.tile / 48)
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
        // Placed when the hovered item changes, at the item's position and magnified size at
        // that moment; it does not follow the magnification frame by frame (EFFECTS.md 4.4).
        Item {
            id: pillAnchor
            readonly property Item target: root.pillTarget
            height: 1
            onTargetChanged: place()

            function place(): void {
                const t = target;
                if (!t) {
                    return;
                }
                if (t instanceof TaskItem) {
                    const task = t as TaskItem;
                    // The size the hovered icon grows to with the pointer where it is now.
                    const r = root.rest;
                    const c = r.taskC[task.index] ?? 0;
                    const d = isNaN(root.cursorX) ? 0 : (c - root.cursorX) / r.radius;
                    const full = root.zoom > 0 || root.pointerOverTasks
                        ? (root.zoomSize - r.taskTile) * Math.max(0, 1 - d * d) : 0;
                    const grow = Math.max(task.grow, full);
                    x = task.x + task.shift - grow / 2;
                    width = task.width + grow;
                    y = task.iconTop - grow - 12;
                } else {
                    const button = t as DockButton;
                    const shift = button.transform.length > 0 ? (button.transform[0] as Translate).x : 0;
                    x = button.x + shift;
                    width = button.width;
                    y = button.face.y - 12;
                }
                if (pill.item) {
                    (pill.item as NamePill).reposition();
                }
                if (preview.item) {
                    (preview.item as WindowPreview).reposition();
                }
            }
        }
    }

    readonly property Item wantedPillTarget: {
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
    // The pill is its own window: moving between two items while still over the dock keeps it
    // shown for 150 ms instead of unmapping and mapping the window again.
    property Item pillTarget: null
    onWantedPillTargetChanged: {
        if (wantedPillTarget || !hoverHandler.hovered || menuOpen || dragRow >= 0) {
            pillHideTimer.stop();
            pillTarget = wantedPillTarget;
        } else {
            pillHideTimer.restart();
        }
    }
    Timer {
        id: pillHideTimer
        interval: 150
        onTriggered: root.pillTarget = root.wantedPillTarget
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
            visible: root.pillText !== "" && root.visible && root.previewTarget === null
        }
    }

    // ---- Audio indicator (the stock task manager's): the apps' streams, from plasma-pa ----
    // Without plasma-pa the file does not load and the tiles show no indicator.
    Loader {
        id: audioLoader
        asynchronous: true
        source: "AudioStreams.qml"
    }
    readonly property QtObject audio: audioLoader.item
    // The process ids of a task: for a group, every window's (they can be several processes; the
    // group's own AppPid is its first window's).
    function taskPids(row: int): var {
        const atm = TaskManager.AbstractTasksModel;
        const index = tasksModel.makeModelIndex(row);
        const pids = [];
        const take = pid => {
            if (pid > 0 && pids.indexOf(pid) === -1) {
                pids.push(pid);
            }
        };
        if (tasksModel.data(index, atm.IsGroupParent) === true) {
            for (let j = 0; j < tasksModel.rowCount(index); ++j) {
                take(Number(tasksModel.data(tasksModel.makeModelIndex(row, j), atm.AppPid) || 0));
            }
        } else {
            take(Number(tasksModel.data(index, atm.AppPid) || 0));
        }
        return pids;
    }
    // Windows came or went (a group gained or lost a process): the tiles match their streams again.
    function refreshAudio(): void {
        for (let i = 0; i < taskRepeater.count; ++i) {
            const task = taskRepeater.itemAt(i) as TaskItem;
            if (task) {
                task.updateAudioStreams();
            }
        }
    }

    // ---- Window previews (showPreviews; the stock task manager's tooltips) ----
    // After the pointer rests on a running app for 500 ms its windows' previews replace the name
    // pill; moving to another running app switches at once. The preview stays while the pointer
    // is on it, and leaving both the app and the preview hides it after 300 ms (time to cross the
    // gap between them).
    property Item previewTarget: null
    // Read fresh where it decides: a change handler can run before this binding is updated.
    function previewWantedNow(): bool {
        return Plasmoid.configuration.showPreviews && pillTarget instanceof TaskItem && (pillTarget as TaskItem).isRunning;
    }
    readonly property bool previewWanted: previewWantedNow()
    readonly property bool previewHovered: preview.item ? (preview.item as WindowPreview).hovered : false
    onPillTargetChanged: {
        if (previewWantedNow()) {
            previewHide.stop();
            if (previewTarget) {
                previewTarget = pillTarget;
            } else {
                previewDwell.restart();
            }
        } else {
            previewDwell.stop();
            if (previewTarget && !previewHovered) {
                previewHide.restart();
            }
        }
    }
    onPreviewHoveredChanged: {
        if (previewHovered) {
            previewHide.stop();
        } else if (previewTarget && !previewWantedNow()) {
            previewHide.restart();
        }
    }
    Timer {
        id: previewDwell
        interval: 500
        onTriggered: {
            if (root.previewWantedNow()) {
                root.previewTarget = root.pillTarget;
            }
        }
    }
    Timer {
        id: previewHide
        interval: 300
        onTriggered: {
            if (!root.previewHovered && !root.previewWantedNow()) {
                root.previewTarget = null;
            }
        }
    }
    Loader {
        id: preview
        active: root.previewTarget !== null
        sourceComponent: WindowPreview {
            pal: dockPal
            taskModel: tasksModel
            screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
            anchorItem: pillAnchor
            row: root.previewTarget ? (root.previewTarget as TaskItem).index : -1
            appName: root.previewTarget ? (root.previewTarget as TaskItem).name : ""
            visible: root.visible
            onDone: root.previewTarget = null
        }
    }

    Component.onCompleted: {
        launcherApplet = findLauncherApplet();
        insetTimer.start();
        relayout();
        // tent posture: the first decision is always written (clears a stale value)
        tentTimer.restart();
    }
}
