#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the design boards to the preview images in design/previews/.

    design/render/render.py                 every board of design/boards/canvas.json, in canvas order
    design/render/render.py NAME.dc.html ...  only the named boards
    design/render/render.py --check         render to a scratch directory and diff against the
                                            committed previews (mean absolute difference per channel)

Each board is served over a local HTTP server (dc-import fetches its component, which file://
blocks), the board is opened in headless Chrome at twice its canvas size with design/render/
runtime.js resolving the template language (the authoring tool's runtime is not part of this
repository), and the screenshot becomes a WebP preview, like the ones the tool produced.

Requires: google-chrome (or CHROME=...), Pillow.
"""
import argparse
import http.server
import json
import os
import socketserver
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

from PIL import Image

DESIGN = Path(__file__).resolve().parents[1]
BOARDS = DESIGN / "boards"
OUT = DESIGN / "previews"
CHROME = os.environ.get("CHROME", "google-chrome")
SCALE = int(os.environ.get("RENDER_SCALE", "2"))
QUALITY = int(os.environ.get("RENDER_QUALITY", "90"))


def boards() -> dict:
    return json.loads((BOARDS / "canvas.json").read_text())["boards"]


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(DESIGN), **kw)

    def log_message(self, *a):
        pass

    def do_GET(self):
        # Serve a board with the render runtime in place of the authoring tool's ./support.js.
        if self.path.startswith("/boards/") and self.path.endswith(".dc.html"):
            p = BOARDS / self.path[len("/boards/"):]
            if p.is_file():
                html = p.read_text()
                inject = '<script src="/render/runtime.js"></script>'
                if '<script src="./support.js"></script>' in html:
                    html = html.replace('<script src="./support.js"></script>', inject, 1)
                else:
                    html = html.replace("</head>", inject + "</head>", 1)
                body = html.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
        super().do_GET()


def serve() -> tuple[socketserver.TCPServer, int]:
    srv = socketserver.TCPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv, srv.server_address[1]


def render(name: str, w: int, h: int, port: int, dest: Path) -> Path:
    work = Path(tempfile.mkdtemp(prefix="board-render-"))
    profile = work / "chrome"
    png = work / (name + ".png")
    url = f"http://127.0.0.1:{port}/boards/{name}"
    cmd = [
        CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
        f"--user-data-dir={profile}",
        f"--force-device-scale-factor={SCALE}", f"--window-size={w},{h}",
        "--virtual-time-budget=20000", f"--screenshot={png}", url,
    ]
    subprocess.run(cmd, check=True, capture_output=True, timeout=300)
    dest.parent.mkdir(parents=True, exist_ok=True)
    im = Image.open(png)
    if im.size != (w * SCALE, h * SCALE):
        print(f"warning: {name}: {im.size} rendered, canvas says {w * SCALE}x{h * SCALE}", file=sys.stderr)
    im.convert("RGB").save(dest, "WEBP", quality=QUALITY, method=6)
    return dest


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
                    if not want.exists():
                        print(f"{name}: no committed preview to check against")
                        continue
                    a = Image.open(got).convert("RGB")
                    b = Image.open(want).convert("RGB")
                    if a.size != b.size:
                        print(f"{name}: size {a.size} vs {b.size}")
                        continue
                    diff = Image.open(got).convert("RGB")
                    import numpy as np
                    d = np.asarray(diff, dtype=int) - np.asarray(b, dtype=int)
                    mad = abs(d).mean()
                    print(f"{name}: mean abs difference {mad:.1f} over {a.size[0]}x{a.size[1]}")
                    if mad > 12:
                        rc = 1
            else:
                dest = render(name, w, h, port, args.out / (name.split(".dc.html")[0] + ".webp"))
                print(f"{dest} ({w * SCALE}x{h * SCALE})")
    finally:
        srv.shutdown()
    return rc


if __name__ == "__main__":
    sys.exit(main())
