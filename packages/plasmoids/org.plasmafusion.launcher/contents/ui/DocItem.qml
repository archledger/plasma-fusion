/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel

import "../code/launcher.js" as Launcher

// Recent file row: 52 px, radius 12, 34 px coloured type tile, name (13 px, 700) and
// "Folder · 12 min ago" (11.5 px, muted). The row height (from the grid), the text and the
// paddings next to it follow the user's text size; the type tile keeps its size.
Item {
    id: row

    required property int index
    required property var model

    readonly property NavGrid grid: GridView.view as NavGrid
    readonly property bool keyboardCurrent: GridView.isCurrentItem && grid !== null && grid.activeFocus
    // Pointer hover counts only once the pointer moved (see NavGrid.pointerMovedTo).
    readonly property bool hovered: mouse.containsMouse && grid !== null && grid.pointerActive
    readonly property string url: String(model.url || model.favoriteId || "")
    readonly property bool isLocal: url.indexOf("file:///") === 0
    readonly property string fileName: {
        const clean = url.replace(/\/+$/, "");
        const last = clean.slice(clean.lastIndexOf("/") + 1);
        try {
            return decodeURIComponent(last);
        } catch (e) {
            return last; // malformed escape in the URL
        }
    }
    readonly property string folderName: {
        const d = String(model.description || "");
        const parts = d.split("/").filter(p => p.length > 0);
        return parts.length > 0 ? parts[parts.length - 1] : "";
    }
    readonly property var kind: Launcher.fileKind(fileName || model.display, url)
    property date lastUsed: new Date(0)
    // Delegates are reused for other files: forget the previous file's time.
    onUrlChanged: lastUsed = new Date(0)
    readonly property string age: lastUsed.getTime() > 0 && grid && grid.launcher ? grid.launcher.formatAge(lastUsed) : ""
    function px(v: real): real {
        return grid && grid.metrics ? grid.metrics.px(v) : v;
    }

    width: grid ? grid.cellWidth - grid.gap : 313
    height: grid ? grid.itemHeight : 52

    Accessible.role: Accessible.Button
    Accessible.name: model.display || fileName
    Accessible.description: subtitle.text

    Rectangle {
        anchors.fill: parent
        radius: 12
        antialiasing: true
        color: (row.hovered || row.keyboardCurrent) && row.grid ? row.grid.pal.rowHover : "transparent"

        FocusRing {
            anchors.margins: 0
            radius: 12
            visible: row.keyboardCurrent && row.grid.keyboardNavigation
            ringColor: row.grid ? row.grid.pal.focusRing : "transparent"
        }
    }

    Rectangle {
        id: typeTile
        x: row.px(10)
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34
        radius: 9
        antialiasing: true
        color: row.kind.color

        Glyph {
            anchors.centerIn: parent
            name: row.kind.glyph
            size: 18
            color: "#ffffff"
        }
    }

    Column {
        anchors.left: typeTile.right
        anchors.leftMargin: row.px(12)
        anchors.right: parent.right
        anchors.rightMargin: row.px(10)
        anchors.verticalCenter: parent.verticalCenter
        spacing: row.px(2)

        FusionText {
            width: parent.width
            text: row.model.display || row.fileName
            elide: Text.ElideMiddle
            color: row.grid ? row.grid.pal.text : "white"
            metrics: row.grid ? row.grid.metrics : null
            px: 13
            weight: 700
        }

        FusionText {
            id: subtitle
            width: parent.width
            elide: Text.ElideRight
            visible: text.length > 0
            text: [row.folderName, row.age].filter(s => s.length > 0).join(" · ")
            color: row.grid ? row.grid.pal.muted : "gray"
            metrics: row.grid ? row.grid.metrics : null
            px: 11.5
        }
    }

    // Age of the file: its modification time. The activity manager's own "last used" times are
    // not exposed to QML, and access times change whenever an indexer or thumbnailer reads the
    // file, so they are not used. Read only while the launcher is open.
    Instantiator {
        active: row.isLocal && row.fileName.length > 0 && row.grid !== null && row.grid.launcher && row.grid.launcher.menuOpen
        model: 1
        delegate: FolderListModel {
            folder: row.url.slice(0, row.url.lastIndexOf("/") + 1)
            nameFilters: [row.fileName.replace(/[\[\]*?]/g, "?")]
            showDirs: false
            showDotAndDotDot: false
            showHidden: true
            sortField: FolderListModel.Unsorted
            onStatusChanged: {
                if (status !== FolderListModel.Ready) {
                    return;
                }
                for (let i = 0; i < count; ++i) {
                    if (get(i, "fileName") === row.fileName) {
                        const modified = get(i, "fileModified");
                        if (modified && modified.getTime() > 0) {
                            row.lastUsed = modified;
                        }
                        return;
                    }
                }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPositionChanged: mouseEvent => {
            if (row.grid && row.grid.pointerMovedTo(mouse, mouseEvent.x, mouseEvent.y)) {
                row.grid.keyboardNavigation = false;
                row.grid.currentIndex = row.index;
            }
        }
        onClicked: mouseEvent => {
            if (!row.grid) {
                return;
            }
            if (mouseEvent.button === Qt.RightButton) {
                row.grid.currentIndex = row.index;
                row.grid.openMenu(row.index, row, mouseEvent.x, mouseEvent.y);
            } else {
                row.grid.launch(row.index);
            }
        }
    }
}
