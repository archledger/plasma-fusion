/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Templates as T
import org.kde.kitemmodels as KItemModels
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
// order); the A-Z pages show "+" on apps not on page 1. Each change can be undone for 5 s. "Done"
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
    readonly property int firstRows: Math.max(1, Math.floor((gridTop + gridHeight - firstTop) / cellHeight))

    readonly property var favoritesModel: rootModel.favoritesModel
    readonly property var allModel: {
        const model = rootModel.count > 0 ? rootModel.modelForRow(0) : null;
        return model && model.description === "KICKER_ALL_MODEL" ? model : null;
    }
    readonly property int allCount: allModel ? allModel.count : 0
    readonly property int pageCount: 1 + Math.ceil(allCount / Math.max(1, perPage))
    readonly property alias currentPage: pages.currentIndex
    property real dragDown: 0

    // ---- Edit mode
    property bool editing: false
    property int dragFrom: -1
    property int dropTo: -1
    property point ghostPos: Qt.point(0, 0)
    property var ghostSource
    property string ghostName: ""
    // {kind: "remove", id, index} | {kind: "add", id} | {kind: "move", from, to}
    property var undoAction: null
    function startEditing(): void {
        editing = true;
        home.forceActiveFocus();
    }
    function stopEditing(): void {
        editing = false;
        dragFrom = -1;
        dropTo = -1;
        undoAction = null;
    }
    // (the model's `favorites` list reads empty from QML: the tile passes its favoriteId)
    function removeAt(row: int, id: string): void {
        if (id !== "") {
            favoritesModel.removeFavorite(id);
            remember({ "kind": "remove", "id": id, "index": row });
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
        } else if (a.kind === "add") {
            favoritesModel.removeFavorite(a.id);
        } else if (a.kind === "move") {
            favoritesModel.moveRow(a.to, a.from);
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
        model: home.pageCount
        Accessible.role: Accessible.PageTabList
        Accessible.name: i18nc("@label", "Home screen pages")

        delegate: Item {
            id: pageItem
            required property int index
            readonly property bool first: index === 0
            readonly property int pageColumns: first ? home.firstColumns : home.columns
            readonly property int start: first ? 0 : (index - 1) * home.perPage
            readonly property int count: first ? home.firstColumns * home.firstRows : home.perPage
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
                    sourceModel: pageItem.first ? home.favoritesModel : home.allModel
                    filterRowCallback: (row, parent) => row >= pageItem.start && row < pageItem.start + pageItem.count
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
        y: home.height - home.dockReserve - home.dotsHeight + 14
        spacing: 10
        visible: home.pageCount > 1
        Repeater {
            model: home.pageCount
            // AbstractButtons (not TapHandlers): they take the press, so the page's empty-space tap
            // (which ends edit mode) does not fire with them.
            delegate: T.AbstractButton {
                id: dotCell
                required property int index
                width: dot.width
                height: 8
                padding: 0
                Accessible.role: Accessible.PageTab
                Accessible.name: i18nc("@action:button %1 page number", "Page %1", dotCell.index + 1)
                onClicked: pages.currentIndex = dotCell.index
                // a 44 px target around the 8 px dot
                containmentMask: QtObject {
                    function contains(point: point): bool {
                        return point.x >= -18 && point.x < dotCell.width + 18 && point.y >= -18 && point.y < dotCell.height + 18;
                    }
                }
                contentItem: Item {}
                background: Rectangle {
                    id: dot
                    width: dotCell.index === pages.currentIndex ? 20 : 8
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, dotCell.index === pages.currentIndex ? 0.9 : 0.4)
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
        y: dots.y + 4 - 28
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

        readonly property var source: pageView.index === 0 ? home.favoritesModel : home.allModel
        readonly property bool pinnedPage: pageView.index === 0
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
                    home.move(home.dragFrom, home.dropTo);
                    home.dragFrom = -1;
                    home.dropTo = -1;
                }
            }
            onCentroidChanged: {
                if (!active) {
                    return;
                }
                const p = tile.mapToItem(home, centroid.position.x, centroid.position.y);
                home.ghostPos = p;
                const g = tile.mapToItem(tile.pageView, centroid.position.x, centroid.position.y);
                home.dropTo = tile.pageView.indexAt(g.x, g.y);
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
                 : home.editing && tile.pinnedPage ? (home.dropTo === tile.index && home.dragFrom !== tile.index ? 0.84 : 0.92) : 1
            opacity: home.dragFrom === tile.sourceRow && tile.pinnedPage ? 0.3 : 1
            Behavior on scale {
                enabled: home.motion.animate
                NumberAnimation {
                    duration: home.motion.press
                    easing.type: home.motion.standardEasing
                }
            }
            RectangularShadow {
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
