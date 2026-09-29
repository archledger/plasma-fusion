// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.workspace.dbus as DBus

// Notification history and Do Not Disturb. The stock Notifications applet must
// stay loaded (for example hidden in the system tray): it owns the pop-ups and the
// Do Not Disturb bookkeeping; this list shares its history and read state.
Item {
    id: notif

    readonly property var model: history
    readonly property int count: history.count
    readonly property int unread: history.unreadNotificationsCount
    readonly property bool serverValid: NotificationManager.Server.valid

    // ---- Do Not Disturb
    readonly property var inhibitedUntil: settings.notificationsInhibitedUntil
    readonly property bool inhibitedByApp: settings.notificationsInhibitedByApplication
    readonly property bool dndActive: NotificationManager.Server.inhibited
    readonly property string dndUntilText: {
        if (!dndActive) {
            return "";
        }
        const until = inhibitedUntil;
        if (until && !isNaN(until.getTime())) {
            const ms = until.getTime() - Date.now();
            if (ms > 0 && ms < 24 * 3600 * 1000) {
                return Qt.formatTime(until, Qt.locale().timeFormat(Locale.ShortFormat));
            }
        }
        return "";
    }

    function toggleDnd() {
        const before = dndActive;
        DBus.SessionBus.asyncCall({
            service: "org.kde.kglobalaccel",
            path: "/component/plasmashell",
            iface: "org.kde.kglobalaccel.Component",
            member: "invokeShortcut",
            arguments: [new DBus.string("toggle do not disturb")],
            signature: "(s)"
        });
        dndFallback.expected = !before;
        dndFallback.restart();
    }

    // Used when no Notifications applet is loaded to react to the shortcut.
    Timer {
        id: dndFallback
        property bool expected: false
        interval: 600
        onTriggered: {
            if (NotificationManager.Server.inhibited === expected) {
                return;
            }
            if (expected) {
                const d = new Date();
                d.setFullYear(d.getFullYear() + 1);
                settings.notificationsInhibitedUntil = d;
            } else {
                settings.notificationsInhibitedUntil = undefined;
                settings.revokeApplicationInhibitions();
            }
            settings.save();
            NotificationManager.Server.inhibited = expected;
        }
    }

    // ---- History
    function indexFor(row) {
        return history.index(row, 0);
    }
    function invokeAction(row: int, actionName: string, resident: bool) {
        const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
        if (actionName === "default") {
            history.invokeDefaultAction(indexFor(row), behavior);
        } else {
            history.invokeAction(indexFor(row), actionName, behavior);
        }
    }
    function close(row: int) {
        history.close(indexFor(row));
    }
    function configure(row: int) {
        history.configure(indexFor(row));
    }
    function killJob(row: int) {
        history.killJob(indexFor(row));
    }
    function markRead() {
        history.lastRead = undefined; // resets to "now"
    }
    function clearAll() {
        history.clear(NotificationManager.Notifications.ClearExpired);
        // Also remove notifications that are still shown or were kept by Do Not Disturb,
        // except running jobs and notifications that must stay (resident).
        for (let row = history.count - 1; row >= 0; --row) {
            const idx = history.index(row, 0);
            const type = history.data(idx, NotificationManager.Notifications.TypeRole);
            const closable = history.data(idx, NotificationManager.Notifications.ClosableRole);
            const resident = history.data(idx, NotificationManager.Notifications.ResidentRole);
            if (type === NotificationManager.Notifications.NotificationType && closable && !resident) {
                history.close(idx);
            }
        }
    }

    NotificationManager.Settings {
        id: settings
    }

    NotificationManager.Notifications {
        id: history
        showExpired: true
        showDismissed: true
        showJobs: settings.jobsInNotifications
        sortMode: NotificationManager.Notifications.SortByDate
        groupMode: NotificationManager.Notifications.GroupDisabled
        expandUnread: true
        ignoreBlacklistDuringInhibition: true
        blacklistedDesktopEntries: settings.historyBlacklistedApplications
        blacklistedNotifyRcNames: settings.historyBlacklistedServices
        urgencies: {
            let urgencies = NotificationManager.Notifications.CriticalUrgency
                          | NotificationManager.Notifications.NormalUrgency;
            if (settings.lowPriorityHistory) {
                urgencies |= NotificationManager.Notifications.LowUrgency;
            }
            return urgencies;
        }
    }
}
