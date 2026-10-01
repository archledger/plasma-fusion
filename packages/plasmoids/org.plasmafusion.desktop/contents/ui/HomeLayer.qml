/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Templates as T
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker
import org.kde.plasma.workspace.dbus as DBus
import org.kde.kirigami as Kirigami

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
    Component.onCompleted: syncPages()
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
    // The dock splits the screen on a splitRequest "<left|right>:<nonce>:<app>.desktop".
    function requestSplit(side: string, appId: string): void {
        if (appId === "" || (side !== "left" && side !== "right")) {
            return;
        }
        console.info("home: split request: " + appId + " to the " + side);
        DBus.SessionBus.asyncCall({
            "service": "org.kde.plasmashell", "path": "/PlasmaShell", "iface": "org.kde.PlasmaShell",
            "member": "evaluateScript",
            "arguments": [new DBus.string("panels().forEach(function (p) { p.widgets(\"org.plasmafusion.dock\").forEach(function (w) {"
                + " w.currentConfigGroup = [\"General\"]; w.writeConfig(\"splitRequest\", \"" + side + ":\" + Date.now() + \":" + appId + "\"); }); });")],
            "signature": "(s)"
        }, () => {}, error => console.warn("home: split request failed: " + error));
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
            enabled: !home.editing
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
        visible: home.pageCount > 1
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
        text: tile.model.display || ""
        Accessible.role: Accessible.Button
        Accessible.name: text

        readonly property var source: pageView.pinned ? home.favoritesModel : home.allModel
        readonly property bool pinnedPage: pageView.pinned
        readonly property bool addable: home.editing && !pinnedPage && !!tile.model.favoriteId
                                        && !home.favoritesModel.isFavorite(String(tile.model.favoriteId))
        onClicked: {
            if (home.editing) {
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
                y: Math.round((parent.height - (72 + 10 + label.height)) / 2)
                size: 72
                source: tile.model.decoration || "application-x-executable"
                iconName: home.iconNameFor(tile.model)
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
                    if (tile.pinnedPage) {
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
        }
    }
}
