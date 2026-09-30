// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Copied unchanged from the perf-measure study (perf-measure/scripts/winmon.js).
// KWin script for perf runs: log every window that is added or removed, with the epoch time in ms,
// to KWin's stderr (category kwin_scripting / js, enabled with QT_LOGGING_RULES in the session).
function tag(w) {
    return [w.resourceClass, w.resourceName, w.caption, w.popupWindow ? "popup" : "",
            w.dialog ? "dialog" : "", w.specialWindow ? "special" : "", w.internalId].join("|");
}
// print() may not reach stderr; also send the line as the argument of a harmless bus call that
// the scenario's dbus-monitor records.
function log(s) {
    print(s);
    callDBus("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", s);
}
workspace.windowAdded.connect(function (w) {
    log("PFPERF added " + Date.now() + " " + tag(w));
});
workspace.windowRemoved.connect(function (w) {
    log("PFPERF removed " + Date.now() + " " + tag(w));
});
log("PFPERF winmon loaded " + Date.now());
