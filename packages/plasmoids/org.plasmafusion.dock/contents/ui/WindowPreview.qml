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
    // The item whose top edge the preview sits on (horizontally centred on it).
    property Item anchorItem
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
    location: PlasmaCore.Types.Floating
    backgroundHints: PlasmaCore.Dialog.NoBackground
    visualParent: anchorItem

    function reposition(): void {
        if (!anchorItem || !anchorItem.Window.window) {
            return;
        }
        const p = anchorItem.mapToGlobal(0, 0);
        const screen = anchorItem.Window.window.screen;
        let left = Math.round(p.x + (anchorItem.width - width) / 2);
        if (screen) {
            left = Math.max(screen.virtualX + 8, Math.min(left, screen.virtualX + screen.width - width - 8));
        }
        x = left;
        y = Math.round(p.y - height);
    }
    onWidthChanged: if (visible) Qt.callLater(reposition)
    onVisibleChanged: if (visible) Qt.callLater(reposition)

    // [{child, title, winId, active, minimized}] of the task's windows (at most 6).
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
            for (let j = 0; j < taskModel.rowCount(parent) && out.length < 6; ++j) {
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
    // Testing: the card items, in window order.
    function cards(): list<Item> {
        const out = [];
        for (let i = 0; i < cardRepeater.count; ++i) {
            out.push(cardRepeater.itemAt(i));
        }
        return out;
    }
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
    }

    mainItem: Rectangle {
        id: frame

        FusionMetrics {
            id: m
        }
        readonly property real pad: m.px(8)
        readonly property real thumbW: m.px(208)
        readonly property real thumbH: m.px(130)

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
                model: preview.windows

                delegate: T.AbstractButton {
                    id: card
                    required property var modelData
                    readonly property bool live: thumbnail.ready
                    readonly property Item closeTarget: closeButton

                    implicitWidth: frame.thumbW + 2 * m.px(6)
                    implicitHeight: column.implicitHeight + 2 * m.px(6)
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    text: modelData.title
                    Accessible.role: Accessible.Button
                    Accessible.name: i18nc("@action:button %1 window title", "Switch to %1", modelData.title)
                    onClicked: {
                        preview.taskModel.requestActivate(preview.indexFor(modelData.child));
                        preview.done();
                    }

                    background: Rectangle {
                        radius: 10
                        color: card.down ? Qt.rgba(1, 1, 1, 0.14) : card.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                        border.width: card.modelData.active ? 1 : 0
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
                                text: card.modelData.title
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
                                Accessible.name: i18nc("@action:button %1 window title", "Close %1", card.modelData.title)
                                onClicked: preview.taskModel.requestClose(preview.indexFor(card.modelData.child))
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
                                uuid: card.modelData.minimized ? "" : card.modelData.winId
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
