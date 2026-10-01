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

// The home screen in tablet posture (TABLET2 H1, owner decision "iPad-style"): pages of apps in the
// desktop window, under the apps, in place of Folder View (whose rubber band was the owner's pen
// "selection box" on the home screen). Page 1 holds the pinned apps (the launcher's pins: one list,
// KActivities client org.plasmafusion.launcher.favorites), the next pages every app A to Z, as in
// the tablet launcher sheet. Grid 6 x 5 in landscape, 5 x 6 in portrait (TABLET2 decision 1); on
// page 1 the columns stop before the widget area (the containment's cards, `widgetRect`), which
// fades out on the other pages. 72 px icons in 120 px tall cells, labels white over the wallpaper,
// page dots, the dock's 128 px kept clear. A tap launches; a long press (or a right click, a pen's
// barrel button) opens the app's menu: add to or remove from page 1, its actions.
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

    ListView {
        id: pages
        objectName: "homePages"
        anchors.fill: parent
        orientation: ListView.Horizontal
        snapMode: ListView.SnapOneItem
        highlightRangeMode: ListView.StrictlyEnforceRange
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
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

    // Page dots: 8 x 8, the current one 20 x 8, 10 apart, above the dock; tappable (44 px rows).
    Row {
        id: dots
        anchors.horizontalCenter: parent.horizontalCenter
        y: home.height - home.dockReserve - home.dotsHeight + 14
        spacing: 10
        visible: home.pageCount > 1
        Repeater {
            model: home.pageCount
            delegate: Item {
                id: dotCell
                required property int index
                width: dot.width
                height: 8
                Rectangle {
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
                TapHandler {
                    margin: 18
                    gesturePolicy: TapHandler.ReleaseWithinBounds
                    onTapped: pages.currentIndex = dotCell.index
                }
                Accessible.role: Accessible.PageTab
                Accessible.name: i18nc("@action:button %1 page number", "Page %1", dotCell.index + 1)
            }
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
        onClicked: {
            if (source) {
                source.trigger(tile.sourceRow, "", null);
            }
        }
        onPressAndHold: actionMenu.openFor(source, tile.sourceRow, tile.model, tile, width / 2, height / 2)
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: (eventPoint, button) => actionMenu.openFor(tile.source, tile.sourceRow, tile.model, tile, eventPoint.position.x, eventPoint.position.y)
        }

        background: Item {}
        contentItem: Item {
            scale: tile.down ? 0.94 : 1
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
