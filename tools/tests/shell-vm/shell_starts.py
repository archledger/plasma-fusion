#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Shell starts with a top bar whose screen is gone (run inside a live Plasma Fusion session).

  shell_starts.py [ROUNDS] [--keep]

A Plasma Fusion top bar of a monitor that was unplugged stays in plasmashell's layout: Plasma 6.8
keeps it on its last screen, Plasma 6.7 on screen -1. On Plasma 6.8, reading such a panel's height
or hiding from desktop scripting crashed plasmashell (SIGSEGV in KConfigGroup::readEntry from
WorkspaceScripting::Panel), and the tablet KWin script reads them at every shell start, so the
shell crashed until systemd gave up. This scenario makes sure such a bar exists (it adds one on
the first missing screen to plasma-org.kde.plasma.desktop-appletsrc while plasmashell is stopped,
and removes it at the end unless --keep), then restarts plasmashell ROUNDS times (default 6). Every
second round is in tablet posture (kwinrc [Input] TabletMode=on), so the panel script writes sizes
too. While the shell starts, the tablet script is also triggered every half second for 12 s
through its shortcut "Plasma Fusion: Tablet Window Mode" (it runs by itself when the shell's panel
windows appear). A whole session start (log out, automatic login) kills this script with the
session; repeat those from outside (loginctl terminate-user). Checks after each start:
  - plasmashell dumped no core and still runs, with the PID it started with (a SIGABRT core of the
    shell being stopped, from systemd's stop timeout, is only noted);
  - the tablet script's panel script ran ("plasmafusion-tablet: panels: ..." with a result), and
    reports the bar without a screen as skipped;
  - the bars on the screen have their posture's height (tablet: 44 px or more, laptop: less).
TabletMode is set back to its value from before at the end. Exit status 1 when a check fails.
"""

import json
import os
from pathlib import Path
import re
import sys
import time

import shellvm as s

APPLETSRC = Path(os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc"))
TOP = ("org.plasmafusion.quicksettings", "org.plasmafusion.clockpill")
MARK = "shell_starts.py"

# Only properties that never read a panel's view config: id, screen, location and the widgets;
# the sizes of the panels on a present screen.
SAFE_JS = r'''
var r = {screens: screenCount, panels: []};
panels().forEach(function (p) {
    var on = p.screen >= 0 && p.screen < screenCount;
    r.panels.push({id: p.id, screen: p.screen, location: p.location, on: on, height: on ? p.height : null,
                   widgets: p.widgets().map(function (w) { return w.type; })});
});
print(JSON.stringify(r));
'''


def layout():
    """The layout; a shell that crashes at its start (the bug) is started again for it."""
    for _ in range(5):
        try:
            s.session_env()
            s.wait_shell(timeout=120)
            return json.loads(s.js(SAFE_JS))
        except (RuntimeError, ValueError):
            s.run("systemctl", "--user", "reset-failed", "plasma-plasmashell.service", check=False)
            s.run("systemctl", "--user", "start", "plasma-plasmashell.service", check=False, timeout=180)
    raise RuntimeError("plasmashell did not answer for its layout")


def top_bars(state, on):
    return [p for p in state["panels"] if p["on"] == on and any(t in p["widgets"] for t in TOP)]


def groups(text):
    """[(header, body lines)] of a KConfig file."""
    out = []
    for line in text.splitlines():
        if line.startswith("["):
            out.append([line, []])
        elif out:
            out[-1][1].append(line)
        else:
            out.append(["", [line]])
    return out


def add_screenless_bar(screen):
    """Adds a top bar with a clock pill on `screen` to the layout file (plasmashell stopped)."""
    text = APPLETSRC.read_text()
    ids = [int(x) for x in re.findall(r"^\[Containments\]\[(\d+)\]", text, re.M)]
    ids += [int(x) for x in re.findall(r"\]\[Applets\]\[(\d+)\]", text)]
    cid = max(ids + [0]) + 1
    aid = cid + 1
    block = ("\n[Containments][%d]\nactivityId=\nformfactor=2\nimmutability=1\nlastScreen=%d\nlocation=3\n"
             "plugin=org.kde.panel\nwallpaperplugin=org.kde.image\n# %s\n\n"
             "[Containments][%d][Applets][%d]\nimmutability=1\nplugin=org.plasmafusion.clockpill\n"
             % (cid, screen, MARK, cid, aid))
    APPLETSRC.write_text(text.rstrip("\n") + "\n" + block)
    return cid


def remove_bar(cid):
    head = "[Containments][%d]" % cid
    kept = [g for g in groups(APPLETSRC.read_text()) if not (g[0] == head or g[0].startswith(head + "["))]
    APPLETSRC.write_text("\n".join("\n".join(([h] if h else []) + body) for h, body in kept).rstrip("\n") + "\n")


def shell_pid():
    pids = s.run("pgrep", "-u", str(os.getuid()), "-x", "plasmashell", check=False).split()
    return pids[0] if pids else ""


def cores_since(epoch):
    out = s.run("coredumpctl", "list", "--no-pager", "--no-legend", "--since=@%d" % epoch, "/usr/bin/plasmashell",
                check=False)
    return [line for line in out.splitlines() if "plasmashell" in line]


def trigger_tablet_script(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            s.session_env()
            s.run("qdbus-qt6", "org.kde.kglobalaccel", "/component/kwin", "org.kde.kglobalaccel.Component.invokeShortcut",
                  "Plasma Fusion: Tablet Window Mode", check=False, timeout=10)
        except RuntimeError:
            pass
        time.sleep(0.5)


def start():
    s.run("systemctl", "--user", "reset-failed", "plasma-plasmashell.service", check=False)
    s.run("systemctl", "--user", "restart", "plasma-plasmashell.service", timeout=180)
    trigger_tablet_script(12)


def set_posture(tablet):
    s.session_env()
    s.run("kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode",
          "on" if tablet else "off")


def main(argv):
    args = list(argv[1:])
    keep = "--keep" in args
    args = [a for a in args if not a.startswith("--")]
    rounds = int(args[0]) if args else 6
    s.session_env()
    before = s.run("kreadconfig6", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode", "--default", "auto")
    state = layout()
    added = None
    if not top_bars(state, False):
        s.note("adding a top bar on missing screen %d" % state["screens"])
        s.run("systemctl", "--user", "stop", "plasma-plasmashell.service", timeout=180)
        added = add_screenless_bar(state["screens"])
        s.run("systemctl", "--user", "start", "plasma-plasmashell.service", timeout=180)
        state = layout()
    gone = top_bars(state, False)
    s.check(bool(gone), "a top bar without a screen is in the layout (%s; %d screen(s))"
            % (", ".join("panel %d on screen %d" % (p["id"], p["screen"]) for p in gone) or "none", state["screens"]))
    try:
        for r in range(rounds):
            tablet = r % 2 == 1
            label = "round %d (%s)" % (r + 1, "tablet" if tablet else "laptop")
            set_posture(tablet)
            time.sleep(2)
            c = s.cursor()
            epoch = int(time.time())
            old = shell_pid()
            s.note("%s: starting the shell" % label)
            start()
            pid = shell_pid()
            time.sleep(25)
            s.session_env()
            # The shell being stopped can leave a SIGABRT core: Fedora's systemd aborts a stop that
            # takes more than 40 s (docs/parts/testing.md). That is noted, not counted.
            cores = []
            for line in cores_since(epoch):
                fields = line.split()
                if len(fields) > 7 and fields[4] == old and fields[7] == "SIGABRT":
                    s.note("%s: the stopped shell %s was aborted by systemd's stop timeout" % (label, old))
                else:
                    cores.append(line)
            s.check(not cores and pid and shell_pid() == pid,
                    "%s: plasmashell did not crash (pid %s -> %s; cores: %s)"
                    % (label, pid or "none", shell_pid() or "none", "; ".join(cores) or "none"))
            lines = [line.split("plasmafusion-tablet: panels: ", 1)[1] for line in s.journal_after(c).splitlines()
                     if "plasmafusion-tablet: panels: " in line]
            results = [line for line in lines if re.match(r"(top|dock) \d+|\d+ without a screen", line)]
            s.check(bool(results) and "without a screen skipped" in results[-1],
                    "%s: the panel script ran and skipped the bar without a screen (%s)"
                    % (label, " | ".join(lines[-4:]) or "no panel script log"))
            if not cores and shell_pid():
                heights = [p["height"] for p in top_bars(layout(), True)]
                ok = bool(heights) and all((h >= 44) == tablet for h in heights)
                s.check(ok, "%s: the top bars on the screen have the %s height (%s)"
                        % (label, "tablet" if tablet else "laptop", heights))
            else:
                s.run("systemctl", "--user", "reset-failed", "plasma-plasmashell.service", check=False)
                s.run("systemctl", "--user", "start", "plasma-plasmashell.service", check=False, timeout=180)
    finally:
        s.session_env()
        s.run("kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode", before or "auto")
        if added is not None and not keep:
            s.run("systemctl", "--user", "stop", "plasma-plasmashell.service", timeout=180, check=False)
            remove_bar(added)
            s.run("systemctl", "--user", "start", "plasma-plasmashell.service", timeout=180, check=False)
            s.note("removed the added top bar %d" % added)
    s.note("%d failed" % len(s.fails))
    return 1 if s.fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
