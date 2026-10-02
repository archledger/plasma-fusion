#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the Plasma Fusion Plymouth theme (script plugin) from design/boards/Splash.dc.html, with
the disk unlock form of design/boards/Boot.dc.html.

    gen_plymouth.py OUTDIR [--meta FILE]

OUTDIR receives the finished theme directory contents (plasma-fusion.plymouth,
plasma-fusion.script, the PNG images) and greeting/, which tools/system/plymouth-install.sh uses
to draw the owner's name into the greeting on the target machine (it is not copied into the
installed theme or the initramfs); --meta writes the layout tables as JSON for the offline
preview (generators/plymouth/tests/preview.py). Nothing else is written.

Plymouth draws the boot splash before any font is guaranteed to exist in the initramfs, so every
text is drawn here (Manrope and Space Grotesk, the static per-weight files in fonts/):

  * fixed texts (the headings, the unlock prompts, "Starting up", "Esc shows boot messages",
    "Caps Lock is on") as ready images, shaped with HarfBuzz through Qt;
  * the greeting with generators/plymouth/greeting.py (Pillow): "Welcome back" here, the
    owner's name at install time;
  * texts only known at boot (the disk name taken from systemd's prompt, other prompts,
    messages, a typed answer, the keyboard layout label) from glyph atlases: every glyph of the
    character set in two horizontal sub-pixel phases, plus advance and kerning tables that the
    script uses to place one sprite per glyph.

The board is 1440x900 logical px. Plymouth works in device px, so everything is rendered for a
set of scale factors and the script picks the one that fits the screen (1920x1200 uses 4/3, the
same factor as the Plasma session on the ThinkPad X13). Positions that are not whole device
pixels are baked into the images, so the result matches a full-frame rendering of the board.
The blurred wallpaper is one 1920x1200 image (the log-in splash's own, from
generators/look-and-feel/splash_background.py) that the script scales to cover the screen.

Needs PySide6 (QtGui, QtSvg), Pillow (with libraqm) and NumPy; runs offscreen.
"""
import argparse
import io
import json
import math
import os
import shutil
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from PySide6.QtCore import QByteArray, QPointF, QRectF  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QGlyphRun, QGuiApplication,  # noqa: E402
                           QImage, QPainter, QRawFont, QTextLayout)
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PKG = os.path.join(ROOT, "packages", "plymouth")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "generators", "look-and-feel"))
import greeting  # noqa: E402
import splash_background  # noqa: E402

# (family key, CSS weight) -> static font file. "manrope" is the UI face, "grotesk" the display
# face of the greeting and the headings.
FONT_FILES = {
    ("manrope", 400): "fonts/manrope/static/Manrope-Regular.ttf",
    ("manrope", 700): "fonts/manrope/static/Manrope-Bold.ttf",
    ("manrope", 800): "fonts/manrope/static/Manrope-ExtraBold.ttf",
    ("grotesk", 600): "fonts/spacegrotesk/static/SpaceGrotesk-SemiBold.ttf",
}
FAMILY = {"manrope": "Manrope", "grotesk": "Space Grotesk"}
GREETING_FONT = FONT_FILES[("grotesk", 600)]
GREETING_LICENSE = "fonts/spacegrotesk/OFL.txt"

THEME = "plasma-fusion"
BACKGROUND = "background.png"
BG_SIZE = (1920, 1200)

# Scale factors (id, factor). The script takes the largest one not above min(W/1440, H/900)
# + 0.06, and never less than 1.
SCALES = [("100", 1.0), ("125", 1.25), ("133", 4 / 3), ("150", 1.5), ("175", 1.75),
          ("200", 2.0), ("250", 2.5)]

BOARD_W, BOARD_H = 1440, 900

# Board colours (Splash.dc.html, Boot.dc.html).
C_TEXT = "#e8ebf4"
C_SECONDARY = "#8f98b3"     # Splash: status line and the "Plasma Fusion" mark
C_PROMPT = "#a3abc2"        # Boot: the unlock prompt
C_HINT = "#6f7892"          # Boot: drive caption; here the "Esc" hint (see docs, deviations)
C_ACCENT = "#5b9dff"
C_ORANGE = "#f2a65a"
C_TEAL = "#3cc4b0"
C_FIELD = "#111522"
C_BUTTON = "#2f6fdf"

# Vertical metrics (hhea): Manrope ascender 2132, descender 600 of 2000 units; Space Grotesk 984,
# 292 of 1000.
METRICS = {"manrope": (1.066, 0.300), "grotesk": (0.984, 0.292)}


def css_ascent(size, family="manrope"):
    """Ascent of a CSS line box with line-height normal, rounded like Chrome does at 1x."""
    return round(size * METRICS[family][0])


def css_line(size, family="manrope"):
    asc, desc = METRICS[family]
    return round(size * asc) + round(size * desc)


# Text roles drawn from glyph atlases: (pixel size, weight, colour, phases, charset).
ASCII = [chr(c) for c in range(0x20, 0x7F)]
EXTRA = list("·…–—‘’“”") + [chr(c) for c in range(0xC0, 0x100)]
FULL_SET = ASCII + EXTRA
CHIP_SET = [" "] + [chr(c) for c in range(ord("A"), ord("Z") + 1)] + list("0123456789-+_()")

# ---------------------------------------------------------------- layout (board px)
# "frame" = relative to the 1440x900 board frame centred on the screen; "bottom" = y relative to
# the bottom edge of the screen (negative), x relative to the left or right edge.

# Emblem (Splash board): two orbit rings and three dots around the emblem centre, the logo.
EMBLEM = (720, 380)
RINGS = [(120, 0.06), (190, 0.04)]             # radius, white opacity; 1.5 px stroke
LOGO_R = 46
# The board blends the logo "screen" over the dark background; these are the blended colours
# (the log-in splash, Splash.qml, uses the same).
LOGO_CIRCLES = [(720, 352, "#63a3ff"), (689, 406, "#f3ac6f"), (751, 406, "#46c8ba")]
ORBIT_R = 190
# Dots: start angle clockwise from 12 o'clock (the board positions), diameter, colour.
ORBIT_DOTS = [(0.0, 10, C_ACCENT), (70.1, 8, C_ORANGE), (240.0, 8, C_TEAL)]
ORBIT_PERIOD = 16.0                             # seconds per turn (as the log-in splash)
DOT_PHASES = 2                                  # sub-pixel phases per axis

# The column under the emblem: greeting (Space Grotesk 30/600), 18 px, bar 260x4, 18 px, status
# (13 px Manrope, #8f98b3).
COLUMN_TOP = 610
GREETING_SIZE = 30
GREETING_TOP = COLUMN_TOP
BAR = (590, GREETING_TOP + css_line(GREETING_SIZE, "grotesk") + 18, 260, 4)
STATUS_SIZE = 13
STATUS_TOP = BAR[1] + BAR[3] + 18
NOTE_TOP = STATUS_TOP + css_line(STATUS_SIZE) + 6     # update mode: "Do not turn off ..."
COLUMN_MAXW = 1040                                    # widest text line

# Unlock form (Boot board, moved under the emblem): prompt 14 px, 14 px, field, 14 px, caption.
CENTRE_X = 720
PROMPT_TOP = COLUMN_TOP
PILL = (540, PROMPT_TOP + css_line(14) + 14, 360, 46)
HINT_TOP = PILL[1] + PILL[3] + 14                     # 13 px caption (status style)
MESSAGE_TOP = HINT_TOP + css_line(STATUS_SIZE) + 20   # messages under the form
PILL_INNER = 1.5                                      # border width, inside the box
LOCK = (PILL[0] + PILL_INNER + 16, None, 17)          # x, (centred), size
# The board render (Chrome) draws the lock icon and the bullets about 1 px lower than the exact
# CSS geometry (it snaps the icon box and the text baseline to whole pixels); follow the render.
FIELD_NUDGE = 1
BUTTON = 34
BULLET_SIZE = 15
BULLET_SPACING = 0.3 * BULLET_SIZE                    # letter-spacing: 0.3em

# Bottom corners. The Splash board's mark: 18 px logo, 10 px gap, "Plasma Fusion" 13 px / 700,
# 40 px from the left, 32 px from the bottom. While a prompt is shown the Boot board's "Esc
# shows boot messages" takes its place and the keyboard layout sits in the right corner, both
# on the mark's centre line and 40 px from the edges.
MARK_X = 40
MARK_BOTTOM = -32
MARK_ICON = 18
MARK_GAP = 10
MARK_ROW = max(MARK_ICON, css_line(13))
CORNER_CENTRE = MARK_BOTTOM - MARK_ROW / 2           # centre line of the corner items
CORNER_SIZE = 11.5
KBD_ICON = 14
KBD_GAP = 6

STATIC_TEXTS = {
    # key: text (14 px prompt line)
    "t-passphrase": "Enter the passphrase to unlock this disk",
    "t-recovery": "Enter the recovery key to unlock this disk",
    "t-either": "Enter the passphrase or recovery key to unlock this disk",
    "t-verify": "Enter the passphrase again to confirm",
    "t-pin": "Enter the PIN to unlock this disk",
    "t-answer": "Type your answer and press Enter",
}
# 13 px lines: (text, colour, line top)
STATUS_TEXTS = {
    "t-starting": ("Starting up", C_SECONDARY, STATUS_TOP),
    "t-encrypted": ("Encrypted disk", C_SECONDARY, HINT_TOP),
    "t-capslock": ("Caps Lock is on", C_ORANGE, HINT_TOP),
    # systemd-cryptsetup asks the same prompt again after a wrong answer.
    "t-wrong": ("Wrong passphrase, try again", C_ORANGE, HINT_TOP),
    "t-wrong-recovery": ("Wrong recovery key, try again", C_ORANGE, HINT_TOP),
    "t-wrong-pin": ("Wrong PIN, try again", C_ORANGE, HINT_TOP),
    "t-dontoff": ("Do not turn off your computer", C_SECONDARY, NOTE_TOP),
}
# Headings in the greeting's place (Space Grotesk 30 px / 600).
HEADINGS = {
    "h-shutdown": "Shutting down…",
    "h-reboot": "Restarting…",
    "h-updates": "Installing updates",
    "h-upgrade": "Upgrading the system",
    "h-firmware": "Updating the firmware",
    "h-reset": "Resetting the system",
}
GREETING = dict(text="Welcome back", with_name="Welcome back, {name}")

ROLES = {
    # Prompts that are not systemd's, messages while a prompt is shown, the typed answer of a
    # plymouth question: as the board's prompt line.
    "prompt": dict(size=14, weight=400, color=C_PROMPT, phases=2, charset=FULL_SET,
                   under=("frame", PROMPT_TOP, css_line(14))),
    # The disk name under the field, boot messages on the status line, the update percentage.
    "status": dict(size=STATUS_SIZE, weight=400, color=C_SECONDARY, phases=2, charset=FULL_SET,
                   under=("frame", STATUS_TOP, css_line(STATUS_SIZE))),
    # Keyboard layout label, bottom right ("EN").
    "chip": dict(size=CORNER_SIZE, weight=800, color=C_SECONDARY, phases=1, charset=CHIP_SET,
                 under=("corner", None, None)),
}


# --------------------------------------------------------------------------- helpers

def to_pil(img):
    rgba = img.convertToFormat(QImage.Format_RGBA8888)
    data = bytes(rgba.constBits())[: rgba.sizeInBytes()]
    return Image.frombuffer("RGBA", (rgba.width(), rgba.height()), data, "raw", "RGBA",
                            rgba.bytesPerLine(), 1).copy()


def compensate_crop(pil, under=(0, 0, 0)):
    """Prepare an image that the script only shows through Image.Crop.

    Crop copies into a new, fully transparent pixel buffer, and libply blends into a
    non-opaque destination with the source colour multiplied by its alpha once more
    (blend_two_pixel_values in ply-pixel-buffer.c): translucent pixels (glyph edges) come out
    darker by their own alpha. Store the colour divided by that alpha instead; where the result
    would exceed 255, raise the pixel's alpha just enough and add the background colour `under`
    that the extra alpha hides (the smallest alpha2 with T + B (alpha2 - alpha) / 255 <=
    alpha2^2 / 255 in every channel, T the wanted premultiplied colour, B `under`). Over a
    background of colour `under` the crop then shows exactly the intended colour; over a
    slightly different one the raised edge pixels are off by a fraction of the difference."""
    a = np.asarray(pil, dtype=np.float64)
    alpha = a[..., 3]
    target = a[..., :3] * alpha[..., None] / 255.0          # wanted premultiplied colour
    b = np.asarray(under, dtype=np.float64)
    disc = b * b + 4.0 * (255.0 * target - b * alpha[..., None])
    root = (b + np.sqrt(np.maximum(disc, 0.0))) / 2.0
    need = np.ceil(root.max(axis=-1) - 1e-9)
    alpha2 = np.clip(np.maximum(alpha, need), 0, 255)
    after = target + b * (alpha2 - alpha)[..., None] / 255.0  # premultiplied colour after the crop
    safe = np.where(alpha2 > 0, alpha2, 1.0)
    colour = np.clip(np.ceil(after * 255.0 * 255.0 / (safe[..., None] ** 2) - 1e-6), 0, 255)
    colour[alpha2 == 0] = 0
    out = np.dstack([colour, alpha2]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def save_png(pil, path):
    """Write a plain 8-bit RGBA PNG (what libply's loader expects)."""
    buf = io.BytesIO()
    pil.convert("RGBA").save(buf, "PNG", optimize=True)
    with open(path, "wb") as f:
        f.write(buf.getvalue())


def to_png(img, path, under=None):
    pil = to_pil(img)
    if under is not None:
        pil = compensate_crop(pil, under)
    save_png(pil, path)


def blank(w, h):
    img = QImage(max(1, w), max(1, h), QImage.Format_ARGB32_Premultiplied)
    img.fill(0)
    return img


def render_svg(svg, dev_x, dev_y, dev_w, dev_h, pad=1):
    """Render an SVG so that its viewBox covers the device rectangle (dev_x, dev_y, dev_w,
    dev_h), given relative to an integer anchor. Returns (image, x, y): the image and the
    integer offset of its top-left corner from the anchor."""
    x0 = math.floor(dev_x) - pad
    y0 = math.floor(dev_y) - pad
    x1 = math.ceil(dev_x + dev_w) + pad
    y1 = math.ceil(dev_y + dev_h) + pad
    img = blank(x1 - x0, y1 - y0)
    renderer = QSvgRenderer(QByteArray(svg.encode()))
    if not renderer.isValid():
        raise SystemExit("gen_plymouth: invalid SVG:\n" + svg)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.SmoothPixmapTransform)
    renderer.render(p, QRectF(dev_x - x0, dev_y - y0, dev_w, dev_h))
    p.end()
    return img, x0, y0


def svg_doc(vw, vh, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{vw}" height="{vh}" '
            f'viewBox="0 0 {vw} {vh}">{body}</svg>')


def icon(path_d, colour, size, x, y):
    """A board icon: 24-unit viewBox, stroke 1.8, round caps/joins, drawn at size px."""
    k = size / 24
    return (f'<g transform="translate({x:.4f},{y:.4f}) scale({k:.6f})" fill="none" '
            f'stroke="{colour}" stroke-width="1.8" stroke-linecap="round" '
            f'stroke-linejoin="round"><path d="{path_d}"/></g>')


LOCK_D = "M7 11h10a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2zM8 11V8a4 4 0 0 1 8 0v3"
ARROW_D = "M5 12h14M13 6l6 6-6 6"
KBD_D = "M3 7h18v10H3zM7 11h.01M11 11h.01M15 11h.01M8 14h8"


class Fonts:
    def __init__(self):
        for path in sorted(set(FONT_FILES.values())):
            if QFontDatabase.addApplicationFont(os.path.join(ROOT, path)) < 0:
                raise SystemExit(f"gen_plymouth: cannot load {path}")
        self._raw = {}
        self._shape_cache = {}

    def raw(self, weight, px, family="manrope"):
        key = (family, weight, round(px, 5))
        if key not in self._raw:
            r = QRawFont(os.path.join(ROOT, FONT_FILES[(family, weight)]), px, QFont.PreferVerticalHinting)
            if not r.isValid():
                raise SystemExit("gen_plymouth: QRawFont failed")
            self._raw[key] = r
        return self._raw[key]

    def shape(self, text, weight, family="manrope"):
        """HarfBuzz shaping through QTextLayout at 1000 px: (glyph ids, x positions, advance),
        all in 1/1000 em."""
        key = (text, weight, family)
        if key in self._shape_cache:
            return self._shape_cache[key]
        font = QFont(FAMILY[family])
        font.setPixelSize(1000)
        font.setWeight(QFont.Weight(weight))
        font.setHintingPreference(QFont.PreferNoHinting)
        font.setKerning(True)
        layout = QTextLayout(text, font)
        layout.beginLayout()
        line = layout.createLine()
        line.setLineWidth(1e7)
        layout.endLayout()
        ids, xs = [], []
        want = os.path.splitext(os.path.basename(FONT_FILES[(family, weight)]))[0].split("-")[1]
        for run in layout.glyphRuns():
            raw = run.rawFont()
            if raw.familyName() != FAMILY[family] or raw.styleName().replace(" ", "") != want:
                raise SystemExit(f"gen_plymouth: shaping used {raw.familyName()} {raw.styleName()}")
            ids += list(run.glyphIndexes())
            xs += [p.x() for p in run.positions()]
        result = (ids, xs, line.naturalTextWidth())
        self._shape_cache[key] = result
        return result


def text_image(fonts, text, size, weight, colour, s, pen_x, baseline, pad=2, family="manrope"):
    """Draw `text` with its pen starting at device x pen_x (float) and its baseline at device y
    `baseline` (integer), both relative to an anchor. Returns (image, x, y, advance)."""
    ids, xs, adv = fonts.shape(text, weight, family)
    px = size * s
    raw = fonts.raw(weight, px, family)
    asc, desc = METRICS[family]
    k = px / 1000
    boxes = [raw.boundingRect(g) for g in ids]
    left = min([b.left() + x * k for b, x in zip(boxes, xs)] + [0])
    right = max([b.right() + x * k for b, x in zip(boxes, xs)] + [adv * k])
    top = min([b.top() for b in boxes] + [-px * asc])
    bottom = max([b.bottom() for b in boxes] + [px * desc])
    x0 = math.floor(pen_x + left) - pad
    x1 = math.ceil(pen_x + right) + pad
    y0 = math.floor(baseline + top) - pad
    y1 = math.ceil(baseline + bottom) + pad
    img = blank(x1 - x0, y1 - y0)
    run = QGlyphRun()
    run.setRawFont(raw)
    run.setGlyphIndexes(ids)
    run.setPositions([QPointF(x * k, 0) for x in xs])
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.TextAntialiasing)
    p.setPen(QColor(colour))
    p.drawGlyphRun(QPointF(pen_x - x0, baseline - y0), run)
    p.end()
    return img, x0, y0, adv * k


def centred_text(fonts, text, size, weight, colour, s, centre_x, baseline, family="manrope"):
    adv = fonts.shape(text, weight, family)[2] * size * s / 1000
    return text_image(fonts, text, size, weight, colour, s, centre_x - adv / 2, baseline, family=family)


def coverage(path):
    """Code point ranges the font has glyphs for (Basic Multilingual Plane)."""
    raw = QRawFont(path, 100)
    ranges, start = [], None
    for c in range(0x20, 0x10000):
        ok = 0xD800 > c or c > 0xDFFF
        ok = ok and raw.supportsCharacter(c)
        if ok and start is None:
            start = c
        elif not ok and start is not None:
            ranges.append([start, c - 1])
            start = None
    if start is not None:
        ranges.append([start, 0xFFFF])
    return ranges


# --------------------------------------------------------------------------- background

class Background:
    """The log-in splash's blurred wallpaper (1920x1200), and its colour under a board area."""

    def __init__(self):
        self.img = splash_background.render(*BG_SIZE)
        self.px = np.asarray(self.img.convert("RGB"), dtype=np.float64)
        k = BG_SIZE[0] / BOARD_W
        # The sun's centre after the board's 1.08 scale about the centre, for portrait crops.
        self.sun_x = (BOARD_W / 2 + (splash_background.SUN[1][0] - BOARD_W / 2) * splash_background.SCALE) * k

    def under(self, x0, x1, y0, y1):
        """Mean colour of the board rectangle [x0, x1) x [y0, y1) (board px, 16:10 screen)."""
        k = BG_SIZE[0] / BOARD_W
        a = self.px[int(y0 * k):max(int(y0 * k) + 1, int(y1 * k)), int(x0 * k):max(int(x0 * k) + 1, int(x1 * k))]
        return tuple(float(v) for v in a.reshape(-1, 3).mean(axis=0))


# --------------------------------------------------------------------------- atlases

def build_atlas(fonts, role, s):
    spec = ROLES[role]
    px = spec["size"] * s
    raw = fonts.raw(spec["weight"], px)
    chars = spec["charset"]
    nph = spec["phases"]
    pad = 1
    boxes = []
    for ch in chars:
        g = raw.glyphIndexesForString(ch)
        if len(g) != 1 or g[0] == 0:
            raise SystemExit(f"gen_plymouth: Manrope has no glyph for {ch!r}")
        boxes.append((g[0], raw.boundingRect(g[0])))
    min_left = min(b.left() for _, b in boxes)
    max_right = max(b.right() for _, b in boxes)
    min_top = min(min(b.top() for _, b in boxes), -px * METRICS["manrope"][0])
    max_bottom = max(max(b.bottom() for _, b in boxes), px * METRICS["manrope"][1])
    origin_x = pad + max(0, math.ceil(-min_left))
    cell_w = origin_x + math.ceil(max_right) + 1 + pad
    base_row = pad + math.ceil(-min_top)
    cell_h = base_row + math.ceil(max_bottom) + pad
    img = blank(cell_w * len(chars), cell_h * nph)
    p = QPainter(img)
    p.setRenderHint(QPainter.Antialiasing)
    p.setRenderHint(QPainter.TextAntialiasing)
    p.setPen(QColor(spec["color"]))
    for i, (g, _) in enumerate(boxes):
        for ph in range(nph):
            run = QGlyphRun()
            run.setRawFont(raw)
            run.setGlyphIndexes([g])
            run.setPositions([QPointF(0, 0)])
            p.drawGlyphRun(QPointF(i * cell_w + origin_x + ph / nph, ph * cell_h + base_row), run)
    p.end()
    return img, dict(cellw=cell_w, cellh=cell_h, ox=origin_x, base=base_row, phases=nph)


def advances_em(fonts, weight, chars):
    """Advance of every character in 1/1000 em (design metrics)."""
    raw = fonts.raw(weight, 1000)
    out = {}
    for ch in chars:
        g = raw.glyphIndexesForString(ch)
        a = raw.advancesForGlyphIndexes(g, QRawFont.UseDesignMetrics)
        out[ch] = round(a[0].x(), 2)
    return out


def kerning_em(fonts, weight, chars, adv, threshold=20):
    """Pair kerning (GPOS, through HarfBuzz) in 1/1000 em, pairs of at least `threshold`."""
    out = {}
    for a in chars:
        for b in chars:
            if a == " " or b == " ":
                continue
            ids, xs, total = fonts.shape(a + b, weight)
            if len(ids) != 2:
                continue  # ligature or composition: leave unkerned
            k = total - adv[a] - adv[b]
            if abs(k) >= threshold:
                out[a + b] = round(k, 1)
    return out


# --------------------------------------------------------------------------- script data

def sq(s):
    """Plymouth script string literal. The scanner keeps any byte except newline and NUL;
    only backslash and double quote need escaping."""
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def num(v):
    if isinstance(v, int) or float(v).is_integer():
        return str(int(v))
    return f"{v:.4f}".rstrip("0").rstrip(".")


def greeting_box(s):
    """The greeting image of scale s: box (x, y, w, h) relative to the frame, pen centre x and
    baseline relative to the box, widest text."""
    half = COLUMN_MAXW / 2
    x0 = math.floor((CENTRE_X - half) * s)
    x1 = math.ceil((CENTRE_X + half) * s)
    y0 = math.floor((GREETING_TOP - 8) * s)
    y1 = math.ceil((GREETING_TOP + css_line(GREETING_SIZE, "grotesk") + 8) * s)
    base = round((GREETING_TOP + css_ascent(GREETING_SIZE, "grotesk")) * s)
    return dict(x=x0, y=y0, w=x1 - x0, h=y1 - y0, cx=CENTRE_X * s - x0, base=base - y0,
                maxw=(COLUMN_MAXW - 40) * s)


def build(out, meta_path=None):
    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])  # noqa: F841
    fonts = Fonts()
    bg = Background()
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png") or f in (THEME + ".plymouth", THEME + ".script"):
            os.remove(os.path.join(out, f))
    gdir = os.path.join(out, "greeting")
    shutil.rmtree(gdir, ignore_errors=True)
    os.makedirs(gdir)

    data = []      # script lines
    meta = {"scales": [], "layout": {}, "atlas": {}, "roles": {}, "board": {
        "emblem": EMBLEM, "pill": PILL, "prompt_top": PROMPT_TOP, "hint_top": HINT_TOP,
        "bar": BAR, "status_top": STATUS_TOP, "greeting_top": GREETING_TOP}}

    def emit(line):
        data.append(line)

    emit("# ---- generated by generators/plymouth/gen_plymouth.py; do not edit ----")
    emit(f"global.pf.nscales = {len(SCALES)};")
    for i, (sid, s) in enumerate(SCALES):
        emit(f"global.pf.scale[{i}] = {num(s)}; global.pf.sid[{i}] = {sq(sid)};")

    # Background: one image for every scale, scaled by the script to cover the screen.
    save_png(bg.img.convert("RGBA"), os.path.join(out, BACKGROUND))
    emit(f"global.pf.bg.file = {sq(BACKGROUND)}; global.pf.bg.w = {BG_SIZE[0]}; global.pf.bg.h = {BG_SIZE[1]}; "
         f"global.pf.bg.sunx = {num(round(bg.sun_x, 2))};")
    meta["bg"] = dict(file=BACKGROUND, w=BG_SIZE[0], h=BG_SIZE[1], sunx=round(bg.sun_x, 2))

    # Orbit.
    emit(f"global.pf.orbit.period = {num(ORBIT_PERIOD)};")
    for i, (angle, _, _) in enumerate(ORBIT_DOTS):
        emit(f"global.pf.orbit.angle[{i}] = {num(angle)};")
    meta["orbit"] = dict(period=ORBIT_PERIOD, angles=[a for a, _, _ in ORBIT_DOTS])

    # Glyph tables (scale independent).
    charset_index = {}
    for role, spec in ROLES.items():
        charset_index[role] = "chip" if spec["charset"] is CHIP_SET else "full"
    emit("global.pf.charset = [];")
    for key, chars in (("full", FULL_SET), ("chip", CHIP_SET)):
        for i, ch in enumerate(chars):
            emit(f"pf.charset[{sq(key)}][{sq(ch)}] = {i + 1};")
    emit("global.pf.adv = []; global.pf.kern = [];")
    for weight, chars in ((400, FULL_SET), (800, CHIP_SET)):
        adv = advances_em(fonts, weight, chars)
        for ch in chars:
            emit(f"pf.adv[{weight}][{sq(ch)}] = {num(adv[ch])};")
        kchars = [c for c in chars if c in ASCII]
        kern = kerning_em(fonts, weight, kchars, adv)
        for pair in sorted(kern):
            emit(f"pf.kern[{weight}][{sq(pair)}] = {num(kern[pair])};")
        meta.setdefault("adv", {})[str(weight)] = adv
        meta.setdefault("kern", {})[str(weight)] = kern
    for role, spec in ROLES.items():
        emit(f"pf.role[{sq(role)}].size = {num(spec['size'])}; pf.role[{sq(role)}].weight = {spec['weight']}; "
             f"pf.role[{sq(role)}].charset = {sq(charset_index[role])};")
        meta["roles"][role] = dict(size=spec["size"], weight=spec["weight"], charset=charset_index[role])
    meta["charset"] = {"full": FULL_SET, "chip": CHIP_SET}

    # Background colour under each atlas role's lines (for the crop compensation).
    unders = {}
    for role, spec in ROLES.items():
        kind, top_y, height = spec["under"]
        if kind == "frame":
            unders[role] = bg.under(CENTRE_X - 180, CENTRE_X + 180, top_y, top_y + height)
        else:
            unders[role] = bg.under(BOARD_W - 40 - 60, BOARD_W - 40,
                                    BOARD_H + CORNER_CENTRE - 8, BOARD_H + CORNER_CENTRE + 8)
    meta["under"] = unders

    # Greeting layout for greeting.py (here and on the target).
    glayout = dict(font=os.path.basename(GREETING_FONT), size=GREETING_SIZE, colour=C_TEXT,
                   text=GREETING["text"], with_name=GREETING["with_name"],
                   coverage=coverage(os.path.join(ROOT, GREETING_FONT)), scales=[])

    # Per-scale images and offsets.
    for sid, s in SCALES:
        L = {}
        files = []

        def put(name, img, under=None):
            fn = f"{sid}-{name}.png"
            if isinstance(img, Image.Image):
                save_png(img, os.path.join(out, fn))
            else:
                to_png(img, os.path.join(out, fn), under)
            files.append(fn)
            return fn

        def place(key, name, img, x, y):
            L[key] = dict(file=put(name, img), x=x, y=y, w=img.width(), h=img.height())

        ex, ey = EMBLEM

        # Orbit rings: 1.5 px white strokes at 6 % and 4 %.
        rmax = max(r for r, _ in RINGS) + 1
        body = "".join(f'<circle cx="{rmax}" cy="{rmax}" r="{r}" fill="none" stroke="#ffffff" '
                       f'stroke-opacity="{o}" stroke-width="1.5"/>' for r, o in RINGS)
        img, x, y = render_svg(svg_doc(2 * rmax, 2 * rmax, body), (ex - rmax) * s, (ey - rmax) * s,
                               2 * rmax * s, 2 * rmax * s)
        place("rings", "rings", img, x, y)

        # Logo: three opaque circles, blue under orange under teal.
        lx0 = min(cx for cx, _, _ in LOGO_CIRCLES) - LOGO_R
        ly0 = min(cy for _, cy, _ in LOGO_CIRCLES) - LOGO_R
        lx1 = max(cx for cx, _, _ in LOGO_CIRCLES) + LOGO_R
        ly1 = max(cy for _, cy, _ in LOGO_CIRCLES) + LOGO_R
        body = "".join(f'<circle cx="{cx - lx0}" cy="{cy - ly0}" r="{LOGO_R}" fill="{c}"/>'
                       for cx, cy, c in LOGO_CIRCLES)
        img, x, y = render_svg(svg_doc(lx1 - lx0, ly1 - ly0, body), lx0 * s, ly0 * s,
                               (lx1 - lx0) * s, (ly1 - ly0) * s)
        place("logo", "logo", img, x, y)

        # Orbiting dots: each dot in DOT_PHASES x DOT_PHASES sub-pixel positions (separate
        # images, so no crop is involved), drawn with its box's top-left corner at
        # (pad + px / N, pad + py / N).
        L["orbit"] = dict(cx=ex * s, cy=ey * s, r=ORBIT_R * s, phases=DOT_PHASES)
        for i, (_, d, colour) in enumerate(ORBIT_DOTS):
            dd = d * s
            pad = 1
            size = math.ceil(dd + 1) + 2 * pad
            entry = dict(d=dd, pad=pad)
            for py in range(DOT_PHASES):
                for px in range(DOT_PHASES):
                    img = blank(size, size)
                    renderer = QSvgRenderer(QByteArray(svg_doc(d, d, f'<circle cx="{d / 2}" cy="{d / 2}" r="{d / 2}" '
                                                                     f'fill="{colour}"/>').encode()))
                    p = QPainter(img)
                    p.setRenderHint(QPainter.Antialiasing)
                    renderer.render(p, QRectF(pad + px / DOT_PHASES, pad + py / DOT_PHASES, dd, dd))
                    p.end()
                    entry[f"file{px}{py}"] = put(f"dot{i}-{px}{py}", img)
            L[f"dot{i}"] = entry

        # Greeting: the generic text here; plymouth-install.sh draws the name on the target.
        gb = greeting_box(s)
        L["greeting"] = dict(file=f"{sid}-greeting.png", x=gb["x"], y=gb["y"], w=gb["w"], h=gb["h"])
        glayout["scales"].append(dict(sid=sid, s=s, file=f"{sid}-greeting.png", w=gb["w"], h=gb["h"],
                                      cx=gb["cx"], base=gb["base"], maxw=gb["maxw"]))
        files.append(f"{sid}-greeting.png")

        # Headings in the greeting's place.
        cx = CENTRE_X * s
        gbase = gb["y"] + gb["base"]
        for key, text in HEADINGS.items():
            img, x, y, _ = centred_text(fonts, text, GREETING_SIZE, 600, C_TEXT, s, cx, gbase, family="grotesk")
            place(key, key, img, x, y)

        # Progress bar (boot progress, system updates): the track, and the fill in three parts
        # so that no crop is needed: the rounded head (fixed), a one-pixel column that the
        # script stretches with Image.Scale, the rounded tail (moves with the end).
        bx, by, bw, bh = BAR
        X0, Y0, W, H = bx * s, by * s, bw * s, bh * s
        R = H / 2
        img, x, y = render_svg(svg_doc(bw, bh, f'<rect width="{bw}" height="{bh}" rx="{bh / 2}" '
                                               f'fill="#ffffff" fill-opacity="0.1"/>'), X0, Y0, W, H, pad=0)
        place("track", "bar-track", img, x, y)
        fill_svg = svg_doc(bw, bh, f'<rect width="{bw}" height="{bh}" rx="{bh / 2}" fill="{C_ACCENT}"/>')
        full, fx0, fy0 = render_svg(fill_svg, X0, Y0, W, H, pad=0)
        full = to_pil(full)
        hx = math.ceil(X0 + R)                          # first column of the straight part
        head = full.crop((0, 0, hx - fx0, full.height))
        column = full.crop((hx - fx0, 0, hx - fx0 + 1, full.height))
        # The tail: the same bar ending exactly on a pixel boundary (at x = 0 here).
        tail_w = math.ceil(R) + 1
        endimg, ex0, _ = render_svg(fill_svg, -W, Y0, W, H, pad=0)
        endimg = to_pil(endimg)
        tail = endimg.crop((endimg.width - tail_w, 0, endimg.width, endimg.height))
        L["bar"] = dict(x0=X0, w=W, left=fx0, y=fy0, head=hx - fx0, tail=tail_w,
                        minw=(hx - fx0) + tail_w, end=math.floor(X0 + W + 0.5))
        L["head"] = dict(file=put("bar-head", head), x=fx0, y=fy0)
        L["body"] = dict(file=put("bar-body", column), x=hx, y=fy0, h=column.height)
        L["tail"] = dict(file=put("bar-tail", tail), y=fy0)

        # Status line, its fixed texts and the other 13 px lines.
        status_base = round((STATUS_TOP + css_ascent(STATUS_SIZE)) * s)
        hint_base = round((HINT_TOP + css_ascent(STATUS_SIZE)) * s)
        for key, (text, colour, top_y) in STATUS_TEXTS.items():
            base = round((top_y + css_ascent(STATUS_SIZE)) * s)
            img, x, y, _ = centred_text(fonts, text, STATUS_SIZE, 400, colour, s, cx, base)
            place(key, key, img, x, y)

        # Password field (focused look of the board) and the same field without the lock icon
        # for plymouth questions.
        px_, py_, pw, ph = PILL
        lock_y = PILL_INNER + (ph - 2 * PILL_INNER - LOCK[2]) / 2 + FIELD_NUDGE
        btn_x = pw - PILL_INNER - 6 - BUTTON
        btn_y = PILL_INNER + (ph - 2 * PILL_INNER - BUTTON) / 2
        frame = (f'<rect x="0.75" y="0.75" width="{pw - 1.5}" height="{ph - 1.5}" rx="{(ph - 1.5) / 2}" '
                 f'fill="{C_FIELD}" stroke="{C_ACCENT}" stroke-width="1.5"/>'
                 f'<circle cx="{btn_x + BUTTON / 2}" cy="{btn_y + BUTTON / 2}" r="{BUTTON / 2}" fill="{C_BUTTON}"/>'
                 + icon(ARROW_D, "#ffffff", 16, btn_x + (BUTTON - 16) / 2, btn_y + (BUTTON - 16) / 2))
        lock = icon(LOCK_D, C_PROMPT, LOCK[2], LOCK[0] - px_, lock_y)
        img, x, y = render_svg(svg_doc(pw, ph, frame + lock), px_ * s, py_ * s, pw * s, ph * s)
        place("pill", "pill", img, x, y)
        img, x, y = render_svg(svg_doc(pw, ph, frame), px_ * s, py_ * s, pw * s, ph * s)
        place("pillq", "pill-question", img, x, y)

        # Bullets: Manrope "•" at 15 px with 0.3em letter-spacing, in a 15 px line box that is
        # centred in the field (align-items: center).
        text_x = LOCK[0] + LOCK[2] + 8                  # after the lock icon and the 8 px gap
        line_h = css_line(BULLET_SIZE)
        span_top = py_ + PILL_INNER + (ph - 2 * PILL_INNER - line_h) / 2
        base = round((span_top + css_ascent(BULLET_SIZE) + FIELD_NUDGE) * s)
        adv_bullet = fonts.shape("•", 400)[2] * BULLET_SIZE / 1000
        pitch = (adv_bullet + BULLET_SPACING) * s
        field_end = px_ + btn_x - 8                      # 8 px gap before the button
        # Three sub-pixel phases (pen at +0, +1/3, +2/3 px) with the same image offsets.
        bullet = dict(x0=text_x * s, base=base, pitch=pitch, phases=3,
                      max=int(((field_end - text_x) * s - 4 * s) // pitch))
        for phase in range(3):
            img, x, y, _ = text_image(fonts, "•", BULLET_SIZE, 400, C_TEXT, s, phase / 3, 0, pad=3)
            bullet[f"file{phase}"] = put(f"bullet{phase}", img)
            if phase == 0:
                bullet.update(x=x, y=y)
            elif (x, y) != (bullet["x"], bullet["y"]):
                raise SystemExit("gen_plymouth: bullet phases moved")
        L["bullet"] = bullet
        # Text cursor: 1.5 px wide, 18 px tall, centred on the bullets, where the next bullet
        # would start (letter-spacing included, like a browser's caret).
        caret_h = 18
        img, x, y = render_svg(svg_doc(1.5, caret_h, f'<rect width="1.5" height="{caret_h}" fill="{C_TEXT}"/>'),
                               0, (py_ + ph / 2 + FIELD_NUDGE - caret_h / 2) * s, 1.5 * s, caret_h * s, pad=0)
        L["caret"] = dict(file=put("caret", img), y=y, x0=text_x * s, gap=2 * s,
                          after=-0.75 * s)
        # Question answer: typed text (prompt atlas), starting where the lock would be.
        L["answer"] = dict(x0=(LOCK[0]) * s, base=base, maxw=(field_end - LOCK[0]) * s)

        # Prompt line (14 px), centred.
        prompt_base = round((PROMPT_TOP + css_ascent(14)) * s)
        message_base = round((MESSAGE_TOP + css_ascent(14)) * s)
        for key, text in STATIC_TEXTS.items():
            img, x, y, _ = centred_text(fonts, text, 14, 400, C_PROMPT, s, cx, prompt_base)
            place(key, key, img, x, y)
        L["lines"] = dict(cx=cx, prompt=prompt_base, hint=hint_base, message=message_base,
                          status=status_base, maxw=int(COLUMN_MAXW * s), hintmaxw=int(520 * s))

        # Bottom left: the "Plasma Fusion" mark (logo at 0.9 / 0.9 / 0.85, 13 px / 700 text),
        # or "Esc shows boot messages" while a prompt is shown. Bottom right: the keyboard
        # layout, right-aligned 40 px from the edge.
        row_top = MARK_BOTTOM - MARK_ROW
        centre = row_top + MARK_ROW / 2
        mark_base = round((centre - css_line(13) / 2 + css_ascent(13)) * s)
        tx = MARK_X + MARK_ICON + MARK_GAP
        timg, tx0, ty0, _ = text_image(fonts, "Plasma Fusion", 13, 700, C_SECONDARY, s, tx * s, mark_base)
        k = MARK_ICON / 24
        logo18 = "".join(f'<circle cx="{cx_ * k}" cy="{cy_ * k}" r="{5.5 * k}" fill="{c}" fill-opacity="{o}"/>'
                         for cx_, cy_, c, o in ((12, 8.5, C_ACCENT, 0.9), (8, 15, C_ORANGE, 0.9),
                                                (16, 15, C_TEAL, 0.85)))
        iimg, ix0, iy0 = render_svg(svg_doc(MARK_ICON, MARK_ICON, logo18), MARK_X * s,
                                    (centre - MARK_ICON / 2) * s, MARK_ICON * s, MARK_ICON * s)
        mx0, my0 = min(tx0, ix0), min(ty0, iy0)
        mx1 = max(tx0 + timg.width(), ix0 + iimg.width())
        my1 = max(ty0 + timg.height(), iy0 + iimg.height())
        mark = Image.new("RGBA", (mx1 - mx0, my1 - my0), (0, 0, 0, 0))
        mark.alpha_composite(to_pil(iimg), (ix0 - mx0, iy0 - my0))
        mark.alpha_composite(to_pil(timg), (tx0 - mx0, ty0 - my0))
        L["mark"] = dict(file=put("mark", mark), x=mx0, y=my0)

        corner_line = css_line(CORNER_SIZE)
        corner_base = round((CORNER_CENTRE - corner_line / 2 + css_ascent(CORNER_SIZE)) * s)
        img, x, y, _ = text_image(fonts, "Esc shows boot messages", CORNER_SIZE, 400, C_HINT, s, MARK_X * s,
                                  corner_base)
        place("esc", "esc", img, x, y)
        img, x, y = render_svg(svg_doc(KBD_ICON, KBD_ICON, icon(KBD_D, C_SECONDARY, KBD_ICON, 0, 0)),
                               0, (CORNER_CENTRE - KBD_ICON / 2) * s, KBD_ICON * s, KBD_ICON * s)
        L["kbd"] = dict(file=put("keyboard", img), x=x, y=y, right=-MARK_X * s, base=corner_base,
                        gap=KBD_GAP * s, size=KBD_ICON * s)

        # Glyph atlases.
        atlases = {}
        for role in ROLES:
            img, info = build_atlas(fonts, role, s)
            info["file"] = put(f"atlas-{role}", img, under=unders[role])
            atlases[role] = info

        # Emit.
        emit(f"fun pf_data_{sid}() {{")
        emit("  local.L = [];")
        for key, v in L.items():
            for field, val in v.items():
                # Keys such as "t-passphrase" are not identifiers: always use the index form.
                emit(f"  L[{sq(key)}].{field} = {sq(val) if isinstance(val, str) else num(val)};")
        for role, info in atlases.items():
            for field, val in info.items():
                emit(f"  L.atlas[{sq(role)}].{field} = {sq(val) if isinstance(val, str) else num(val)};")
        emit("  return L;")
        emit("}")
        meta["scales"].append([sid, s])
        meta["layout"][sid] = L
        meta["atlas"][sid] = atlases

    emit("fun pf_data(sid) {")
    for sid, _ in SCALES:
        emit(f"  if (sid == {sq(sid)}) return pf_data_{sid}();")
    emit("  return pf_data_100();")
    emit("}")
    emit("# ---- end of generated data ----")

    # Greeting: the renderer, its layout and font go to greeting/ (used by the installer, not
    # installed); the generic greeting is drawn now.
    with open(os.path.join(gdir, "layout.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(glayout, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    shutil.copyfile(os.path.join(HERE, "greeting.py"), os.path.join(gdir, "greeting.py"))  # run as python3 greeting.py
    shutil.copyfile(os.path.join(ROOT, GREETING_FONT), os.path.join(gdir, glayout["font"]))
    shutil.copyfile(os.path.join(ROOT, GREETING_LICENSE), os.path.join(gdir, "OFL-SpaceGrotesk.txt"))
    for entry in glayout["scales"]:
        img, _ = greeting.render(glayout, os.path.join(gdir, glayout["font"]), entry, "")
        save_png(img, os.path.join(out, entry["file"]))
    meta["greeting"] = glayout

    with open(os.path.join(PKG, THEME + ".script.in"), encoding="utf-8") as f:
        template = f.read()
    marker = "#@PF_DATA@\n"
    if template.count(marker) != 1:
        raise SystemExit("gen_plymouth: the script template needs exactly one #@PF_DATA@ line")
    script = template.replace(marker, "\n".join(data) + "\n")
    with open(os.path.join(out, THEME + ".script"), "w", encoding="utf-8", newline="\n") as f:
        f.write(script)
    with open(os.path.join(PKG, THEME + ".plymouth.in"), encoding="utf-8") as f:
        theme = f.read()
    with open(os.path.join(out, THEME + ".plymouth"), "w", encoding="utf-8", newline="\n") as f:
        f.write(theme)

    if meta_path:
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=1, ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("outdir")
    ap.add_argument("--meta")
    args = ap.parse_args()
    build(os.path.abspath(args.outdir), args.meta)


if __name__ == "__main__":
    main()
