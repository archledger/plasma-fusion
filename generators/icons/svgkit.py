# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Small SVG toolkit for the Plasma Fusion icon generator (Python standard library only).

The path helpers rr/ci/el/gear are ports of the helpers in the design boards
(AppIcon.dc.html, FileIcons.dc.html) and produce the same path data.
"""
import math
import re


def fmt(v):
    """Format a number the way the boards' JavaScript prints it, without float noise."""
    if isinstance(v, int):
        return str(v)
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    if s in ('-0', ''):
        return '0'
    return s


def rr(x, y, w, h, r):
    """Rounded rectangle, same command sequence as the boards' rr()."""
    return (f"M{fmt(x + r)} {fmt(y)}h{fmt(w - 2 * r)}a{fmt(r)} {fmt(r)} 0 0 1 {fmt(r)} {fmt(r)}"
            f"v{fmt(h - 2 * r)}a{fmt(r)} {fmt(r)} 0 0 1 {fmt(-r)} {fmt(r)}h{fmt(-(w - 2 * r))}"
            f"a{fmt(r)} {fmt(r)} 0 0 1 {fmt(-r)} {fmt(-r)}v{fmt(-(h - 2 * r))}"
            f"a{fmt(r)} {fmt(r)} 0 0 1 {fmt(r)} {fmt(-r)}z")


def ci(cx, cy, r):
    return f"M{fmt(cx - r)} {fmt(cy)}a{fmt(r)} {fmt(r)} 0 1 0 {fmt(2 * r)} 0a{fmt(r)} {fmt(r)} 0 1 0 {fmt(-2 * r)} 0z"


def el(cx, cy, rx, ry):
    return (f"M{fmt(cx - rx)} {fmt(cy)}a{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(2 * rx)} 0"
            f"a{fmt(rx)} {fmt(ry)} 0 1 0 {fmt(-2 * rx)} 0z")


def gear(cx, cy, ro, ri, n):
    half = math.pi / n
    tw = half * 0.42
    g = half * 0.14
    pts = []
    for k in range(n):
        a = k * 2 * half - math.pi / 2
        pts += [(ri, a - half + g), (ro, a - tw), (ro, a + tw), (ri, a + half - g)]
    return 'M' + 'L'.join('%.2f %.2f' % (cx + p[0] * math.cos(p[1]), cy + p[0] * math.sin(p[1])) for p in pts) + 'Z'


def color_attr(prefix, value):
    """Return fill/stroke attributes for a colour; rgba() becomes colour + opacity for QtSvg."""
    if value is None or value == 'none':
        return f'{prefix}="none"'
    m = re.fullmatch(r'rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([0-9.]+)\s*\)', value)
    if m:
        r, g, b, a = int(m.group(1)), int(m.group(2)), int(m.group(3)), float(m.group(4))
        return f'{prefix}="#{r:02x}{g:02x}{b:02x}" {prefix}-opacity="{fmt(a)}"'
    return f'{prefix}="{value}"'


_NUM = re.compile(r'-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')


def transform_abs_path(d, scale, tx, ty):
    """Scale and translate a path that uses only absolute M/L/C/Q/Z commands."""
    out = []
    for cmd, args in re.findall(r'([MLCQZmlcqz])([^MLCQZmlcqz]*)', d):
        if cmd in 'Zz':
            out.append('Z')
            continue
        if cmd.islower():
            raise ValueError('relative commands are not supported: ' + cmd)
        nums = [float(n) for n in _NUM.findall(args)]
        pairs = []
        for i in range(0, len(nums), 2):
            pairs.append(f"{fmt(nums[i] * scale + tx)} {fmt(nums[i + 1] * scale + ty)}")
        out.append(cmd + ' '.join(pairs))
    return ''.join(out)


class Svg:
    """Collects elements and serialises a small, plain SVG document.

    No DOCTYPE, entities, external references, <text> or filters: KIconLoader re-serialises
    the file with QXmlStreamReader/Writer and QtSvg renders it, GTK may render it with librsvg.
    """

    def __init__(self, size, style=None):
        self.size = size
        self.style = style
        self.items = []

    def fill(self, d, color, evenodd=False, cls=None, opacity=None):
        if not d or color in (None, 'none'):
            return self
        extra = ''
        if cls:
            extra += f' class="{cls}"'
        if evenodd:
            extra += ' fill-rule="evenodd"'
        if opacity is not None:
            extra += f' opacity="{fmt(opacity)}"'
        self.items.append(f'<path{extra} d="{d}" {color_attr("fill", color)}/>')
        return self

    def stroke(self, d, color, width, cls=None, opacity=None, cap='round', join='round'):
        if not d or color in (None, 'none') or not width:
            return self
        extra = ''
        if cls:
            extra += f' class="{cls}"'
        if opacity is not None:
            extra += f' opacity="{fmt(opacity)}"'
        self.items.append(f'<path{extra} d="{d}" fill="none" {color_attr("stroke", color)} '
                          f'stroke-width="{fmt(width)}" stroke-linecap="{cap}" stroke-linejoin="{join}"/>')
        return self

    def raw(self, text):
        self.items.append(text)
        return self

    def render(self):
        s = self.size
        head = f'<svg xmlns="http://www.w3.org/2000/svg" width="{s}" height="{s}" viewBox="0 0 {s} {s}">'
        body = []
        if self.style:
            body.append(f'<style type="text/css" id="current-color-scheme">{self.style}</style>')
        body.extend(self.items)
        return head + '\n' + '\n'.join(body) + '\n</svg>\n'
