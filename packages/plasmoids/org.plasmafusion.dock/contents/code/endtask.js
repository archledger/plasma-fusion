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

// The processes still to end at the confirmation's click: those the app had when it was asked
// (ASKED) that its windows still have (NOW, from the task model again). A process that quit in
// between, and any other that got its number since, is not among the app's windows: left alone.
function stillOurs(asked, now) {
    var current = endTaskPids(now);
    return endTaskPids(asked).filter(function (p) {
        return current.indexOf(p) >= 0;
    });
}

// A process's identity: its start time (field 22 of /proc/PID/stat, the 20th after the ") " that
// ends its name), which a process that takes the same number later does not share.
var START_TIME = "st() { sed 's/.*) //' /proc/$1/stat 2>/dev/null | cut -d' ' -f20; }; "
    // The time since boot in hundredths of a second (/proc/uptime), for the wait of 3 s.
    + "cs() { cut -d' ' -f1 /proc/uptime | tr -d .; }; ";

// The shell command that prints the identity, "PID:START", of each of these processes that is
// there and not one of the session's own, a line each. The dock runs it when it asks, so the
// processes ended are the ones the user was asked about, not others that got their numbers since.
function identityCommand(pids) {
    var ok = endTaskPids(pids);
    if (ok.length === 0) {
        return "";
    }
    return START_TIME + "for i in " + ok.join(" ") + "; do case \"$(cat /proc/$i/comm 2>/dev/null)\" in "
        + SESSION_PROCESSES.join("|") + "|'') ;; *) t=$(st $i); [ -n \"$t\" ] && echo \"$i:$t\" ;; esac; done; exit 0";
}

// The identities in identityCommand()'s output (or given as a list): "PID:START" with a PID above 1,
// each PID once.
function identities(text) {
    var out = [], seen = [];
    (Array.isArray(text) ? text : String(text || "").split("\n")).forEach(function (line) {
        var m = /^([0-9]+):([0-9]+)$/.exec(String(line).trim());
        if (m && Number(m[1]) > 1 && seen.indexOf(m[1]) < 0) {
            seen.push(m[1]);
            out.push(Number(m[1]) + ":" + m[2]);
        }
    });
    return out;
}

// Of IDENTITIES, those whose process is among PIDS.
function boundTo(ids, pids) {
    var keep = endTaskPids(pids);
    return identities(ids).filter(function (e) {
        return keep.indexOf(Number(e.split(":")[0])) >= 0;
    });
}

// The shell command (sh -c, the executable engine's) that ends the processes with these
// identities, or "" when there is none. Those still running are looked for at least once, also
// when the wait is over before the first look (a machine paused that long). A process gets
// SIGTERM, and SIGKILL after the wait, only
// while its start time is still the one taken when the user was asked, and never one with a
// session process's name, so a number that went to another process since is left alone. (Between
// that check and the signal itself a few shell steps remain; only a pidfd would close them, which
// the executable engine has no helper for.)
function endTaskCommand(ids) {
    var ok = identities(ids);
    if (ok.length === 0) {
        return "";
    }
    return START_TIME + "s=; for e in " + ok.join(" ") + "; do i=${e%:*}; case \"$(cat /proc/$i/comm 2>/dev/null)\" in "
        + SESSION_PROCESSES.join("|") + "|'') ;; *) [ \"$(st $i)\" = \"${e#*:}\" ] && s=\"$s $e\" ;; esac; done; "
        + "[ -n \"$s\" ] || exit 0; for e in $s; do kill -TERM ${e%:*} 2>/dev/null; done; d=$(($(cs) + 300)); "
        + "while :; do a=; for e in $s; do i=${e%:*}; "
        + "[ \"$(st $i)\" = \"${e#*:}\" ] && [ \"$(sed 's/.*) //' /proc/$i/stat 2>/dev/null | cut -c1)\" != Z ] && a=\"$a $e\"; done; "
        + "[ -n \"$a\" ] || exit 0; [ $(cs) -lt $d ] || break; sleep 0.1; done; "
        + "for e in $a; do i=${e%:*}; [ \"$(st $i)\" = \"${e#*:}\" ] && kill -KILL $i 2>/dev/null; done; exit 0";
}
