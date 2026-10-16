// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

import "../../code/chips.js" as Chips

// Who is signed in to this computer from elsewhere: systemd-logind's sessions (any user) with
// Remote=yes, sshd's and Tailscale SSH's among them, not those closing (Chips.remoteLogins). Read
// again when logind adds or removes a session, and every minute while one is shown (logind does
// not announce a session's move to "closing").
Item {
    id: logins

    // [{ id, user, host, ssh, since (ms) }], oldest first.
    property var sessions: []
    readonly property bool inUse: sessions.length > 0

    property int serial: 0
    function str(value): string {
        return value === undefined || value === null ? "" : String(value);
    }

    function reload(): void {
        const run = ++serial;
        DBus.SystemBus.asyncCall({
            "service": "org.freedesktop.login1",
            "path": "/org/freedesktop/login1",
            "iface": "org.freedesktop.login1.Manager",
            "member": "ListSessions",
            "signature": "()"
        }, reply => {
            // a(susso): id, uid, user, seat, object path.
            const list = reply.value || [];
            const found = [];
            let left = list.length;
            if (left === 0) {
                logins.publish(run, found);
                return;
            }
            for (const s of list) {
                const path = logins.str(s[4]);
                DBus.SystemBus.asyncCall({
                    "service": "org.freedesktop.login1",
                    "path": path,
                    "iface": "org.freedesktop.DBus.Properties",
                    "member": "GetAll",
                    "arguments": [new DBus.string("org.freedesktop.login1.Session")],
                    "signature": "(s)"
                }, props => {
                    const p = props.value || {};
                    found.push({
                        id: logins.str(s[0]),
                        user: logins.str(p.Name || s[2]),
                        remote: p.Remote === true,
                        remoteHost: logins.str(p.RemoteHost),
                        service: logins.str(p.Service),
                        state: logins.str(p.State),
                        since: Number(p.Timestamp || 0)
                    });
                    if (--left === 0) {
                        logins.publish(run, found);
                    }
                }, () => {
                    if (--left === 0) {
                        logins.publish(run, found);
                    }
                });
            }
        }, reply => console.info("livechips: no systemd-logind (" + logins.str(reply.error && reply.error.message) + ")"));
    }
    function publish(run: int, found: var): void {
        if (run !== serial) {
            return;
        }
        const next = Chips.remoteLogins(found);
        if (JSON.stringify(next) !== JSON.stringify(sessions)) {
            sessions = next;
            console.info("livechips: remote logins " + JSON.stringify(next));
        }
    }

    DBus.SignalWatcher {
        busType: DBus.BusType.System
        service: "org.freedesktop.login1"
        path: "/org/freedesktop/login1"
        iface: "org.freedesktop.login1.Manager"
        function dbusSessionNew(id, path) { logins.reload(); }
        function dbusSessionRemoved(id, path) { logins.reload(); }
    }
    Timer {
        interval: 60000
        repeat: true
        running: logins.inUse
        onTriggered: logins.reload()
    }
    Component.onCompleted: reload()
}
