#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check that a widget's FusionBackdrop follows the widget's glass key.

The settings module (Glass, High contrast) and the power service (critical tier) write the glass
level into the [General] glass key of the Fusion widgets. A FusionBackdrop that follows the
wallpaper and is left at its default "full" keeps drawing the blurred picture under Solid glass.
For a plasmoid package this checks that:
  - its config/main.xml declares glass as a String with the default "full";
  - the package binds Plasmoid.configuration.glass somewhere;
  - every FusionBackdrop block with followWallpaper: true sets glass.

  backdrop_glass_test.py PACKAGE_DIR...
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

KCFG = "{http://www.kde.org/standards/kcfg/1.0}"


def backdrop_blocks(text):
    """The text of every `FusionBackdrop { ... }` block, matched by braces."""
    for match in re.finditer(r"\bFusionBackdrop\s*\{", text):
        depth, i = 0, match.end() - 1
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    yield text[match.start():i + 1], text.count("\n", 0, match.start()) + 1
                    break
            i += 1


def check(package):
    problems = []
    xml = package / "contents/config/main.xml"
    entry = None
    if xml.is_file():
        for e in ET.parse(xml).getroot().iter(KCFG + "entry"):
            if e.get("name") == "glass":
                entry = e
    if entry is None:
        problems.append(f"{xml}: no glass entry")
    else:
        default = entry.find(KCFG + "default")
        if entry.get("type") != "String":
            problems.append(f"{xml}: glass must be a String entry, not {entry.get('type')}")
        if default is None or (default.text or "").strip() != "full":
            problems.append(f"{xml}: glass must default to full")
    qml = sorted(package.glob("contents/ui/**/*.qml"))
    if not any("Plasmoid.configuration.glass" in f.read_text() for f in qml):
        problems.append(f"{package}: nothing binds Plasmoid.configuration.glass")
    for f in qml:
        if f.name == "FusionBackdrop.qml":
            continue
        for block, line in backdrop_blocks(f.read_text()):
            if re.search(r"followWallpaper\s*:\s*true", block) and not re.search(r"^\s*glass\s*:", block, re.M):
                problems.append(f"{f}:{line}: FusionBackdrop follows the wallpaper but leaves glass at full")
    return problems


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip().splitlines()[-1].strip(), file=sys.stderr)
        return 2
    problems = []
    for arg in argv[1:]:
        problems += check(Path(arg))
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
