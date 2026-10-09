// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// An app's audio streams, matched as the stock task manager's PulseAudio.qml does: the portal app id
// first, then the process id (streams with a portal app id may carry a sandbox's pid), else the
// application name, but only for an app never matched by process id (so that of two instances only
// the playing one shows the indicator). Tests: tests/audio.test.js.
.pragma library

// streams: [{pid, appName, portalAppId}]; pidMatched(appName): whether the app was matched by process
// id before; pids: the task's process id, or all of a grouped task's (its windows can be several
// processes). Returns {streams, pidMatch}: pidMatch is the app name to remember as matched by process
// id ("" when none).
function match(streams, pidMatched, appId, pids, appName) {
    const own = (Array.isArray(pids) ? pids : [pids]).filter(p => p > 0);
    if (appId !== "") {
        const byApp = streams.filter(s => s.portalAppId === appId);
        if (byApp.length > 0) {
            return { streams: byApp, pidMatch: "" };
        }
    }
    if (own.length > 0) {
        const byPid = streams.filter(s => own.indexOf(s.pid) !== -1 && s.portalAppId === "");
        if (byPid.length > 0) {
            return { streams: byPid, pidMatch: appName };
        }
    }
    if (appName !== "" && !pidMatched(appName)) {
        return { streams: streams.filter(s => s.appName === appName), pidMatch: "" };
    }
    return { streams: [], pidMatch: "" };
}
