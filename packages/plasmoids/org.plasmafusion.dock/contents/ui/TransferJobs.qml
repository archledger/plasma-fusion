/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import org.kde.notificationmanager as NotificationManager

import "../code/jobs.js" as Jobs

// The jobs of Plasma's notification server (a copy in Dolphin, a download) as progress per app:
// `progress` maps a desktop entry ("org.kde.dolphin") to {count, progress 0..1} (code/jobs.js). A
// separate object so that the offscreen test runs the same declarations. The job's pop-up closes
// after its timeout (setup: [Jobs] PermanentPopups false), so expired and dismissed jobs count
// until they stop.
Item {
    id: transfers

    property var progress: ({})

    NotificationManager.Notifications {
        id: jobs
        showNotifications: false
        showJobs: true
        showExpired: true
        showDismissed: true
        groupMode: NotificationManager.Notifications.GroupDisabled
        onDataChanged: Qt.callLater(transfers.recount)
    }
    Instantiator {
        id: reader
        model: jobs
        delegate: QtObject {
            required property var desktopEntry
            required property var percentage
            required property var jobState
        }
        onObjectAdded: Qt.callLater(transfers.recount)
        onObjectRemoved: Qt.callLater(transfers.recount)
    }

    function recount(): void {
        const list = [];
        for (let i = 0; i < reader.count; ++i) {
            const j = reader.objectAt(i);
            if (j) {
                list.push({ desktopEntry: j.desktopEntry, percentage: j.percentage, state: j.jobState });
            }
        }
        const next = Jobs.progressByApp(list);
        // Only on a change: the tiles re-read their entries whenever this map changes.
        if (JSON.stringify(next) !== JSON.stringify(progress)) {
            progress = next;
        }
    }
}
