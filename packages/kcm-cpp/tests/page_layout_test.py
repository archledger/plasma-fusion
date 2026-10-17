#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): where the page's content column stands, rendered offscreen
(offscreen_preview.py --report) in System Settings' widths. In a window wider than the column
(560 px) the column stands in the middle of the page, as System Settings' own pages centre their
form (Kirigami.FormLayout), on a whole pixel; in a narrow one it takes the whole width.
Then the touchpad gestures group (offscreen_preview.py --gestures, board Gestures.dc.html): each
row shows the module's choice, a key in a drop-down sets the module's value, and the notes on
KWin's own gestures show on their rows while the module says KWin uses them, and a note under the
group while the snap script, which does the gestures, is off. And the dock's rows
(offscreen_preview.py --rows, --act; board DockSize.dc.html): Dock size and Group an app's windows
show the module's values and a click sets them, the magnified size reads +8 / +14 px; Dock position
(board DockPosition.dc.html) shows the module's edge with its note and a click sets it; Hide the top
bar automatically (board Island.dc.html) shows the module's value with its note and a click sets it.

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


def rows(*extra):
    r = preview(900, "REPORT_ROWS", "--rows", *extra)
    return {row["text"]: row for row in r["rows"]}, r["kcm"]


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
    check(r["snapOffNote"] is None, "  no note on the snap script while KWin loads it (%s)" % r["snapOffNote"])
    r = gestures("--state", "snapScriptOn=false")
    check(r["snapOffNote"] is not None and "do nothing" in r["snapOffNote"] and "KWin Scripts" in r["snapOffNote"],
          "  the snap script off: the group says the gestures do nothing and where it is turned on (%s)" % r["snapOffNote"])
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
    by, k = rows("--state", "dockSize=2", "groupWindows=false")
    size, group, magnified = by.get("Dock size"), by.get("Group an app's windows"), by.get("Magnified icon size")
    check(size is not None and size["labels"] == ["Small", "Medium", "Large"] and size["index"] == 2,
          "dock: Dock size shows the module's size, Large (%s)" % size)
    check(group is not None and group["checked"] is False and group["note"] == "Off: one icon for each window.",
          "  Group an app's windows shows off, with its note (%s)" % group)
    check(magnified is not None and magnified["labels"] == ["+8 px", "+14 px"] and magnified["index"] == 1,
          "  the magnified size as a step: +8 / +14 px, +14 chosen (62) (%s)" % magnified)
    by, k = rows("--act", "Dock size=0", "--act", "Group an app's windows")
    check(k["dockSize"] == 0 and k["groupWindows"] is False and by["Dock size"]["index"] == 0,
          "  a click on Small and on the switch sets the module's values (%s)" % k)
    by, k = rows("--act", "Magnified icon size=0")
    check(k["magnifiedSize"] == 56, "  +8 px is the Medium dock's 56 px (%s)" % k)
    by, k = rows("--state", "dockPosition=2")
    pos = by.get("Dock position")
    check(pos is not None and pos["labels"] == ["Bottom", "Left", "Right"] and pos["index"] == 2
          and pos["note"] == "In tablet mode the dock is at the bottom.",
          "  Dock position shows the module's edge, Right, with its note (%s)" % pos)
    by, k = rows("--act", "Dock position=1")
    check(k["dockPosition"] == 1 and by["Dock position"]["index"] == 1,
          "  a click on Left sets the module's value (%s)" % k)
    by, k = rows("--state", "topBarAutoHide=true")
    hide = by.get("Hide the top bar automatically")
    check(hide is not None and hide["checked"] is True and hide["note"].startswith("Move the pointer to the top of the screen"),
          "top bar: Hide the top bar automatically shows on, with its note (%s)" % hide)
    by, k = rows("--act", "Hide the top bar automatically")
    check(k["topBarAutoHide"] is True and by["Hide the top bar automatically"]["checked"] is True,
          "  a click turns it on (%s)" % k)
    print("page_layout_test: %s" % ("all passed" if not failed else "%d failed" % failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
