/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Templates as T

import org.kde.kirigami as Kirigami
import org.kde.pipewire as PipeWire
import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager

import "../code/previews.js" as Previews
import "../code/placement.js" as Placement

// Window previews above a hovered running app (the stock task manager's tooltips): one card per
// window with the app icon, the window title, a close button and a live thumbnail from KWin's
// screencast (ScreencastingRequest + PipeWireSourceItem, as the stock tooltips use), or the app
// icon while there is no frame (a minimized window). Clicking a card activates that window. The
// name pill's palette; the window takes pointer input but never focus. The PipeWire streams run
// only while the preview is shown (the dock unloads it otherwise).
PlasmaCore.Dialog {
    id: preview

    required property DockPalette pal
    required property var taskModel
    // The item whose top edge the preview sits on (horizontally centred on it), or on a dock on
    // the left or right the item beside which it sits (vertically centred on it).
    property Item anchorItem
    property string edge: "bottom"
    // The dock's screen (its containment's screenGeometry, global coordinates): the preview stays
    // 8 px inside it and its cards fit its width, beside a dock on the left or right the room
    // between the anchor and the screen's far edge (roomWidth, measured when it shows).
    property rect screenGeometry: Qt.rect(0, 0, 0, 0)
    property real roomWidth: 0
    // The task's row in taskModel; a group's windows are its children.
    property int row: -1
    property string appName
    // The pointer is over the preview (the dock keeps it open meanwhile).
    readonly property bool hovered: hover.hovered
    // Bumped when the model changes, so the window list is read again.
    property int revision: 0

    // A card was used (the dock hides the preview).
    signal done()

    type: PlasmaCore.Dialog.Tooltip
    flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
    // Plasma's Dialog places itself again (popupPosition) when it is shown or resized: above
    // its visual parent for Floating, beside it, centred on it, for a left or right edge.
    location: edge === "left" ? PlasmaCore.Types.LeftEdge : edge === "right" ? PlasmaCore.Types.RightEdge : PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    visualParent: anchorItem

    function reposition(): void {
        if (!anchorItem || !anchorItem.Window.window) {
            return;
        }
        const p = anchorItem.mapToGlobal(0, 0);
        const g = screenGeometry;
        const at = Placement.popupPosition({ x: p.x, y: p.y, width: anchorItem.width, height: anchorItem.height },
                                           { width: width, height: height }, edge,
                                           { x: g.x, y: g.y, width: g.width, height: g.height });
        x = at.x;
        y = at.y;
    }
    function measureRoom(): void {
        const g = screenGeometry;
        if (!anchorItem || !anchorItem.Window.window || !(g.width > 0)) {
            roomWidth = 0;
            return;
        }
        const p = anchorItem.mapToGlobal(0, 0);
        roomWidth = Placement.room({ x: p.x, y: p.y, width: anchorItem.width, height: anchorItem.height }, edge,
                                   { x: g.x, y: g.y, width: g.width, height: g.height });
    }
    onWidthChanged: if (visible) Qt.callLater(reposition)
    onVisibleChanged: if (visible) {
        measureRoom();
        Qt.callLater(reposition);
    }
    onAnchorItemChanged: measureRoom()
    onEdgeChanged: measureRoom()

    // [{child, title, winId, active, minimized}] of all the task's windows (the cards show at most
    // six, shownWindows(); all are read so that the active one is found wherever it is).
    readonly property var windows: {
        void revision;
        const atm = TaskManager.AbstractTasksModel;
        if (!taskModel || row < 0 || row >= taskModel.rowCount()) {
            return [];
        }
        const out = [];
        const read = (index, child) => {
            const ids = taskModel.data(index, atm.WinIdList) || [];
            out.push({
                child: child,
                title: String(taskModel.data(index, Qt.DisplayRole) || preview.appName),
                winId: ids.length > 0 ? String(ids[0]) : "",
                active: taskModel.data(index, atm.IsActive) === true,
                minimized: taskModel.data(index, atm.IsMinimized) === true,
            });
        };
        const parent = taskModel.makeModelIndex(row);
        if (taskModel.data(parent, atm.IsGroupParent) === true) {
            for (let j = 0; j < taskModel.rowCount(parent); ++j) {
                read(taskModel.makeModelIndex(row, j), j);
            }
        } else if (taskModel.data(parent, atm.IsWindow) === true) {
            read(parent, -1);
        }
        return out;
    }
    // The app's icon as the dock tile draws it (the task's DecorationRole).
    readonly property var appIcon: {
        void revision;
        return taskModel && row >= 0 && row < taskModel.rowCount() ? taskModel.data(taskModel.makeModelIndex(row), Qt.DecorationRole) : "";
    }
    // The first `count` windows, the active one among them (in the last place when it would be
    // left out).
    function shownWindows(count: int): var {
        const list = windows.slice(0, count);
        const active = windows.findIndex(w => w.active);
        if (active >= count && count > 0) {
            list[count - 1] = windows[active];
        }
        return list;
    }
    // Testing: the card items, in window order.
    function cards(): list<Item> {
        const out = [];
        for (let i = 0; i < cardRepeater.count; ++i) {
            out.push(cardRepeater.itemAt(i));
        }
        return out;
    }
    // The cards' rows, kept in step with shownWindows() (contents/code/previews.js): a window that
    // stays keeps its card and screencast stream when its title or the active window changes.
    readonly property ListModel cardModel: ListModel {}
    readonly property var wantedCards: shownWindows(frame.shown)
    onWantedCardsChanged: Previews.syncCards(cardModel, wantedCards)
    Component.onCompleted: Previews.syncCards(cardModel, wantedCards)

    function indexFor(child: int): var {
        return child < 0 ? taskModel.makeModelIndex(row) : taskModel.makeModelIndex(row, child);
    }

    // A Dialog's children become its main item: the watcher is a property.
    readonly property Connections modelWatch: Connections {
        target: preview.taskModel
        enabled: preview.visible
        function onDataChanged(): void { preview.revision++; }
        function onRowsInserted(): void { preview.revision++; }
        function onRowsRemoved(): void { preview.revision++; }
        function onRowsMoved(): void { preview.revision++; }
        function onModelReset(): void { preview.revision++; }
        function onLayoutChanged(): void { preview.revision++; }
    }

    mainItem: Rectangle {
        id: frame

        FusionMetrics {
            id: m
        }
        readonly property real pad: m.px(8)
        // The cards fit the screen (less 8 px on each side; beside a dock on a side, the room
        // beside it): they shrink from 208 px thumbnails down to 140 px, and the windows that still
        // do not fit are left out (a grouped app with six windows on a 1280 px screen), keeping the
        // active one.
        readonly property real screenWidth: preview.screenGeometry.width > 0 ? preview.screenGeometry.width : 1280
        readonly property real cardInset: 2 * m.px(6)
        readonly property real room: (preview.roomWidth > 0 ? preview.roomWidth : screenWidth - 16) - 2 * pad - 2
        readonly property int shown: Math.max(1, Math.min(preview.windows.length, 6,
                                                          Math.floor((room + pad) / (m.px(140) + cardInset + pad))))
        readonly property real thumbW: Math.min(m.px(208), (room + pad) / shown - pad - cardInset)
        readonly property real thumbH: Math.round(thumbW * 130 / 208)

        implicitWidth: cards.implicitWidth + 2 * pad + 2
        implicitHeight: cards.implicitHeight + 2 * pad + 2
        width: implicitWidth
        height: implicitHeight
        radius: 14
        color: preview.pal.tipFill
        antialiasing: true

        HoverHandler {
            id: hover
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: preview.pal.tipBorder
            antialiasing: true
        }

        Row {
            id: cards
            x: frame.pad + 1
            y: frame.pad + 1
            spacing: frame.pad

            Repeater {
                id: cardRepeater
                model: preview.cardModel

                delegate: T.AbstractButton {
                    id: card
                    required property int child
                    required property string title
                    required property string winId
                    required property bool active
                    required property bool minimized
                    readonly property bool live: thumbnail.ready
                    readonly property Item closeTarget: closeButton

                    implicitWidth: frame.thumbW + frame.cardInset
                    implicitHeight: column.implicitHeight + 2 * m.px(6)
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    text: card.title
                    Accessible.role: Accessible.Button
                    Accessible.name: i18nc("@action:button %1 window title", "Switch to %1", card.title)
                    onClicked: {
                        preview.taskModel.requestActivate(preview.indexFor(card.child));
                        preview.done();
                    }

                    background: Rectangle {
                        radius: 10
                        color: card.down ? Qt.rgba(1, 1, 1, 0.14) : card.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.width: card.active ? 1 : 0
                        border.color: preview.pal.activeRing
                    }

                    contentItem: ColumnLayout {
                        id: column
                        spacing: m.px(6)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: m.px(6)
                            Kirigami.Icon {
                                Layout.preferredWidth: m.px(16)
                                Layout.preferredHeight: m.px(16)
                                source: preview.appIcon
                            }
                            Text {
                                Layout.fillWidth: true
                                text: card.title
                                elide: Text.ElideRight
                                color: preview.pal.tipText
                                font.family: m.family
                                font.pixelSize: m.font(12)
                                font.weight: Font.Bold
                                renderType: Text.QtRendering
                            }
                            T.AbstractButton {
                                id: closeButton
                                Layout.preferredWidth: m.px(20)
                                Layout.preferredHeight: m.px(20)
                                hoverEnabled: true
                                focusPolicy: Qt.NoFocus
                                text: i18nc("@action:button close a window", "Close")
                                Accessible.name: i18nc("@action:button %1 window title", "Close %1", card.title)
                                onClicked: preview.taskModel.requestClose(preview.indexFor(card.child))
                                background: Rectangle {
                                    radius: width / 2
                                    color: closeButton.hovered ? Qt.rgba(1, 1, 1, 0.16) : "transparent"
                                }
                                contentItem: Item {
                                    Glyph {
                                        anchors.centerIn: parent
                                        size: m.px(14)
                                        path: "M7 7l10 10M17 7L7 17"
                                        color: preview.pal.tipText
                                    }
                                }
                            }
                        }
                        Item {
                            Layout.preferredWidth: frame.thumbW
                            Layout.preferredHeight: frame.thumbH
                            clip: true

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: m.px(48)
                                height: m.px(48)
                                visible: !thumbnail.ready
                                source: preview.appIcon
                            }
                            TaskManager.ScreencastingRequest {
                                id: cast
                                uuid: card.minimized ? "" : card.winId
                            }
                            // Stays visible: the item streams only while visible (and draws
                            // nothing before the first frame, so the icon below shows).
                            PipeWire.PipeWireSourceItem {
                                id: thumbnail
                                anchors.fill: parent
                                nodeId: cast.nodeId
                            }
                        }
                    }
                }
            }
        }
    }
}
