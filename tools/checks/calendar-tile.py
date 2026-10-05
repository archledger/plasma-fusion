#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Calendar tile date overlay contract (the AppIcon board's fixed SEP / 28 art).

  tools/checks/calendar-tile.py [--warn] [PATH...]      default PATH: packages/

The launcher's AppTile and the dock's TaskItem paint today's month and day over the calendar tile
art, which carries a fixed SEP / 28 (generators/icons/art_tiles.py, TILES['calendar']). The patch
exists only to hide that art, so it must track the art's names and colours exactly. A name that
draws another tile (an app's own design, as GNOME Calendar's) must not get the patch, and a name
that draws the dated art must get it (or the tile keeps a stale SEP 28).

Findings, one per line as FILE:LINE: RULE message | source:
  calendar-apps     the overlay's app-name list is not the set of icon names the icon theme draws
                    with the dated calendar art (generators/icons/names.py APPS['calendar'])
  calendar-colors   a covering rectangle or its label text does not use the tile art's own colour
                    (TILES['calendar']: c1 the month band, base the page, t2c and tc the labels),
                    so the patch shows as a seam on the band or the page
Exit status: 1 when anything is found, 0 otherwise; with --warn always 0 (tools/build.sh).
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "generators", "icons"))
import art_tiles  # noqa: E402  # pyright: ignore[reportMissingImports]
import names  # noqa: E402  # pyright: ignore[reportMissingImports]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qmlscan  # noqa: E402

# The names whose Fusion tile art carries the baked labels; the overlay list must equal this.
EXPECTED_APPS = set(names.APPS["calendar"])
ART = art_tiles.TILES["calendar"]
# The patch's own colours, as the art draws them: the month band, the page, the two labels.
BAND = ART["c1"].lower()
PAGE = ART["base"].lower()
MONTH_TEXT = ART["t2c"].lower()
DAY_TEXT = ART["tc"].lower()

APPS_BINDING = re.compile(r"\bcalendarApp:\s*(\[[^\]]*\])")
STRING = re.compile(r'"([^"]*)"')


def color_of(obj):
    """A colour binding as '#rrggbb' (lowercase), '' when not a literal."""
    v = obj.value("color").strip().strip('"').strip("'").lower()
    return v if re.fullmatch(r"#[0-9a-f]{6}", v) else ""


def label_rects(cal):
    """(kind, rectangle, text) for the month and day patches under the overlay object."""
    out = {}
    for o in qmlscan.walk([cal]):
        if o.short != "Text":
            continue
        t = o.value("text")
        kind = "month" if "monthText" in t else "day" if "dayText" in t else ""
        if not kind:
            continue
        for p in o.ancestors():
            if p.short == "Rectangle":
                out[kind] = (p, o)
                break
    return out


def check_file(path):
    findings = []
    text = path.read_text(encoding="utf-8", errors="replace")
    bare = qmlscan.strip_comments(text)
    for m in APPS_BINDING.finditer(bare):
        line = bare[: m.start()].count("\n") + 1
        apps = set(STRING.findall(m.group(1)))
        missing = sorted(EXPECTED_APPS - apps)
        extra = sorted(apps - EXPECTED_APPS)
        if missing or extra:
            why = []
            if missing:
                why.append("missing " + ", ".join(missing))
            if extra:
                why.append("extra " + ", ".join(extra))
            findings.append((line, "calendar-apps",
                             f"the date overlay's apps must be names.py APPS['calendar'] ({'; '.join(why)})"))
    for cal in (o for o in qmlscan.walk(qmlscan.scan(text)) if o.value("id") == "calOverlay"):
        patches = label_rects(cal)
        want = {"month": (BAND, MONTH_TEXT), "day": (PAGE, DAY_TEXT)}
        for kind, (rect, label) in patches.items():
            band, textc = want[kind]
            got = color_of(rect)
            if got and got != band:
                findings.append((rect.line, "calendar-colors",
                                 f"the {kind} patch must use the tile art's colour {band}, not {got}"))
            got = color_of(label)
            if got and got != textc:
                findings.append((label.line, "calendar-colors",
                                 f"the {kind} label must use the tile art's colour {textc}, not {got}"))
        for kind in ("month", "day"):
            if kind not in patches:
                findings.append((cal.line, "calendar-colors",
                                 f"no {kind} patch (rectangle with a {kind}Text label) under calOverlay"))
    return findings


def main(argv):
    warn = False
    if argv and argv[0] == "--warn":
        warn, argv = True, argv[1:]
    paths = argv or [os.path.join(ROOT, "packages")]
    findings = []
    for f in qmlscan.qml_files(paths):
        if "calendarApp" not in f.read_text(encoding="utf-8", errors="replace"):
            continue
        path = str(f.resolve())
        rel = os.path.relpath(path, ROOT) if path.startswith(ROOT + os.sep) else str(f)
        for line, rule, msg in check_file(f):
            findings.append((rel, line, rule, msg, path))
    findings.sort(key=lambda x: (x[0], x[1]))
    for rel, line, rule, msg, path in findings:
        print(f"{rel}:{line}: {rule} {msg} | {qmlscan.source_line(path, line)}")
    print(f"calendar-tile: {len(findings)} finding(s) in {len({x[0] for x in findings})} file(s)", file=sys.stderr)
    if warn:
        return 0
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
