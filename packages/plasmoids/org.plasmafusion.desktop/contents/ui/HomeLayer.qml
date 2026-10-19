/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import QtQuick.Templates as T
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.plasma.plasma5support as P5Support

import "code/home.js" as HomeLogic
import "FusionPairs.js" as Pairs

// The home screen in tablet posture (TABLET2 H1, owner decision "iPad-style"): pages of apps in the
// desktop window, under the apps, in place of Folder View (whose rubber band was the owner's pen
// "selection box" on the home screen). Page 1 holds the pinned apps (the launcher's pins: one list,
// KActivities client org.plasmafusion.launcher.favorites), the next pages every app A to Z, as in
// the tablet launcher sheet. Grid 6 x 5 in landscape, 5 x 6 in portrait (TABLET2 decision 1); on
// page 1 the columns stop before the widget area (the containment's cards, `widgetRect`), which
// fades out on the other pages. 72 px icons in 120 px tall cells, labels white over the wallpaper,
// page dots, the dock's 128 px kept clear. A tap launches; a long press (or a right click, a pen's
// barrel button) opens the app's menu: add to or remove from page 1, its actions. A swipe down
// (96 px or 800 px/s; the pages follow the finger) opens the launcher's search with the keyboard
// (TABLET2 H2, iPadOS and Android).
//
// Edit mode (TABLET2 H2; research A-ipad: visible Done, undo, deterministic placement): a long press
// on empty space, or "Edit Home Screen" in an app's menu. Page 1's tiles get a little smaller and
// carry a remove badge; a tile dragged onto another takes its place (the pinned list's
// order), dragged onto a page dot it moves to that page (its last place; a full page passes its last
// app on); the A-Z pages show "+" on apps not on the home pages. Pins that do not fit on page 1
// continue on further pages before the A-Z pages. Each change can be undone for 5 s. "Done"
// (56 px, right of the page dots), a tap on empty space, Escape or leaving tablet posture ends it.
Item {
    id: home

    required property var plasmoidItem
    required property FusionMetrics metrics
    required property Motion motion
    // The cards' bounding rectangle in this item's coordinates (empty: none).
    property rect widgetRect: Qt.rect(0, 0, 0, 0)

    readonly property bool portrait: height > width
    readonly property int columns: portrait ? 5 : 6
    readonly property int dockReserve: 128
    readonly property int dotsHeight: 36
    readonly property real gridTop: 24
    readonly property real gridHeight: Math.max(120, height - gridTop - dockReserve - dotsHeight)
    readonly property int rows: Math.max(1, Math.min(portrait ? 6 : 5, Math.floor(gridHeight / 120)))
    readonly property real cellWidth: Math.floor((width - 96) / columns)
    readonly property real cellHeight: Math.floor(gridHeight / rows)
    readonly property int perPage: columns * rows
    // Page 1 leaves the widget column (landscape) or band (portrait) free.
    readonly property bool widgetsAtRight: widgetRect.width > 0 && widgetRect.x > width / 2
    readonly property bool widgetsAtTop: widgetRect.height > 0 && !widgetsAtRight && widgetRect.y + widgetRect.height < height / 2
    readonly property int firstColumns: widgetsAtRight ? Math.max(1, Math.floor((widgetRect.x - 48 - 24) / cellWidth)) : columns
    readonly property real firstTop: widgetsAtTop ? widgetRect.y + widgetRect.height + 16 : gridTop
    // (exactly `rows` unless the widgets sit above the grid: the ratio below dips by one for a frame
    // while the height animates, before cellHeight follows)
    readonly property int firstRows: widgetsAtTop ? Math.max(1, Math.floor((gridTop + gridHeight - firstTop) / cellHeight)) : rows

    readonly property var favoritesModel: rootModel.favoritesModel
    readonly property var allModel: {
        const model = rootModel.count > 0 ? rootModel.modelForRow(0) : null;
        return model && model.description === "KICKER_ALL_MODEL" ? model : null;
    }
    readonly property int allCount: allModel ? allModel.count : 0
    // Home pages (TABLET2 section 7; iPadOS): the pins in order, page by page, then the A-Z pages.
    // How many pins each page holds is kept (containment config homePageSizes, "7,2"), so an app
    // moved to another page does not pull its neighbours across; empty: page 1 fills first. A page
    // holds at most its capacity (the rest moves on to the next page, so a rotation or a bigger
    // widget area never hides an app); new pins fill the last page's room, then new pages.
    readonly property int firstSlots: firstColumns * firstRows
    readonly property int favoritesCount: favoritesModel ? favoritesModel.count : 0
    readonly property var storedSizes: String(Plasmoid.configuration.homePageSizes || "").split(",")
        .filter(s => s.trim() !== "").map(s => Math.max(0, parseInt(s, 10) || 0))
    readonly property var pageTakes: layoutPages(storedSizes, favoritesCount, firstSlots, perPage)
    readonly property int pinnedPages: pageTakes.length
    readonly property int pageCount: pinnedPages + Math.ceil(allCount / Math.max(1, perPage))
    function capacity(page: int): int {
        return page <= 0 ? firstSlots : perPage;
    }
    function layoutPages(sizes: var, count: int, first: int, per: int): var {
        const takes = [];
        let remaining = count;
        let carry = 0;
        for (let i = 0; i < sizes.length && remaining > 0; ++i) {
            const cap = i === 0 ? first : per;
            const want = sizes[i] + carry;
            const take = Math.min(want, cap, remaining);
            carry = want > cap ? want - cap : 0;
            remaining -= take;
            if (take > 0 || takes.length === 0) {
                takes.push(take);
            }
        }
        if (remaining > 0 && takes.length > 0) {
            const last = takes.length - 1;
            const add = Math.min(Math.max(0, (last === 0 ? first : per) - takes[last]), remaining);
            takes[last] += add;
            remaining -= add;
        }
        while (remaining > 0) {
            const take = Math.min(takes.length === 0 ? first : per, remaining);
            takes.push(take);
            remaining -= take;
        }
        return takes.length > 0 ? takes : [0];
    }
    function pageStart(page: int): int {
        if (page >= pinnedPages) {
            return (page - pinnedPages) * perPage;
        }
        let start = 0;
        for (let i = 0; i < page; ++i) {
            start += pageTakes[i];
        }
        return start;
    }
    function pageSize(page: int): int {
        return page < pinnedPages ? pageTakes[page] : perPage;
    }
    function pageOf(row: int): int {
        let end = 0;
        for (let i = 0; i < pinnedPages; ++i) {
            end += pageTakes[i];
            if (row < end) {
                return i;
            }
        }
        return -1;
    }
    // The pages as rows: an int model would reset the view to page 1 whenever the count changes (an
    // app added from an A-Z page that opens a new home page); rows inserted or removed before the
    // current page keep the view where it is. Home pages change at their end, A-Z pages at the end.
    ListModel {
        id: pageModel
    }
    property int modelPinned: 0
    property int modelAll: 0
    function syncPages(): void {
        const all = Math.ceil(allCount / Math.max(1, perPage));
        // an A-Z page in view stays in view (a home page inserted at its index would take its place)
        const allIndex = pageModel.count > 0 ? pages.currentIndex - modelPinned : -1;
        while (modelPinned < pinnedPages) {
            pageModel.insert(modelPinned, { "page": 0 });
            ++modelPinned;
        }
        while (modelPinned > pinnedPages) {
            pageModel.remove(modelPinned - 1);
            --modelPinned;
        }
        while (modelAll < all) {
            pageModel.append({ "page": 0 });
            ++modelAll;
        }
        while (modelAll > all) {
            pageModel.remove(pageModel.count - 1);
            --modelAll;
        }
        if (allIndex >= 0 && allIndex < modelAll) {
            pages.forceLayout(); // (the view applies model changes at its next layout)
            if (pages.currentIndex !== modelPinned + allIndex) {
                pages.positionViewAtIndex(modelPinned + allIndex, ListView.Beginning);
                pages.currentIndex = modelPinned + allIndex;
            }
        }
    }
    // once per event loop pass, with settled values (both change together)
    onPinnedPagesChanged: Qt.callLater(syncPages)
    onPageCountChanged: Qt.callLater(syncPages)
    Component.onCompleted: {
        syncPages();
        Qt.callLater(findFreeSide);
    }
    function storeSizes(sizes: var): void {
        const s = sizes.slice();
        while (s.length > 1 && s[s.length - 1] <= 0) {
            s.pop();
        }
        Plasmoid.configuration.homePageSizes = s.map(n => Math.max(0, n)).join(",");
    }
    readonly property alias currentPage: pages.currentIndex
    property real dragDown: 0

    // ---- Edit mode
    property bool editing: false
    property int dragFrom: -1
    property int dropTo: -1
    // A dragged tile over a page dot (a pinned page): dropped there, it moves to that page.
    property int dropPage: -1
    property point ghostPos: Qt.point(0, 0)
    property var ghostSource
    property string ghostName: ""
    // {kind: "remove", id, index, sizes} | {kind: "add", id} | {kind: "move", from, to}
    // | {kind: "pagemove", from, to, sizes}
    property var undoAction: null
    function startEditing(): void {
        editing = true;
        home.forceActiveFocus();
    }
    function stopEditing(): void {
        editing = false;
        dragFrom = -1;
        dropTo = -1;
        dropPage = -1;
        undoAction = null;
    }
    // (the model's `favorites` list reads empty from QML: the tile passes its favoriteId)
    function removeAt(row: int, id: string): void {
        if (id !== "") {
            const before = pageTakes.slice();
            const page = pageOf(row);
            favoritesModel.removeFavorite(id);
            if (page >= 0) {
                const s = before.slice();
                s[page] -= 1;
                storeSizes(s);
            }
            remember({ "kind": "remove", "id": id, "index": row, "sizes": before });
        }
    }
    function addToHome(entry): void {
        const id = entry && entry.favoriteId ? String(entry.favoriteId) : "";
        if (id !== "" && !favoritesModel.isFavorite(id)) {
            favoritesModel.addFavorite(id, -1);
            remember({ "kind": "add", "id": id });
        }
    }
    function move(from: int, to: int): void {
        if (from >= 0 && to >= 0 && from !== to) {
            favoritesModel.moveRow(from, to);
            remember({ "kind": "move", "from": from, "to": to });
        }
    }
    // To the last place of a pinned page; on a full page its last app moves on to the next one.
    function moveToPage(from: int, page: int): void {
        const fromPage = pageOf(from);
        if (page < 0 || page >= pinnedPages || fromPage < 0 || fromPage === page) {
            return;
        }
        const before = pageTakes.slice();
        const s = before.slice();
        s[fromPage] -= 1;
        s[page] += 1;
        let start = 0;
        for (let i = 0; i < page; ++i) {
            start += s[i];
        }
        const to = Math.min(start + Math.min(s[page], capacity(page)) - 1, favoritesCount - 1);
        if (to !== from) {
            favoritesModel.moveRow(from, to);
        }
        storeSizes(layoutPages(s, favoritesCount, firstSlots, perPage));
        remember({ "kind": "pagemove", "from": from, "to": to, "sizes": before });
        pages.currentIndex = page;
    }
    // The pinned page whose dot is under `p` (home coordinates), or -1.
    function dotAt(p: point): int {
        if (!dots.visible) {
            return -1;
        }
        const q = dots.mapFromItem(home, p.x, p.y);
        const cell = q.y >= 0 && q.y < dots.height ? dots.childAt(q.x, q.y) : null;
        return cell && typeof cell.index === "number" && cell.index < pinnedPages ? cell.index : -1;
    }
    function remember(action): void {
        undoAction = action;
        undoTimer.restart();
    }
    function undo(): void {
        const a = undoAction;
        undoAction = null;
        if (!a) {
            return;
        }
        if (a.kind === "remove") {
            favoritesModel.addFavorite(a.id, a.index);
            storeSizes(a.sizes);
        } else if (a.kind === "add") {
            favoritesModel.removeFavorite(a.id);
        } else if (a.kind === "move") {
            favoritesModel.moveRow(a.to, a.from);
        } else if (a.kind === "pagemove") {
            if (a.to !== a.from) {
                favoritesModel.moveRow(a.to, a.from);
            }
            storeSizes(a.sizes);
            pages.currentIndex = Math.min(pageOf(a.from), pinnedPages - 1);
        }
    }
    Timer {
        id: undoTimer
        interval: 5000
        onTriggered: home.undoAction = null
    }
    Keys.onEscapePressed: event => {
        if (editing) {
            stopEditing();
        } else {
            event.accepted = false;
        }
    }

    // An app's desktop file id for a split ("" for anything else): "applications:x.desktop" -> "x.desktop".
    function splitAppId(favoriteId: string): string {
        const id = String(favoriteId || "").replace(/^applications:/, "");
        return /^[A-Za-z0-9._-]+\.desktop$/.test(id) ? id : "";
    }
    // The dock splits the screen on a splitRequest "<left|right>:<nonce>:<app>.desktop": the dock of
    // this screen only (home.js splitScript), so a dock on every screen does not start it twice.
    function requestSplit(side: string, appId: string): void {
        if (appId === "" || (side !== "left" && side !== "right")) {
            return;
        }
        console.info("home: split request: " + appId + " to the " + side);
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell", "path": "/PlasmaShell", "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript",
            "arguments": [new DBus.string(HomeLogic.splitScript(side, appId, Plasmoid.containment.screen, Date.now()))],
            "signature": "(s)"
        }, () => {}, error => console.warn("home: split request failed: " + error));
    }

    // ---- The free side (board TabletSplit.dc.html): one app fills a half, top to bottom, and
    // nothing is shown beside it (a split with nothing else open, or the other app of a split closed
    // or sent home). The pages, their dots and the cards step aside, and the free part offers the
    // apps (FreeSidePicker.qml); a tap opens the app on that side the way a split request does. The
    // windows of this screen, desktop and activity come from the task manager's model (their
    // geometry, which KWin publishes), so no script has to say where the split is.
    property var freeSide: null
    readonly property bool picking: freeSide !== null
    onPickingChanged: {
        if (picking) {
            stopEditing();
        }
    }
    TaskManager.VirtualDesktopInfo {
        id: desktopInfo
    }
    TaskManager.ActivityInfo {
        id: activityInfo
    }
    TaskManager.TasksModel {
        id: screenTasks
        screenGeometry: home.plasmoidItem.screenGeometry
        virtualDesktop: desktopInfo.currentDesktop
        activity: activityInfo.currentActivity
        filterByVirtualDesktop: true
        filterByActivity: true
        filterByScreen: true
        filterMinimized: true
        filterHidden: true
        groupMode: TaskManager.TasksModel.GroupDisabled
    }
    Connections {
        target: screenTasks
        function onCountChanged(): void { Qt.callLater(home.findFreeSide); }
        function onDataChanged(): void { Qt.callLater(home.findFreeSide); }
        function onModelReset(): void { Qt.callLater(home.findFreeSide); }
        function onLayoutChanged(): void { Qt.callLater(home.findFreeSide); }
    }
    onWidthChanged: Qt.callLater(findFreeSide)
    onHeightChanged: Qt.callLater(findFreeSide)
    function findFreeSide(): void {
        const atm = TaskManager.AbstractTasksModel;
        // The window geometry is the screen's (global) one; this layer starts at the work area's
        // corner (the containment's availableScreenRect, relative to its screen).
        const screen = home.plasmoidItem.screenGeometry;
        const avail = home.plasmoidItem.availableScreenRect;
        const ox = screen.x + avail.x;
        const oy = screen.y + avail.y;
        const windows = [];
        for (let row = 0; row < screenTasks.count; ++row) {
            const index = screenTasks.makeModelIndex(row);
            if (screenTasks.data(index, atm.IsWindow) !== true || screenTasks.data(index, atm.IsMinimized) === true
                    || screenTasks.data(index, atm.IsHidden) === true) {
                continue;
            }
            const g = screenTasks.data(index, atm.Geometry);
            if (!g) {
                continue;
            }
            windows.push({ "x": g.x - ox, "y": g.y - oy, "width": g.width, "height": g.height,
                           "appId": String(screenTasks.data(index, atm.AppId) || "") });
        }
        const found = HomeLogic.freeSide(windows, { "x": 0, "y": 0, "width": home.width, "height": home.height });
        if (!HomeLogic.sameFree(found, freeSide)) {
            freeSide = found;
            console.info("home: free side: " + (found ? found.side + ", " + Math.round(found.width) + " px from x "
                                                + Math.round(found.x) + " beside " + found.appId : "none"));
        }
    }
    // A tap in the free part: the app opens on that side (the dock's split request; the app beside
    // it is already in the other half, where KWin leaves a window quick-tiled again to its side).
    function pickForSide(iconItem: Item, entry, side: string, appId: string): void {
        if (appId === "") {
            return;
        }
        const p = home.mapToGlobal(freeSide ? freeSide.x : 0, freeSide ? freeSide.y : 0);
        launchZoom.play(iconItem, entry.decoration || "application-x-executable", iconNameFor(entry),
                        freeSide ? Qt.rect(p.x, p.y, freeSide.width, freeSide.height) : undefined);
        requestSplit(side, appId);
    }

    // ---- Saved app pairs (board TabletPairs.dc.html, docs/parts/apppairs.md): a pair is an
    // application entry of its own (org.plasmafusion.pair-ID.desktop in the user's applications,
    // written by the plasma-fusion-app-pair helper), held on the home screen as a pinned app. Its
    // tile shows both apps' tiles on a plate; a tap has this screen's dock open both side by side.
    // The apps of the A-Z pages by desktop file id: a pair's apps, with their names and icons.
    Instantiator {
        id: appIndex
        model: home.allModel
        delegate: QtObject {
            required property string favoriteId
            required property string display
            required property var decoration
        }
    }
    // Desktop files read as QtCore Settings reads them (read only: a Settings object stores each
    // property declared on it in its file, so this one declares none).
    Component {
        id: entryFile
        Settings {}
    }
    function readEntry(location: url, read): var {
        const file = entryFile.createObject(home, { "location": location });
        if (!file) {
            return null;
        }
        const result = read(k => file.value(k));
        file.destroy();
        return result;
    }
    // An app of a pair: the A-Z pages' entry, else its desktop file in the data directories (an
    // app the menus hide), else gone: {name, source, iconName, missing}.
    function pairApp(appId: string, fallbackName: string): var {
        const iconName = Pairs.iconName(appId);
        for (let i = 0; i < appIndex.count; ++i) {
            const a = appIndex.objectAt(i);
            if (a && a.favoriteId === "applications:" + appId) {
                return { "name": a.display, "source": a.decoration || "application-x-executable", "iconName": iconName, "missing": false };
            }
        }
        const dirs = StandardPaths.standardLocations(StandardPaths.GenericDataLocation);
        for (let i = 0; i < dirs.length; ++i) {
            const app = readEntry(dirs[i] + "/applications/" + appId, v => Pairs.readApp(v, Qt.locale().name));
            if (app) {
                return { "name": app.name || iconName, "source": app.icon || "application-x-executable", "iconName": iconName, "missing": false };
            }
        }
        return { "name": fallbackName || iconName, "source": "application-x-executable", "iconName": iconName, "missing": true };
    }
    // The pair a favourite is, or null: {id, left, right (pairApp), leftId, rightId, share, label}.
    function pairInfo(favoriteId: string): var {
        const id = Pairs.pairId(favoriteId);
        if (id === "") {
            return null;
        }
        const location = StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/applications/" + id;
        const entry = readEntry(location, v => {
            const pair = Pairs.readPair(v);
            return pair ? Object.assign(pair, { "names": String(v("Desktop Entry/Name") ?? "").split(" · ") }) : null;
        });
        if (!entry) {
            return null;
        }
        const left = pairApp(entry.left, entry.names.length === 2 ? entry.names[0] : "");
        const right = pairApp(entry.right, entry.names.length === 2 ? entry.names[1] : "");
        return { "id": id, "left": left, "right": right, "leftId": entry.left, "rightId": entry.right,
                 "share": entry.share, "label": Pairs.label(left.name, right.name) };
    }
    // A tap on a pair: this screen's dock opens both apps (its pairRequest).
    function openPair(pair): void {
        if (!pair || pair.left.missing || pair.right.missing) {
            return;
        }
        console.info("home: pair: " + pair.leftId + " | " + pair.rightId + ", split " + pair.share);
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell", "path": "/PlasmaShell", "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript",
            "arguments": [new DBus.string(Pairs.pairScript({ "left": pair.leftId, "right": pair.rightId, "share": pair.share },
                                                         Plasmoid.containment.screen, Date.now()))],
            "signature": "(s)"
        }, () => {}, error => console.warn("home: pair request failed: " + error));
    }
    // Keep in Dock: this screen's dock pins the pair's entry (its keepRequest), as the launcher's
    // Keep in Dock pins an app.
    function keepPairInDock(favoriteId: string): void {
        const script = Pairs.keepScript(favoriteId, Plasmoid.containment.screen, Date.now());
        if (script === "") {
            return;
        }
        console.info("home: pair: keep in dock " + Pairs.pairId(favoriteId));
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell", "path": "/PlasmaShell", "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript", "arguments": [new DBus.string(script)], "signature": "(s)"
        }, () => {}, error => console.warn("home: keep in dock failed: " + error));
    }
    // Swap Sides and Remove Pair: the helper rewrites or deletes the entry, then rebuilds KDE's
    // application cache, and the pinned apps model reads the pair again.
    P5Support.DataSource {
        id: pairHelper
        engine: "executable"
        onNewData: (source, data) => {
            if (Number(data["exit code"]) !== 0) {
                console.warn("home: pair helper failed (" + data["exit code"] + "): " + String(data.stderr || "").trim());
            }
            disconnectSource(source);
        }
    }
    function swapPair(pairIdValue: string): void {
        const command = Pairs.helperCommand("swap", pairIdValue);
        if (command !== "") {
            console.info("home: pair: swap " + pairIdValue);
            pairHelper.connectSource(command);
        }
    }
    // Unpinned and deleted at once (no undo: the entry is gone with it).
    function removePair(row: int, favoriteId: string): void {
        const id = Pairs.pairId(favoriteId);
        const command = Pairs.helperCommand("remove", id);
        if (command === "") {
            return;
        }
        console.info("home: pair: remove " + id);
        const page = row >= 0 ? pageOf(row) : -1;
        const sizes = pageTakes.slice();
        favoritesModel.removeFavorite(favoriteId);
        if (page >= 0) {
            sizes[page] -= 1;
            storeSizes(sizes);
        }
        pairHelper.connectSource(command);
    }
    // The helper's "save" (the app switcher's Save pair) asks every home screen to pin the new
    // pair: pinRequest "nonce:applications:ID", a pair's entry only. The switcher works on the
    // laptop too, where this layer is not loaded: a request waiting in the configuration is taken
    // when the layer loads (rootModel's favourites ready), and every request is cleared once taken (a pair removed since is not
    // pinned again).
    Connections {
        target: Plasmoid.configuration
        function onPinRequestChanged(): void {
            home.takePinRequest();
        }
    }
    function takePinRequest(): void {
        const request = String(Plasmoid.configuration.pinRequest || "");
        if (request === "" || !favoritesModel) {
            return;
        }
        const favoriteId = request.slice(request.indexOf(":") + 1);
        Plasmoid.configuration.pinRequest = "";
        if (pairInfo(favoriteId) !== null && !favoritesModel.isFavorite(favoriteId)) {
            console.info("home: pair: pin " + favoriteId);
            favoritesModel.addFavorite(favoriteId, -1);
        }
    }

    // The launcher (in the dock) opens on an openRequest "<mode>:<nonce>[:<argument>]".
    function openSearch(): void {
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell", "path": "/PlasmaShell", "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript",
            "arguments": [new DBus.string("panels().forEach(function (p) { p.widgets(\"org.plasmafusion.launcher\").forEach(function (w) {"
                + " w.currentConfigGroup = [\"General\"]; w.writeConfig(\"openRequest\", \"search:\" + Date.now()); }); });")],
            "signature": "(s)"
        }, () => {}, () => {});
    }

    // The models the launcher uses (a second instance; KActivities keeps the pins in sync).
    Kicker.RootModel {
        id: rootModel
        autoPopulate: false
        appletInterface: home.plasmoidItem
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showRootSeparator: false
        showTopLevelItems: true
        showAllApps: true
        showAllAppsCategorized: false
        showRecentApps: false
        showRecentDocs: false
        showRecentFolders: false
        showPowerSession: false
        showFavoritesPlaceholder: false
        highlightNewlyInstalledApps: false
        Component.onCompleted: {
            (favoritesModel as Kicker.KAStatsFavoritesModel).initForClient("org.plasmafusion.launcher.favorites");
            refresh();
            // (the favourites take a pin only from here on: a request waiting since the laptop)
            Qt.callLater(home.takePinRequest);
        }
    }

    function iconNameFor(entry): string {
        const id = entry && entry.favoriteId ? String(entry.favoriteId) : "";
        if (id === "" || id.indexOf("://") >= 0) {
            return "";
        }
        return id.replace(/^applications:/, "").replace(/\.desktop$/, "");
    }

    HomeActionMenu {
        id: actionMenu
        home: home
    }

    // The app-open zoom (TABLET2 M1).
    FusionLaunchZoom {
        id: launchZoom
        dark: {
            const c = Kirigami.Theme.backgroundColor;
            return (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) < 0.5;
        }
    }

    ListView {
        id: pages
        objectName: "homePages"
        visible: !home.picking
        width: parent.width
        height: parent.height
        y: Math.min(120, home.dragDown * 0.5)
        opacity: 1 - Math.min(0.5, home.dragDown / 400)
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        // edit mode: tile drags, not page flicks (the dots still change pages)
        interactive: !home.editing
        highlightMoveDuration: home.motion.surface
        cacheBuffer: 0
        clip: true
        model: pageModel
        Accessible.role: Accessible.PageTabList
        Accessible.name: i18nc("@label", "Home screen pages")

        delegate: Item {
            id: pageItem
            required property int index
            readonly property bool first: index === 0
            readonly property bool pinned: index < home.pinnedPages
            readonly property int pageColumns: first ? home.firstColumns : home.columns
            readonly property int start: home.pageStart(index)
            readonly property int count: home.pageSize(index)
            width: pages.width
            height: pages.height

            // Empty space (tiles take their own presses): a long press starts edit mode, a tap
            // ends it.
            TapHandler {
                onLongPressed: home.startEditing()
                onTapped: {
                    if (home.editing) {
                        home.stopEditing();
                    }
                }
            }

            GridView {
                id: grid
                readonly property int index: pageItem.index
                readonly property bool pinned: pageItem.pinned
                readonly property int start: pageItem.start
                x: 48
                y: pageItem.first ? home.firstTop : home.gridTop
                width: pageItem.pageColumns * home.cellWidth
                height: (pageItem.first ? home.firstRows : home.rows) * home.cellHeight
                cellWidth: home.cellWidth
                cellHeight: home.cellHeight
                interactive: false
                Accessible.role: Accessible.List
                model: KItemModels.KSortFilterProxyModel {
                    sourceModel: pageItem.pinned ? home.favoritesModel : home.allModel
                    // A new callback whenever the page's slice changes: the proxy filters again only
                    // when its callback changes.
                    filterRowCallback: {
                        const start = pageItem.start;
                        const end = start + pageItem.count;
                        return (row, parent) => row >= start && row < end;
                    }
                }
                delegate: HomeTile {
                    pageView: grid
                }
            }
        }
    }

    // Swipe down: in a layer above the tiles, so the handler sees the touch first and holds only a
    // passive grab until the threshold; taps, long presses and page flicks still reach the tiles
    // and the pages (as in the launcher sheet).
    Item {
        anchors.fill: parent
        z: 100
        DragHandler {
            // (not while the free side's list scrolls up and down)
            enabled: !home.editing && !home.picking
            acceptedDevices: PointerDevice.TouchScreen
            target: null
            xAxis.enabled: false
            dragThreshold: 16
            onTranslationChanged: {
                if (active) {
                    home.dragDown = Math.max(0, translation.y);
                }
            }
            onActiveChanged: {
                if (active) {
                    return;
                }
                if (home.dragDown >= 96 || centroid.velocity.y >= 800) {
                    home.openSearch();
                }
                dragBack.start();
            }
        }
    }
    NumberAnimation {
        id: dragBack
        target: home
        property: "dragDown"
        to: 0
        duration: home.motion.popupOut
        easing.type: home.motion.standardEasing
    }

    // Page dots: 8 x 8, the current one 20 x 8, 10 apart, above the dock; tappable (44 px rows).
    Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        y: home.height - home.dockReserve - home.dotsHeight + 14 - 18
        spacing: 0
        visible: home.pageCount > 1 && !home.picking
        Repeater {
            model: home.pageCount
            // AbstractButtons (not TapHandlers): they take the press, so the page's empty-space tap
            // (which ends edit mode) does not fire with them.
            delegate: T.AbstractButton {
                id: dotCell
                required property int index
                // The target is the cell: the dot's pitch wide (dot + 10), 44 px tall. (A
                // containmentMask cannot reach past an item's bounds since Qt 6.8.)
                width: dot.width + 10
                height: 44
                padding: 0
                Accessible.role: Accessible.PageTab
                Accessible.name: i18nc("@action:button %1 page number", "Page %1", dotCell.index + 1)
                onClicked: pages.currentIndex = dotCell.index
                contentItem: Item {}
                background: Item {}
                Rectangle {
                    id: dot
                    anchors.centerIn: parent
                    // the current page, and in edit mode the pinned page a dragged tile would go to
                    readonly property bool target: home.dropPage === dotCell.index
                    width: dotCell.index === pages.currentIndex || target ? 20 : 8
                    height: target ? 12 : 8
                    radius: height / 2
                    color: target ? "#2f6fe0" : Qt.rgba(1, 1, 1, dotCell.index === pages.currentIndex ? 0.9 : 0.4)
                    Behavior on width {
                        enabled: home.motion.animate
                        NumberAnimation {
                            duration: home.motion.toggle
                            easing.type: home.motion.standardEasing
                        }
                    }
                }
            }
        }
    }

    Loader {
        active: home.picking
        x: home.freeSide ? home.freeSide.x : 0
        y: home.freeSide ? home.freeSide.y : 0
        width: home.freeSide ? home.freeSide.width : 0
        height: home.freeSide ? home.freeSide.height : 0
        sourceComponent: FreeSidePicker {
            home: home
            side: home.freeSide ? home.freeSide.side : "right"
            otherApp: home.freeSide ? home.freeSide.appId : ""
        }
    }

    // ---- Edit mode chrome: the dragged tile's ghost, Undo and Done (56 px pills at the right end of
    // the page dots' row, which is free on every page; at the top right they covered an app or a card).
    FusionIconTile {
        visible: home.dragFrom >= 0
        z: 200
        size: 80
        x: home.ghostPos.x - 40
        y: home.ghostPos.y - 40
        source: home.ghostSource
        iconName: home.ghostName
        calendarDate: true
    }
    Row {
        visible: home.editing
        z: 150
        anchors.right: parent.right
        anchors.rightMargin: 24
        y: dots.y + 18 + 4 - 28
        spacing: 12
        EditPill {
            visible: home.undoAction !== null
            text: i18nc("@action:button", "Undo")
            onClicked: home.undo()
        }
        EditPill {
            text: i18nc("@action:button leave the home screen's edit mode", "Done")
            accent: true
            onClicked: home.stopEditing()
        }
    }
    component EditPill: T.AbstractButton {
        id: pill
        property bool accent: false
        implicitWidth: Math.max(96, pillLabel.implicitWidth + 40)
        implicitHeight: 56
        Accessible.role: Accessible.Button
        Accessible.name: text
        contentItem: Text {
            id: pillLabel
            text: pill.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: "#ffffff"
            font.pixelSize: home.metrics.font(15)
            font.weight: Font.DemiBold
            textFormat: Text.PlainText
        }
        background: Rectangle {
            radius: height / 2
            color: pill.accent ? (pill.down ? "#2559b8" : "#2f6fe0") : (pill.down ? Qt.rgba(12 / 255, 15 / 255, 28 / 255, 0.85) : Qt.rgba(12 / 255, 15 / 255, 28 / 255, 0.7))
            border.width: pill.accent ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, 0.25)
        }
    }

    component HomeTile: T.AbstractButton {
        id: tile
        required property var pageView
        required property int index
        required property var model
        readonly property int sourceRow: pageView.start + index

        width: home.cellWidth
        height: home.cellHeight
        hoverEnabled: true
        // A saved app pair (null for an app): its two apps and the split.
        readonly property var pair: home.pairInfo(String(tile.model.favoriteId || ""))
        readonly property string missingApp: !pair ? "" : pair.left.missing ? pair.left.name : pair.right.missing ? pair.right.name : ""
        text: pair ? pair.label : (tile.model.display || "")
        // (where a pair is, for the session test that taps it, as the free side is logged)
        Component.onCompleted: {
            if (pair) {
                Qt.callLater(() => {
                    const c = tile.mapToGlobal(tile.width / 2, tile.height / 2);
                    console.info("home: pair tile: " + pair.id + " at " + Math.round(c.x) + "," + Math.round(c.y));
                });
            }
        }
        Accessible.role: Accessible.Button
        Accessible.name: !pair ? text
                         : missingApp !== "" ? i18nc("@info:whatsthis %1 the pair's name, %2 an app's name", "%1, an app pair, %2 is not installed", text, missingApp)
                         : i18nc("@info:whatsthis %1 the pair's name", "%1, an app pair", text)

        readonly property var source: pageView.pinned ? home.favoritesModel : home.allModel
        readonly property bool pinnedPage: pageView.pinned
        readonly property bool addable: home.editing && !pinnedPage && !!tile.model.favoriteId
                                        && !home.favoritesModel.isFavorite(String(tile.model.favoriteId))
        onClicked: {
            if (home.editing) {
                return;
            }
            // A pair opens both apps; with one of them gone, its menu (Remove Pair) instead.
            if (pair) {
                if (missingApp !== "") {
                    actionMenu.openFor(source, tile.sourceRow, tile.model, tile, width / 2, height / 2);
                } else {
                    home.openPair(pair);
                }
                return;
            }
            if (source) {
                launchZoom.play(icon, tile.model.decoration || "application-x-executable", home.iconNameFor(tile.model));
                source.trigger(tile.sourceRow, "", null);
            }
        }
        onPressAndHold: {
            if (!home.editing) {
                actionMenu.openFor(source, tile.sourceRow, tile.model, tile, width / 2, height / 2);
            }
        }
        // Edit mode, page 1: drag onto another tile to move there.
        DragHandler {
            enabled: home.editing && tile.pinnedPage
            target: null
            dragThreshold: 8
            onActiveChanged: {
                if (active) {
                    home.dragFrom = tile.sourceRow;
                    home.ghostSource = tile.model.decoration || "application-x-executable";
                    home.ghostName = home.iconNameFor(tile.model);
                } else if (home.dragFrom >= 0) {
                    if (home.dropPage >= 0) {
                        home.moveToPage(home.dragFrom, home.dropPage);
                    } else {
                        home.move(home.dragFrom, home.dropTo);
                    }
                    home.dragFrom = -1;
                    home.dropTo = -1;
                    home.dropPage = -1;
                }
            }
            onCentroidChanged: {
                if (!active) {
                    return;
                }
                const p = tile.mapToItem(home, centroid.position.x, centroid.position.y);
                home.ghostPos = p;
                home.dropPage = home.dotAt(p);
                const g = tile.mapToItem(tile.pageView, centroid.position.x, centroid.position.y);
                const local = tile.pageView.indexAt(g.x, g.y);
                home.dropTo = home.dropPage < 0 && local >= 0 ? tile.pageView.start + local : -1;
            }
        }
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint, button) => actionMenu.openFor(tile.source, tile.sourceRow, tile.model, tile, eventPoint.position.x, eventPoint.position.y)
        }

        background: Item {}
        contentItem: Item {
            // Edit mode: page 1's tiles a little smaller (a static cue: no endless jiggle, which
            // would keep the GPU drawing), the drop target smaller still.
            scale: tile.down && !home.editing ? 0.94
                 : home.editing && tile.pinnedPage ? (home.dropTo === tile.sourceRow && home.dragFrom !== tile.sourceRow ? 0.84 : 0.92) : 1
            opacity: home.dragFrom === tile.sourceRow && tile.pinnedPage ? 0.3 : 1
            Behavior on scale {
                enabled: home.motion.animate
                NumberAnimation {
                    duration: home.motion.press
                    easing.type: home.motion.standardEasing
                }
            }
            FusionShadow {
                anchors.fill: icon
                offset.y: 3
                blur: 8
                radius: 0.234 * icon.size
                color: Qt.rgba(0, 0, 0, 0.30)
            }
            FusionIconTile {
                id: icon
                x: (parent.width - width) / 2
                y: Math.round((parent.height - (72 + 10 + label.height + (missing.visible ? missing.height : 0))) / 2)
                size: 72
                visible: !tile.pair
                source: tile.model.decoration || "application-x-executable"
                iconName: home.iconNameFor(tile.model)
                // Today's date over the calendar tile, as in the launcher and the dock.
                calendarDate: true
            }
            FusionPairTile {
                visible: !!tile.pair
                x: icon.x
                y: icon.y
                size: icon.size
                leftSource: tile.pair ? tile.pair.left.source : ""
                leftIconName: tile.pair ? tile.pair.left.iconName : ""
                leftMissing: !!tile.pair && tile.pair.left.missing
                rightSource: tile.pair ? tile.pair.right.source : ""
                rightIconName: tile.pair ? tile.pair.right.iconName : ""
                rightMissing: !!tile.pair && tile.pair.right.missing
            }
            // Edit mode: remove (page 1) or add to page 1 (A-Z pages); 26 px drawn, 44 px target.
            T.AbstractButton {
                visible: (home.editing && tile.pinnedPage) || tile.addable
                x: icon.x - 22 + 4
                y: icon.y - 22 + 4
                width: 44
                height: 44
                text: tile.pinnedPage ? i18nc("@action:button %1 app name", "Remove %1 from the home screen", tile.text)
                                      : i18nc("@action:button %1 app name", "Add %1 to the home screen", tile.text)
                Accessible.name: text
                onClicked: {
                    if (tile.pinnedPage && tile.pair) {
                        home.removePair(tile.sourceRow, String(tile.model.favoriteId || ""));
                    } else if (tile.pinnedPage) {
                        home.removeAt(tile.sourceRow, String(tile.model.favoriteId || ""));
                    } else {
                        home.addToHome(tile.model);
                    }
                }
                contentItem: Item {}
                background: Item {
                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: tile.pinnedPage ? "#3a4157" : "#2f6fe0"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.5)
                        Rectangle {
                            anchors.centerIn: parent
                            width: 12
                            height: 2
                            radius: 1
                            color: "#ffffff"
                        }
                        Rectangle {
                            visible: !tile.pinnedPage
                            anchors.centerIn: parent
                            width: 2
                            height: 12
                            radius: 1
                            color: "#ffffff"
                        }
                    }
                }
            }
            Text {
                id: label
                anchors.top: icon.bottom
                anchors.topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: tile.text
                textFormat: Text.PlainText
                color: "#ffffff"
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.45)
                font.pixelSize: home.metrics.font(13)
                font.weight: Font.DemiBold
            }
            // A pair with one app gone says which (board TabletPairs.dc.html, "An app gone").
            Text {
                id: missing
                visible: tile.missingApp !== ""
                anchors.top: label.bottom
                anchors.topMargin: 2
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                text: i18nc("@info %1 an app's name", "%1 is not installed", tile.missingApp)
                textFormat: Text.PlainText
                color: Qt.rgba(1, 1, 1, 0.78)
                style: Text.Raised
                styleColor: Qt.rgba(0, 0, 0, 0.45)
                font.pixelSize: home.metrics.font(12)
                font.weight: Font.DemiBold
            }
        }
    }
}
