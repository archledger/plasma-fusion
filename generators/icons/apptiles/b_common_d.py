# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Plasma Fusion app tiles, batch common-d (popular third-party system apps).
import math

from apptiles.kit import *  # noqa: F401,F403


def _f(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def pt(cx, cy, r, a):
    """Point on a circle; a in degrees, 0 = +x, positive = clockwise on screen."""
    t = math.radians(a)
    return cx + r * math.cos(t), cy + r * math.sin(t)


def arc(cx, cy, r, a0, a1):
    """Open arc path from a0 to a1 (a1 > a0, clockwise), for strokes."""
    x0, y0 = pt(cx, cy, r, a0)
    x1, y1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return f"M{_f(x0)} {_f(y0)}A{_f(r)} {_f(r)} 0 {large} 1 {_f(x1)} {_f(y1)}"


def band(cx, cy, ro, ri, a0, a1):
    """Annular sector from a0 to a1 (clockwise), a filled ring segment."""
    p0 = pt(cx, cy, ro, a0); p1 = pt(cx, cy, ro, a1)
    q1 = pt(cx, cy, ri, a1); q0 = pt(cx, cy, ri, a0)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(p0[0])} {_f(p0[1])}A{_f(ro)} {_f(ro)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}"
            f"L{_f(q1[0])} {_f(q1[1])}A{_f(ri)} {_f(ri)} 0 {large} 0 {_f(q0[0])} {_f(q0[1])}z")


def wedge(cx, cy, r, a0, a1):
    p0 = pt(cx, cy, r, a0); p1 = pt(cx, cy, r, a1)
    large = 1 if (a1 - a0) % 360 > 180 else 0
    return (f"M{_f(cx)} {_f(cy)}L{_f(p0[0])} {_f(p0[1])}"
            f"A{_f(r)} {_f(r)} 0 {large} 1 {_f(p1[0])} {_f(p1[1])}z")


def xform(pts, ang, tx, ty):
    """Rotate points by ang degrees about the origin, then translate."""
    c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(x * c - y * s + tx, x * s + y * c + ty) for x, y in pts]


def cw(pts):
    """Clockwise (on screen) orientation, so nonzero unions never cancel."""
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]))
    return pts if a > 0 else pts[::-1]


def wrench(hx, hy, ang, r=7.0, slot=2.6, depth=-1.0, hw=3.0, length=24.0):
    """Open-end wrench: head centred on (hx, hy) with its jaw opening away from the handle,
    the handle running along angle ang (degrees)."""
    a0 = math.degrees(math.asin(slot / r))
    head = [(depth, -slot)]
    for k in range(0, 41):
        a = 180 + a0 + (360 - 2 * a0) * k / 40
        head.append((r * math.cos(math.radians(a)), r * math.sin(math.radians(a))))
    head.append((depth, slot))
    handle = [(2, -hw), (length, -hw)]
    for k in range(1, 12):
        a = -90 + 180 * k / 12
        handle.append((length + hw * math.cos(math.radians(a)), hw * math.sin(math.radians(a))))
    handle += [(length, hw), (2, hw)]
    return poly(*cw(xform(head, ang, hx, hy))) + poly(*cw(xform(handle, ang, hx, hy)))


# --- Syncthing node geometry (from the logo: three nodes on the ring, one inside) -------------
_ST_C, _ST_R = (32, 30), 16.5
_ST_L = pt(*_ST_C, _ST_R, 165)
_ST_UR = pt(*_ST_C, _ST_R, -26)
_ST_LR = pt(*_ST_C, _ST_R, 49)
_ST_M = (34.5, 31.5)

# --- BleachBit broom geometry ------------------------------------------------------------------
_BB_A, _BB_B = (13.0, 10.0), (27.0, 29.0)


def _bb_axis(t):
    d = (_BB_B[0] - _BB_A[0], _BB_B[1] - _BB_A[1]); n = math.hypot(*d)
    u = (d[0] / n, d[1] / n)
    return (_BB_A[0] + u[0] * t, _BB_A[1] + u[1] * t), (-u[1], u[0])


def _bb_quad(t0, w0, t1, w1, off=0.0):
    (c0, n), (c1, _) = _bb_axis(t0), _bb_axis(t1)
    o0, o1 = off * (8 + (20 - 8) * (t0 - 21) / 19), off * 20
    c0 = (c0[0] + n[0] * o0, c0[1] + n[1] * o0); c1 = (c1[0] + n[0] * o1, c1[1] + n[1] * o1)
    return poly((c0[0] + n[0] * w0 / 2, c0[1] + n[1] * w0 / 2), (c0[0] - n[0] * w0 / 2, c0[1] - n[1] * w0 / 2),
                (c1[0] - n[0] * w1 / 2, c1[1] - n[1] * w1 / 2), (c1[0] + n[0] * w1 / 2, c1[1] + n[1] * w1 / 2))


def _bb_brush(t0=21.0, w0=8.0, t1=40.5, w1=21.0, teeth=4, depth=3.2):
    """Broom head: a fan widening along the handle axis, its far edge serrated into bristle tufts."""
    def at(t, v):
        c, n = _bb_axis(t)
        return (c[0] + n[0] * v, c[1] + n[1] * v)
    pts = [at(t0, -w0 / 2), at(t0, w0 / 2)]
    for k in range(teeth * 2 + 1):
        v = w1 / 2 - w1 * k / (teeth * 2)
        pts.append(at(t1 if k % 2 == 0 else t1 - depth, v))
    return poly(*pts)


TILES = {
    # Flatseal: the roll of tape (white roll, tan core) seen slightly from the front.
    # Review: base moved off amber (a white ring on amber/orange sat next to Showfoto's and Lutris's rings).
    'flatseal': dict(label='Flatseal', base='#475069', lip='#323950',
                     g1=ci(34, 32, 16.5), c1='#dcb985',
                     g2=ring(30.5, 28, 16.5, 9.2), c2='#ffffff',
                     g3=ring(30.5, 28, 9.2, 6.4), c3='#d9a865',
                     x=[(ci(30.5, 28, 6.4), '#475069')]),
    # GParted: a drive seen from above whose platter is the partition pie (green, orange, red).
    'gparted': dict(label='GParted', base='#3aa65b', lip='#2a7e44',
                    g1=rr(12, 12, 40, 36, 6), c1='#ffffff',
                    g2=ci(32, 28.5, 13) + rr(23, 43, 18, 3, 1.5), c2='#3aa65b',
                    g3=wedge(32, 28.5, 13, 185, 250), c3='#f2a65a',
                    x=[(wedge(32, 28.5, 13, 345, 410), '#e5484d'), (ci(32, 28.5, 3.4), '#ffffff')]),
    # Timeshift: a clock turned back by a counter-clockwise arrow (restore a snapshot).
    'timeshift': dict(label='Timeshift', base='#e8743b', lip='#b8552a',
                      s1=arc(32, 30, 16, 180, 480) + 'M32 30V21.5M32 30l6 4', sc='#ffffff', sw=3.6,
                      g3=poly((10, 27.5), (22, 27.5), (16, 35.5)), c3='#ffffff',
                      x=[(ci(32, 30, 2.6), '#ffffff')]),
    # VirtualBox: the blue cube.
    'virtualbox': dict(label='VirtualBox', base='#262c42', lip='#131726',
                       g1=poly((32, 10.5), (49, 20), (32, 29.5), (15, 20)), c1='#ffffff',
                       g2=poly((15, 20), (32, 29.5), (32, 49), (15, 39.5)), c2='#bcd4ff',
                       g3=poly((32, 29.5), (49, 20), (49, 39.5), (32, 49)), c3='#5b9dff',
                       # review: seams widened to the 2.4 minimum and pulled in from the corners (the round caps
                       # poked out of the cube's outline as dark nubs)
                       s1='M16.6 20.9 32 29.5 47.4 20.9M32 29.5V47.6', sc='#262c42', sw=2.4),
    # Virtual Machine Manager: the VMM mark (maroon V, grey MM).
    'virt-manager': dict(label='Virtual Machine Manager', base='#f4f5f9', lip='#d5d9e3',
                         g1=poly((10.2, 19.5), (15.2, 19.5), (17.4, 31), (19.6, 19.5), (24.6, 19.5), (19.8, 40.5),
                                 (15, 40.5)), c1='#c93a42',  # review: V moved right, MM left, into x 10-54
                         s1='M24.2 39 27 21.5 30.2 32.5 33.4 21.5 36.2 39M39.8 39 42.6 21.5 45.8 32.5 49 21.5 51.8 39',
                         sc='#3b4255', sw=3.8),
    # GNOME Boxes: the wireframe box with round joints.
    'gnome-boxes': dict(label='GNOME Boxes', base='#9b3fb5', lip='#742d88',
                        s1='M15 13H49V47H15ZM25 23H39V37H25ZM15 13l10 10M49 13 39 23M49 47 39 37M15 47l10-10',
                        sc='#ffffff', sw=3,
                        g3=ci(15, 13, 4) + ci(49, 13, 4) + ci(49, 47, 4) + ci(15, 47, 4), c3='#ffffff',
                        x=[(ci(25, 23, 3.1) + ci(39, 23, 3.1) + ci(39, 37, 3.1) + ci(25, 37, 3.1), '#ffffff')]),
    # Remmina: blue and green ring around the interlocked >< chevrons.
    'remmina': dict(label='Remmina', base='#f4f5f9', lip='#d5d9e3',
                    g1=band(32, 30, 18, 14.2, 150, 318) + poly((41, 26.5), (45.5, 26.5), (39.5, 33.5), (45.5, 40.5),
                                                                (41, 40.5), (35, 33.5)), c1='#3b82f0',
                    g2=band(32, 30, 18, 14.2, 330, 498) + poly((19, 19.5), (23.5, 19.5), (29.5, 26.5), (23.5, 33.5),
                                                                (19, 33.5), (25, 26.5)), c2='#2fa25a'),
    # FileZilla: the white Fz monogram on red.
    'filezilla': dict(label='FileZilla', base='#c8282b', lip='#961e20',
                      g1=poly((14, 46), (20.5, 46), (22.6, 33), (31.6, 33), (32.4, 27.5), (23.5, 27.5),
                              (24.6, 20.5), (36, 20.5), (36.9, 14), (19, 14)), c1='#ffffff',
                      g2=poly((31.5, 24.5), (50.5, 24.5), (49.8, 29.5), (37.5, 40.5), (47.5, 40.5),
                              (46.6, 46), (27, 46), (27.8, 41), (40.5, 29.5), (30.8, 29.5)), c2='#ffffff'),
    # qBittorrent: the qb monogram on the blue badge.
    'qbittorrent': dict(label='qBittorrent', base='#3f7fe0', lip='#2b5db5',
                        g1=ci(32, 30, 19.5), c1='#5b9dff',
                        g2=ring(22.5, 31, 8.5, 5) + ring(41.5, 31, 8.5, 5), c2='#ffffff',
                        g3=rr(27.5, 23, 3.5, 23.5, 1.2) + rr(33, 12.5, 3.5, 27, 1.2), c3='#ffffff'),
    # Transmission: the red drum over a white box with the dark down arrow.
    'transmission': dict(label='Transmission', base='#5b6478', lip='#414859',
                         g1=rr(15, 20, 34, 28, 4), c1='#ffffff',
                         g2=rr(11, 11.5, 42, 11, 5.5), c2='#e5484d',
                         g3=rr(28.5, 11.5, 7, 21, 1) + poly((19, 30), (45, 30), (32, 44)), c3='#1b2031'),
    # Bitwarden: the shield, inner right half filled.
    'bitwarden': dict(label='Bitwarden', base='#175ddc', lip='#1146a5',
                      g1='M16 11H48V29C48 38.5 41 45 32 49.5 23 45 16 38.5 16 29Z', c1='#ffffff',
                      g2='M20.5 15.5H32V44.2C25 40.5 20.5 35.5 20.5 29Z', c2='#175ddc'),
    # KeePassXC: the white key inside the dark ring on green.
    'keepassxc': dict(label='KeePassXC', base='#56a832', lip='#407e25',
                      g2=ring(32, 30, 19.5, 16.3), c2='#1b2031',
                      g3=ci(32, 21.5, 6.8) + ci(32, 20.3, 2.5), c3='#ffffff',
                      x=[(poly((29.5, 26), (34.5, 26), (34.5, 33.5), (39, 33.5), (39, 36.7), (34.5, 36.7),
                               (34.5, 38.7), (38, 38.7), (38, 41.9), (34.5, 41.9), (34.5, 43), (32, 45.5),
                               (29.5, 43)), '#ffffff')]),
    # Proton VPN: the folded downward triangle.
    'protonvpn': dict(label='Proton VPN', base='#6447e0', lip='#4b35a8',
                      g1=poly((15, 14.5), (49.5, 20.5), (29.5, 47.5)), c1='#ffffff',
                      s1='M15 14.5 49.5 20.5 29.5 47.5Z', sc='#ffffff', sw=4,
                      g3=poly((26, 19.5), (46, 23), (30.5, 42)), c3='#3cc4b0'),
    # Mullvad VPN: the mole in the yellow hard hat, facing left.
    'mullvad-vpn': dict(label='Mullvad VPN', base='#22406a', lip='#152a47',
                        g1='M13 21.6C17 21 21 22 25 23L49.5 23C49.5 28 48 32 47.5 36 48.5 41 51 46 53.5 50H22.5'
                           'C24.5 44 25.5 38 27 32.5 21.5 30.5 17 28 13.5 26 11.5 25.2 11.2 22.4 13 21.6Z',
                        c1='#f2a65a',
                        g2='M21.5 24.6 50.5 23C50.5 14 44.5 8.8 37.5 9 30.5 9.2 26.5 14 25.5 20.5Z'
                           + ci(33, 15.6, 2.7), c2='#f7c948',
                        x=[(ci(13.2, 23.8, 2.1) + ci(29.5, 26.8, 1.8), '#1b2031')]),
    # Nextcloud: the three rings, the middle one larger.
    'nextcloud': dict(label='Nextcloud', base='#1484c4', lip='#0f6393',
                      g2=ring(32, 30, 8.6, 5.2) + ring(16, 30, 5.7, 3.1) + ring(48, 30, 5.7, 3.1),
                      c2='#ffffff'),
    # Syncthing: the ring with its node network.
    'syncthing': dict(label='Syncthing', base='#22a3d8', lip='#197aa2',
                      s1=ci(32, 30, _ST_R) + 'M%s %sL%s %sL%s %sM%s %sL%s %sL%s %s' % (
                          _f(_ST_L[0]), _f(_ST_L[1]), _f(_ST_M[0]), _f(_ST_M[1]), _f(_ST_UR[0]), _f(_ST_UR[1]),
                          _f(_ST_M[0]), _f(_ST_M[1]), _f(_ST_LR[0]), _f(_ST_LR[1]), _f(_ST_UR[0]), _f(_ST_UR[1])),
                      sc='#ffffff', sw=3,
                      g3=ci(*_ST_L, 3.6) + ci(*_ST_UR, 3.6) + ci(*_ST_LR, 3.6) + ci(*_ST_M, 3.4), c3='#ffffff'),
    # LocalSend: the dashed ring around the solid disc.
    'localsend': dict(label='LocalSend', base='#1f9e8f', lip='#15756a',
                      s1=''.join(arc(32, 30, 16.5, a - 10, a + 10) for a in range(0, 360, 45)), sc='#ffffff', sw=4.4,
                      g3=ci(32, 30, 9.5), c3='#ffffff'),
    # Mission Center: the light panel with a sidebar of graphs and a big pulse screen.
    # review: blue instead of slate-dark; on slate-dark it sat beside board:monitor (Plasma System Monitor),
    # the same dark tile with a teal line chart in a dark screen
    'mission-center': dict(label='Mission Center', base='#3f7fe0', lip='#2b5db5',
                           g1=rr(11, 13, 42, 34, 5), c1='#ffffff',
                           g2=rr(14.5, 16.5, 10.5, 27, 2.5) + rr(28, 16.5, 21.5, 3.2, 1.6)
                              + rr(28, 22.5, 21.5, 14, 2.5) + rr(28, 39.8, 21.5, 3.2, 1.6), c2='#1b2031',
                           s1='M30.5 29.5H35l2-4.5 2.5 8.5 2-4H47M17.5 21.5h4.5M17.5 27h4.5M17.5 32.5h4.5M17.5 38h4.5',
                           sc='#3cc4b0', sw=2.4),
    # BleachBit: the yellow broom sweeping over a drive.
    'bleachbit': dict(label='BleachBit', base='#5a2ca0', lip='#3e1e70',
                      g1=rr(24, 32, 29, 16, 4), c1='#ffffff',
                      g2=rr(38, 42, 11, 3, 1.5), c2='#d9ccff',
                      s1='M12.5 9.5 26 27.6', sc='#f2a65a', sw=3.6,
                      g3=_bb_brush(),
                      c3='#f7c948',
                      x=[(_bb_quad(17.5, 9.4, 22.5, 9.4), '#f2a65a')]),
    # GNOME Disks: a drive with the wrench across it.
    'gnome-disks': dict(label='GNOME Disks', base='#5b6478', lip='#414859',
                        g1=rr(14, 11, 36, 38, 5), c1='#ffffff',
                        g2=ring(32, 27, 12, 4.2) + rr(22, 43, 20, 3, 1.5), c2='#d5dae6',
                        g3=wrench(25.5, 23.5, 45), c3='#1b2031'),
}

APPS = {
    'com.github.tchx84.Flatseal': 'flatseal',
    'gparted': 'gparted',
    'timeshift': 'timeshift',
    'virtualbox': 'virtualbox',
    'virt-manager': 'virt-manager',
    'org.gnome.Boxes': 'gnome-boxes',
    'org.remmina.Remmina': 'remmina',
    'filezilla': 'filezilla',
    'org.qbittorrent.qBittorrent': 'qbittorrent',
    'com.transmissionbt.Transmission': 'transmission',
    'com.bitwarden.desktop': 'bitwarden',
    'org.keepassxc.KeePassXC': 'keepassxc',
    'com.protonvpn.www': 'protonvpn',
    'mullvad-vpn': 'mullvad-vpn',
    'com.nextcloud.desktopclient.nextcloud': 'nextcloud',
    'syncthing-gtk': 'syncthing',
    'org.localsend.localsend_app': 'localsend',
    'io.missioncenter.MissionCenter': 'mission-center',
    'org.bleachbit.BleachBit': 'bleachbit',
    'org.gnome.DiskUtility': 'gnome-disks',
}
