#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Helpers for the scenarios in this directory, which run inside a live Plasma Fusion session
(the test VM, or a device) as the session's user, over ssh or a terminal. Test tool only.

The session's bus and Wayland socket are taken from plasmashell's environment, so the scenarios
also work from an ssh login. They drive the shell through desktop scripting
(org.kde.PlasmaShell.evaluateScript), the widgets' debugAction and openRequest keys and
kscreen-doctor, and read the widgets' log lines from the user journal.
"""

import json
import os
from pathlib import Path
import re
import subprocess
import time

QS = "org.plasmafusion.quicksettings"
fails = []


def note(msg):
    print(time.strftime("%H:%M:%S", time.gmtime()) + "Z " + msg, flush=True)


def check(ok, what):
    note(("PASS " if ok else "FAIL ") + what)
    if not ok:
        fails.append(what)
    return ok


def run(*args, timeout=60, check=True):
    r = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{args!r} rc={r.returncode}: {r.stdout.strip()} {r.stderr.strip()}")
    return (r.stdout + r.stderr).strip()


def session_env():
    """The live session's D-Bus and Wayland variables, from plasmashell (or KWin) environment."""
    for name in ("plasmashell", "kwin_wayland"):
        pids = run("pgrep", "-u", str(os.getuid()), "-x", name, check=False).split()
        if pids:
            break
    else:
        raise RuntimeError("no Plasma session of this user")
    for entry in Path(f"/proc/{pids[0]}/environ").read_bytes().split(b"\0"):
        key, sep, value = entry.partition(b"=")
        if sep and key.decode() in {"DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"}:
            os.environ[key.decode()] = value.decode()


def js(script, timeout=60):
    return run("qdbus-qt6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script,
               timeout=timeout)


def wait_shell(timeout=240):
    """Waits until plasmashell answers desktop scripting with its panels."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            session_env()
            if int(js("print(panels().length)", timeout=20) or 0) > 0:
                return
        except (RuntimeError, ValueError, subprocess.TimeoutExpired):
            pass
        time.sleep(3)
    raise RuntimeError("plasmashell did not answer")


def cursor():
    return run("journalctl", "--user", "-n", "0", "--show-cursor", "--no-pager").split("-- cursor: ", 1)[1].strip()


def journal_after(c):
    return run("journalctl", "--user", "--after-cursor", c, "-o", "cat", "--no-pager", timeout=90)


def panels():
    """[{id, location, screen, height, hiding, widgets: [type]}] of every panel."""
    out = js('''var r = [];
panels().forEach(function (p) {
    r.push({id: p.id, location: p.location, screen: p.screen, height: p.height, hiding: p.hiding,
            widgets: p.widgets().map(function (w) { return w.type; })});
});
print(JSON.stringify(r));''')
    return json.loads(out)


def widget_js(wid, body):
    return js('panels().forEach(function (p) { p.widgets().forEach(function (w) { if (w.id === %d) {'
              ' w.currentConfigGroup = ["General"]; %s } }); });' % (wid, body))


def qs_widget():
    """The id of the quick settings widget in the first screen's top bar."""
    out = js('''var r = [];
panels().forEach(function (p) {
    if (p.location !== "top" || p.screen < 0) return;
    p.widgets("%s").forEach(function (w) { r.push([p.screen, w.id]); });
});
print(JSON.stringify(r));''' % QS)
    found = sorted(json.loads(out))
    if not found:
        raise RuntimeError("no quick settings widget in a top bar")
    return found[0][1]


def qs_dump(wid):
    """The quick settings dump (config key debugAction dump:TAG) as {part: text}: "summary",
    "bar", "sheet" and "frame"."""
    tag = str(time.time_ns())
    c = cursor()
    widget_js(wid, 'w.writeConfig("debugAction", "dump:%s");' % tag)
    deadline = time.monotonic() + 15
    parts = {}
    while time.monotonic() < deadline and len(parts) < 4:
        time.sleep(0.4)
        for line in journal_after(c).splitlines():
            m = re.search(r"quicksettings: dump %s(?: (\w+))?: (.*)$" % tag, line)
            if m:
                parts[m[1] or "summary"] = m[2]
    if "summary" not in parts:
        raise RuntimeError("no dump from quick settings widget %d" % wid)
    return parts


def ints(text):
    return [int(round(float(x))) for x in re.findall(r"-?\d+(?:\.\d+)?", text)]
