#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline checks for the generated Aurorae themes (not installed).

    check_aurorae.py THEMES_DIR

For every theme directory: required files, metadata.desktop and rc keys, every SVG loads in
QtSvg, the frame and button elements Aurorae v2 looks up exist, and their sizes are consistent
(corner = side widths, button states = button box, padding inside the corner slices).
Exit status 1 on any failure.
"""
import configparser
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

FRAME = ["topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright"]
STATES = ["active", "inactive", "hover", "hover-inactive", "pressed", "pressed-inactive",
          "deactivated", "deactivated-inactive"]
BUTTON_FILES = ["minimize", "maximize", "restore", "close", "keepabove", "keepbelow",
                "alldesktops", "shade", "help", "appmenu"]

errors = []


def fail(msg):
    errors.append(msg)
    print("FAIL", msg)


def bounds(r, eid):
    if not r.elementExists(eid):
        return None
    b = r.transformForElement(eid).mapRect(r.boundsOnElement(eid))
    return (round(b.x(), 3), round(b.y(), 3), round(b.width(), 3), round(b.height(), 3))


def read_rc(path):
    cp = configparser.ConfigParser(interpolation=None, strict=True)
    cp.optionxform = str
    with open(path, encoding="utf-8") as f:
        text = "".join(line for line in f if not line.startswith("#"))
    cp.read_string(text)
    return cp


def check_theme(d):
    name = os.path.basename(d.rstrip("/"))
    for f in ["metadata.desktop", "decoration.svg", name + "rc"] + [b + ".svg" for b in BUTTON_FILES]:
        if not os.path.isfile(os.path.join(d, f)):
            fail("%s: missing %s" % (name, f))
    if os.path.exists(os.path.join(d, "menu.svg")):
        fail("%s: menu.svg must not exist (the app icon is drawn in the menu slot)" % name)
    md = read_rc(os.path.join(d, "metadata.desktop"))
    de = md["Desktop Entry"]
    if de.get("X-KDE-PluginInfo-Name") != name or not de.get("Name"):
        fail("%s: metadata Name / X-KDE-PluginInfo-Name" % name)
    rc = read_rc(os.path.join(d, name + "rc"))
    lay = {k: int(v) for k, v in rc["Layout"].items()}
    gen = rc["General"]
    for k in ("ActiveTextColor", "InactiveTextColor"):
        parts = gen[k].split(",")
        if len(parts) not in (3, 4) or not all(0 <= int(p) <= 255 for p in parts):
            fail("%s: bad %s" % (name, k))
    th = max(lay["TitleHeight"], lay["ButtonHeight"] + lay["ButtonMarginTop"])
    title = th + lay["TitleEdgeTop"] + lay["TitleEdgeBottom"]
    title_max = th + lay["TitleEdgeTopMaximized"] + lay["TitleEdgeBottomMaximized"]
    if title != 50 or title_max != 40:
        fail("%s: title bar %d / %d px, expected 50 / 40" % (name, title, title_max))
    print("%s: title bar %d px, maximized %d px" % (name, title, title_max))

    r = QSvgRenderer(os.path.join(d, "decoration.svg"))
    if not r.isValid():
        fail("%s: decoration.svg does not load" % name)
        return
    for prefix in ("decoration", "decoration-inactive"):
        b = {e: bounds(r, "%s-%s" % (prefix, e)) for e in FRAME}
        for e, v in b.items():
            if v is None:
                fail("%s: missing %s-%s" % (name, prefix, e))
        if None in b.values():
            continue
        L, T = b["topleft"][2], b["topleft"][3]
        R, B = b["bottomright"][2], b["bottomright"][3]
        if (b["left"][2], b["top"][3], b["right"][2], b["bottom"][3]) != (L, T, R, B) \
                or b["topright"][2:] != (R, T) or b["bottomleft"][2:] != (L, B):
            fail("%s: %s slice sizes disagree: %s" % (name, prefix, b))
        if L <= lay["PaddingLeft"] or R <= lay["PaddingRight"] or T < lay["PaddingTop"] + title \
                or B <= lay["PaddingBottom"]:
            fail("%s: %s corners do not cover padding + title bar" % (name, prefix))
        print("  %s: corners L%s T%s R%s B%s -> smallest clean window %sx%s, title safe from h %s"
              % (prefix, L, T, R, B, L + R - lay["PaddingLeft"] - lay["PaddingRight"],
                 T + B - lay["PaddingTop"] - lay["PaddingBottom"], B - lay["PaddingBottom"] + title))
    for e in ("decoration-maximized-center", "decoration-maximized-inactive-center", "hint-stretch-borders"):
        if bounds(r, e) is None:
            fail("%s: missing %s" % (name, e))

    box = (lay["ButtonWidth"], lay["ButtonHeight"])
    for bf in BUTTON_FILES:
        br = QSvgRenderer(os.path.join(d, bf + ".svg"))
        if not br.isValid():
            fail("%s: %s.svg does not load" % (name, bf))
            continue
        for st in STATES:
            v = bounds(br, st + "-center")
            if v is None:
                fail("%s: %s.svg missing %s-center" % (name, bf, st))
            elif (v[2], v[3]) != box:
                fail("%s: %s.svg %s-center is %sx%s, button box %sx%s" % (name, bf, st, v[2], v[3], *box))


def main():
    app = QGuiApplication(sys.argv[:1])  # noqa: F841
    root = sys.argv[1]
    themes = sorted(t for t in os.listdir(root) if os.path.isdir(os.path.join(root, t)))
    if not themes:
        fail("no themes in %s" % root)
    for t in themes:
        check_theme(os.path.join(root, t))
    print("%d theme(s), %d error(s)" % (len(themes), len(errors)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
