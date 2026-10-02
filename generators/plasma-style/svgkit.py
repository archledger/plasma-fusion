# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Small SVG toolkit for KSvg frame files (Plasma styles).

KSvg draws a frame from nine elements per prefix (topleft, top, topright, left,
center, right, bottomleft, bottom, bottomright). The size of a border is the
size of its element, so every cell element here carries an invisible rectangle
that pins its bounds to the full cell, whatever is painted inside it.

Shapes are rounded rectangles described by layers:
  Fill(inset, paint)            region of the shape shrunk by `inset`
  Ring(inset, width, paint)     band between shrink `inset` and `inset + width`
All geometry is analytic (quarter-circle arcs), no strokes, so the cells stay
crisp and their bounds are exact.
"""
import base64
import io
import math
from dataclasses import dataclass

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# --------------------------------------------------------------------------
# paints
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class RGBA:
    r: int
    g: int
    b: int
    a: float

    def attrs(self, extra_alpha=1.0):
        a = round(self.a * extra_alpha, 4)
        return f'style="fill:#{self.r:02x}{self.g:02x}{self.b:02x};fill-opacity:{a}"'


@dataclass(frozen=True)
class Scheme:
    """A colour taken from the active colour scheme (KSvg stylesheet class)."""
    cls: str          # e.g. "ColorScheme-Text"
    a: float = 1.0

    def attrs(self, extra_alpha=1.0):
        a = round(self.a * extra_alpha, 4)
        return f'class="{self.cls}" style="fill:currentColor;fill-opacity:{a}"'


def fmt(v):
    """Compact number formatting for path data."""
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    return f"{v:.4f}".rstrip("0").rstrip(".")


# --------------------------------------------------------------------------
# rounded-rectangle geometry clipped to a cell
# --------------------------------------------------------------------------


@dataclass
class Fill:
    inset: float
    paint: object


@dataclass
class Ring:
    inset: float
    width: float
    paint: object


def _rr_polygon(x0, y0, x1, y1, r, steps=32):
    """Rounded rectangle outline as a polygon (clockwise), arcs sampled finely."""
    pts = []
    for (cx, cy, a0) in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(steps + 1):
            a = math.radians(a0 + 90.0 * i / steps)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def _clip(poly, x0, y0, x1, y1):
    """Sutherland-Hodgman clip of a polygon to an axis-aligned rectangle."""
    def clip_edge(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            cur, prev = pts[i], pts[i - 1]
            if inside(cur):
                if not inside(prev):
                    out.append(inter(prev, cur))
                out.append(cur)
            elif inside(prev):
                out.append(inter(prev, cur))
        return out

    def ix(xc):
        return lambda p, q: (xc, p[1] + (q[1] - p[1]) * (xc - p[0]) / (q[0] - p[0]))

    def iy(yc):
        return lambda p, q: (p[0] + (q[0] - p[0]) * (yc - p[1]) / (q[1] - p[1]), yc)

    for inside, inter in ((lambda p: p[0] >= x0, ix(x0)), (lambda p: p[0] <= x1, ix(x1)),
                          (lambda p: p[1] >= y0, iy(y0)), (lambda p: p[1] <= y1, iy(y1))):
        poly = clip_edge(poly, inside, inter)
        if not poly:
            return []
    return poly


def rr_cell_path(shape, d, cell, corner):
    """Path of (rounded rect `shape` shrunk by d) intersected with `cell`.

    shape = (x0, y0, x1, y1, r); cell = (cx0, cy0, cx1, cy1).
    corner is one of topleft/topright/bottomleft/bottomright or None. Side and
    centre cells are always straight (they are stretched). A corner cell smaller
    than the arc gets the arc clipped to the cell, so a frame can keep a large
    radius while staying drawable at small sizes (cells never overlap).
    Returns '' when the intersection is empty.
    """
    x0, y0, x1, y1, r = shape
    x0, y0, x1, y1 = x0 + d, y0 + d, x1 - d, y1 - d
    rd = r - d
    cx0, cy0, cx1, cy1 = cell
    ax0, ay0, ax1, ay1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
    if ax1 - ax0 <= 1e-6 or ay1 - ay0 <= 1e-6:
        return ""
    if corner is None or rd <= 1e-6:
        return f"M{fmt(ax0)},{fmt(ay0)}H{fmt(ax1)}V{fmt(ay1)}H{fmt(ax0)}Z"
    fits = {"topleft": x0 + rd <= cx1 + 1e-9 and y0 + rd <= cy1 + 1e-9,
            "topright": x1 - rd >= cx0 - 1e-9 and y0 + rd <= cy1 + 1e-9,
            "bottomright": x1 - rd >= cx0 - 1e-9 and y1 - rd >= cy0 - 1e-9,
            "bottomleft": x0 + rd <= cx1 + 1e-9 and y1 - rd >= cy0 - 1e-9}[corner]
    if not fits:
        poly = _clip(_rr_polygon(x0, y0, x1, y1, rd), cx0, cy0, cx1, cy1)
        if len(poly) < 3:
            return ""
        return "M" + " L".join(f"{fmt(round(px, 4))},{fmt(round(py, 4))}" for px, py in poly) + "Z"
    # corner cell with the whole arc inside it: exact arc
    if corner == "topleft":
        return (f"M{fmt(x0)},{fmt(ay1)}V{fmt(y0 + rd)}"
                f"A{fmt(rd)},{fmt(rd)} 0 0 1 {fmt(x0 + rd)},{fmt(y0)}"
                f"H{fmt(ax1)}V{fmt(ay1)}Z")
    if corner == "topright":
        return (f"M{fmt(ax0)},{fmt(y0)}H{fmt(x1 - rd)}"
                f"A{fmt(rd)},{fmt(rd)} 0 0 1 {fmt(x1)},{fmt(y0 + rd)}"
                f"V{fmt(ay1)}H{fmt(ax0)}Z")
    if corner == "bottomright":
        return (f"M{fmt(x1)},{fmt(ay0)}V{fmt(y1 - rd)}"
                f"A{fmt(rd)},{fmt(rd)} 0 0 1 {fmt(x1 - rd)},{fmt(y1)}"
                f"H{fmt(ax0)}V{fmt(ay0)}Z")
    if corner == "bottomleft":
        return (f"M{fmt(ax1)},{fmt(y1)}H{fmt(x0 + rd)}"
                f"A{fmt(rd)},{fmt(rd)} 0 0 1 {fmt(x0)},{fmt(y1 - rd)}"
                f"V{fmt(ay0)}H{fmt(ax1)}Z")
    raise ValueError(corner)


def rr_full_path(x0, y0, x1, y1, r):
    """Closed rounded-rectangle path (for standalone elements)."""
    r = max(0.0, min(r, (x1 - x0) / 2, (y1 - y0) / 2))
    if r <= 1e-6:
        return f"M{fmt(x0)},{fmt(y0)}H{fmt(x1)}V{fmt(y1)}H{fmt(x0)}Z"
    return (f"M{fmt(x0 + r)},{fmt(y0)}H{fmt(x1 - r)}A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x1)},{fmt(y0 + r)}"
            f"V{fmt(y1 - r)}A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x1 - r)},{fmt(y1)}"
            f"H{fmt(x0 + r)}A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0)},{fmt(y1 - r)}"
            f"V{fmt(y0 + r)}A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0 + r)},{fmt(y0)}Z")


def circle_path(cx, cy, r):
    return (f"M{fmt(cx - r)},{fmt(cy)}A{fmt(r)},{fmt(r)} 0 1 1 {fmt(cx + r)},{fmt(cy)}"
            f"A{fmt(r)},{fmt(r)} 0 1 1 {fmt(cx - r)},{fmt(cy)}Z")


CELLS = ("topleft", "top", "topright", "left", "center", "right",
         "bottomleft", "bottom", "bottomright")
CORNERS = ("topleft", "topright", "bottomleft", "bottomright")


# --------------------------------------------------------------------------
# document
# --------------------------------------------------------------------------

DEFAULT_STYLE = """
      .ColorScheme-Text { color:#e8ebf4; }
      .ColorScheme-Background { color:#1b2031; }
      .ColorScheme-Highlight { color:#2f6fdf; }
      .ColorScheme-HighlightedText { color:#ffffff; }
      .ColorScheme-ButtonFocus { color:#8ab8ff; }
      .ColorScheme-NeutralText { color:#f5c08c; }
      .ColorScheme-NegativeText { color:#ff8a8f; }
      .ColorScheme-PositiveText { color:#7fd99c; }
"""


class Doc:
    """An SVG document with a simple top-to-bottom, left-to-right layout."""

    def __init__(self, title):
        self.title = title
        self.parts = []
        self.y = 0          # top of the current row
        self.x = 0          # next x in the current row
        self.row_h = 0
        self.width = 0
        self.ids = set()
        self.uses_scheme = False
        self.max_row_w = 1600
        self.bounds = {}    # element id -> (x, y, w, h) of its cell
        self.index = {}     # element id -> index in self.parts

    # -- layout
    def place(self, w, h, gap=12):
        if self.x > 0 and self.x + w > self.max_row_w:
            self.newline(gap)
        x, y = self.x, self.y
        self.x += w + gap
        self.row_h = max(self.row_h, h)
        self.width = max(self.width, self.x)
        return x, y

    def newline(self, gap=12):
        self.y += self.row_h + gap
        self.x = 0
        self.row_h = 0

    # -- output
    def add(self, s):
        self.parts.append(s)

    def reg(self, ident):
        if ident in self.ids:
            raise ValueError(f"duplicate id {ident} in {self.title}")
        self.ids.add(ident)
        return ident

    def overlay(self, ident, draw):
        """Append markup to an existing element; draw(x, y, w, h) gets the element's cell."""
        i = self.index[ident]
        head = self.parts[i][:-len("</g>")]
        self.parts[i] = head + draw(*self.bounds[ident]) + "</g>"

    def paint_attrs(self, paint, extra_alpha=1.0):
        if isinstance(paint, Scheme):
            self.uses_scheme = True
        return paint.attrs(extra_alpha)

    def render(self):
        w = max(self.width, 16)
        h = self.y + self.row_h + 12
        # REUSE-IgnoreStart
        head = ('<?xml version="1.0" encoding="UTF-8"?>\n'
                f'<!-- Plasma Fusion Plasma style: {self.title}. Generated by generators/plasma-style; '
                'do not edit by hand. SPDX-License-Identifier: CC-BY-SA-4.0 -->\n'
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
                f'version="1.1" width="{fmt(w)}" height="{fmt(h)}" viewBox="0 0 {fmt(w)} {fmt(h)}">\n')
        # REUSE-IgnoreEnd
        style = ""
        if self.uses_scheme:
            style = f'<style type="text/css" id="current-color-scheme">{DEFAULT_STYLE}</style>\n'
        return head + style + "\n".join(self.parts) + "\n</svg>\n"


def bounds_rect(x, y, w, h):
    return (f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" '
            'style="fill:#000000;fill-opacity:0"/>')


def hint(doc, ident, w, h):
    """A hint element: only its size matters. Zero sizes become 0.001 (still valid)."""
    w = max(w, 0.001)
    h = max(h, 0.001)
    x, y = doc.place(max(w, 1), max(h, 1), gap=6)
    doc.add(f'<rect id="{doc.reg(ident)}" x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" '
            'style="fill:#ff00ff;fill-opacity:0"/>')


def margins_hint(doc, prefix, m):
    """prefix-hint-{top,bottom,left,right}-margin; m = (top, bottom, left, right)."""
    p = f"{prefix}-" if prefix else ""
    t, b, l, r = m
    hint(doc, f"{p}hint-top-margin", 2, t)
    hint(doc, f"{p}hint-bottom-margin", 2, b)
    hint(doc, f"{p}hint-left-margin", l, 2)
    hint(doc, f"{p}hint-right-margin", r, 2)


# --------------------------------------------------------------------------
# nine-slice frames
# --------------------------------------------------------------------------


@dataclass
class Frame:
    prefix: str
    radius: float
    layers: list
    margins: tuple = None              # (top, bottom, left, right) content padding
    insets: tuple = (0, 0, 0, 0)       # transparent space outside the shape (t, r, b, l)
    cells: tuple = None                # explicit cell sizes (t, r, b, l); default computed
    mask: bool = False
    stretch: float = 16                # length of the stretchable side/centre cells
    note: str = ""
    # The blur region is a 1-bit mask; a slightly larger corner radius keeps its
    # stair-stepped corner inside the anti-aliased edge (straight edges stay flush).
    mask_radius_extra: float = 3


def frame_cells(fr):
    if fr.cells:
        return fr.cells
    ext = max([fr.radius, 1] + [(l.inset + l.width) if isinstance(l, Ring) else l.inset for l in fr.layers])
    ext = math.ceil(ext)
    t, r, b, l = fr.insets
    return (t + ext, r + ext, b + ext, l + ext)


def add_frame(doc, fr, layers=None, id_prefix=None):
    """Emit the nine cells of `fr` (and its margins, and its mask when asked)."""
    layers = fr.layers if layers is None else layers
    pfx = fr.prefix if id_prefix is None else id_prefix
    p = f"{pfx}-" if pfx else ""
    ct, cr, cb, cl = frame_cells(fr)
    S = fr.stretch
    W, H = cl + S + cr, ct + S + cb
    doc.newline()
    ox, oy = doc.place(W, H)
    it, ir, ib, il = fr.insets
    shape = (ox + il, oy + it, ox + W - ir, oy + H - ib, fr.radius)
    xs = (ox, ox + cl, ox + cl + S, ox + W)
    ys = (oy, oy + ct, oy + ct + S, oy + H)
    if fr.note:
        doc.add(f"<!-- {fr.note} -->")
    for i, name in enumerate(CELLS):
        cx, cy = i % 3, i // 3
        cell = (xs[cx], ys[cy], xs[cx + 1], ys[cy + 1])
        corner = name if name in CORNERS else None
        body = [bounds_rect(cell[0], cell[1], cell[2] - cell[0], cell[3] - cell[1])]
        for lay in layers:
            if isinstance(lay, Fill):
                d = rr_cell_path(shape, lay.inset, cell, corner)
                if d:
                    body.append(f'<path {doc.paint_attrs(lay.paint)} d="{d}"/>')
            else:
                outer = rr_cell_path(shape, lay.inset, cell, corner)
                inner = rr_cell_path(shape, lay.inset + lay.width, cell, corner)
                if outer:
                    body.append(f'<path {doc.paint_attrs(lay.paint)} fill-rule="evenodd" d="{outer}{inner}"/>')
        ident = doc.reg(p + name)
        doc.bounds[ident] = (cell[0], cell[1], cell[2] - cell[0], cell[3] - cell[1])
        doc.index[ident] = len(doc.parts)
        doc.add(f'<g id="{ident}">' + "".join(body) + "</g>")
    if fr.margins is not None:
        margins_hint(doc, pfx, fr.margins)
    if fr.mask:
        doc.newline()
        mx, my = doc.place(W, H)
        dx, dy = mx - ox, my - oy
        mr = fr.radius + fr.mask_radius_extra if fr.radius > 0 else 0
        mshape = (shape[0] + dx, shape[1] + dy, shape[2] + dx, shape[3] + dy, mr)
        for i, name in enumerate(CELLS):
            cx, cy = i % 3, i // 3
            cell = (xs[cx] + dx, ys[cy] + dy, xs[cx + 1] + dx, ys[cy + 1] + dy)
            corner = name if name in CORNERS else None
            d = rr_cell_path(mshape, 0, cell, corner)
            body = bounds_rect(cell[0], cell[1], cell[2] - cell[0], cell[3] - cell[1])
            if d:
                body += f'<path style="fill:#000000" d="{d}"/>'
            doc.add(f'<g id="{doc.reg("mask-" + p + name)}">{body}</g>')


def add_element(doc, ident, w, h, draw):
    """A standalone element of size w x h. draw(x, y) returns SVG markup."""
    x, y = doc.place(w, h)
    doc.add(f'<g id="{doc.reg(ident)}">{bounds_rect(x, y, w, h)}{draw(x, y)}</g>')


# --------------------------------------------------------------------------
# pre-rendered shadows (CSS box-shadow equivalent), embedded as PNG
# --------------------------------------------------------------------------

SS = 4  # supersampling for anti-aliased coverage masks


def _rr_mask(size, box, r):
    """Anti-aliased coverage ('L') of a rounded rect box=(x0,y0,x1,y1) in an image of `size`."""
    W, H = size
    big = Image.new("L", (W * SS, H * SS), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        [box[0] * SS, box[1] * SS, box[2] * SS - 1, box[3] * SS - 1], radius=r * SS, fill=255)
    return big.resize((W, H), Image.BOX)


def shadow_coverage(size, box, r, dy, blur, spread=0, clear_r=None):
    """CSS box-shadow(0 dy blur spread) of a rounded rect, as an 'L' image.

    The result is already clipped by the box itself (CSS paints box-shadow only
    outside the border box), so it can sit under translucent surfaces. clear_r
    (default r) is the corner radius of that clip: a larger value keeps the
    shadow under the corners of frames with a larger radius that share the tiles.
    """
    sbox = (box[0] - spread, box[1] - spread + dy, box[2] + spread, box[3] + spread + dy)
    sh = _rr_mask(size, sbox, r + spread)
    if blur > 0:
        sh = sh.filter(ImageFilter.GaussianBlur(blur / 2.0))
    inside = _rr_mask(size, box, r if clear_r is None else clear_r)
    return ImageChops.multiply(sh, ImageChops.invert(inside))


def colorize(cov, color, alpha):
    """RGBA image of `color` whose alpha is coverage * alpha."""
    r, g, b = color
    img = Image.new("RGBA", cov.size, (r, g, b, 0))
    img.putalpha(cov.point(lambda v: int(round(v * alpha))))
    return img


def window_shadow(r, dy, blur, alpha, color, spread=0, corner="extended", wide=0, headroom=0, clear_r=None):
    """Tiles and paddings for a KWindowShadow (or a 'shadow' frame).

    corner="extended": corner tiles reach c=r px into the window so the shadow
    follows the rounded corner (KWin shadows). corner="frame": corner tiles are
    exactly padding-sized, as FrameSvg expects for a 'shadow' prefix frame.
    wide > 0 makes the bottom corner tiles `wide` px wider than their padding
    (they overlap and KWin splits them in the middle).
    headroom shifts the top padding down: the shadow belongs to a shape that
    starts `headroom` px below the window's top edge.
    clear_r > r keeps the shadow under the corners of a frame with that larger
    radius (for example a launcher prefix sharing the pop-up's shadow tiles).
    Returns (pads, tiles) with pads = dict(top, bottom, left, right).
    """
    sigma = blur / 2.0
    reach = int(math.ceil(2.5 * sigma)) + spread
    pad_t, pad_b = max(0, reach - dy), reach + dy
    pad_l = pad_r = reach
    c = int(math.ceil(max(r, clear_r or 0))) if corner == "extended" else 0
    cw = max(c, wide)
    bw = 2 * cw + 2 * reach + 8
    bh = 2 * c + 2 * reach + 8
    W, H = pad_l + bw + pad_r, pad_t + bh + pad_b
    box = (pad_l, pad_t, pad_l + bw, pad_t + bh)
    img = colorize(shadow_coverage((W, H), box, r, dy, blur, spread, clear_r), color, alpha)
    mx, my = W // 2, H // 2

    def crop(x0, y0, x1, y1):
        return img.crop((x0, y0, x1, y1))

    tiles = {
        "shadow-topleft": crop(0, 0, pad_l + c, pad_t + c),
        "shadow-top": crop(mx, 0, mx + 1, pad_t),
        "shadow-topright": crop(W - pad_r - c, 0, W, pad_t + c),
        "shadow-right": crop(W - pad_r, my, W, my + 1),
        "shadow-bottomright": crop(W - pad_r - cw, H - pad_b - c, W, H),
        "shadow-bottom": crop(mx, H - pad_b, mx + 1, H),
        "shadow-bottomleft": crop(0, H - pad_b - c, pad_l + cw, H),
        "shadow-left": crop(0, my, pad_l, my + 1),
    }
    pads = dict(top=pad_t - headroom, bottom=pad_b, left=pad_l, right=pad_r)
    return pads, tiles


def png_data_uri(img):
    buf = io.BytesIO()
    img.save(buf, format="PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


def add_image(doc, ident, img):
    w, h = img.size
    x, y = doc.place(w, h)
    doc.add(f'<image id="{doc.reg(ident)}" x="{fmt(x)}" y="{fmt(y)}" width="{w}" height="{h}" '
            f'preserveAspectRatio="none" xlink:href="{png_data_uri(img)}"/>')
