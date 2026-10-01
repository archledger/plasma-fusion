/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Templates as T
import org.kde.plasma.private.kicker as Kicker

import "../code/launcher.js" as Launcher

// Keyboard-navigable grid used for app tiles and recent files. The view is one gap wider than
// the content box so that every cell (item + gap) has the same size and the last column ends flush.
GridView {
    id: grid

    property FusionColors pal
    property FusionMetrics metrics
    property var launcher
    property bool designLabels: false
    property int columns: 6
    property int gap: 4
    property bool keyboardNavigation: false
    // Only the first `limit` items can be reached with the keyboard (0: all). The home view's
    // "Recommended" grid shows four files of a longer list.
    property int limit: 0
    readonly property int navCount: limit > 0 ? Math.min(count, limit) : count

    // Hover selects only after the pointer really moved: items that appear or scroll under a
    // resting pointer must not take the selection (Enter would launch them).
    property bool pointerActive: false
    property point lastPointer: Qt.point(NaN, NaN)

    signal exitTop()
    signal exitBottom()
    // Printable text typed while the grid has focus; "\b" for Backspace.
    signal typed(string text)

    property int itemHeight: 84
    // The pinned grid: a tile dropped on it moves there (GAPS C7).
    property bool reorderable: false

    // Drags a tile's desktop file (BACKLOG M3). The extra application/x-xbel type makes KIO treat
    // the drop as a bookmark, which it links without the Move/Copy/Link menu (KIO DropJob): onto
    // the desktop the app becomes a link (a symlink to the system desktop file, so it starts
    // without a trust prompt). The helper's drag is modal; the launcher closes when the pointer
    // leaves its card (LauncherCard's drop area) and when the drag ends outside it.
    Kicker.DragHelper {
        id: dragHelper
        dragIconSize: 48
        onDropped: {
            const launcher = grid.launcher;
            if (launcher) {
                launcher.dragEnded();
            }
        }
    }
    property int dragIndex: -1
    function startDrag(tile: AppTile) {
        // qmllint disable missing-property
        const entry = tile.model;
        const url = entry && entry.url ? entry.url : "";
        // qmllint enable missing-property
        if (!url || String(url) === "" || dragHelper.dragging) {
            return;
        }
        dragIndex = tile.index;
        if (launcher) {
            launcher.dragStarted();
        }
        console.info("launcher: drag " + url);
        dragHelper.startDrag(tile, url, Launcher.iconNameFor(entry) || "application-x-executable", "application/x-xbel",
                             "<?xml version=\"1.0\"?><xbel version=\"1.0\"></xbel>");
    }

    DropArea {
        anchors.fill: parent
        enabled: grid.reorderable
        keys: ["text/uri-list"]
        onEntered: {
            if (grid.launcher) {
                grid.launcher.dragInsideCard();
            }
        }
        onExited: {
            if (grid.launcher) {
                grid.launcher.dragLeftCard();
            }
        }
        onDropped: drop => {
            const from = grid.dragIndex;
            // (the drop area lies in the view's content item: content coordinates)
            const to = grid.indexAt(drop.x, drop.y);
            if (from >= 0 && to >= 0 && from !== to && grid.launcher) {
                console.info("launcher: pin " + from + " moved to " + to);
                grid.launcher.favoritesModel.moveRow(from, to);
                drop.accept(Qt.MoveAction);
            } else {
                drop.accept(Qt.IgnoreAction);
            }
            grid.dragIndex = -1;
        }
    }

    // Fractional on purpose: the board's columns are (width - gaps) / columns wide.
    cellWidth: width / columns
    cellHeight: itemHeight + gap
    currentIndex: -1
    clip: true
    reuseItems: true
    boundsBehavior: Flickable.StopAtBounds
    keyNavigationEnabled: true
    highlightFollowsCurrentItem: false
    activeFocusOnTab: true
    pixelAligned: true

    Accessible.role: Accessible.List

    T.ScrollBar.vertical: ThinScrollBar {
        pal: grid.pal
        visible: grid.interactive && size < 1.0
    }

    function labelFor(entry): string {
        if (designLabels && entry && entry.favoriteId) {
            const label = Launcher.designLabels[Launcher.appId(entry.favoriteId)];
            if (label) {
                return label;
            }
        }
        return entry && entry.display ? entry.display : "";
    }

    function launch(index: int) {
        if (!model || index < 0 || index >= count) {
            return;
        }
        if (model.trigger(index, "", null) && launcher) {
            launcher.close();
        }
    }

    function openMenu(index: int, item: Item, x: real, y: real) {
        if (launcher && item) {
            launcher.openActionMenu(model, index, item.model, item, x, y);
        }
    }

    function focusFirst() {
        if (navCount > 0) {
            if (currentIndex < 0 || currentIndex >= navCount) {
                currentIndex = 0;
            }
            keyboardNavigation = true;
            pointerActive = false;
            forceActiveFocus(Qt.TabFocusReason);
            positionViewAtIndex(currentIndex, GridView.Contain);
            return true;
        }
        return false;
    }

    function resetPointer() {
        pointerActive = false;
        lastPointer = Qt.point(NaN, NaN);
    }

    // Called by the delegates' hover handlers. True when the pointer moved to (x, y) of `item`
    // since the previous call, i.e. the hover comes from the user and may change the selection.
    function pointerMovedTo(item: Item, x: real, y: real): bool {
        const p = item.mapToItem(null, x, y);
        const moved = !isNaN(lastPointer.x) && (Math.abs(p.x - lastPointer.x) >= 1 || Math.abs(p.y - lastPointer.y) >= 1);
        lastPointer = Qt.point(p.x, p.y);
        if (moved) {
            pointerActive = true;
        }
        return moved;
    }

    onActiveFocusChanged: {
        if (activeFocus && (currentIndex < 0 || currentIndex >= navCount) && navCount > 0) {
            currentIndex = 0;
        }
    }

    // There is no highlight item to follow, so keep the keyboard selection in view.
    onCurrentIndexChanged: {
        if (keyboardNavigation && currentIndex >= 0) {
            positionViewAtIndex(currentIndex, GridView.Contain);
        }
    }

    Keys.onPressed: event => {
        const row = Math.floor(currentIndex / columns);
        const lastRow = Math.floor((navCount - 1) / columns);
        switch (event.key) {
        case Qt.Key_Up:
            keyboardNavigation = true;
            pointerActive = false;
            if (row <= 0) {
                exitTop();
                event.accepted = true;
            }
            break;
        case Qt.Key_Down:
            keyboardNavigation = true;
            pointerActive = false;
            if (row >= lastRow) {
                exitBottom();
                event.accepted = true;
            } else if (currentIndex + columns >= navCount) {
                currentIndex = navCount - 1;
                event.accepted = true;
            }
            break;
        case Qt.Key_Right:
        case Qt.Key_End:
        case Qt.Key_PageDown:
            keyboardNavigation = true;
            pointerActive = false;
            if (limit > 0) {
                // Keep the selection inside the visible part.
                currentIndex = event.key === Qt.Key_Right ? Math.min(navCount - 1, currentIndex + 1) : navCount - 1;
                event.accepted = true;
            }
            break;
        case Qt.Key_Left:
        case Qt.Key_Home:
        case Qt.Key_PageUp:
            keyboardNavigation = true;
            pointerActive = false;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            launch(currentIndex);
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            if (currentItem) {
                openMenu(currentIndex, currentItem, currentItem.width / 2, currentItem.height / 2);
            }
            event.accepted = true;
            break;
        case Qt.Key_Backspace:
            typed("\b");
            event.accepted = true;
            break;
        default:
            // Escape and other keys without printable text go on to the card.
            if (Launcher.isPrintable(event.text) && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                typed(event.text);
                event.accepted = true;
            }
            break;
        }
    }
}
