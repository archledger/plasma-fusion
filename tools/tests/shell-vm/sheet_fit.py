#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Quick settings: the sheet's window fits its content (run inside a live Plasma Fusion session).

  sheet_fit.py [--restart] [--notifications N] [MODE...]

MODE is WIDTHxHEIGHT@SCALE (for example 1280x800@1 1920x1200@1.5) for the first output, set with
kscreen-doctor one after the other and put back at the end; without one the current mode is used.
--restart restarts plasmashell first: the sheet's content is built in the background after start,
before the window was ever shown, which is when the frame padding was missed (the content was drawn
14 px too low and right and its last 28 px were cut off). --notifications N sends N notifications
first, so the main page is taller than the screen allows and scrolls.

For the main page and each drill-down page (startPage) the sheet is opened through openRequest and
measured with the widget's dump (config key debugAction dump:TAG, its "frame" line), checking:
  - the content item sits at the frame's padding and fills the window less the padding;
  - the content asks for exactly that size (nothing cut off, nothing drawn outside);
  - the window is the card's outer width, no taller than the room below the top bar, and ends
    popupScreenMargin above the bottom of the available area or higher;
  - the page scrolls only when it is taller than that room.
Exit status 1 when a check fails.
"""

import json
import sys
import time

import shellvm as s

PAGES = ["main", "power", "audio", "wifi", "bluetooth"]


def set_mode(output, spec):
    size, _, scale = spec.partition("@")
    width, height = (int(v) for v in size.split("x"))
    data = json.loads(s.run("kscreen-doctor", "-j"))
    out = next(o for o in data["outputs"] if o["name"] == output)
    modes = [m for m in out["modes"] if m["size"]["width"] == width and m["size"]["height"] == height]
    if not modes:
        raise RuntimeError("output %s has no %s mode" % (output, size))
    mode = max(modes, key=lambda m: m["refreshRate"])
    s.run("kscreen-doctor", "output.%s.mode.%s" % (output, mode["id"]), "output.%s.scale.%s" % (output, scale or "1"))
    time.sleep(6)


def current_mode(output):
    data = json.loads(s.run("kscreen-doctor", "-j"))
    out = next(o for o in data["outputs"] if o["name"] == output)
    mode = next(m for m in out["modes"] if m["id"] == out["currentModeId"])
    return "%dx%d@%s" % (mode["size"]["width"], mode["size"]["height"], out["scale"])


def open_page(wid, output, page):
    s.widget_js(wid, 'w.writeConfig("openRequest", "close:%d:%s");' % (time.time_ns(), output))
    time.sleep(0.8)
    s.widget_js(wid, 'w.writeConfig("startPage", "%s");' % page)
    s.widget_js(wid, 'w.writeConfig("openRequest", "sheet:%d:%s");' % (time.time_ns(), output))
    time.sleep(2)


def measure(wid, label, margin):
    d = s.qs_dump(wid)
    summary, frame = d["summary"], d.get("frame", "")
    if "sheet closed" in summary or not frame or frame == "closed":
        s.check(False, "%s: the sheet is open (%s)" % (label, summary[:80]))
        return
    sx, sy, sw, sh = s.ints(summary.split(", sheet ", 1)[1].split(", max")[0])[:4]
    top = summary.split(", max ", 1)[1]
    max_h, outer = s.ints(top)[0], s.ints(top.split(", outer ", 1)[1])[0]
    win_w, win_h, pl, pt, pr, pb, ix, iy, iw, ih, ww, wh, page, ax, ay, aw, ah = s.ints(frame.split(" at ")[0])[:17]
    s.note("%s: %s" % (label, frame))
    s.check(abs(ix - pl) <= 1 and abs(iy - pt) <= 1,
            "%s: the content sits at the frame padding (item %d,%d, padding %d,%d)" % (label, ix, iy, pl, pt))
    s.check(abs(iw - (win_w - pl - pr)) <= 1 and abs(ih - (win_h - pt - pb)) <= 1,
            "%s: the content fills the window less its padding (item %dx%d, window %dx%d)" % (label, iw, ih, win_w, win_h))
    s.check(abs(ww - iw) <= 1 and abs(wh - ih) <= 1,
            "%s: the content asks for the size it gets (wanted %dx%d, item %dx%d)" % (label, ww, wh, iw, ih))
    s.check(abs(win_w - outer) <= 1, "%s: the window is the card's outer width (%d, outer %d)" % (label, win_w, outer))
    s.check(win_h <= max_h + 1 and sy + sh <= ay + ah - margin + 1,
            "%s: the window fits below the bar (height %d, room %d; bottom %d, area bottom %d - %d)"
            % (label, win_h, max_h, sy + sh, ay + ah, margin))
    if page > ih + 1:
        s.check(abs(win_h - max_h) <= 1, "%s: the page scrolls only when the screen is too small (page %d, window %d, room %d)"
                % (label, page, win_h, max_h))
    else:
        s.check(True, "%s: the whole page is shown (page %d in %d)" % (label, page, ih))


def main(argv):
    args = list(argv[1:])
    restart = "--restart" in args
    if restart:
        args.remove("--restart")
    notifications = 0
    if "--notifications" in args:
        i = args.index("--notifications")
        notifications = int(args[i + 1])
        del args[i:i + 2]
    s.session_env()
    output = json.loads(s.run("kscreen-doctor", "-j"))["outputs"][0]["name"]
    start_mode = current_mode(output)
    if restart:
        s.note("restarting plasmashell")
        s.run("systemctl", "--user", "restart", "plasma-plasmashell.service", timeout=120)
        time.sleep(5)
        s.wait_shell()
        # the sheet's content is built in the background 4 s after start
        time.sleep(8)
    s.session_env()
    wid = s.qs_widget()
    margin = int(s.widget_js(wid, 'print(String(w.readConfig("popupScreenMargin", 16)));') or 16)
    for i in range(notifications):
        # Plasma keeps a notification in the history when it names its application.
        s.run("notify-send", "-a", "Konsole", "-h", "string:desktop-entry:org.kde.konsole", "Sheet test %d" % (i + 1),
              "A notification that makes the main page taller.")
    if notifications:
        time.sleep(2)
    try:
        for spec in args or [start_mode]:
            if args:
                s.note("mode " + spec)
                set_mode(output, spec)
            for page in PAGES:
                open_page(wid, output, page)
                measure(wid, "%s %s" % (spec, page), margin)
    finally:
        s.widget_js(wid, 'w.writeConfig("startPage", "main");')
        s.widget_js(wid, 'w.writeConfig("openRequest", "close:%d:%s");' % (time.time_ns(), output))
        if args:
            set_mode(output, start_mode)
    s.note("%d failed" % len(s.fails))
    return 1 if s.fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
