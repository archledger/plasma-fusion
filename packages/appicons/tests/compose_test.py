# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The familiar icon composition on synthetic originals: a square and a rounded square become the
# tile, a one-colour circle gets a tile in its own hue, a multi-colour logo the neutral tile, a wide
# shape a plate. Usage: python3 compose_test.py <path to plasma-fusion-app-icons>
import importlib.machinery, importlib.util, pathlib, sys, tempfile
import xml.dom.minidom as minidom
from PIL import Image, ImageDraw

loader = importlib.machinery.SourceFileLoader("appicons", sys.argv[1])
spec = importlib.util.spec_from_loader("appicons", loader)
tool = importlib.util.module_from_spec(spec)
loader.exec_module(tool)
try:
    painter = tool.Painter()
except ImportError as e:
    print(f"app-icons compose test skipped: {e}")
    sys.exit(0)


def xpm(path):
    # Shaped like xterm's icon: tab-separated colour lines and a space as a colour key, which
    # Pillow's XPM reader rejects (ValueError) while Qt reads it.
    rows = ["." * 32] * 4 + ["...." + " " * 24 + "...."] * 24 + ["." * 32] * 4
    text = '/* XPM */\nstatic char * t_xpm[] = {\n"32 32 2 1",\n".\tc None",\n" \tc #282830",\n'
    text += ",\n".join('"%s"' % r for r in rows) + "};\n"
    path.write_text(text)
    return str(path)


def png(draw, path):
    im = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
    draw(ImageDraw.Draw(im))
    im.save(path)
    return str(path)


with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    cases = {
        "square": (png(lambda g: g.rectangle((8, 8, 119, 119), fill=(40, 40, 48, 255)), d / "a.png"), "tile", None),
        "rounded": (png(lambda g: g.rounded_rectangle((8, 8, 119, 119), radius=26, fill=(30, 90, 200, 255)), d / "b.png"), "tile", None),
        "circle": (png(lambda g: g.ellipse((8, 8, 119, 119), fill=(20, 160, 60, 255)), d / "c.png"), "plate", "green"),
        "logo": (png(lambda g: [g.pieslice((8, 8, 119, 119), a, a + 120, fill=c) for a, c in
                                ((0, (220, 40, 40, 255)), (120, (40, 160, 60, 255)), (240, (240, 190, 20, 255)))], d / "d.png"),
                 "plate", "neutral"),
        "wide": (png(lambda g: g.rectangle((4, 44, 123, 83), fill=(200, 60, 120, 255)), d / "e.png"), "plate", None),
    }
    if painter.qt:
        cases["xpm"] = (xpm(d / "f.xpm"), "tile", None)
    fails = []
    for name, (src, kind, tint) in cases.items():
        svg, info = tool.compose(painter, src)
        if not svg or tool.MARK not in svg:
            fails.append(f"{name}: no svg")
            continue
        minidom.parseString(svg)
        if info["kind"] != kind:
            fails.append(f"{name}: kind {info['kind']}, want {kind}")
        plate = info.get("plate") or ""
        if tint == "neutral" and plate != tool.NEUTRAL:
            fails.append(f"{name}: plate {plate}, want neutral")
        if tint == "green":
            r, g, b = (int(plate[i:i + 2], 16) for i in (1, 3, 5))
            if not (g > r and g > b and min(r, g, b) > 180):
                fails.append(f"{name}: plate {plate}, want a light green")
    if fails:
        print("app-icons compose test failed:\n  " + "\n  ".join(fails), file=sys.stderr)
        sys.exit(1)
    print(f"app-icons compose test: {len(cases)} cases ok ({'QtSvg' if painter.qt else 'rsvg-convert'})")
