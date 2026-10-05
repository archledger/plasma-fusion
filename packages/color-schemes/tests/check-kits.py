#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The generated reference kits must carry the shipped colour schemes' values.

  packages/color-schemes/tests/check-kits.py

Each kit under packages/color-schemes/reference-kits/ is generated from PlasmaFusion{Dark,Light}
.colors by export-kits.py. A scheme's accent is its Colors:Selection BackgroundNormal (the same
value the XDG settings portal reports as accent-color). Exit 1 when a kit is missing or stale.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def accent(scheme_name):
    """Colors:Selection BackgroundNormal of a scheme as an (r, g, b) tuple."""
    text = (ROOT / scheme_name).read_text(encoding="utf-8")
    section = text.split("[Colors:Selection]", 1)
    if len(section) != 2:
        print(f"check-kits: no [Colors:Selection] in {scheme_name}")
        sys.exit(1)
    found = re.search(r"^BackgroundNormal=(\d+),(\d+),(\d+)", section[1], re.M)
    if not found:
        print(f"check-kits: no Selection BackgroundNormal in {scheme_name}")
        sys.exit(1)
    return tuple(int(v) for v in found.groups())


fail = 0
checks = []
for scheme_name, kit in (("PlasmaFusionDark.colors", "fusion-dark.css"),
                         ("PlasmaFusionLight.colors", "fusion-light.css")):
    r, g, b = accent(scheme_name)
    checks.append((kit, f"--fusion-accent: #{r:02x}{g:02x}{b:02x};"))

dark = accent("PlasmaFusionDark.colors")
upper = "%02X%02X%02X" % dark
lower = "#%02x%02x%02x" % dark
checks.append(("imgui_fusion.cpp", lower))
checks.append(("flutter_fusion.dart", f"Color(0xFF{upper})"))
checks.append(("wx_fusion.md", lower))

for name, needle in checks:
    path = ROOT / "reference-kits" / name
    if not path.is_file():
        print(f"check-kits: reference-kits/{name} is missing")
        fail += 1
    elif needle not in path.read_text(encoding="utf-8"):
        print(f"check-kits: reference-kits/{name} does not carry {needle}")
        fail += 1

print("check-kits: ok" if not fail else f"check-kits: {fail} problem(s)")
sys.exit(1 if fail else 0)
