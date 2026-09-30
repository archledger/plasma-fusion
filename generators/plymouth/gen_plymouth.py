#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build the Plasma Fusion Plymouth theme (script plugin) from design/boards/Boot.dc.html.

    gen_plymouth.py OUTDIR [--meta FILE]

OUTDIR receives the finished theme directory contents (plasma-fusion.plymouth,
plasma-fusion.script and the PNG images); --meta writes the layout tables as JSON for the
offline preview (generators/plymouth/tests/preview.py). Nothing else is written.

Plymouth draws the boot splash before any font is guaranteed to exist in the initramfs, so every
text is drawn here with Manrope (the static per-weight files in fonts/manrope/static):

  * fixed texts (the unlock prompt, "Esc shows boot messages", "Caps Lock is on", the update
    titles) as ready images, shaped with HarfBuzz through Qt;
  * texts only known at boot (the disk name taken from systemd's prompt, other prompts, messages,
    a typed answer, the keyboard layout label) from glyph atlases: every glyph of the character
    set in three horizontal sub-pixel phases, plus advance and kerning tables that the script
    uses to place one sprite per glyph.

The board is 1440x900 logical px. Plymouth works in device px, so everything is rendered for a
set of scale factors and the script picks the one that fits the screen (1920x1200 uses 4/3, the
same factor as the Plasma session on the ThinkPad X13). Positions that are not whole device
pixels are baked into the images, so the result matches a full-frame rendering of the board.

Needs PySide6 (QtGui, QtSvg), Pillow and NumPy; runs offscreen.
"""
import argparse
import io
import json
import math
import os
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402
from PySide6.QtCore import QByteArray, QPointF, QRectF  # noqa: E402
from PySide6.QtGui import (QColor, QFont, QFontDatabase, QGlyphRun, QGuiApplication,  # noqa: E402
                           QImage, QPainter, QRawFont, QTextLayout)
from PySide6.QtSvg import QSvgRenderer  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PKG = os.path.join(ROOT, "packages", "plymouth")
FONT_DIR = os.path.join(ROOT, "fonts", "manrope", "static")
FONT_FILES = {400: "Manrope-Regular.ttf", 800: "Manrope-ExtraBold.ttf"}

THEME = "plasma-fusion"

# Scale factors (id, factor). The script takes the largest one not above min(W/1440, H/900)
# + 0.06, and never less than 1.
SCALES = [("100", 1.0), ("125", 1.25), ("133", 4 / 3), ("150", 1.5), ("175", 1.75),
          ("200", 2.0), ("250", 2.5)]

BOARD_W, BOARD_H = 1440, 900

# Board colours (Boot.dc.html).
C_TEXT = "#e8ebf4"
C_PROMPT = "#a3abc2"
C_HINT = "#6f7892"
C_FAINT = "#4a5168"
C_ACCENT = "#5b9dff"
C_ORANGE = "#f2a65a"
C_TEAL = "#3cc4b0"
C_FIELD = "#111522"
C_BUTTON = "#2f6fdf"

# Manrope vertical metrics (hhea, units per em 2000): ascender 2132, descender 600.
ASC_EM, DESC_EM = 1.066, 0.300


def css_ascent(size):
    """Ascent of a CSS line box with line-height normal, rounded like Chrome does at 1x."""
    return round(size * ASC_EM)


def css_line(size):
    return round(size * ASC_EM) + round(size * DESC_EM)


# Text roles drawn from glyph atlases: (pixel size, weight, colour, phases, charset).
ASCII = [chr(c) for c in range(0x20, 0x7F)]
EXTRA = list("·…–—‘’“”") + [chr(c) for c in range(0xC0, 0x100)]
FULL_SET = ASCII + EXTRA
CHIP_SET = [" "] + [chr(c) for c in range(ord("A"), ord("Z") + 1)] + list("0123456789-+_()")
ROLES = {
    # Prompts that are not systemd's and plymouth messages: as the board's prompt line.
    # Also the typed answer of a plymouth question (rare; saves a third atlas).
    "prompt": dict(size=14, weight=400, color=C_PROMPT, phases=2, charset=FULL_SET),
    # The disk name under the field: as the board's "Internal drive · 512 GB".
    "hint": dict(size=12, weight=400, color=C_HINT, phases=2, charset=FULL_SET),
    # Keyboard layout label, bottom right ("EN").
    "chip": dict(size=11.5, weight=800, color=C_HINT, phases=1, charset=CHIP_SET),
}

# Layout in board px. "frame" = relative to the 1440x900 board frame centred on the screen;
# "bottom" = y relative to the bottom edge of the screen (negative), x relative to the frame.
LOGO = (672, 250, 96, 96)                  # 96 px logo, top edge 250 px down
FORM_TOP = 250 + 96 + 44                   # 44 px gap under the logo
PROMPT_TOP = FORM_TOP                      # 14 px line
PILL = (540, PROMPT_TOP + css_line(14) + 14, 360, 46)
HINT_TOP = PILL[1] + PILL[3] + 14          # 12 px line
MESSAGE_TOP = HINT_TOP + css_line(12) + 20  # messages under the form (password mode)
CENTRE_X = 720
PILL_INNER = 1.5                           # border width, inside the box
LOCK = (PILL[0] + PILL_INNER + 16, None, 17)   # x, (centred), size
# The board render (Chrome) draws the lock icon and the bullets about 1 px lower than the exact
# CSS geometry (it snaps the icon box and the text baseline to whole pixels); follow the render.
FIELD_NUDGE = 1
BUTTON = 34
BULLET_SIZE = 15
BULLET_SPACING = 0.3 * BULLET_SIZE         # letter-spacing: 0.3em
DOTS_Y = -120 - 8                          # 8 px dots, 120 px above the bottom
DOTS_X = [698, 716, 734]
DOT_COLOURS = [C_ACCENT, C_ORANGE, C_TEAL]
CORNER_X = 32
CORNER_BOTTOM = -28                        # line box bottom, 11.5 px text
KBD_ICON = 14
KBD_GAP = 6
BAR = (590, PROMPT_TOP + css_line(14) + 18, 260, 4)   # update progress bar (Splash board style)
PERCENT_TOP = BAR[1] + BAR[3] + 14

STATIC_TEXTS = {
    # key: (text, role-like style, line top (frame) or None, anchor)
    "t-passphrase": "Enter the passphrase to unlock this disk",
    "t-recovery": "Enter the recovery key to unlock this disk",
    "t-either": "Enter the passphrase or recovery key to unlock this disk",
    "t-verify": "Enter the passphrase again to confirm",
    "t-pin": "Enter the PIN to unlock this disk",
    "t-answer": "Type your answer and press Enter",
    "t-updates": "Installing updates",
    "t-upgrade": "Upgrading the system",
    "t-firmware": "Updating the firmware",
    "t-reset": "Resetting the system",
}
HINT_TEXTS = {
    "t-encrypted": ("Encrypted disk", C_HINT),
    "t-capslock": ("Caps Lock is on", C_ORANGE),
    "t-dontoff": ("Do not turn off your computer", C_HINT),
}


# --------------------------------------------------------------------------- helpers

def to_pil(img):
    rgba = img.convertToFormat(QImage.Format_RGBA8888)
    data = bytes(rgba.constBits())[: rgba.sizeInBytes()]
    return Image.frombuffer("RGBA", (rgba.width(), rgba.height()), data, "raw", "RGBA",
                            rgba.bytesPerLine(), 1).copy()


def compensate_crop(pil):
    """Prepare an image that the script only shows through Image.Crop.

    Crop copies into a new, fully transparent pixel buffer, and libply blends into a
    non-opaque destination with the source colour multiplied by its alpha once more
    (blend_two_pixel_values in ply-pixel-buffer.c): translucent pixels (glyph edges) come out
    darker by their own alpha. Store the colour divided by that alpha instead; where the
    result would exceed 255, raise the pixel's alpha just enough (sqrt(target * 255)). Over the
    black background the crop then shows exactly the intended colour; over the field the edge
    pixels cover a little more of it (a few 1/255 on #111522)."""
    a = np.asarray(pil, dtype=np.float64)
    alpha = a[..., 3]
    target = a[..., :3] * alpha[..., None] / 255.0          # wanted premultiplied colour
    need = np.ceil(np.sqrt(target.max(axis=-1) * 255.0))
    alpha2 = np.clip(np.maximum(alpha, need), 0, 255)
    safe = np.where(alpha2 > 0, alpha2, 1.0)
    colour = np.clip(np.ceil(target * 255.0 * 255.0 / (safe[..., None] ** 2) - 1e-6), 0, 255)
    colour[alpha2 == 0] = 0
    out = np.dstack([colour, alpha2]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def to_png(img, path, crop_only=False):
    """Write a QImage as a plain 8-bit RGBA PNG (what libply's loader expects)."""
    pil = to_pil(img)
    if crop_only:
        pil = compensate_crop(pil)
    buf = io.BytesIO()
    pil.save(buf, "PNG", optimize=True)
    with open(path, "wb") as f:
        f.write(buf.getvalue())


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
        for f in sorted(os.listdir(FONT_DIR)):
            if f.endswith(".ttf"):
                if QFontDatabase.addApplicationFont(os.path.join(FONT_DIR, f)) < 0:
                    raise SystemExit(f"gen_plymouth: cannot load {f}")
        self._raw = {}
        self._shape_cache = {}

    def raw(self, weight, px):
        key = (weight, round(px, 5))
        if key not in self._raw:
            r = QRawFont(os.path.join(FONT_DIR, FONT_FILES[weight]), px, QFont.PreferVerticalHinting)
            if not r.isValid():
                raise SystemExit("gen_plymouth: QRawFont failed")
            self._raw[key] = r
        return self._raw[key]

    def shape(self, text, weight):
        """HarfBuzz shaping through QTextLayout at 1000 px: (glyph ids, x positions, advance),
        all in 1/1000 em."""
        key = (text, weight)
        if key in self._shape_cache:
            return self._shape_cache[key]
        font = QFont("Manrope")
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
        for run in layout.glyphRuns():
            raw = run.rawFont()
            want = os.path.splitext(FONT_FILES[weight])[0].split("-")[1]
            if raw.familyName() != "Manrope" or raw.styleName().replace(" ", "") != want:
                raise SystemExit(f"gen_plymouth: shaping used {raw.familyName()} {raw.styleName()}")
            ids += list(run.glyphIndexes())
            xs += [p.x() for p in run.positions()]
        result = (ids, xs, line.naturalTextWidth())
        self._shape_cache[key] = result
        return result


def text_image(fonts, text, size, weight, colour, s, pen_x, baseline, pad=2):
    """Draw `text` with its pen starting at device x pen_x (float) and its baseline at device y
    `baseline` (integer), both relative to an anchor. Returns (image, x, y) like render_svg."""
    ids, xs, adv = fonts.shape(text, weight)
    px = size * s
    raw = fonts.raw(weight, px)
    k = px / 1000
    boxes = [raw.boundingRect(g) for g in ids]
    left = min([b.left() + x * k for b, x in zip(boxes, xs)] + [0])
    right = max([b.right() + x * k for b, x in zip(boxes, xs)] + [adv * k])
    top = min([b.top() for b in boxes] + [-px * ASC_EM])
    bottom = max([b.bottom() for b in boxes] + [px * DESC_EM])
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


def centred_text(fonts, text, size, weight, colour, s, centre_x, baseline):
    adv = fonts.shape(text, weight)[2] * size * s / 1000
    return text_image(fonts, text, size, weight, colour, s, centre_x - adv / 2, baseline)


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
    min_top = min(min(b.top() for _, b in boxes), -px * ASC_EM)
    max_bottom = max(max(b.bottom() for _, b in boxes), px * DESC_EM)
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


def build(out, meta_path=None):
    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])  # noqa: F841
    fonts = Fonts()
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith(".png") or f in (THEME + ".plymouth", THEME + ".script"):
            os.remove(os.path.join(out, f))

    data = []      # script lines
    meta = {"scales": [], "layout": {}, "atlas": {}, "roles": {}, "board": {
        "logo": LOGO, "pill": PILL, "prompt_top": PROMPT_TOP, "hint_top": HINT_TOP}}

    def emit(line):
        data.append(line)

    emit("# ---- generated by generators/plymouth/gen_plymouth.py; do not edit ----")
    emit(f"global.pf.nscales = {len(SCALES)};")
    for i, (sid, s) in enumerate(SCALES):
        emit(f"global.pf.scale[{i}] = {num(s)}; global.pf.sid[{i}] = {sq(sid)};")

    # Glyph tables (scale independent).
    charset_index = {}
    for role, spec in ROLES.items():
        key = "chip" if spec["charset"] is CHIP_SET else "full"
        charset_index[role] = key
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

    # Per-scale images and offsets.
    for sid, s in SCALES:
        L = {}
        files = []

        def put(name, img, crop_only=False):
            fn = f"{sid}-{name}.png"
            to_png(img, os.path.join(out, fn), crop_only)
            files.append(fn)
            return fn

        def place(key, name, img, x, y):
            L[key] = dict(file=put(name, img), x=x, y=y, w=img.width(), h=img.height())

        # Logo: three opaque circles, blue under orange under teal (the board's screen blend
        # over black leaves the colours unchanged).
        body = (f'<circle cx="12" cy="8.5" r="5.5" fill="{C_ACCENT}"/>'
                f'<circle cx="8" cy="15" r="5.5" fill="{C_ORANGE}"/>'
                f'<circle cx="16" cy="15" r="5.5" fill="{C_TEAL}"/>')
        img, x, y = render_svg(svg_doc(24, 24, body), LOGO[0] * s, LOGO[1] * s, LOGO[2] * s, LOGO[3] * s)
        place("logo", "logo", img, x, y)

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

        # Prompt line (14 px) and hint line (12 px), centred.
        cx = CENTRE_X * s
        prompt_base = round((PROMPT_TOP + css_ascent(14)) * s)
        hint_base = round((HINT_TOP + css_ascent(12)) * s)
        message_base = round((MESSAGE_TOP + css_ascent(14)) * s)
        for key, text in STATIC_TEXTS.items():
            img, x, y, _ = centred_text(fonts, text, 14, 400, C_PROMPT, s, cx, prompt_base)
            place(key, key, img, x, y)
        for key, (text, colour) in HINT_TEXTS.items():
            # Update mode: title, bar, percentage, progress message (hint line), then the
            # "Do not turn off" note last.
            base = round((MESSAGE_TOP + css_ascent(12)) * s) if key == "t-dontoff" else hint_base
            img, x, y, _ = centred_text(fonts, text, 12, 400, colour, s, cx, base)
            place(key, key, img, x, y)
        L["lines"] = dict(cx=cx, prompt=prompt_base, hint=hint_base, message=message_base,
                          maxw=int(min(1040, BOARD_W - 2 * 64) * s), hintmaxw=int(520 * s))

        # Throbber dots: 8 px, bottom 120 px, 10 px apart, full opacity (the script pulses them).
        for i, (dx, colour) in enumerate(zip(DOTS_X, DOT_COLOURS)):
            img, x, y = render_svg(svg_doc(8, 8, f'<circle cx="4" cy="4" r="4" fill="{colour}"/>'),
                                   dx * s, DOTS_Y * s, 8 * s, 8 * s)
            place(f"dot{i}", f"dot{i}", img, x, y)

        # Bottom corners: "Esc shows boot messages" (left) and the keyboard chip (right), 11.5 px
        # lines whose boxes end 28 px above the bottom.
        corner_line = css_line(11.5)
        corner_top = CORNER_BOTTOM - corner_line
        corner_base = round((corner_top + css_ascent(11.5)) * s)
        img, x, y, _ = text_image(fonts, "Esc shows boot messages", 11.5, 400, C_FAINT, s, CORNER_X * s, corner_base)
        place("esc", "esc", img, x, y)
        icon_top = corner_top + (corner_line - KBD_ICON) / 2
        img, x, y = render_svg(svg_doc(KBD_ICON, KBD_ICON, icon(KBD_D, C_HINT, KBD_ICON, 0, 0)),
                               0, icon_top * s, KBD_ICON * s, KBD_ICON * s)
        L["kbd"] = dict(file=put("keyboard", img), x=x, y=y, right=-CORNER_X * s, base=corner_base,
                        gap=KBD_GAP * s, size=KBD_ICON * s)

        # Update progress: track and fill (the Splash board's bar), percentage line.
        bx, by, bw, bh = BAR
        img, x, y = render_svg(svg_doc(bw, bh, f'<rect width="{bw}" height="{bh}" rx="{bh / 2}" '
                                               f'fill="#ffffff" fill-opacity="0.1"/>'),
                               bx * s, by * s, bw * s, bh * s, pad=0)
        place("track", "bar-track", img, x, y)
        img, x, y = render_svg(svg_doc(bw, bh, f'<rect width="{bw}" height="{bh}" rx="{bh / 2}" fill="{C_ACCENT}"/>'),
                               bx * s, by * s, bw * s, bh * s, pad=0)
        L["fill"] = dict(file=put("bar-fill", img, crop_only=True), x=x, y=y, w=img.width(), h=img.height(),
                         cap=math.ceil(bh * s / 2) + 1)
        L["percent"] = dict(base=round((PERCENT_TOP + css_ascent(12)) * s))

        # Glyph atlases.
        atlases = {}
        for role in ROLES:
            img, info = build_atlas(fonts, role, s)
            info["file"] = put(f"atlas-{role}", img, crop_only=True)
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
