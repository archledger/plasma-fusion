# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, round 3 batch candidates.
from apptiles.kit import *  # noqa: F401,F403  helpers and palette
# Plasma Fusion app tiles, round 3, batch candidates: developer tools and a few common third-party apps.
import math
import re


# ---- local helpers ---------------------------------------------------------------------------

def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def ci_cw(cx, cy, r):
    """Circle drawn clockwise, so it unions with rr() shapes in a nonzero layer (ci() runs the other way)."""
    return (f"M{_f(cx - r)} {_f(cy)}a{_f(r)} {_f(r)} 0 1 1 {_f(2 * r)} 0"
            f"a{_f(r)} {_f(r)} 0 1 1 {_f(-2 * r)} 0z")


def tr(pts, s, ox, oy, c=(32, 30)):
    """Scale points by s about (ox, oy) and move that point to c."""
    return [(c[0] + (x - ox) * s, c[1] + (y - oy) * s) for x, y in pts]


def _cubic(p0, p1, p2, p3, n):
    out = []
    for k in range(n + 1):
        t = k / n; u = 1 - t
        out.append((u * u * u * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t * t * t * p3[0],
                    u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1]))
    return out


def ribbon(segs, widths, n=24):
    """Filled calligraphic stroke along cubic segments [(p0, p1, p2, p3), ...]; widths = [(fraction, w), ...]
    over the arc length, linearly interpolated. Ends are cut square (tapered by the width table)."""
    pts = []
    for sg in segs:
        c = _cubic(*sg, n)
        pts += c if not pts else c[1:]
    L = [0.0]
    for a, b in zip(pts, pts[1:]):
        L.append(L[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    left, right = [], []
    for i, p in enumerate(pts):
        a = pts[max(i - 1, 0)]; b = pts[min(i + 1, len(pts) - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]; d = math.hypot(dx, dy) or 1
        nx, ny = -dy / d, dx / d
        s = L[i] / L[-1]
        for (s0, w0), (s1, w1) in zip(widths, widths[1:]):
            if s0 <= s <= s1:
                w = w0 + (w1 - w0) * (s - s0) / ((s1 - s0) or 1)
                break
        left.append((p[0] + nx * w / 2, p[1] + ny * w / 2))
        right.append((p[0] - nx * w / 2, p[1] - ny * w / 2))
    return poly(*(left + right[::-1]))


_TOK = re.compile(r"[MLHVCSQTAZmlhvcsqtaz]|-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")
_NARGS = dict(M=2, L=2, H=1, V=1, C=6, S=4, Q=4, T=2, A=7, Z=0)


def xf(d, s, tx, ty):
    """Uniformly scale (s) and translate (tx, ty) an SVG path with absolute and relative commands."""
    toks = _TOK.findall(d)
    out, i, cmd = [], 0, None
    while i < len(toks):
        t = toks[i]
        if t.isalpha():
            cmd = t; i += 1
            if cmd in "Zz":
                out.append("z"); continue
        n = _NARGS[cmd.upper()]
        a = [float(v) for v in toks[i:i + n]]; i += n
        rel_ = cmd.islower(); U = cmd.upper()
        if U == "H":
            v = [a[0] * s + (0 if rel_ else tx)]
        elif U == "V":
            v = [a[0] * s + (0 if rel_ else ty)]
        elif U == "A":
            v = [a[0] * s, a[1] * s, a[2], a[3], a[4],
                 a[5] * s + (0 if rel_ else tx), a[6] * s + (0 if rel_ else ty)]
        else:
            v = [a[k] * s + (0 if rel_ else (tx if k % 2 == 0 else ty)) for k in range(n)]
        out.append(cmd + " ".join(_f(x) if k not in (3, 4) or U != "A" else str(int(x)) for k, x in enumerate(v)))
        if cmd == "M":
            cmd = "L"
        elif cmd == "m":
            cmd = "l"
    return "".join(out)


# ---- marks -----------------------------------------------------------------------------------

# Ghostty: a white ghost (round head, three scalloped hems) on a dark terminal screen, prompt face.
GHOST = ('M19 27A13 13 0 0 1 45 27V41.6A4.33 4.33 0 0 1 36.33 41.6A4.33 4.33 0 0 1 27.67 41.6'
         'A4.33 4.33 0 0 1 19 41.6Z')

# Neovim: the faceted N (blue left pillar with a green cap, olive diagonal, green right pillar),
# taken from the logo's proportions.
_NV = dict(s=0.08, ox=782.5, oy=260)
NV_LEFT = poly(*tr([(575, 115), (683, 10), (683, 510), (575, 405)], **_NV))
NV_CAP = poly(*tr([(608, 88), (683, 10), (683, 205)], **_NV))
NV_DIAG = poly(*tr([(683, 10), (883, 315), (883, 510), (683, 205)], **_NV))
NV_RIGHT = poly(*tr([(883, 10), (990, 115), (990, 405), (883, 510)], **_NV))

# Emacs: the white calligraphic E ribbon (four turns, flared start, thin second turn, tapered tail)
# on the purple badge.
EMACS_E = ribbon([((43.5, 13.6), (32, 13.4), (22.5, 15), (22.6, 19)),
                  ((22.6, 19), (22.7, 22.6), (37.5, 21.4), (37.4, 24.8)),
                  ((37.4, 24.8), (37.3, 28.6), (18.2, 29.8), (18.6, 35.6)),
                  ((18.6, 35.6), (19, 40), (40, 36.6), (44.4, 39)),
                  ((44.4, 39), (49, 41.6), (38, 46.4), (25.5, 46.4))],
                 [(0, 5.6), (0.12, 4.4), (0.27, 3.2), (0.36, 2.6), (0.5, 4.8), (0.66, 4.6), (0.8, 4.4),
                  (0.9, 3.4), (1, 1.4)])

# Docker: Moby the whale (head left, tail and fluke right) carrying the 5-3-1 container stack.
DOCKER_WHALE = ('M22.763 10.036c-.065-.05-.651-.497-1.889-.497-.327 0-.654.03-.977.088-.24-1.663-1.61-2.47-1.67-2.507'
                'l-.333-.193-.22.317a4.523 4.523 0 0 0-.598 1.388c-.218.932-.085 1.81.384 2.554-.565.314-1.484.393'
                '-1.67.4H.752a.75.75 0 0 0-.75.75 11.41 11.41 0 0 0 .7 4.12c.553 1.448 1.375 2.515 2.443 3.168 1.197'
                '.732 3.142 1.152 5.348 1.152.997.003 1.993-.088 2.973-.27a12.29 12.29 0 0 0 3.877-1.41 10.66 10.66 0 0 0'
                ' 2.645-2.165c1.27-1.44 2.028-3.044 2.588-4.469h.224c1.39 0 2.246-.556 2.718-1.023.312-.297.555-.658.713'
                '-1.059l.1-.29z')
_DK_S, _DK_TX, _DK_TY = 1.82, 10.2, 9.6     # round-3 review: was 1.87 / 10.0 / 9.2, the tail ran past x 54


def _docker_boxes():
    out = []
    w, g = 2.5, 0.42
    for row, cols in ((0, range(5)), (1, range(1, 4)), (2, (3,))):
        for c in cols:
            x = 2.15 + c * (w + g)
            y = 7.85 - row * (w + g)
            out.append(rr(x * _DK_S + _DK_TX, y * _DK_S + _DK_TY, w * _DK_S, w * _DK_S, 0.6))
    return ''.join(out)


# 1Password: the keyhole bar with its two offset notches.
OP_KEY = poly((29.3, 21.6), (34.7, 21.6), (34.7, 31.2), (33, 32.8), (34.7, 34.4), (34.7, 38.4),
              (29.3, 38.4), (29.3, 28.8), (31, 27.2), (29.3, 25.6))

# Proton Mail: the open M envelope; left flap and right side panel lighter.
PM_BODY = ('M14 17.4a2.4 2.4 0 0 1 3.9-1.9L30.3 29.6Q32 31 33.7 29.6L46.1 15.5a2.4 2.4 0 0 1 3.9 1.9V42a3 3 0 0 1-3 3H17a3 3 0 0 1-3-3z')
PM_LEFT = 'M14 17.4a2.4 2.4 0 0 1 3.9-1.9L31.2 30.1 14 23.5z'
PM_RIGHT = 'M42.2 19.9L46.1 15.5a2.4 2.4 0 0 1 3.9 1.9V42a3 3 0 0 1-3 3h-4.8z'


# ---- tiles -----------------------------------------------------------------------------------

TILES = {
    'ghostty': dict(label='Ghostty', base='#3a56e0', lip='#2a3fb0',
                    g1=rr(12, 11, 40, 38, 8), c1='#1b2031',
                    g2=GHOST, c2='#ffffff',
                    s1='M25 22.5l4.6 4-4.6 4M32.5 31h7', sc='#3a56e0', sw=3),
    'wezterm': dict(label='WezTerm', base='#262c42', lip='#131726',
                    s1=xf('M25.5 21c-1.4-2.4-3.6-3.5-6.5-3.5-3.9 0-6 2.1-6 5 0 7.5 12.5 4.5 12.5 12 0 3.3-2.6 5.5-6.6 5.5'
                          '-3 0-5.4-1.2-6.6-3.6M19 13v32M29.5 17.5l4.3 23 5.2-17 5.2 17 4.3-23', 1, 1.4, 0),
                    sc='#8580ff', sw=3.6),
    'zed': dict(label='Zed', base='#262c42', lip='#131726',
                s1='M14.5 37V13.5h35L14.5 46.5h35V23M20.5 33V19.5H37.5M43.5 27V40.5H26.5', sc='#ffffff', sw=2.8),
    'emacs': dict(label='Emacs', base='#8c4cc8', lip='#683596',
                  g1=ci(32, 30, 19.5), c1='#a378d8',
                  x=[(EMACS_E, '#ffffff')]),
    'neovim': dict(label='Neovim', base='#f4f5f9', lip='#d5d9e3',
                   g1=NV_LEFT, c1='#3b8fd6', g2=NV_RIGHT, c2='#62b543', g3=NV_DIAG, c3='#3f8a3c',
                   x=[(NV_CAP, '#62b543')]),
    'wireshark': dict(label='Wireshark', base='#1b84c0', lip='#13618d',
                      g1='M14.8 41.4C16.8 28.5 28 14.5 46 10.8C49 10.2 50.6 11.8 49.6 13.8C46 19.5 44.5 27 45 34'
                         'C45.3 37 46 39.4 47.2 41.4Z', c1='#ffffff',
                      s1='M12.5 42.2c4-2.6 8-2.6 12 0s8 2.6 12 0 8-2.6 12 0M14.5 47c3.5-2.2 7-2.2 10.5 0s7 2.2 10.5 0'
                         ' 7-2.2 10.5 0', sc='#bfe3f7', sw=2.4),
    'docker-desktop': dict(label='Docker Desktop', base='#1d63ed', lip='#1549b5',
                           g1=xf(DOCKER_WHALE, _DK_S, _DK_TX, _DK_TY), c1='#ffffff',
                           g3=_docker_boxes(), c3='#ffffff'),
    'onepassword': dict(label='1Password', base='#f4f5f9', lip='#d5d9e3',
                        g2=ring(32, 30, 18.5, 12.5), c2='#1b72e0',
                        g3=OP_KEY, c3='#1b2031'),
    'proton-mail': dict(label='Proton Mail', base='#6447e0', lip='#4b35a8',
                        g1=PM_BODY, c1='#ffffff',
                        g3=PM_LEFT + PM_RIGHT, c3='#d9ccff'),
}

APPS = {
    'com.mitchellh.ghostty': 'ghostty',
    'org.wezfurlong.wezterm': 'wezterm',
    'dev.zed.Zed': 'zed',
    'org.gnu.emacs': 'emacs',
    'io.neovim.nvim': 'neovim',
    'org.wireshark.Wireshark': 'wireshark',
    'docker-desktop': 'docker-desktop',
    'com.onepassword.OnePassword': 'onepassword',
    'me.proton.Mail': 'proton-mail',
}
