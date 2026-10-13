#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check mode's comparison contract (design/render/render.py).

    python3 design/render/tests/render_test.py

Needs Pillow; no Chrome (the comparison runs on fixture images, so a missing preview, a size
mismatch and a stale preview are all exercised without a browser).
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("board_render", ROOT / "design" / "render" / "render.py")
render = importlib.util.module_from_spec(spec)
spec.loader.exec_module(render)

checks = 0
failures = []


def check(ok, message):
    global checks
    checks += 1
    print(("PASS " if ok else "FAIL ") + message)
    if not ok:
        failures.append(message)


def write(path, size, colour):
    Image.new("RGB", size, colour).save(path)
    return path


with tempfile.TemporaryDirectory(prefix="render-test-") as td:
    td = Path(td)
    got = write(td / "got.png", (64, 48), (10, 20, 30))

    check(render.compare("identical", got, write(td / "same.png", (64, 48), (10, 20, 30))) is True,
          "an identical preview passes")
    check(render.compare("close", got, write(td / "close.png", (64, 48), (13, 23, 33))) is True,
          "a preview within the limits passes")
    check(render.compare("stale", got, write(td / "far.png", (64, 48), (60, 20, 30))) is False,
          "a preview past the global limit fails the check")
    local = Image.new("RGB", (256, 256), (10, 20, 30))
    local.paste((255, 255, 255), (0, 0, 32, 32))
    local.save(td / "local.png")
    check(render.compare("localized", write(td / "base256.png", (256, 256), (10, 20, 30)),
                         td / "local.png") is False,
          "a change confined to one small area fails the check")
    icon = Image.new("RGB", (2048, 1280), (10, 20, 30))
    icon.paste((255, 255, 255), (700, 700, 714, 714))     # a 14 px icon on a board-sized render
    icon.save(td / "icon.png")
    check(render.compare("tiny", write(td / "base2048.png", (2048, 1280), (10, 20, 30)),
                         td / "icon.png") is False,
          "a change the size of a 14 px icon fails the check on a board-sized render")
    check(render.compare("size", got, write(td / "wrong.png", (32, 24), (10, 20, 30))) is False,
          "a committed preview of another size fails the check")
    check(render.compare("missing", got, td / "absent.png") is False,
          "a missing committed preview fails the check")

print(f"render check test: {checks - len(failures)}/{checks} passed")
sys.exit(1 if failures else 0)
