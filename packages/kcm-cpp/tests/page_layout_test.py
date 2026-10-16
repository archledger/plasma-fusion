#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): where the page's content column stands, rendered offscreen
(offscreen_preview.py --report) in System Settings' widths. In a window wider than the column
(560 px) the column stands in the middle of the page, as System Settings' own pages centre their
form (Kirigami.FormLayout), on a whole pixel; in a narrow one it takes the whole width.
Then the touchpad gestures group (offscreen_preview.py --gestures, board Gestures.dc.html): each
row shows the module's choice, a key in a drop-down sets the module's value, and the notes on
KWin's own gestures show on their rows while the module says KWin uses them.

    tests/page_layout_test.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

failed = 0


def check(ok, what):
    global failed
    failed += not ok
    print(("PASS " if ok else "FAIL ") + what)


def preview(width, prefix, *extra):
    with tempfile.TemporaryDirectory(prefix="pfkm-layout-") as tmp:
        out = subprocess.run([sys.executable, os.path.join(HERE, "offscreen_preview.py"), os.path.join(tmp, "page.png"), "dark",
                              "--width", str(width), "--height", "700", *extra],
                             capture_output=True, text=True, timeout=120)
    for line in out.stdout.splitlines():
        if line.startswith(prefix + " "):
            return json.loads(line[len(prefix) + 1:])
    raise SystemExit("no %s at %d px (rc %d):\n%s%s" % (prefix, width, out.returncode, out.stdout, out.stderr))


def report(width):
    return preview(width, "REPORT", "--report")


def gestures(*extra):
    return preview(900, "REPORT_GESTURES", "--gestures", *extra)


def notes(r):
    return [row["text"] for row in r["rows"] if row["note"]]


def main():
    # 1720: the content area of the owner's System Settings window; 900 and 640: smaller ones.
    for width in (1720, 900, 640):
        r = report(width)
        if r is None:
            check(False, "%d px: the page has its content column" % width)
            continue
        middle = r["x"] + r["width"] / 2
        check(r["width"] == 560 and abs(middle - r["parentWidth"] / 2) <= 0.5,
              "%d px: the 560 px column stands in the middle of the page (%s)" % (width, r))
        check(r["x"] == int(r["x"]), "%d px: on a whole pixel (x %s)" % (width, r["x"]))
    r = report(500)
    check(r is not None and r["x"] == 0 and r["width"] == r["parentWidth"],
          "500 px: the column takes the page's whole width (%s)" % r)

    r = gestures()
    check(r["choices"] == ["Overview", "Show desktop", "Nothing", "Nothing", "Launcher", "Show desktop"],
          "gestures: each row shows the module's choice (%s)" % r["choices"])
    check(notes(r) == [] and r["oneRow"] is True, "  no note while KWin uses none of them, the switch on (%s)" % r)
    r = gestures("--state", "gestureSidewaysShared=true")
    check(notes(r) == ["Swipe right with three fingers"] and "left and right" in r["rows"][3]["note"],
          "  KWin's three fingers sideways: the note under the left and right rows (%s)" % notes(r))
    r = gestures("--state", "gestureUpDownShared=true", "desktopsInOneRow=false")
    check(notes(r) == ["Swipe down with three fingers"] and "up and down" in r["rows"][1]["note"] and r["oneRow"] is False,
          "  KWin's three fingers up and down: the note under the up and down rows (%s)" % notes(r))
    r = gestures("--key-dropdown", "2", "Down")
    check(r["kcm"]["gestureSwipeLeft"] == 1 and r["choices"][2] == "Overview",
          "  Down in the left row's drop-down sets the module's value to the next choice (%s)" % r["kcm"])
    r = gestures("--key-dropdown", "4", "End")
    check(r["kcm"]["gesturePinchIn"] == 8 and r["choices"][4] == "Snap layouts",
          "  End in the pinch-in row's drop-down: the last choice, Snap layouts (%s)" % r["kcm"])
    print("page_layout_test: %s" % ("all passed" if not failed else "%d failed" % failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
