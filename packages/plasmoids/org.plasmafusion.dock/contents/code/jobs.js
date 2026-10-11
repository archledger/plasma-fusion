// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// File-transfer progress on the dock's apps: the jobs of Plasma's notification server (a Dolphin
// copy, a download) by the app's desktop entry, as libnotificationmanager reports them to the stock
// task manager (JobsModelPrivate::updateApplicationPercentage: the mean of the percentages of the
// app's jobs that have not stopped). Tests: tests/jobs.test.js.
.pragma library

// The job states of NotificationManager.Notifications (JobStateStopped, JobStateRunning,
// JobStateSuspended).
const STOPPED = 0;

// jobs: [{desktopEntry, percentage, state}]. Returns {desktopEntry: {count, progress}}, progress
// 0..1 in whole percent, for every app with a job that has not stopped.
function progressByApp(jobs) {
    const sums = {};
    for (const job of jobs || []) {
        const key = String(job && job.desktopEntry || "").replace(/\.desktop$/, "");
        if (key === "" || job.state === STOPPED) {
            continue;
        }
        const percent = Math.max(0, Math.min(100, Math.round(Number(job.percentage) || 0)));
        const entry = sums[key] || (sums[key] = { count: 0, total: 0 });
        entry.count++;
        entry.total += percent;
    }
    const out = {};
    for (const key of Object.keys(sums)) {
        out[key] = { count: sums[key].count, progress: Math.floor(sums[key].total / sums[key].count) / 100 };
    }
    return out;
}

// The dock's per-app state ({count, countVisible, progress, progressVisible, urgent}, drawn by
// TaskItem) with the job progress added: an app's own progress (a Unity LauncherEntry) wins, the
// job progress fills in where it shows none. Neither input is changed.
function withJobs(entries, jobs) {
    const out = Object.assign({}, entries || {});
    for (const key of Object.keys(jobs || {})) {
        const own = out[key];
        if (own && own.progressVisible === true) {
            continue;
        }
        out[key] = Object.assign({ count: 0, countVisible: false, urgent: false }, own || {},
                                 { progress: jobs[key].progress, progressVisible: true });
    }
    return out;
}
