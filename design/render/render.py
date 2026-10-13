#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the design boards to the preview images in design/previews/.

    design/render/render.py                 every board of design/boards/canvas.json, in canvas order
    design/render/render.py NAME.dc.html ...  only the named boards
    design/render/render.py --check         render to a scratch directory and diff against the
                                            committed previews (mean absolute difference per channel);
                                            a missing preview or a size mismatch fails the check

Each board is served over a local HTTP server (dc-import fetches its component, which file://
blocks) with the fonts this repository bundles (fonts/, so rendering is offline and does not move
with fonts.googleapis.com), the board is opened in headless Chrome at twice its canvas size with
design/render/runtime.js resolving the template language (the authoring tool's runtime is not part
of this repository), the runtime's data-board-rendered marker is waited for (a board that does not
finish rendering fails the run), and the screenshot becomes a WebP preview, like the ones the tool
produced.

Requires: google-chrome (or CHROME=...), Pillow.
"""
import argparse
import http.server
import json
import os
import re
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

DESIGN = Path(__file__).resolve().parents[1]
REPO = DESIGN.parent
BOARDS = DESIGN / "boards"
OUT = DESIGN / "previews"
CHROME = os.environ.get("CHROME", "google-chrome")
SCALE = int(os.environ.get("RENDER_SCALE", "2"))
QUALITY = int(os.environ.get("RENDER_QUALITY", "90"))
MAD_LIMIT = 12

# The fonts the boards ask Google for, served from this repository instead: same files, so an
# offline render (and --check) is stable across network state and upstream stylesheet changes.
FONTS = [
    ("Manrope", 400, "fonts/manrope/static/Manrope-Regular.ttf"),
    ("Manrope", 500, "fonts/manrope/static/Manrope-Medium.ttf"),
    ("Manrope", 600, "fonts/manrope/static/Manrope-SemiBold.ttf"),
    ("Manrope", 700, "fonts/manrope/static/Manrope-Bold.ttf"),
    ("Manrope", 800, "fonts/manrope/static/Manrope-ExtraBold.ttf"),
    ("Space Grotesk", 500, "fonts/spacegrotesk/static/SpaceGrotesk-Medium.ttf"),
    ("Space Grotesk", 600, "fonts/spacegrotesk/static/SpaceGrotesk-SemiBold.ttf"),
    ("Space Grotesk", 700, "fonts/spacegrotesk/static/SpaceGrotesk-Bold.ttf"),
]
FONT_CSS = "<style>" + "".join(
    f"@font-face{{font-family:'{fam}';font-weight:{weight};src:url('/{path}')}}" for fam, weight, path in FONTS
) + "</style>"
GOOGLE_FONTS_LINK = re.compile(r"<link[^>]*fonts\.googleapis\.com[^>]*>")
RENDERED_MARKER = 'data-board-rendered="1"'


def boards() -> dict:
    return json.loads((BOARDS / "canvas.json").read_text())["boards"]


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(DESIGN), **kw)

    def log_message(self, *a):
        pass

    def send_bytes(self, body: bytes, mime: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        # The bundled fonts (the repository root is not the document root).
        if self.path.startswith("/fonts/"):
            p = REPO / self.path[1:]
            if p.is_file() and p.suffix in (".ttf", ".otf"):
                self.send_bytes(p.read_bytes(), "font/" + p.suffix[1:])
                return
        # Serve a board with the render runtime in place of the authoring tool's ./support.js and
        # the bundled fonts in place of the Google Fonts stylesheet (imports take the same path).
        if self.path.startswith("/boards/") and self.path.endswith(".dc.html"):
            p = BOARDS / self.path[len("/boards/"):]
            if p.is_file():
                html = p.read_text()
                inject = '<script src="/render/runtime.js"></script>'
                if '<script src="./support.js"></script>' in html:
                    html = html.replace('<script src="./support.js"></script>', inject, 1)
                else:
                    html = html.replace("</head>", inject + "</head>", 1)
                html = GOOGLE_FONTS_LINK.sub(FONT_CSS, html, count=1)
                self.send_bytes(html.encode(), "text/html; charset=utf-8")
                return
        super().do_GET()


def serve() -> tuple[socketserver.TCPServer, int]:
    srv = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def render(name: str, w: int, h: int, port: int, dest: Path) -> Path:
    url = f"http://127.0.0.1:{port}/boards/{name}"
    with tempfile.TemporaryDirectory(prefix="board-render-") as td:
        work = Path(td)
        common = [
            CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
            f"--user-data-dir={work / 'chrome'}",
            f"--force-device-scale-factor={SCALE}", f"--window-size={w},{h}",
            "--virtual-time-budget=20000",
        ]
        dom = subprocess.run(common + ["--dump-dom", url], check=True, capture_output=True,
                             timeout=300).stdout
        if RENDERED_MARKER.encode() not in dom:
            raise RuntimeError(f"{name}: the board did not finish rendering (no {RENDERED_MARKER})")
        png = work / (name + ".png")
        subprocess.run(common + [f"--screenshot={png}", url], check=True, capture_output=True,
                       timeout=300)
        dest.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(png)
        if im.size != (w * SCALE, h * SCALE):
            print(f"warning: {name}: {im.size} rendered, canvas says {w * SCALE}x{h * SCALE}",
                  file=sys.stderr)
        im.convert("RGB").save(dest, "WEBP", quality=QUALITY, method=6)
    return dest


def compare(name: str, got: Path, want: Path) -> bool:
    """Print the difference of a fresh render against the committed preview; False when the
    committed preview is missing, has another size, or is too different (a stale preview)."""
    if not want.exists():
        print(f"{name}: no committed preview to check against")
        return False
    a = Image.open(got).convert("RGB")
    b = Image.open(want).convert("RGB")
    if a.size != b.size:
        print(f"{name}: size {a.size} vs {b.size}")
        return False
    mad = sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3
    print(f"{name}: mean abs difference {mad:.1f} over {a.size[0]}x{a.size[1]}")
    return mad <= MAD_LIMIT


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("boards", nargs="*", help="board file names (default: all, canvas order)")
    ap.add_argument("--check", action="store_true", help="render to a scratch dir and compare")
    ap.add_argument("--out", type=Path, default=OUT)
    args = ap.parse_args()

    meta = boards()
    order = json.loads((BOARDS / "canvas.json").read_text())["order"]
    names = args.boards or order
    unknown = [n for n in names if n not in meta]
    if unknown:
        print("not in canvas.json:", " ".join(unknown), file=sys.stderr)
        return 2

    srv, port = serve()
    rc = 0
    try:
        for name in names:
            w, h = meta[name]["w"], meta[name]["h"]
            if args.check:
                with tempfile.TemporaryDirectory(prefix="board-check-") as td:
                    got = render(name, w, h, port, Path(td) / (name + ".webp"))
                    want = args.out / (name.split(".dc.html")[0] + ".webp")
                    if not compare(name, got, want):
                        rc = 1
            else:
                dest = render(name, w, h, port, args.out / (name.split(".dc.html")[0] + ".webp"))
                print(f"{dest} ({w * SCALE}x{h * SCALE})")
    finally:
        srv.shutdown()
    return rc


if __name__ == "__main__":
    sys.exit(main())
