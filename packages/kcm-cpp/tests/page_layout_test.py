#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Test tooling (not installed): where the page's content column stands, rendered offscreen
(offscreen_preview.py --report) in System Settings' widths. In a window wider than the column
(560 px) the column stands in the middle of the page, as System Settings' own pages centre their
form (Kirigami.FormLayout), on a whole pixel; in a narrow one it takes the whole width.

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


def report(width):
    with tempfile.TemporaryDirectory(prefix="pfkm-layout-") as tmp:
        out = subprocess.run([sys.executable, os.path.join(HERE, "offscreen_preview.py"), os.path.join(tmp, "page.png"), "dark",
                              "--width", str(width), "--height", "700", "--report"],
                             capture_output=True, text=True, timeout=120)
    for line in out.stdout.splitlines():
        if line.startswith("REPORT "):
            return json.loads(line[len("REPORT "):])
    raise SystemExit("no report at %d px (rc %d):\n%s%s" % (width, out.returncode, out.stdout, out.stderr))


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
    print("page_layout_test: %s" % ("all passed" if not failed else "%d failed" % failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
