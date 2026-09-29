// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

pragma Singleton

import QtQuick
import org.kde.notificationmanager as NotificationManager

// Notifications that arrive while the screen is locked, grouped by application.
//
// WatchedNotificationsModel registers this process as a watcher with Plasma's notification
// server (the same mechanism as Plasma Mobile's lock screen), so only notifications sent after
// locking are known. One instance serves every screen (the greeter shares one QML engine).
// Only the application, a count and the time are exposed; bodies and actions never are.
QtObject {
    id: store

    readonly property bool valid: watched.valid
    // [{ key, appName, iconName, count, latest (Date), summary }], newest group first.
    property var groups: []

    readonly property NotificationManager.WatchedNotificationsModel watched: NotificationManager.WatchedNotificationsModel { }

    function rebuild() {
        const byKey = {};
        const list = [];
        const rows = watched.rowCount();
        for (let i = 0; i < rows; ++i) {
            const idx = watched.index(i, 0);
            if (watched.data(idx, NotificationManager.Notifications.TransientRole) === true) {
                continue;
            }
            const appName = watched.data(idx, NotificationManager.Notifications.ApplicationNameRole) || "";
            const desktopEntry = watched.data(idx, NotificationManager.Notifications.DesktopEntryRole) || "";
            const key = desktopEntry || appName || "?";
            const created = watched.data(idx, NotificationManager.Notifications.UpdatedRole) || watched.data(idx, NotificationManager.Notifications.CreatedRole);
            const time = created ? new Date(created) : new Date();
            let group = byKey[key];
            if (!group) {
                group = {
                    key: key,
                    appName: appName,
                    // The server forwards the application's icon as the notification icon.
                    iconName: watched.data(idx, NotificationManager.Notifications.ApplicationIconNameRole)
                              || watched.data(idx, NotificationManager.Notifications.IconNameRole) || desktopEntry || "",
                    count: 0,
                    latest: time,
                    summary: ""
                };
                byKey[key] = group;
                list.push(group);
            }
            group.count += 1;
            if (time >= group.latest) {
                group.latest = time;
                group.summary = watched.data(idx, NotificationManager.Notifications.SummaryRole) || "";
            }
        }
        list.sort((a, b) => b.latest - a.latest);
        groups = list;
    }

    readonly property Timer rebuildTimer: Timer {
        interval: 50
        onTriggered: store.rebuild()
    }

    readonly property Connections modelConnections: Connections {
        target: store.watched
        function onRowsInserted() { store.rebuildTimer.restart(); }
        function onRowsRemoved() { store.rebuildTimer.restart(); }
        function onDataChanged() { store.rebuildTimer.restart(); }
        function onModelReset() { store.rebuildTimer.restart(); }
    }
}
