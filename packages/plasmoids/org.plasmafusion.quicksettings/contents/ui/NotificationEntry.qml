// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

import "components"
import "components/Icons.js" as Icons
import "../code/notifications.js" as Notes

// One row of the notification history, in the sheet (PopupContent.qml) and in the tablet
// Notification Centre: the history is grouped by app as in the stock applet (services/
// Notifications.qml, GroupApplicationsFlat), so a row is either an app's group header (its icon
// and name, Configure, Close Group) or a notification card (NotificationCard.qml). Under the last
// listed card of a group: "Show N More" while some are hidden, "Show Fewer" once it is expanded.
// The Centre draws a collapsed group's hidden notifications as card edges under it (`stackEdges`,
// the stack of TABLET2 S1). The row makes the history calls itself; `done()` asks the sheet to
// close (a default action ran, a file was opened).
ColumnLayout {
    id: row

    required property var model
    required property int index
    required property FusionPalette pal
    required property FusionMetrics metrics
    // Backend.notif.
    required property var notif
    property double now: Date.now()
    property color surface: pal.overlay(0.06)
    property color edge: pal.overlay(0.08)
    property bool stackEdges: false
    // The Centre's card menu (a long press, a right click, the Menu key on a card).
    property bool menus: false

    signal done()
    signal menuRequested(Item card, point at)

    readonly property var entry: model || ({})
    readonly property bool isGroup: !!entry?.isGroup
    readonly property Item card: cardLoader.item
    readonly property var footer: Notes.groupFooter(entry?.isInGroup, notif.lastInGroup(index, notif.revision),
                                                    entry?.groupChildrenCount || 0, entry?.expandedGroupChildrenCount || 0,
                                                    !!entry?.isGroupExpanded)
    // Keyboard focus is on one of this row's controls (the sheet scrolls it into view).
    readonly property bool focusInside: {
        for (let item = Window.activeFocusItem; item; item = item.parent) {
            if (item === row) {
                return true;
            }
        }
        return false;
    }

    spacing: metrics.px(8)

    // ---- An app's group header.
    RowLayout {
        objectName: "groupHeader"
        Layout.fillWidth: true
        Layout.leftMargin: row.metrics.px(6)
        Layout.preferredHeight: row.pal.touch ? 44 : row.metrics.px(26)
        visible: row.isGroup
        spacing: row.metrics.px(8)

        Kirigami.Icon {
            Layout.preferredWidth: row.metrics.px(20)
            Layout.preferredHeight: row.metrics.px(20)
            source: row.entry?.applicationIconName || "preferences-desktop-notification-bell"
        }
        FText {
            objectName: "groupName"
            Layout.fillWidth: true
            pal: row.pal
            metrics: row.metrics
            text: (row.entry?.applicationName || "") + (row.entry?.originName ? " · " + row.entry.originName : "")
            px: 12.5
            font.weight: Font.ExtraBold
            Accessible.role: Accessible.Heading
        }
        IconButton {
            objectName: "groupConfigure"
            visible: !!row.entry?.configurable
            pal: row.pal
            size: row.pal.touch ? 32 : 22
            iconSize: row.pal.touch ? 14 : 12
            fill: "transparent"
            iconPath: Icons.settingsSmall
            text: row.entry?.configureActionLabel || i18nc("@action:button notification settings of an app", "Configure")
            Accessible.description: row.entry?.applicationName || ""
            onClicked: {
                row.notif.configure(row.index);
                row.done();
            }
        }
        IconButton {
            objectName: "groupClose"
            visible: row.entry?.closable !== false
            pal: row.pal
            size: row.pal.touch ? 32 : 22
            iconSize: row.pal.touch ? 14 : 12
            fill: "transparent"
            iconPath: Icons.close
            text: i18nc("@action:button close all notifications of an app", "Close Group")
            Accessible.description: row.entry?.applicationName || ""
            onClicked: row.notif.close(row.index)
        }
    }

    // ---- A notification.
    Loader {
        id: cardLoader
        Layout.fillWidth: true
        Layout.preferredHeight: item ? item.implicitHeight : 0
        active: !row.isGroup
        visible: active
        z: 1
        sourceComponent: NotificationCard {
            pal: row.pal
            metrics: row.metrics
            model: row.model
            index: row.index
            now: row.now
            surface: row.surface
            edge: row.edge
            Accessible.name: String(row.entry?.summary || row.entry?.applicationName || "")
            onActionInvoked: name => {
                row.notif.invokeAction(row.index, name, !!row.entry?.resident);
                if (name === "default") {
                    row.done();
                }
            }
            onReplied: text => row.notif.reply(row.index, text, !!row.entry?.resident)
            onUrlOpened: url => {
                row.notif.openUrl(row.index, url);
                row.done();
            }
            onFolderRequested: (url, highlight) => {
                row.notif.openFolder(row.index, url, highlight);
                row.done();
            }
            onCloseClicked: row.notif.close(row.index)
            onConfigureClicked: {
                row.notif.configure(row.index);
                row.done();
            }
            onKillJobClicked: row.notif.killJob(row.index)
            onSuspendJobClicked: row.notif.suspendJob(row.index)
            onResumeJobClicked: row.notif.resumeJob(row.index)
            onMenuRequested: at => {
                if (row.menus) {
                    row.menuRequested(row.card, at);
                }
            }
            TapHandler {
                enabled: row.menus
                acceptedDevices: PointerDevice.TouchScreen | PointerDevice.Stylus | PointerDevice.Mouse
                onLongPressed: row.menuRequested(row.card, point.position)
            }
        }
    }

    // A collapsed group's hidden notifications: two card edges under the last listed card.
    Item {
        objectName: "stackEdges"
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        Layout.topMargin: -row.spacing - 12
        visible: row.stackEdges && row.footer.shown && row.footer.more > 0
        Repeater {
            model: 2
            delegate: Rectangle {
                required property int index
                x: 12 * (index + 1)
                width: row.width - 24 * (index + 1)
                y: 1 + 7 * index
                height: 24
                radius: 14
                color: row.surface
                opacity: 0.8 - 0.25 * index
                border.width: 1
                border.color: row.edge
                z: -1 - index
            }
        }
    }

    TextButton {
        objectName: "groupFooter"
        Layout.alignment: Qt.AlignHCenter
        visible: row.footer.shown
        pal: row.pal
        metrics: row.metrics
        implicitHeight: row.pal.touch ? 44 : row.metrics.px(28)
        radius: height / 2
        fontSize: 12.5
        text: row.footer.more > 0 ? i18nc("Expand to show n more notifications", "Show %1 More", row.footer.more)
                                  : i18nc("@action:button collapse an app's notifications", "Show Fewer")
        onClicked: row.notif.setGroupExpanded(row.index, !row.entry?.isGroupExpanded)
    }
}
