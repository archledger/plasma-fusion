// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.clock
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
    // The clock the "Until" text is read at: moved on by the minute clock below (Date.now() in a
    // binding is read once, so the text stayed as it was when Do Not Disturb was turned on).
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

    // Do Not Disturb until a time (G18: the "for a while" choices), as the stock applet's own
    // choices set it: the notification settings keep the end, and the stock applet (Globals.qml,
    // loaded and hidden) inhibits the server until then and releases it on its first wall-clock
    // minute past the end, also right after a resume. This widget never ends it itself, so the end
    // has one owner. An end that has passed (choices read long ago) is refused: written, it would
    // leave nothing to end and the server as it is.
    function dndUntil(until): bool {
        if (!Dnd.valid(until) || until.getTime() <= Date.now()) {
            return false;
        }
        settings.notificationsInhibitedUntil = until;
        settings.save();
        return true;
    }
    // The "Until" text changes on a whole minute (a day before the end, a week before...): Plasma's
    // clock ticks on the wall clock's minutes, also right after a resume or a clock change, where
    // a Timer would go on counting the time the machine was awake. It is the timer the stock
    // applet's minute check runs on, shared in the shell, and it is not listened to while nothing
    // is ahead ("until turned off").
    Loader {
        active: notif.dndActive && notif.dndLabel.refreshAt > 0
        sourceComponent: Clock {
            onDateTimeChanged: notif.dndNow = Date.now()
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
    // Grouped by app as in the stock applet's history (GroupApplicationsFlat, two notifications of
    // a group listed until it is expanded; unread ones always): each group is a header row followed
    // by its notifications. `revision` moves on with every change of the rows, for lastInGroup().
    property int revision: 0
    Connections {
        target: history
        function onRowsInserted() {
            ++notif.revision;
        }
        function onRowsRemoved() {
            ++notif.revision;
        }
        function onRowsMoved() {
            ++notif.revision;
        }
        function onModelReset() {
            ++notif.revision;
        }
        function onLayoutChanged() {
            ++notif.revision;
        }
    }
    function indexFor(row) {
        return history.index(row, 0);
    }
    // Whether `row` is the last listed notification of its group (the "Show N more" button goes
    // under it). Bind with `revision` so it is read again when rows come and go.
    function lastInGroup(row: int, revision: int): bool {
        if (row < 0 || row >= history.count || !history.data(indexFor(row), NotificationManager.Notifications.IsInGroupRole)) {
            return false;
        }
        return row + 1 >= history.count || !history.data(indexFor(row + 1), NotificationManager.Notifications.IsInGroupRole);
    }
    function setGroupExpanded(row: int, expanded: bool) {
        history.setData(indexFor(row), expanded, NotificationManager.Notifications.IsGroupExpandedRole);
    }
    function collapseAllGroups() {
        history.collapseAllGroups();
    }
    function invokeAction(row: int, actionName: string, resident: bool) {
        const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
        if (actionName === "default") {
            history.invokeDefaultAction(indexFor(row), behavior);
        } else {
            history.invokeAction(indexFor(row), actionName, behavior);
        }
    }
    // Inline reply (the stock applet's NotificationReplyField): a non-resident notification closes.
    function reply(row: int, text: string, resident: bool) {
        const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
        history.reply(indexFor(row), text, behavior);
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
    function suspendJob(row: int) {
        history.suspendJob(indexFor(row));
    }
    function resumeJob(row: int) {
        history.resumeJob(indexFor(row));
    }
    // Shows a file in the file manager, selected (KIO's highlightInFileManager, the stock applet's
    // "Open Containing Folder" for one file).
    function showInFolder(url: string) {
        DBus.SessionBus.asyncCall({
            service: "org.freedesktop.FileManager1",
            path: "/org/freedesktop/FileManager1",
            iface: "org.freedesktop.FileManager1",
            member: "ShowItems",
            arguments: [[url], new DBus.string("")],
            signature: "(ass)"
        });
    }
    function markRead() {
        history.lastRead = undefined; // resets to "now"
    }
    function clearAll() {
        history.clear(NotificationManager.Notifications.ClearExpired);
        // Also remove notifications that are still shown or were kept by Do Not Disturb, except
        // running jobs and notifications that must stay (resident). Groups are opened first so
        // their hidden notifications are rows too (from the end: opening one adds rows after it).
        for (let row = history.count - 1; row >= 0; --row) {
            const idx = history.index(row, 0);
            if (history.data(idx, NotificationManager.Notifications.IsGroupRole)) {
                history.setData(idx, true, NotificationManager.Notifications.IsGroupExpandedRole);
            }
        }
        for (let row = history.count - 1; row >= 0; --row) {
            const idx = history.index(row, 0);
            if (history.data(idx, NotificationManager.Notifications.IsGroupRole)) {
                continue;
            }
            const type = history.data(idx, NotificationManager.Notifications.TypeRole);
            const closable = history.data(idx, NotificationManager.Notifications.ClosableRole);
            const resident = history.data(idx, NotificationManager.Notifications.ResidentRole);
            if (type === NotificationManager.Notifications.NotificationType && closable && !resident) {
                history.close(idx);
            }
        }
        history.collapseAllGroups();
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
        groupMode: NotificationManager.Notifications.GroupApplicationsFlat
        groupLimit: 2
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
