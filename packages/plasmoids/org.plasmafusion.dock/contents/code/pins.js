.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    Dock pin dedupe (pre-0.3.0): a preferred:// role pin resolves to whatever the system's
    preferred application is and can land on an app that is pinned explicitly too. On a machine
    without a browser, preferred://browser resolves to the text/plain handler for text/html
    (MIME subclass fallback) and the dock showed two identical tiles of it. One row per app:
    an explicit applications: pin wins over a preferred:// role pin in either order, and rows of
    the same kind keep the first. Rows without an app are left to the caller.

    isRolePin reads one entry of the task model's raw launcher list (preferred:// URLs are role
    pins); those entries carry an optional "[activities]\n" prefix that must be ignored.
*/
function isRolePin(entry) {
    const s = String(entry === undefined || entry === null ? "" : entry);
    const nl = s.indexOf("\n");
    return (nl >= 0 ? s.slice(nl + 1) : s).indexOf("preferred:") === 0;
}

function hiddenDuplicates(rows) {
    const keep = {};
    const hidden = [];
    for (let i = 0; i < rows.length; ++i) {
        const app = rows[i].app;
        if (!app) {
            continue;
        }
        const rolePin = rows[i].rolePin === true;
        const earlier = keep[app];
        if (earlier === undefined) {
            keep[app] = { index: i, rolePin: rolePin };
        } else if (rolePin && !earlier.rolePin) {
            hidden.push(i);
        } else if (!rolePin && earlier.rolePin) {
            hidden.push(earlier.index);
            keep[app] = { index: i, rolePin: rolePin };
        } else {
            hidden.push(i);
        }
    }
    return hidden.sort(function (a, b) { return a - b; });
}

// The dock launcher URL of an app given by its desktop id, with or without the applications:
// scheme (the launcher's pinned entries, and all of its entries on Plasma 6.8, have it):
// "org.kde.dolphin.desktop" and "applications:org.kde.dolphin.desktop" both give
// "applications:org.kde.dolphin.desktop".
function appLauncherUrl(id) {
    return "applications:" + String(id || "").replace(/^applications:/, "");
}
