// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.workspace.dbus as DBus

import "../../code/dnd.js" as Dnd

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
    // The clock the "Until" text is read at: moved on by dndClock when the text changes (Date.now()
    // in a binding is read once, so the text stayed as it was when Do Not Disturb was turned on).
    property double dndNow: Date.now()
    readonly property var dndLabel: Dnd.untilLabel(inhibitedUntil, dndNow)
    // The end as it reads: a time ("18:00", within 24 hours), a day and time ("Mon 06:00", within a
    // week), a date, or "" (no end, or "until turned off").
    readonly property string dndUntilText: {
        if (!dndActive) {
            return "";
        }
        const until = inhibitedUntil;
        const time = Qt.locale().timeFormat(Locale.ShortFormat);
        switch (dndLabel.kind) {
        case "time":
            return Qt.formatTime(until, time);
        case "day":
            return Qt.formatDateTime(until, "ddd " + time);
        case "date":
            return Qt.formatDate(until, Qt.locale().dateFormat(Locale.ShortFormat));
        default:
            return "";
        }
    }
    // Why it is on besides a time (stock wording): the apps that hold it, mirrored screens, a full
    // screen window; [] when none.
    readonly property var dndReasons: {
        if (!dndActive) {
            return [];
        }
        return Dnd.reasons({
            byApp: inhibitedByApp,
            names: settings.notificationInhibitionApplications,
            reasons: settings.notificationInhibitionReasons,
            whenMirrored: settings.inhibitNotificationsWhenScreensMirrored,
            mirrored: settings.screensMirrored,
            whenFullscreen: settings.inhibitNotificationsWhenFullscreen,
            fullscreen: settings.fullscreenFocused
        }).map(entry => {
            switch (entry.kind) {
            case "app":
                return entry.reason !== ""
                    ? i18nc("Do not disturb until app has finished (reason)", "While %1 is active (%2)", entry.name, entry.reason)
                    : i18nc("Do not disturb until app has finished", "While %1 is active", entry.name);
            case "mirrored":
                return i18nc("Do not disturb because external mirrored screens connected", "Screens are mirrored");
            default:
                return i18nc("Do not disturb because fullscreen app is focused", "Fullscreen app is focused");
            }
        });
    }

    // Do Not Disturb until a time (G18: the "for a while" choices). The notification settings keep
    // the time; the server is inhibited at once and released when it passes.
    function dndUntil(until) {
        settings.notificationsInhibitedUntil = until;
        settings.save();
        NotificationManager.Server.inhibited = true;
        dndNow = Date.now();
    }
    // One shot at the next moment the "Until" text changes or the time runs out, instead of a check
    // every minute: the text is right on time and nothing wakes up for an "until turned off".
    Timer {
        id: dndClock
        running: notif.dndActive && notif.dndLabel.refreshAt > 0
        // Repeating, so that a new interval (set from the moved clock) starts it again. Timer
        // intervals are ints: at most a day, then it looks again.
        repeat: true
        interval: Math.max(50, Math.min(24 * 3600 * 1000, notif.dndLabel.refreshAt - notif.dndNow + 50))
        onTriggered: {
            notif.dndNow = Date.now();
            const until = notif.inhibitedUntil;
            if (until && !isNaN(until.getTime()) && until.getTime() <= notif.dndNow && !notif.inhibitedByApp) {
                settings.notificationsInhibitedUntil = undefined;
                settings.save();
                NotificationManager.Server.inhibited = false;
            }
        }
    }
    onDndActiveChanged: dndNow = Date.now()
    onInhibitedUntilChanged: dndNow = Date.now()

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
    // After a file of the notification was opened it has done its job (the stock applet expires it;
    // a resident one only counts as expired).
    function expire(row: int) {
        const idx = indexFor(row);
        if (history.data(idx, NotificationManager.Notifications.ResidentRole)) {
            history.setData(idx, true, NotificationManager.Notifications.ExpiredRole);
        } else {
            history.expire(idx);
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
