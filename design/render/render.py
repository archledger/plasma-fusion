#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Render the design boards to the preview images in design/previews/.

    design/render/render.py                 every board of design/boards/canvas.json, in canvas order
    design/render/render.py NAME.dc.html ...  only the named boards
    design/render/render.py --check         render to a scratch directory and diff against the
                                            committed previews; a missing preview, a size mismatch,
                                            a mean per-channel difference over 12 or a worst
                                            16x16-block mean over 16 fails the check

Each board is served over a local HTTP server (dc-import fetches its component, which file://
blocks) with the fonts this repository bundles (fonts/, so rendering is offline and does not move
with fonts.googleapis.com). One headless Chrome drives the page over its remote-debugging pipe:
the renderer navigates, waits for the runtime's data-board-rendered marker through
Runtime.evaluate (a board that does not finish, or whose template expressions fail, fails the
run), and captures that same page at twice its canvas size, which becomes a WebP preview, like
the ones the tool produced.

Requires: google-chrome (or CHROME=...), Pillow.
"""
import argparse
import base64
import http.server
import json
import os
import re
import shutil
import signal
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
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
WINDOW = 32
WINDOW_LIMIT = 20
RENDER_TIMEOUT_MS = 20000

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
RENDERED_MARKER = "data-board-rendered"
WAIT_FOR_MARKER = (
    "new Promise((resolve, reject) => {"
    "  const t0 = Date.now();"
    # The marker says the template is resolved; the bundled fonts load asynchronously (a fresh
    # profile every time), so wait for them before the capture paints.
    "  const done = () => document.fonts.ready.then(() => resolve('rendered'), reject);"
    "  const tick = () => {"
    f"    if (document.documentElement.dataset.boardRendered === '1') {{ done(); }}"
    f"    else if (Date.now() - t0 > {RENDER_TIMEOUT_MS}) {{ reject(new Error('the board did not finish rendering')); }}"
    "    else { setTimeout(tick, 50); }"
    "  };"
    "  tick();"
    "})"
)


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


class DevTools:
    """The smallest CDP client that fits: Chrome's remote-debugging pipe (fd 3 in, fd 4 out,
    NUL-separated JSON), so one browser process owns the whole render - the page that passes the
    marker check is the page the screenshot comes from."""

    def __init__(self, work: Path):
        r_in, self.w_in = os.pipe()
        self.r_out, w_out = os.pipe()
        cmd = [
            CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
            # The shared-memory default fails in small containers, which also run as root and
            # then need the sandbox off (the CI's chromium).
            "--disable-dev-shm-usage",
            f"--user-data-dir={work / 'chrome'}", "--remote-debugging-pipe", "about:blank",
        ]
        if hasattr(os, "geteuid") and os.geteuid() == 0:
            cmd.append("--no-sandbox")
        sh = 'exec "$0" "$@" 3<&%d 4>&%d' % (r_in, w_out)
        # Its own process group: Chrome starts helpers, and the group is what close() reaps.
        self.proc = subprocess.Popen(["sh", "-c", sh, *cmd], pass_fds=(r_in, w_out),
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                     start_new_session=True)
        os.close(r_in)
        os.close(w_out)
        self._id = 0
        self._buf = b""

    def close(self) -> None:
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.proc.wait(timeout=10)

    def _send(self, message: dict) -> None:
        os.write(self.w_in, json.dumps(message).encode() + b"\0")

    def _recv(self) -> dict:
        while b"\0" not in self._buf:
            chunk = os.read(self.r_out, 65536)
            if not chunk:
                raise RuntimeError("Chrome closed the debugging pipe")
            self._buf += chunk
        line, self._buf = self._buf.split(b"\0", 1)
        return json.loads(line)

    def call(self, method: str, params: dict | None = None, session: str | None = None) -> dict:
        self._id += 1
        message = {"id": self._id, "method": method}
        if params:
            message["params"] = params
        if session:
            message["sessionId"] = session
        self._send(message)
        while True:
            reply = self._recv()
            if reply.get("id") == self._id:
                if "error" in reply:
                    raise RuntimeError(f"{method}: {reply['error']}")
                return reply.get("result", {})


def _remove_work(path: Path) -> None:
    """Chrome's helpers can outlive the killpg by a moment and still write into the profile, so
    the cleanup retries briefly instead of failing a render that already succeeded."""
    for _ in range(25):
        try:
            shutil.rmtree(path)
            return
        except OSError:
            time.sleep(0.2)
    shutil.rmtree(path, ignore_errors=True)


def render(name: str, w: int, h: int, port: int, dest: Path) -> Path:
    td = Path(tempfile.mkdtemp(prefix="board-render-"))
    try:
        cdp = DevTools(Path(td))
        try:
            target = cdp.call("Target.createTarget", {"url": "about:blank"})["targetId"]
            session = cdp.call("Target.attachToTarget", {"targetId": target, "flatten": True})["sessionId"]
            cdp.call("Emulation.setDeviceMetricsOverride",
                     {"width": w, "height": h, "deviceScaleFactor": SCALE, "mobile": False},
                     session=session)
            cdp.call("Page.navigate", {"url": f"http://127.0.0.1:{port}/boards/{name}"}, session=session)
            waited = cdp.call("Runtime.evaluate",
                              {"expression": WAIT_FOR_MARKER, "awaitPromise": True, "returnByValue": True},
                              session=session)
            # A rejected promise comes back in a successful response's exceptionDetails; a board
            # whose template failed must not be captured.
            if "exceptionDetails" in waited:
                reason = waited["exceptionDetails"].get("exception", {}).get("description", "no detail")
                raise RuntimeError(f"{name}: the board did not finish rendering ({reason})")
            if waited.get("result", {}).get("value") != "rendered":
                raise RuntimeError(f"{name}: the render wait returned {waited.get('result')}")
            shot = cdp.call("Page.captureScreenshot",
                            {"format": "png", "captureBeyondViewport": False}, session=session)
        finally:
            cdp.close()
        png = Path(td) / (name + ".png")
        png.write_bytes(base64.b64decode(shot["data"]))
        dest.parent.mkdir(parents=True, exist_ok=True)
        im = Image.open(png)
        if im.size != (w * SCALE, h * SCALE):
            print(f"warning: {name}: {im.size} rendered, canvas says {w * SCALE}x{h * SCALE}",
                  file=sys.stderr)
        im.convert("RGB").save(dest, "WEBP", quality=QUALITY, method=6)
    finally:
        _remove_work(td)
    return dest


def compare(name: str, got: Path, want: Path) -> bool:
    """Print the difference of a fresh render against the committed preview; False when the
    committed preview is missing, has another size, or is stale - globally (mean limit MAD_LIMIT)
    or in any fixed WINDOW x WINDOW pixel area (limit WINDOW_LIMIT), so a change confined to even
    a small element, like a 14 px icon, fails the check."""
    if not want.exists():
        print(f"{name}: no committed preview to check against")
        return False
    a = Image.open(got).convert("RGB")
    b = Image.open(want).convert("RGB")
    if a.size != b.size:
        print(f"{name}: size {a.size} vs {b.size}")
        return False
    diff = ImageChops.difference(a, b)
    mad = sum(ImageStat.Stat(diff).mean) / 3
    worst = 0.0
    w, h = a.size
    for y in range(0, h, WINDOW):
        for x in range(0, w, WINDOW):
            box = (x, y, min(x + WINDOW, w), min(y + WINDOW, h))
            worst = max(worst, sum(ImageStat.Stat(diff.crop(box)).mean) / 3)
    print(f"{name}: mean abs difference {mad:.1f}, worst {WINDOW} px window {worst:.1f} over {w}x{h}")
    return mad <= MAD_LIMIT and worst <= WINDOW_LIMIT


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
