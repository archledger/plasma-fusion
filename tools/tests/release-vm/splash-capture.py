#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The screen of a release VM through one boot, against the Splash board: runs CMD (the reboot,
over ssh), waits for QEMU's RESET event, then takes a screendump every --interval seconds for
--seconds, through QEMU's QMP socket. Each frame is measured against the board: the mean colour of
the logo's three circles where the Plymouth theme centres its 1440x900 frame (the scale its script
picks for the screen, as tests/vmrun.py places it), and of the wallpaper where the script scales
it to cover the screen (the sun, a plain area left of the logo, the lower middle, the top). Needs
Pillow (on NixOS: nix-shell -p python3Packages.pillow).

  splash-capture.py QMP_SOCKET OUTDIR [--expect match|differ] [--board design/previews/Splash.webp]
                    [--seconds 60] [--interval 0.3] [--tol 6] -- CMD...

OUTDIR gets frames.tsv (seconds after the reset, size, largest delta, file kept), first-match.png
and best.png (the frames closest to the board), last.png and sheet.png (every frame, small, in
order); the other frames are not kept. match: some frame has every region within --tol (per
channel, of 255) of the board - the Plasma Fusion splash was shown; differ: every frame has some
region more than three times --tol off - it never was. The verdict is the last line; exit 1 when
it fails, 2 when the VM did not reset.
"""

import argparse
import json
import pathlib
import socket
import subprocess
import sys
import time

from PIL import Image, ImageStat

# The logo's circles, in the theme's 1440x900 frame (the board's coordinates at half its size)
FRAME_REGIONS = {
    "logo-blue": (708, 308, 732, 328),
    "logo-orange": (648, 398, 668, 418),
    "logo-teal": (772, 398, 792, 418),
}
# The wallpaper, in fractions of the screen (the script scales it to cover the screen)
SCREEN_REGIONS = {
    "sun": (1010 / 1440, 310 / 900, 1070 / 1440, 370 / 900),
    "left": (150 / 1440, 250 / 900, 400 / 1440, 450 / 900),
    "low": (550 / 1440, 740 / 900, 890 / 1440, 800 / 900),
    "top": (300 / 1440, 40 / 900, 1140 / 1440, 120 / 900),
}
# The theme's scales (generators/plymouth/gen_plymouth.py): the largest that fits, with a little
# slack, as the script chooses it
SCALES = [1, 1.25, 4 / 3, 1.5, 1.75, 2, 2.5]
THUMB = (160, 100)


def scale_of(w, h):
    fit = min(w / 1440, h / 900)
    s = SCALES[0]
    for v in SCALES:
        if v <= fit + 0.06:
            s = v
    return s


def fill(image, size):
    """IMAGE scaled to cover SIZE and cropped to it around the centre."""
    w, h = size
    scale = max(w / image.width, h / image.height)
    scaled = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    left, top = (scaled.width - w) // 2, (scaled.height - h) // 2
    return scaled.crop((left, top, left + w, top + h))


def boxes(size):
    """Every region's box on a screen of SIZE."""
    w, h = size
    s = scale_of(w, h)
    fx, fy = (w - round(1440 * s)) // 2, (h - round(900 * s)) // 2
    out = {}
    for name, (x0, y0, x1, y1) in FRAME_REGIONS.items():
        out[name] = (fx + round(x0 * s), fy + round(y0 * s), fx + round(x1 * s), fy + round(y1 * s))
    for name, (x0, y0, x1, y1) in SCREEN_REGIONS.items():
        out[name] = (round(x0 * w), round(y0 * h), round(x1 * w), round(y1 * h))
    return out


def expected(board, size):
    """The board as the theme draws it on SIZE: the wallpaper covering the screen, the frame (with
    the logo) at the script's scale, centred."""
    w, h = size
    s = scale_of(w, h)
    screen = fill(board, size)
    frame = board.resize((round(1440 * s), round(900 * s)), Image.LANCZOS)
    fx, fy = (w - frame.width) // 2, (h - frame.height) // 2
    # Only the logo's square from the frame: the rest of the frame is the same wallpaper
    x0, y0, x1, y1 = (round(v * s) for v in (600, 280, 840, 470))
    screen.paste(frame.crop((x0, y0, x1, y1)), (fx + x0, fy + y0))
    return screen


def mean(image, box):
    return tuple(ImageStat.Stat(image.crop(box)).mean)


def deltas(shot, board, cache):
    """Region name -> largest per-channel difference from the board drawn on the shot's size."""
    if shot.size not in cache:
        ref = expected(board, shot.size)
        cache[shot.size] = {n: mean(ref, b) for n, b in boxes(shot.size).items()}
    out = {}
    for name, box in boxes(shot.size).items():
        out[name] = max(abs(x - y) for x, y in zip(mean(shot, box), cache[shot.size][name]))
    return out


class QMP:
    """QEMU's QMP socket: commands, with the events that arrive in between kept."""

    def __init__(self, path):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)
        self.buf = b""
        self.events = []
        self.read()
        self.cmd("qmp_capabilities")

    def read(self, timeout=None):
        self.sock.settimeout(timeout)
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("QMP closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line)

    def cmd(self, name, **args):
        msg = {"execute": name}
        if args:
            msg["arguments"] = args
        self.sock.sendall(json.dumps(msg).encode() + b"\n")
        while True:
            r = self.read(timeout=60)
            if "event" in r:
                self.events.append(r)
            elif "error" in r:
                raise RuntimeError(f"{name}: {r['error']}")
            elif "return" in r:
                return r["return"]

    def wait_event(self, name, timeout):
        end = time.time() + timeout
        while True:
            for e in self.events:
                if e["event"] == name:
                    self.events.remove(e)
                    return e
            left = end - time.time()
            if left <= 0:
                return None
            try:
                r = self.read(timeout=left)
            except (TimeoutError, socket.timeout, EOFError):
                # (EOFError: QEMU went away, so there is no reset to wait for)
                return None
            if "event" in r:
                self.events.append(r)


def sheet(thumbs, path):
    if not thumbs:
        return
    cols = 10
    rows = (len(thumbs) + cols - 1) // cols
    out = Image.new("RGB", (cols * THUMB[0], rows * THUMB[1]))
    for i, t in enumerate(thumbs):
        out.paste(t, ((i % cols) * THUMB[0], (i // cols) * THUMB[1]))
    out.save(path)


def main():
    here = pathlib.Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("qmp")
    ap.add_argument("out")
    ap.add_argument("cmd", nargs="+")
    ap.add_argument("--board", default=str(here.parents[2] / "design/previews/Splash.webp"))
    ap.add_argument("--expect", choices=("match", "differ"), default="match")
    ap.add_argument("--seconds", type=float, default=60)
    ap.add_argument("--interval", type=float, default=0.3)
    ap.add_argument("--tol", type=float, default=6.0)
    ap.add_argument("--reset-timeout", type=float, default=240)
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    board = Image.open(args.board).convert("RGB")
    q = QMP(args.qmp)
    # The reboot: ssh's own status does not matter (the connection drops as the VM goes down)
    subprocess.run(args.cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=120, check=False)
    if q.wait_event("RESET", args.reset_timeout) is None:
        print(f"NO RESET: the VM did not reset within {args.reset_timeout:g} s")
        return 2
    t0 = time.time()
    cache, thumbs, rows = {}, [], []
    # (PPM, QEMU's own format: written without compression, so the frames come closer together)
    tmp = out / "frame.ppm"
    best = first = None
    previous = None
    while time.time() - t0 < args.seconds:
        t = time.time() - t0
        q.cmd("screendump", filename=str(tmp.resolve()))
        shot = Image.open(tmp).convert("RGB")
        small = shot.resize(THUMB)
        if previous is not None and small.tobytes() == previous:
            time.sleep(args.interval)
            continue
        previous = small.tobytes()
        thumbs.append(small)
        d = deltas(shot, board, cache) if shot.width >= 640 and shot.height >= 480 else {}
        worst = max(d.values()) if d else 255.0
        kept = ""
        if worst <= args.tol and first is None:
            first = (t, worst)
            shot.save(out / "first-match.png")
            kept = "first-match.png"
        if best is None or worst < best[1]:
            best = (t, worst, d)
            shot.save(out / "best.png")
            kept = (kept + " best.png").strip()
        shot.save(out / "last.png")
        rows.append(f"{t:.2f}\t{shot.width}x{shot.height}\t{worst:.1f}\t{kept}")
        time.sleep(max(0.0, args.interval - (time.time() - t0 - t)))
    tmp.unlink(missing_ok=True)
    (out / "frames.tsv").write_text("seconds\tsize\tlargest delta\tkept\n" + "\n".join(rows) + "\n")
    sheet(thumbs, out / "sheet.png")
    matching = sum(1 for r in rows if float(r.split("\t")[2]) <= args.tol)
    print(f"frames: {len(rows)} distinct in {args.seconds:g} s after the reset;"
          f" {matching} within the tolerance")
    if best:
        for name, delta in best[2].items():
            print(f"  best frame ({best[0]:.1f} s): {name:11} delta {delta:5.1f}")
    if first:
        print(f"  first match at {first[0]:.1f} s")
    worst_best = best[1] if best else 255.0
    if args.expect == "match":
        ok = first is not None
        print(f"{'match' if ok else 'NO MATCH'}: closest frame's largest delta {worst_best:.1f}"
              f" (tolerance {args.tol:g})")
    else:
        ok = worst_best > 3 * args.tol
        print(f"{'differs' if ok else 'TOO CLOSE'}: closest frame's largest delta {worst_best:.1f}"
              f" (needs more than {3 * args.tol:g})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
