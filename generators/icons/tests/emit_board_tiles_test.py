#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The boards' app tiles stay in sync with the icon theme's drawings.

    python3 generators/icons/tests/emit_board_tiles_test.py

Pure Python (no Pillow, no Chrome): it regenerates the AppIcon component's table and the tablet
boards' embedded tiles and compares them with the committed files, and it pins the seam rule
(a layer drawn in the tile's own base colour keeps that colour and gains the sheen second pass).
"""
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "emit_board_tiles", ROOT / "generators" / "icons" / "emit_board_tiles.py")
emit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(emit)

checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


committed = Path(emit.COMPONENT).read_text()
_, rest = committed.split(emit.BEGIN, 1)
block, _ = rest.split(emit.END, 1)
check(block == emit.block().split(emit.BEGIN, 1)[1].split(emit.END, 1)[0],
      "the AppIcon table matches the emitter (run emit_board_tiles.py --write after a redesign)")

entry = emit.entry("dolphin")
check("c3: '#3f7fe0'" in entry, "a base-coloured layer keeps its colour (Dolphin's g3)")
check("seams: [" in entry, "and gains the sheen second pass")
check("url(#pf-sheen)" not in entry.split("seams:")[0], "the layer itself is not replaced by the sheen")
check("seams:" not in emit.entry("kate"), "a tile without base-coloured layers has no seams")

for path in emit.TABLET:
    check(emit.tablet_html(path) == Path(path).read_text(),
          f"{Path(path).name} carries the drawings the theme ships")

print(f"board tile emitter test: {checks - len(failures)}/{checks} passed")
sys.exit(1 if failures else 0)
