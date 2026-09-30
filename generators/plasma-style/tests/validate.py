#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Static checks of a generated Plasma style.

    validate.py THEME_DIR [THEME_DIR ...]

Checks: XML well-formed, QtSvg can render every file, every frame prefix has all nine cells with
consistent sizes, the elements the Plasma consumers need exist, metadata.json is complete.
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QByteArray  # noqa: E402
from PySide6.QtGui import QGuiApplication  # noqa: E402
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

CELLS = ("topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright")
REQUIRED = {
    "dialogs/background.svg": ["", "launcher", "osd", "notification", "shadow-top", "shadow-hint-top-margin",
                               "mask-center", "hint-top-inset"],
    "widgets/tooltip.svg": ["", "shadow-left", "mask-center"],
    "widgets/panel-background.svg": ["", "south", "north", "west", "east", "mask-south-center", "floating-center",
                                     "floating-hint-bottom-margin", "shadow-left", "shadow-bottomleft"],
    "widgets/background.svg": [""],
    "widgets/plasmoidheading.svg": ["header", "footer"],
    "widgets/button.svg": ["normal", "pressed", "hover", "focus", "toolbutton-hover", "toolbutton-pressed",
                           "toolbutton-focus", "shadow"],
    "widgets/lineedit.svg": ["base", "hover", "focus", "focusframe"],
    "widgets/viewitem.svg": ["normal", "hover", "selected", "selected+hover"],
    "widgets/listitem.svg": ["normal", "hover", "pressed", "section", "separator"],
    "widgets/tabbar.svg": ["north-active-tab", "south-active-tab", "east-active-tab", "west-active-tab"],
    "widgets/menubaritem.svg": ["normal", "hover", "pressed"],
    "widgets/tasks.svg": ["normal", "hover", "focus", "attention", "minimized", "progress",
                          "north-normal", "west-focus", "east-progress"],
    "widgets/scrollbar.svg": ["slider", "mouseover-slider", "background-vertical", "background-horizontal",
                              "hint-scrollbar-size"],
    "widgets/slider.svg": ["groove", "groove-highlight", "horizontal-slider-handle", "horizontal-slider-focus",
                           "horizontal-slider-hover", "horizontal-slider-shadow", "vertical-slider-handle",
                           "hint-handle-size"],
    "widgets/switch.svg": ["inactive", "active", "handle", "handle-hover", "handle-pressed", "handle-focus",
                           "handle-shadow", "hint-bar-size"],
    "widgets/checkmarks.svg": ["checkbox", "radiobutton"],
    "widgets/radiobutton.svg": ["normal", "checked", "hover", "focus", "symbol", "shadow", "hint-size"],
    "widgets/actionbutton.svg": ["normal", "hover", "pressed", "focus", "16-16-normal", "22-22-focus", "24-24-pressed"],
    "widgets/frame.svg": ["plain", "raised", "sunken"],
    "widgets/bar_meter_horizontal.svg": ["bar-inactive", "bar-active", "hint-bar-size"],
    "widgets/busywidget.svg": ["busywidget", "22-22-busywidget", "16-16-busywidget"],
    "widgets/line.svg": ["horizontal-line", "vertical-line"],
    "widgets/arrows.svg": ["up-arrow", "down-arrow", "left-arrow", "right-arrow"],
    "widgets/toolbar.svg": [""],
    "widgets/pager.svg": ["normal", "hover", "active"],
    "widgets/action-overlays.svg": [f"{k}-{s}" for k in ("add", "remove", "open") for s in ("normal", "hover", "pressed")],
}


PANEL_FALLBACK_MAX = 16


def main():
    app = QGuiApplication([])  # noqa: F841
    errors = 0
    for theme in sys.argv[1:]:
        meta = json.load(open(os.path.join(theme, "metadata.json")))
        kp = meta["KPlugin"]
        for key in ("Id", "Name", "Authors", "License", "Version"):
            if not kp.get(key):
                print(f"{theme}: metadata lacks {key}"); errors += 1
        if meta.get("X-Plasma-API") != "5.0":
            print(f"{theme}: X-Plasma-API must be 5.0"); errors += 1
        for root, _, files in os.walk(theme):
            for f in files:
                if not f.endswith(".svg"):
                    continue
                path = os.path.join(root, f)
                rel = os.path.relpath(path, theme)
                data = open(path, "rb").read()
                ET.fromstring(data)
                r = QSvgRenderer(QByteArray(data))
                if not r.isValid():
                    print(f"{rel}: QtSvg cannot load it"); errors += 1; continue
                ids = set(re.findall(r'\bid="([^"]+)"', data.decode()))
                size = lambda i: tuple(round(v, 3) for v in r.transformForElement(i).mapRect(r.boundsOnElement(i)).size().toTuple())  # noqa: E731
                prefixes = {i[:-len("center")] for i in ids if i.endswith("center") and not i.startswith("mask-")}
                for p in prefixes:
                    missing = [c for c in CELLS if p + c not in ids]
                    if missing:
                        # hint-only prefixes (floating-) carry just a centre
                        if p != "floating-":
                            print(f"{rel}: prefix '{p}' lacks {missing}"); errors += 1
                        continue
                    s = {c: size(p + c) for c in CELLS}
                    W, H = 0, 1
                    if not (s["topleft"][H] == s["top"][H] == s["topright"][H]
                            and s["bottomleft"][H] == s["bottom"][H] == s["bottomright"][H]
                            and s["topleft"][W] == s["left"][W] == s["bottomleft"][W]
                            and s["topright"][W] == s["right"][W] == s["bottomright"][W]):
                        print(rel, p, s)
                        print(f"{rel}: prefix '{p}' has inconsistent cell sizes"); errors += 1
                base = rel.split("/", 1)[1] if rel.startswith(("translucent/", "solid/")) else rel
                if base == "widgets/panel-background.svg" and "floating-hint-top-margin" in ids:
                    # --south-frame plain: the headroom is the floating top margin and a 44 px
                    # bottom panel must keep its thickness (south frame drawable at 44 px)
                    if size("floating-hint-top-margin")[1] >= 1:
                        sh = size("south-topleft")[1] + size("south-bottomleft")[1]
                        if sh > 44:
                            print(f"{rel}: plain south frame needs {sh} px (max 44)"); errors += 1
                if base == "widgets/panel-background.svg":
                    # PanelView clamps a panel's thickness to the unprefixed frame's minimum
                    # drawing size while the panel QML starts: keep it below the 34 px top bar.
                    mh = size("top")[1] + size("bottom")[1]
                    mw = size("left")[0] + size("right")[0]
                    if max(mh, mw) > PANEL_FALLBACK_MAX:
                        print(f"{rel}: unprefixed panel frame needs {mw} x {mh} px (max {PANEL_FALLBACK_MAX})"); errors += 1
                for need in REQUIRED.get(base, []):
                    if need == "":
                        ok = "center" in ids
                    else:
                        ok = need in ids or f"{need}-center" in ids
                    if not ok:
                        print(f"{rel}: missing {need or '(unprefixed frame)'}"); errors += 1
    print("errors:", errors)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
