#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The board runtime, exercised in a browser (design/render/runtime.js).

    python3 design/render/tests/runtime_test.py        # CHROME=chromium for another binary

Renders two small fixture boards through render.py's own server and pipe driver - the same code
path the design boards use - and probes the picture: sc-for loops (HTML and inside an <svg>, which
must keep the SVG namespace), sc-if, interpolation, dc-import with props, and the failure path
(a broken expression must withhold the completion marker, so the render fails). Needs Chrome and
Pillow; the fixtures live in a temporary design tree, nothing here is written into the repository.
"""
import importlib.util
import shutil
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


FEATURE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>runtime fixture</title></head>
<body style="margin:0;background:#404040">
<x-dc>
<sc-for list="{{boxes}}" as="b" hint-placeholder-count="2">
<span style="position:absolute;left:{{b.x}}px;top:{{b.y}}px;width:20px;height:20px;background:{{b.c}}"></span>
</sc-for>
<sc-if value="{{yes}}"><span style="position:absolute;left:0;top:100px;width:10px;height:10px;background:#00ff00"></span></sc-if>
<sc-if value="{{no}}"><span style="position:absolute;left:20px;top:100px;width:10px;height:10px;background:#ff0000"></span></sc-if>
<svg width="40" height="40" aria-hidden="true" style="position:absolute;left:100px;top:0">
<sc-for list="{{paths}}" as="p" hint-placeholder-count="1"><path d="{{p.d}}" fill="{{p.c}}"></path></sc-for>
</svg>
<dc-import name="runtime-imported" fill="#ff00ff" hint-size="40px,40px"></dc-import>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":200,"height":120}}'>
class Component extends DCLogic {
  renderVals() {
    return {
      boxes: [{ x: 0, y: 0, c: '#ff0000' }, { x: 20, y: 0, c: '#00ff00' }],
      yes: true, no: false,
      paths: [{ d: 'M0 0h40v40H0z', c: '#0000ff' }]
    };
  }
}
</script>
</body></html>
"""

IMPORTED = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"></head>
<body style="margin:0">
<x-dc>
<div style="position:absolute;left:100px;top:100px;width:40px;height:40px;background:{{c}}"></div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":64,"height":64}}'>
class Component extends DCLogic {
  renderVals() {
    return { c: this.props.fill || '#000000' };
  }
}
</script>
</body></html>
"""

BROKEN = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"></head>
<body><x-dc><span>{{definitelyMissing}}</span></x-dc></body></html>
"""

with tempfile.TemporaryDirectory(prefix="runtime-test-") as td:
    design = Path(td) / "design"
    (design / "boards").mkdir(parents=True)
    (design / "render").mkdir()
    shutil.copy(ROOT / "design" / "render" / "runtime.js", design / "render" / "runtime.js")
    (design / "boards" / "runtime-feature.dc.html").write_text(FEATURE)
    (design / "boards" / "runtime-imported.dc.html").write_text(IMPORTED)
    (design / "boards" / "runtime-broken.dc.html").write_text(BROKEN)

    render.DESIGN = design
    render.BOARDS = design / "boards"
    render.REPO = design

    srv, port = render.serve()
    try:
        with tempfile.TemporaryDirectory(prefix="runtime-out-") as out:
            got = render.render("runtime-feature.dc.html", 200, 120, port, Path(out) / "feature.png")
            im = Image.open(got).convert("RGB")
            check(im.size == (400, 240), f"the fixture renders at {im.size}")

            def probe(x, y, colour):
                # The preview is a lossy WebP, so a channel can shift by a step or two.
                px = im.getpixel((x * render.SCALE + 1, y * render.SCALE + 1))
                return all(abs(a - b) <= 4 for a, b in zip(px, colour))

            check(probe(10, 10, (255, 0, 0)), "sc-for draws its first item (HTML)")
            check(probe(30, 10, (0, 255, 0)), "sc-for draws its second item (HTML)")
            check(probe(5, 105, (0, 255, 0)), "sc-if keeps a true branch")
            check(probe(25, 105, (64, 64, 64)), "sc-if drops a false branch")
            check(probe(120, 20, (0, 0, 255)), "sc-for inside an <svg> keeps the SVG namespace")
            check(probe(110, 110, (255, 0, 255)), "dc-import draws with its props")

        try:
            with tempfile.TemporaryDirectory(prefix="runtime-out-") as out:
                render.render("runtime-broken.dc.html", 200, 120, port, Path(out) / "broken.png")
            check(False, "a board with a failing expression fails the render")
        except RuntimeError:
            check(True, "a board with a failing expression fails the render")
    finally:
        srv.shutdown()

print(f"runtime test: {checks - len(failures)}/{checks} passed")
sys.exit(1 if failures else 0)
