#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the Plasma Fusion window decorations (Aurorae v2 SVG themes).

    gen_aurorae.py OUTDIR [--theme NAME ...]

Writes OUTDIR/<Theme>/ for PlasmaFusionDark, PlasmaFusionLight, PlasmaFusionDark-Left and
PlasmaFusionLight-Left (or only the named ones). Each directory is a complete Aurorae theme:
metadata.desktop, <Theme>rc, decoration.svg and one SVG per button. No menu.svg is written, so
Aurorae draws the window's own icon in the menu slot (the board's "App icon").

Every value comes from design/boards/Windows.dc.html (anatomy, states, buttons on the left),
Main.dc.html / MainLight.dc.html (the same windows in the dark and light desktop) and
Colors.dc.html (title-bar colours). The board line is named next to each token.

How the decoration is drawn (Aurorae v2, KWin 6.7): the "decoration" frame is resized to the
window size plus the [Layout] Padding* margins and painted with its top-left at -padding. KWin
shows the part inside the window's border rect as the decoration (only the 50 px title bar with
BorderSize=None) and turns the part outside the window rect into the window shadow. The frame
therefore holds the soft shadow (pre-rendered PNG slices), the 1 px light edge just outside the
window and the title bar with its 14 px top corners. Bottom corners stay square: Aurorae cannot
clip the client area.
"""
import argparse
import base64
import io
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFilter

VERSION = "1.0"
AUTHOR = "Wisbendji Fimerlus"
EMAIL = "archledger236@gmail.com"

WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
INK = (20, 24, 39)            # #141827, light-scheme text; light boards tint with rgba(20,24,39,a)
RED = (217, 67, 75)           # #d9434b close button (Colors.dc.html: close glyph keeps #D9434B)
ACCENT = (47, 111, 223)       # #2f6fdf default accent; replaced by the colour scheme's Highlight


def mix(bg, fg, a):
    """fg at opacity a over an opaque bg."""
    return tuple(round(b + (f - b) * a) for b, f in zip(bg, fg))


def hexc(c):
    return "#%02x%02x%02x" % tuple(c[:3])


# ---------------------------------------------------------------------------
# design tokens
# ---------------------------------------------------------------------------
SCHEMES = {
    "dark": dict(
        # Colors.dc.html: Title bar, active  Header BackgroundNormal #222840, text #e8ebf4
        #                 Title bar, inactive Header Inactive      #1f2536, text #8891aa
        title=(34, 40, 64), title_inactive=(31, 37, 54),
        text=(232, 235, 244), text_inactive=(136, 145, 170),
        # Windows.dc.html:34 border 1px rgba(255,255,255,0.14) drawn over the window background
        # #1b2031; inactive (Windows.dc.html:93, Main.dc.html:76) 0.08 over #1a1f2e.
        edge=mix((27, 32, 49), WHITE, 0.14), edge_inactive=mix((26, 31, 46), WHITE, 0.08),
        # Windows.dc.html:200 shadow: active 0 34 90 px 55% black, inactive 0 24 60 px 35%
        shadow=dict(dy=34, blur=90, color=BLACK, alpha=0.55),
        shadow_inactive=dict(dy=24, blur=60, color=BLACK, alpha=0.35),
        # Main.dc.html:145-147 active buttons rgba(255,255,255,0.1), glyph #e8ebf4, close #d9434b/#fff
        # Main.dc.html:94-96 inactive buttons rgba(255,255,255,0.07), glyph #a3abc2
        btn=(WHITE, 0.10), glyph=(232, 235, 244),
        btn_inactive=(WHITE, 0.07), glyph_inactive=(163, 171, 194),
        btn_disabled=(WHITE, 0.05), glyph_disabled=((232, 235, 244), 0.30),
        # Windows.dc.html:120 buttons on the left: 13 px circles #8891aa
        dot=((136, 145, 170), 1.0), dot_inactive=((136, 145, 170), 0.40),
        # Windows.dc.html:108 hover ring 3 px rgba(91,157,255,0.3), i.e. a lighter accent. Drawn as
        # white 8 % under the accent at 35 % so it follows the accent colour (over #222840 this
        # gives 50,74,130 against the board's 51,75,121).
        ring=(0.08, 0.35),
    ),
    "light": dict(
        # Colors.dc.html light: Title bar #eceff6 text #141827; inactive #f1f3f8 text #646b80
        title=(236, 239, 246), title_inactive=(241, 243, 248),
        text=(20, 24, 39), text_inactive=(100, 107, 128),
        # MainLight.dc.html:138 border rgba(20,24,39,0.14) over #ffffff; :76 inactive 0.08
        edge=mix(WHITE, INK, 0.14), edge_inactive=mix(WHITE, INK, 0.08),
        # MainLight.dc.html:138 box-shadow 0 34px 90px rgba(20,24,39,0.22); :76 0 24px 60px 0.14
        shadow=dict(dy=34, blur=90, color=INK, alpha=0.22),
        shadow_inactive=dict(dy=24, blur=60, color=INK, alpha=0.14),
        # MainLight.dc.html:145-147 rgba(20,24,39,0.1) glyph #141827; :94-96 0.07 glyph #5b6278
        btn=(INK, 0.10), glyph=(20, 24, 39),
        btn_inactive=(INK, 0.07), glyph_inactive=(91, 98, 120),
        btn_disabled=(INK, 0.04), glyph_disabled=((20, 24, 39), 0.30),
        # no light board for the left layout: the light scheme's soft grey (#9aa0b2)
        dot=((154, 160, 178), 1.0), dot_inactive=((154, 160, 178), 0.45),
        # the same rgba(91,157,255,0.3) ring over #eceff6 (192,214,249): accent at 25 % (190,208,241)
        ring=(0.0, 0.25),
    ),
}

# Shared by all four themes.
RADIUS = 14                 # Windows.dc.html spec 4: 14 px outer radius (edge), 13 px inner (title bar)
TITLE_H = 50                # Windows.dc.html spec 7: 50 px title bar
TITLE_H_MAX = 40            # 40 px maximized
# Shadow padding: the largest shadow reach (active: 0 34 90 -> 90 left/right, 90-34 top, 90+34 bottom).
PAD = dict(left=90, top=56, right=90, bottom=124)
# How far the frame corners reach into the window. The shadow varies along a side only near the
# corners; 70/110/40 px keep every slice seam below 1.5 % alpha (sigma 45, see docs).
CORNER_IN = dict(x=70, top=110, bottom=40)
RED_RING = 0.30             # the close button's ring: its red at 30 % (same weight as the accent ring)
PRESS_DARKEN = 0.20         # pressed: accent (or red) darkened by 20 % black

# Board glyphs (Icons.dc.html symbolic set, 24-unit grid, stroke 1.8, round caps and joins).
GLYPHS = {
    "minimize": "M6 12h12",
    "maximize": "M8 6h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z",
    "close": "M7 7l10 10M17 7L7 17",
    # Not on the boards; drawn in the same style.
    "restore": "M8 10h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2z"
               "M10 7a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2",
    "keepabove": "M6 5h12M12 20V9M7.5 13.5L12 9l4.5 4.5",
    "keepbelow": "M6 19h12M12 4v11M7.5 10.5L12 15l4.5-4.5",
    "alldesktops": "M9 4h6M10 4v5l-3 4h10l-3-4V4M12 13v7",
    "shade": "M5 6h14M7.5 15.5L12 11l4.5 4.5",
    "help": "M9.5 9a2.5 2.5 0 1 1 3.6 2.25c-.66.32-1.1.98-1.1 1.72V14M12 18h.01",
    "appmenu": "M5 7h14M5 12h14M5 17h14",
}

# Button files: (file name, glyph, red close style)
BUTTONS = [
    ("minimize", "minimize", False),
    ("maximize", "maximize", False),
    ("restore", "restore", False),
    ("close", "close", True),
    ("keepabove", "keepabove", False),
    ("keepbelow", "keepbelow", False),
    ("alldesktops", "alldesktops", False),
    ("shade", "shade", False),
    ("help", "help", False),
    ("appmenu", "appmenu", False),
]

# Button styles
STYLES = {
    # Windows.dc.html:35-43: buttons 28 px circles 6 px apart, 10 px from the right; icon 26 px
    # 16 px from the left; title 10 px after the icon. The 34 px button box holds the 28 px circle
    # plus the 3 px hover ring (Windows.dc.html:108), so boxes touch and the circles are 6 px apart.
    # Glyph origin (gx, gy): the board raster (desktop-dark-1) draws the 13 px glyph with its top
    # at title-bar y 18 (centred on the 49 px row above the header's 1 px line, 24.5), so the
    # minimize dash is one crisp pixel row and the square's horizontal strokes fall like the
    # board's. gy 10 in the 34 px box (at title-bar y 8) does the same; gx 11 (0.5 px right of the
    # circle centre) puts the dash ends on whole pixels.
    "right": dict(box=34, circle=28, glyph=13, stroke=1.8, gx=11, gy=10),
    # Windows.dc.html:119-121: 13 px circles, 7 px apart, 12 px from the left, title centred.
    # 20 px boxes (bigger hit area) placed 8 px from the left put the circles at 12, 32, 52.
    # Circle centre (10.5, 9.5) puts the odd 13 px circle on whole pixels (title-bar y 18-31,
    # centre 24.5 as above); the 9 px glyph at (6, 5) keeps its dash on a pixel row.
    "left": dict(box=20, circle=13, cx=10.5, cy=9.5, glyph=9, stroke=2.4, gx=6, gy=5),
}

THEMES = {
    "PlasmaFusionDark": dict(scheme="dark", style="right", name="Plasma Fusion Dark"),
    "PlasmaFusionLight": dict(scheme="light", style="right", name="Plasma Fusion Light"),
    "PlasmaFusionDark-Left": dict(scheme="dark", style="left", name="Plasma Fusion Dark (buttons on the left)"),
    "PlasmaFusionLight-Left": dict(scheme="light", style="left", name="Plasma Fusion Light (buttons on the left)"),
}


def fmt(v):
    s = ("%.4f" % v).rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


# ---------------------------------------------------------------------------
# shadow slices
# ---------------------------------------------------------------------------
REF = 600  # reference window size used to cut the shadow slices (far larger than any corner reach)


def shadow_frame(shadow):
    """RGBA image of the whole frame (reference window REF x REF plus padding) with the shadow of
    the window shape: the window rect grown by the 1 px edge, rounded top corners, square bottom."""
    fw = REF + PAD["left"] + PAD["right"]
    fh = REF + PAD["top"] + PAD["bottom"]
    margin = 200
    sigma = shadow["blur"] / 2.0          # CSS: standard deviation = half the blur radius
    mask = Image.new("L", (fw + 2 * margin, fh + 2 * margin), 0)
    d = ImageDraw.Draw(mask)
    x0 = margin + PAD["left"] - 1
    y0 = margin + PAD["top"] - 1 + shadow["dy"]
    d.rounded_rectangle((x0, y0, x0 + REF + 2 - 1, y0 + REF + 2 - 1), radius=RADIUS, fill=255,
                        corners=(True, True, False, False))
    mask = mask.filter(ImageFilter.GaussianBlur(sigma))
    a = shadow["alpha"]
    mask = mask.point(lambda v: int(round(v * a)))
    mask = mask.crop((margin, margin, margin + fw, margin + fh))
    img = Image.new("RGBA", (fw, fh), shadow["color"] + (0,))
    img.putalpha(mask)
    return img


def png_b64(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return base64.b64encode(buf.getvalue()).decode("ascii")


# ---------------------------------------------------------------------------
# decoration.svg
# ---------------------------------------------------------------------------
def frame_geometry():
    fw = REF + PAD["left"] + PAD["right"]
    fh = REF + PAD["top"] + PAD["bottom"]
    L = PAD["left"] + CORNER_IN["x"]
    R = PAD["right"] + CORNER_IN["x"]
    T = PAD["top"] + CORNER_IN["top"]
    B = PAD["bottom"] + CORNER_IN["bottom"]
    xc, yc = fw // 2, fh // 2
    # slice rects in reference-frame coordinates: name -> (x, y, w, h)
    return fw, fh, {
        "topleft": (0, 0, L, T),
        "top": (xc, 0, 1, T),
        "topright": (fw - R, 0, R, T),
        "left": (0, yc, L, 1),
        "right": (fw - R, yc, R, 1),
        "bottomleft": (0, fh - B, L, B),
        "bottom": (xc, fh - B, 1, B),
        "bottomright": (fw - R, fh - B, R, B),
        "center": (xc, yc, 1, 1),
    }


def clip_rect(shape, rect):
    """Intersect an axis-aligned rect (x0,y0,x1,y1) with the slice rect (x,y,w,h)."""
    x, y, w, h = rect
    x0, y0, x1, y1 = max(shape[0], x), max(shape[1], y), min(shape[2], x + w), min(shape[3], y + h)
    if x1 <= x0 or y1 <= y0:
        return None
    return (x0, y0, x1, y1)


def frame_slice_svg(prefix, name, rect, place, shadow_img, edge, fill):
    """One frame element in the SVG: the shadow crop plus the window shape (edge ring and title
    fill), all clipped to the slice rect, translated to its place in the document. The title fill
    also covers the part of the window below the title bar; KWin never shows it (the client is
    there), but a window smaller than the corners then keeps a filled title bar."""
    x, y, w, h = rect
    px, py = place
    dx, dy = px - x, py - y
    crop = shadow_img.crop((x, y, x + w, y + h))
    out = ['<g id="%s-%s">' % (prefix, name)]
    out.append('<image x="%s" y="%s" width="%s" height="%s" preserveAspectRatio="none" '
               'xlink:href="data:image/png;base64,%s"/>' % (px, py, w, h, png_b64(crop)))
    wx0, wy0 = PAD["left"], PAD["top"]                       # window rect in reference frame
    wx1, wy1 = PAD["left"] + REF, PAD["top"] + REF
    # outer (edge) shape: window rect grown by 1 px, rounded top corners r=14; inner r=13
    for shape, color, r in (((wx0 - 1, wy0 - 1, wx1 + 1, wy1 + 1), edge, RADIUS),
                            ((wx0, wy0, wx1, wy1), fill, RADIUS - 1)):
        c = clip_rect(shape, rect)
        if c is None:
            continue
        cx0, cy0, cx1, cy1 = c
        # does the clipped rect contain a rounded corner of the shape?
        round_tl = (cx0 == shape[0] and cy0 == shape[1])
        round_tr = (cx1 == shape[2] and cy0 == shape[1])
        if name == "topleft" and round_tl:
            d = ("M%s %sA%s %s 0 0 1 %s %sH%sV%sH%sZ" % (
                fmt(cx0 + dx), fmt(cy0 + r + dy), fmt(r), fmt(r), fmt(cx0 + r + dx), fmt(cy0 + dy),
                fmt(cx1 + dx), fmt(cy1 + dy), fmt(cx0 + dx)))
        elif name == "topright" and round_tr:
            d = ("M%s %sH%sA%s %s 0 0 1 %s %sV%sH%sZ" % (
                fmt(cx0 + dx), fmt(cy0 + dy), fmt(cx1 - r + dx), fmt(r), fmt(r), fmt(cx1 + dx),
                fmt(cy0 + r + dy), fmt(cy1 + dy), fmt(cx0 + dx)))
        else:
            d = "M%s %sH%sV%sH%sZ" % (fmt(cx0 + dx), fmt(cy0 + dy), fmt(cx1 + dx), fmt(cy1 + dy), fmt(cx0 + dx))
        out.append('<path d="%s" fill="%s"/>' % (d, hexc(color)))
    out.append("</g>")
    return "\n".join(out)


def decoration_svg(scheme):
    s = SCHEMES[scheme]
    _, _, slices = frame_geometry()
    parts = []
    col_x = 0
    doc_w = doc_h = 0
    for prefix, edge, fill, shadow in (
            ("decoration", s["edge"], s["title"], s["shadow"]),
            ("decoration-inactive", s["edge_inactive"], s["title_inactive"], s["shadow_inactive"])):
        img = shadow_frame(shadow)
        # lay the nine slices out in a 3x3 grid, one grid per prefix, side by side
        colw = [slices["topleft"][2], 1, slices["topright"][2]]
        rowh = [slices["topleft"][3], 1, slices["bottomleft"][3]]
        grid = {
            "topleft": (0, 0), "top": (1, 0), "topright": (2, 0),
            "left": (0, 1), "center": (1, 1), "right": (2, 1),
            "bottomleft": (0, 2), "bottom": (1, 2), "bottomright": (2, 2),
        }
        gap = 4
        for name, (gc, gr) in grid.items():
            px = col_x + sum(colw[:gc]) + gap * gc
            py = sum(rowh[:gr]) + gap * gr
            if name == "center":
                # under the client area, never visible
                parts.append('<rect id="%s-center" x="%s" y="%s" width="1" height="1" fill="%s"/>'
                             % (prefix, px, py, hexc(fill)))
                continue
            parts.append(frame_slice_svg(prefix, name, slices[name], (px, py), img, edge, fill))
        width = sum(colw) + 2 * gap
        doc_h = max(doc_h, sum(rowh) + 2 * gap)
        col_x += width + 20
        doc_w = col_x
    # Maximized: KWin paints only <prefix>-center, stretched over the whole window; the visible
    # part is the 40 px title bar (square corners, no edge, no shadow).
    y = doc_h + 20
    parts.append('<rect id="decoration-maximized-center" x="0" y="%s" width="10" height="10" fill="%s"/>'
                 % (y, hexc(s["title"])))
    parts.append('<rect id="decoration-maximized-inactive-center" x="20" y="%s" width="10" height="10" '
                 'fill="%s"/>' % (y, hexc(s["title_inactive"])))
    # Borders are stretched (the shadow slices are uniform along the side), never tiled.
    parts.append('<rect id="hint-stretch-borders" x="40" y="%s" width="1" height="1" fill="#000000" '
                 'fill-opacity="0"/>' % y)
    doc_h = y + 10
    return svg_doc(doc_w, doc_h, "\n".join(parts))


def svg_doc(w, h, body, style=None):
    # REUSE-IgnoreStart
    head = ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!-- SPDX-FileCopyrightText: 2026 %s <%s> -->\n'
            '<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->\n'
            '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
            'version="1.1" width="%s" height="%s" viewBox="0 0 %s %s">\n' % (AUTHOR, EMAIL, w, h, w, h))
    # REUSE-IgnoreEnd
    if style:
        head += '<style type="text/css" id="current-color-scheme">%s</style>\n' % style
    return head + body + "\n</svg>\n"


# ---------------------------------------------------------------------------
# buttons
# ---------------------------------------------------------------------------
HIGHLIGHT_STYLE = ".ColorScheme-Highlight{color:%s;}" % hexc(ACCENT)


def glyph_svg(glyph, gx, gy, size, stroke, color, opacity=1.0):
    """The 24-unit board glyph scaled to SIZE px with its top-left corner at (gx, gy)."""
    k = size / 24.0
    return ('<path d="%s" transform="translate(%s %s) scale(%s)" fill="none" stroke="%s"%s '
            'stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % (
                GLYPHS[glyph], fmt(gx), fmt(gy), fmt(k), hexc(color),
                "" if opacity >= 1 else ' stroke-opacity="%s"' % fmt(opacity), fmt(stroke)))


def circle(cx, cy, r, color=None, opacity=1.0, accent=False):
    if accent:
        return ('<circle cx="%s" cy="%s" r="%s" class="ColorScheme-Highlight" fill="currentColor"%s/>'
                % (fmt(cx), fmt(cy), fmt(r), "" if opacity >= 1 else ' fill-opacity="%s"' % fmt(opacity)))
    return '<circle cx="%s" cy="%s" r="%s" fill="%s"%s/>' % (
        fmt(cx), fmt(cy), fmt(r), hexc(color), "" if opacity >= 1 else ' fill-opacity="%s"' % fmt(opacity))


def button_states(scheme, style, glyph, red):
    """Return {state prefix: svg body at origin (0,0)} for one button."""
    s = SCHEMES[scheme]
    st = STYLES[style]
    box = st["box"]
    cx = st.get("cx", box / 2.0)
    cy = st.get("cy", box / 2.0)
    r = st["circle"] / 2.0
    g, sw = st["glyph"], st["stroke"]
    gx, gy = st["gx"], st["gy"]
    states = {}

    def hover(pressed):
        body = []
        if style == "right":
            # 3 px ring outside the 28 px circle (Windows.dc.html:108)
            if red:
                body.append(circle(cx, cy, r + 3, RED, RED_RING))
            else:
                white, accent = s["ring"]
                if white > 0:
                    body.append(circle(cx, cy, r + 3, WHITE, white))
                body.append(circle(cx, cy, r + 3, accent=True, opacity=accent))
        body.append(circle(cx, cy, r, RED) if red else circle(cx, cy, r, accent=True))
        if pressed:
            body.append(circle(cx, cy, r, BLACK, PRESS_DARKEN))
        body.append(glyph_svg(glyph, gx, gy, g, sw, WHITE))
        return body

    if style == "right":
        if red:
            active = [circle(cx, cy, r, RED), glyph_svg(glyph, gx, gy, g, sw, WHITE)]
        else:
            active = [circle(cx, cy, r, s["btn"][0], s["btn"][1]), glyph_svg(glyph, gx, gy, g, sw, s["glyph"])]
        inactive = [circle(cx, cy, r, s["btn_inactive"][0], s["btn_inactive"][1]),
                    glyph_svg(glyph, gx, gy, g, sw, s["glyph_inactive"])]
        disabled = [circle(cx, cy, r, s["btn_disabled"][0], s["btn_disabled"][1]),
                    glyph_svg(glyph, gx, gy, g, sw, s["glyph_disabled"][0], s["glyph_disabled"][1])]
    else:
        # plain dots at rest (Windows.dc.html:120); colour and glyph appear on hover
        active = [circle(cx, cy, r, s["dot"][0], s["dot"][1])]
        inactive = [circle(cx, cy, r, s["dot_inactive"][0], s["dot_inactive"][1])]
        disabled = [circle(cx, cy, r, s["dot_inactive"][0], s["dot_inactive"][1] * 0.6)]
    states["active"] = active
    states["inactive"] = inactive
    states["hover"] = hover(False)
    states["hover-inactive"] = hover(False)
    states["pressed"] = hover(True)
    states["pressed-inactive"] = hover(True)
    states["deactivated"] = disabled
    states["deactivated-inactive"] = disabled
    return states


def button_svg(scheme, style, glyph, red):
    st = STYLES[style]
    box = st["box"]
    states = button_states(scheme, style, glyph, red)
    parts = []
    x = 0
    for prefix, body in states.items():
        parts.append('<g id="%s-center" transform="translate(%s 0)">' % (prefix, x))
        # invisible box: fixes the element bounds to the full button size
        parts.append('<rect x="0" y="0" width="%s" height="%s" fill="#000000" fill-opacity="0"/>' % (box, box))
        parts.extend(body)
        parts.append("</g>")
        x += box + 4
    return svg_doc(x - 4, box, "\n".join(parts), style=HIGHLIGHT_STYLE)


# ---------------------------------------------------------------------------
# rc and metadata
# ---------------------------------------------------------------------------
def rc_text(theme):
    t = THEMES[theme]
    s = SCHEMES[t["scheme"]]
    right = t["style"] == "right"
    general = [
        ("ActiveTextColor", "%d,%d,%d" % s["text"]),
        ("InactiveTextColor", "%d,%d,%d" % s["text_inactive"]),
        ("TitleAlignment", "Left" if right else "Center"),
        ("TitleVerticalAlignment", "Center"),
        ("DecorationPosition", "0"),
        # left layout: hovering the group shows all three colours and glyphs together
        ("ButtonGroupHover", "false" if right else "true"),
        ("Animation", "0"),
    ]
    if right:
        box = STYLES["right"]["box"]
        edge_top = (TITLE_H - box) // 2               # 8 -> 8 + 34 + 8 = 50
        edge_top_max = (TITLE_H_MAX - box) // 2       # 3 -> 3 + 34 + 3 = 40
        layout = [
            ("TitleHeight", box),
            ("TitleEdgeTop", edge_top), ("TitleEdgeBottom", TITLE_H - box - edge_top),
            ("TitleEdgeLeft", 16),                    # icon 16 px from the left edge
            ("TitleEdgeRight", 10 - 3),               # circle 10 px from the right, ring box 3 px wider
            ("TitleEdgeTopMaximized", edge_top_max),
            ("TitleEdgeBottomMaximized", TITLE_H_MAX - box - edge_top_max),
            ("TitleEdgeLeftMaximized", 16), ("TitleEdgeRightMaximized", 10 - 3),
            ("TitleBorderLeft", 10),                  # title 10 px after the icon
            ("TitleBorderRight", 10),
            ("ButtonWidth", box), ("ButtonHeight", box),
            ("ButtonWidthMenu", 26),                  # the app icon, 26 px
            ("ButtonWidthAppMenu", box),
            ("ButtonSpacing", 0),                     # boxes touch; circles are 6 px apart
            ("ButtonMarginTop", 0), ("ButtonMarginTopMaximized", 0),
            ("ExplicitButtonSpacer", 10),
        ]
    else:
        box = STYLES["left"]["box"]
        th = 34
        edge_top = (TITLE_H - th) // 2
        edge_top_max = (TITLE_H_MAX - th) // 2
        margin = (TITLE_H - box) // 2 - edge_top      # 15 - 8 = 7: buttons centred in the bar
        layout = [
            ("TitleHeight", th),
            ("TitleEdgeTop", edge_top), ("TitleEdgeBottom", TITLE_H - th - edge_top),
            ("TitleEdgeLeft", 8), ("TitleEdgeRight", 8),   # circles at 12, 32, 52 px
            ("TitleEdgeTopMaximized", edge_top_max),
            ("TitleEdgeBottomMaximized", TITLE_H_MAX - th - edge_top_max),
            ("TitleEdgeLeftMaximized", 8), ("TitleEdgeRightMaximized", 8),
            ("TitleBorderLeft", 10), ("TitleBorderRight", 10),
            ("ButtonWidth", box), ("ButtonHeight", box), ("ButtonWidthMenu", box),
            ("ButtonWidthAppMenu", box),
            ("ButtonSpacing", 0),
            ("ButtonMarginTop", margin),
            ("ButtonMarginTopMaximized", (TITLE_H_MAX - box) // 2 - edge_top_max),
            # ButtonsOnRight=_ reserves the same width as the three buttons, so the title is
            # centred on the whole window (Windows.dc.html:121 margin-right 53px)
            ("ExplicitButtonSpacer", 3 * box),
        ]
    layout = [("BorderLeft", 0), ("BorderRight", 0), ("BorderTop", 0), ("BorderBottom", 0)] + layout + [
        ("PaddingLeft", PAD["left"]), ("PaddingTop", PAD["top"]),
        ("PaddingRight", PAD["right"]), ("PaddingBottom", PAD["bottom"]),
    ]
    # REUSE-IgnoreStart
    lines = ["# SPDX-FileCopyrightText: 2026 %s <%s>" % (AUTHOR, EMAIL),
             "# SPDX-License-Identifier: CC-BY-SA-4.0",
             "[General]"]
    # REUSE-IgnoreEnd
    lines += ["%s=%s" % kv for kv in general]
    lines += ["", "[Layout]"]
    lines += ["%s=%s" % kv for kv in layout]
    return "\n".join(lines) + "\n"


def metadata_text(theme):
    t = THEMES[theme]
    comment = ("Plasma Fusion title bars: 14 px corners, soft shadow, round buttons %s"
               % ("on the right" if t["style"] == "right" else "on the left, title centred"))
    return "\n".join([
        "[Desktop Entry]",
        "Name=%s" % t["name"],
        "Comment=%s" % comment,
        "X-KDE-PluginInfo-Author=%s" % AUTHOR,
        "X-KDE-PluginInfo-Email=%s" % EMAIL,
        "X-KDE-PluginInfo-Name=%s" % theme,
        "X-KDE-PluginInfo-Version=%s" % VERSION,
        "X-KDE-PluginInfo-Category=",
        "X-KDE-PluginInfo-License=CC-BY-SA-4.0",
        "X-KDE-PluginInfo-EnabledByDefault=true",
        "",
    ])


def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def build_theme(outdir, theme, deco_cache):
    t = THEMES[theme]
    d = os.path.join(outdir, theme)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    write(os.path.join(d, "metadata.desktop"), metadata_text(theme))
    write(os.path.join(d, theme + "rc"), rc_text(theme))
    if t["scheme"] not in deco_cache:
        deco_cache[t["scheme"]] = decoration_svg(t["scheme"])
    write(os.path.join(d, "decoration.svg"), deco_cache[t["scheme"]])
    for fname, glyph, red in BUTTONS:
        write(os.path.join(d, fname + ".svg"), button_svg(t["scheme"], t["style"], glyph, red))
    return d


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("outdir")
    ap.add_argument("--theme", action="append", choices=sorted(THEMES))
    args = ap.parse_args(argv)
    os.makedirs(args.outdir, exist_ok=True)
    cache = {}
    for theme in (args.theme or list(THEMES)):
        print(build_theme(args.outdir, theme, cache))
    return 0


if __name__ == "__main__":
    sys.exit(main())
