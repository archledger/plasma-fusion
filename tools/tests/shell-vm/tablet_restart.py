#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Tablet posture across a plasmashell restart (run inside a live Plasma Fusion session).

  tablet_restart.py [ROUNDS] [--back auto|off] [--clear-cache]

Each round: tablet posture on (kwinrc [Input] TabletMode=on, with --notify), plasmashell restarted
in it, then back to the laptop (TabletMode auto, or off), after a wait that grows each round (0, 3,
10, 25 s, again from 0). After each step it checks, through a KWin script and desktop scripting:
  - the top bar and the dock are on screen (KWin's plasmashell dock windows: shown, not
    minimized, opaque, on the output) and have their posture's height (tablet: the panel script's
    44 and 80 px; laptop: what they had before the first round);
  - the desktop shows its posture's layer (the containment's log: home screen in tablet posture,
    Folder View on the laptop);
  - plasmashell logged no QML ReferenceError or TypeError from Plasma Fusion's packages.
--clear-cache also removes plasmashell's QML cache before each restart (as a deploy does), which
makes the start slower. TabletMode is set back to its value from before at the end.
Exit status 1 when a check fails.
"""

import json
import os
import sys
import tempfile
import time

import shellvm as s

KWIN_JS = r'''
var out = [];
var ws = workspace.stackingOrder;
for (var i = 0; i < ws.length; ++i) {
    var w = ws[i];
    if (String(w.resourceClass) !== "plasmashell" || !(w.dock || w.desktopWindow)) continue;
    var g = w.frameGeometry;
    out.push({dock: w.dock, x: g.x, y: g.y, w: g.width, h: g.height, hidden: w.hidden, minimized: w.minimized,
              opacity: w.opacity, output: w.output ? String(w.output.name) : ""});
}
console.info("tablet_restart windows " + JSON.stringify(out));
'''


def kwin_windows():
    """plasmashell's dock and desktop windows as KWin sees them."""
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
        f.write(KWIN_JS)
        path = f.name
    name = "tablet_restart_%d" % time.time_ns()
    c = s.cursor()
    try:
        s.run("qdbus-qt6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.loadScript", path, name)
        s.run("qdbus-qt6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.start")
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            time.sleep(0.5)
            for line in s.journal_after(c).splitlines():
                if "tablet_restart windows " in line:
                    return json.loads(line.split("tablet_restart windows ", 1)[1])
        raise RuntimeError("the KWin script did not report")
    finally:
        s.run("qdbus-qt6", "org.kde.KWin", "/Scripting", "org.kde.kwin.Scripting.unloadScript", name, check=False)
        os.unlink(path)


def kwin_tablet():
    out = s.run("qdbus-qt6", "org.kde.KWin", "/org/kde/KWin", "org.freedesktop.DBus.Properties.Get",
                "org.kde.KWin.TabletModeManager", "tabletMode")
    return out.strip() == "true"


def set_mode(value, want_tablet):
    s.run("kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode", value)
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline and kwin_tablet() != want_tablet:
        time.sleep(0.5)
    return kwin_tablet() == want_tablet


def top_and_dock():
    """(top bar, dock) panels of the first screen from desktop scripting."""
    top = dock = None
    for p in s.panels():
        if p["screen"] != 0:
            continue
        if "org.plasmafusion.quicksettings" in p["widgets"] or "org.plasmafusion.clockpill" in p["widgets"]:
            top = p
        elif "org.plasmafusion.dock" in p["widgets"]:
            dock = p
    return top, dock


def check_state(label, tablet, heights, since):
    # the panel script and the posture handlers run within a few seconds
    time.sleep(6)
    top, dock = top_and_dock()
    if not s.check(top is not None and dock is not None, "%s: a top bar and a dock on screen 0" % label):
        return
    want_top, want_dock = heights
    s.check(top["height"] == want_top and dock["height"] == want_dock,
            "%s: the panels have the %s heights (top %d, dock %d; want %d, %d)"
            % (label, "tablet" if tablet else "laptop", top["height"], dock["height"], want_top, want_dock))
    windows = kwin_windows()
    docks = [w for w in windows if w["dock"]]
    shown = [w for w in docks if not w["hidden"] and not w["minimized"] and w["opacity"] > 0.5 and w["w"] > 0 and w["h"] > 0]
    tops = [w for w in shown if w["y"] <= 0 and w["w"] > w["h"]]
    bottoms = [w for w in shown if w["y"] > 0]
    s.check(len(tops) == 1 and len(bottoms) >= 1,
            "%s: KWin shows the top bar and the dock (%s)" % (label, ", ".join(
                "%d,%d %dx%d%s%s op %.2f" % (w["x"], w["y"], w["w"], w["h"], " hidden" if w["hidden"] else "",
                                             " minimized" if w["minimized"] else "", w["opacity"]) for w in docks)))
    desktops = [w for w in windows if not w["dock"]]
    s.check(len(desktops) >= 1 and all(not w["hidden"] for w in desktops), "%s: the desktop window is shown" % label)
    log = s.journal_after(since)
    # The Folder View layer is unloaded in tablet posture (never loaded when the shell starts in it).
    lines = [line.split("desktop: ", 1)[1] for line in log.splitlines() if "desktop: folder view" in line]
    if tablet:
        ok = not lines or lines[-1].startswith("folder view unloaded")
    else:
        ok = bool(lines) and lines[-1].startswith("folder view loaded")
    s.check(ok, "%s: the desktop shows its %s layer (%s)" % (label, "home screen" if tablet else "Folder View",
                                                              lines[-1] if lines else "no change logged"))
    errors = [line for line in log.splitlines() if ("ReferenceError" in line or "TypeError" in line) and "plasmafusion" in line]
    s.check(not errors, "%s: no QML ReferenceError or TypeError from Plasma Fusion (%s)"
            % (label, "; ".join(sorted(set(e.split(": ", 1)[-1][:160] for e in errors))) or "none"))


def restart_shell(clear_cache):
    if clear_cache:
        cache = os.path.expanduser("~/.cache/plasmashell")
        s.run("rm", "-rf", cache)
    s.run("systemctl", "--user", "restart", "plasma-plasmashell.service", timeout=180)
    time.sleep(2)
    s.wait_shell()


def main(argv):
    args = list(argv[1:])
    back = "auto"
    if "--back" in args:
        i = args.index("--back")
        back = args[i + 1]
        del args[i:i + 2]
    clear_cache = "--clear-cache" in args
    if clear_cache:
        args.remove("--clear-cache")
    rounds = int(args[0]) if args else 4
    s.session_env()
    before = s.run("kreadconfig6", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode", "--default", "auto")
    if kwin_tablet():
        set_mode("off", False)
        time.sleep(5)
    top, dock = top_and_dock()
    laptop = (top["height"], dock["height"])
    s.note("laptop panels: top %d, dock %d" % laptop)
    waits = [0, 3, 10, 25]
    try:
        for r in range(rounds):
            wait = waits[r % len(waits)]
            label = "round %d" % (r + 1)
            c = s.cursor()
            s.check(set_mode("on", True), "%s: KWin is in tablet mode" % label)
            check_state(label + " tablet", True, (44, 80), c)
            c = s.cursor()
            s.note("%s: restarting plasmashell in tablet posture" % label)
            restart_shell(clear_cache)
            check_state(label + " tablet after the restart", True, (44, 80), c)
            time.sleep(wait)
            c = s.cursor()
            s.note("%s: back to the laptop (%s) %d s after the restart" % (label, back, wait))
            s.check(set_mode(back, False), "%s: KWin left tablet mode" % label)
            check_state(label + " laptop", False, laptop, c)
    finally:
        s.run("kwriteconfig6", "--notify", "--file", "kwinrc", "--group", "Input", "--key", "TabletMode", before or "auto")
    s.note("%d failed" % len(s.fails))
    return 1 if s.fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
