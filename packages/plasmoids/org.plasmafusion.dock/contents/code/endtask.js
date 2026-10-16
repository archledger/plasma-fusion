.pragma library
/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later

    End Task (the dock's menu): ends an app that does not answer, as Windows 11's taskbar does.
    The app's processes (every window's, TaskManager's AppPid) get SIGTERM, which a working app
    answers by quitting, and those still running after 3 s get SIGKILL, which no app can refuse.
    KWin's own "not responding" dialog sends SIGABRT first so a crash report is written; a chosen
    End Task is not a crash, so it does not. The session's own processes are never ended: their
    windows get no End Task (sessionApp), and the command leaves any process with one of their
    names alone (/proc/PID/comm, 15 characters), should a window of theirs come with another app
    id. A process that is gone, or a zombie (state Z) waiting to be reaped, counts as ended.
*/
var SESSION_PROCESSES = ["plasmashell", "kwin_wayland", "kwin_wayland_wr", "kwin_x11", "Xwayland", "ksmserver", "kded6",
                         "startplasma-way", "plasma_session", "systemd", "dbus-daemon", "dbus-broker"];
var SESSION_APPS = ["org.kde.plasmashell", "plasmashell", "org.kde.kwin", "kwin_wayland"];

// The app ids whose windows are the session's own (no End Task for them).
function sessionApp(appId) {
    return SESSION_APPS.indexOf(String(appId || "")) >= 0;
}

// The process ids to end: whole numbers above 1, each once.
function endTaskPids(pids) {
    var out = [];
    (pids || []).forEach(function (p) {
        var n = Number(p);
        if (Number.isInteger(n) && n > 1 && out.indexOf(n) < 0) {
            out.push(n);
        }
    });
    return out;
}

// The shell command (sh -c, the executable engine's) that ends them, or "" when there is none.
function endTaskCommand(pids) {
    var ok = endTaskPids(pids);
    if (ok.length === 0) {
        return "";
    }
    return "p=\"" + ok.join(" ") + "\"; s=; for i in $p; do case \"$(cat /proc/$i/comm 2>/dev/null)\" in "
        + SESSION_PROCESSES.join("|") + "|'') ;; *) s=\"$s $i\" ;; esac; done; [ -n \"$s\" ] || exit 0; "
        + "kill -TERM $s 2>/dev/null; n=0; while [ $n -lt 30 ]; do a=; for i in $s; do "
        + "[ -d /proc/$i ] && [ \"$(sed 's/.*) //' /proc/$i/stat 2>/dev/null | cut -c1)\" != Z ] && a=\"$a $i\"; done; "
        + "[ -n \"$a\" ] || exit 0; sleep 0.1; n=$((n + 1)); done; kill -KILL $a 2>/dev/null; exit 0";
}
