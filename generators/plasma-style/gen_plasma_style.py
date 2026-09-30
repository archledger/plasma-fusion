#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Generate the Plasma Fusion Plasma styles (desktop themes).

    gen_plasma_style.py OUTDIR [--variant dark|light|all]
                        [--south-frame headroom|plain] [--north-side-margin 6|0]

Writes OUTDIR/plasma-fusion-dark/ and/or OUTDIR/plasma-fusion-light/, each a
complete Plasma/Theme package with plain .svg files, metadata.json and plasmarc.
Every value comes from the design boards (design/boards/*.dc.html); the board
and the CSS it quotes are named next to each token below.

Panel frame switches (defaults = the frames deployed since round 2):
  --south-frame headroom  the `south` frame is the dock contract: 16 px transparent,
                          unblurred headroom inside an 88 px panel, 72 px frosted dock.
  --south-frame plain     `south` is a plain floating bar (any bottom panel of 44 px or
                          more keeps its thickness; applets get thickness - 8). The
                          headroom moves above the frame: floating-hint-top-margin 16, so
                          a floating panel window is 16 + thickness + 16 px tall and the
                          dock (72 px thick) draws its magnified icons into the top 16 px.
  --north-side-margin 6|0 left/right margin of the `north` (top bar) frame. With 0 the
                          panel containment keeps only its own 4 px row spacing at the
                          screen edges, and the edge plasmoids pad themselves.

Surface colours are fixed per variant (the style never takes surface fills from
the colour scheme). Controls inside pop-ups use colour-scheme classes so they
follow the accent colour: ColorScheme-Highlight (accent fill), ColorScheme-
ButtonFocus (focus ring), ColorScheme-Text (neutral tints).
"""
import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from svgkit import (RGBA, Scheme, Fill, Ring, Frame, Doc, add_frame, add_element,  # noqa: E402
                    add_image, hint, margins_hint, window_shadow, rr_full_path, circle_path, fmt)

VERSION = "1.0"

# ---------------------------------------------------------------------------
# design tokens
# ---------------------------------------------------------------------------
WHITE = (255, 255, 255)
INK = (20, 24, 39)          # #141827, light-scheme text; light boards tint with rgba(20,24,39,a)
BLACK = (0, 0, 0)

VARIANTS = {
    "dark": dict(
        id="plasma-fusion-dark", name="Plasma Fusion Dark",
        description="Frosted dark shell surfaces for the Plasma Fusion desktop",
        # Popups.dc.html / QuickSettings.dc.html: rgba(22,27,46,0.88-0.90), border rgba(255,255,255,0.12),
        # box-shadow 0 18px 44px rgba(0,0,0,0.45), radius 18-22 (tray panel and quick settings 22)
        popup=dict(fill=(22, 27, 46), a=0.88, edge=(WHITE, 0.12), radius=22,
                   shadow=dict(dy=18, blur=44, color=BLACK, alpha=0.45)),
        # Launcher.dc.html: radius 26, rgba(22,27,46,0.86); Popups.dc.html OSD: radius 30, 0.88
        launcher=dict(radius=26, a=0.86), osd=dict(radius=30, a=0.88),
        # Popups.dc.html notification cards: radius 18, 0.90
        notification=dict(radius=18, a=0.90),
        # QuickSettings.dc.html snap layouts flyout: radius 16, rgba(22,27,46,0.9), padding 12,
        # border rgba(255,255,255,0.14) (plasmafusion-snap's Meta+Z flyout uses the prefix)
        snaplayouts=dict(radius=16, a=0.90, edge_a=0.14),
        # Plasma tooltips (ToolTipArea + DefaultToolTip: icon, title, subtitle, Window colours):
        # Popups.dc.html rich tooltip ("Battery 82%"): padding 14, radius 16, rgba(22,27,46,0.9),
        # border rgba(255,255,255,0.12), box-shadow 0 18px 44px rgba(0,0,0,0.45)
        tooltip=dict(fill=(22, 27, 46), a=0.90, edge=(WHITE, 0.12), radius=16,
                     shadow=dict(dy=18, blur=44, color=BLACK, alpha=0.45)),
        # PC3 ToolTip (Tooltip colours, solid/): Controls.dc.html tooltip, inverted
        pc3_tooltip=dict(fill=(12, 15, 28), a=1.0, edge=(WHITE, 0.12), radius=8),
        # Main.dc.html <header>: rgba(9,12,24,0.58), border-bottom rgba(255,255,255,0.06), 34 px
        topbar=dict(fill=(9, 12, 24), a=0.58, edge=(WHITE, 0.06)),
        # Main.dc.html dock: rgba(14,18,34,0.6), radius 24, border rgba(255,255,255,0.1),
        # box-shadow 0 18px 44px rgba(0,0,0,0.35)
        dock=dict(fill=(14, 18, 34), a=0.60, edge=(WHITE, 0.10), radius=24,
                  shadow=dict(dy=18, blur=44, color=BLACK, alpha=0.35)),
        # Main.dc.html widget cards: radius 18, rgba(14,18,34,0.52), border rgba(255,255,255,0.1)
        widget=dict(fill=(14, 18, 34), a=0.52, edge=(WHITE, 0.10), radius=18),
        # PC3 Menu/Popup and widgets without wallpaper blur (Controls.dc.html menu #232a47)
        widget_plain=dict(fill=(22, 27, 46), a=0.96, edge=(WHITE, 0.12)),
        hairline=(WHITE, 0.08),            # Popups.dc.html tray footer border-top
        noblur_a=0.96,                     # root files: no KWin blur available
        handle=WHITE, handle_edge=(INK, 0.10),
        ctl=dict(btn=0.10, btn_hover=0.06, btn_hover_edge=0.16, pressed=0.30, tb_hover=0.10, tb_pressed=0.24,
                 field=0.06, field_edge=0.14, field_hover_edge=0.30, halo=0.22,
                 item_hover=0.20, item_sel=0.30, item_sel_hover=0.38,
                 list_hover=0.07, list_pressed=0.22, track=0.16, scroll=0.30, scroll_hover=0.50,
                 frame=0.04, frame_edge=0.10, line=0.12, radio_edge=0.32, running=0.60,
                 shadow_color=BLACK, shadow_a=0.35),
    ),
    "light": dict(
        id="plasma-fusion-light", name="Plasma Fusion Light",
        description="Frosted light shell surfaces for the Plasma Fusion desktop",
        # PopupsLight.dc.html / QuickSettingsLight.dc.html: rgba(255,255,255,0.88-0.90),
        # border rgba(20,24,39,0.12), box-shadow 0 18px 44px rgba(20,24,39,0.16)
        popup=dict(fill=WHITE, a=0.88, edge=(INK, 0.12), radius=22,
                   shadow=dict(dy=18, blur=44, color=INK, alpha=0.16)),
        launcher=dict(radius=26, a=0.86), osd=dict(radius=30, a=0.88),
        notification=dict(radius=18, a=0.90),
        # QuickSettingsLight.dc.html snap layouts flyout: white 0.9, border rgba(20,24,39,0.14)
        snaplayouts=dict(radius=16, a=0.90, edge_a=0.14),
        # PopupsLight.dc.html rich tooltip: rgba(255,255,255,0.9), border rgba(20,24,39,0.12),
        # radius 16, box-shadow 0 18px 44px rgba(20,24,39,0.16) (Window colours: dark text)
        tooltip=dict(fill=WHITE, a=0.90, edge=(INK, 0.12), radius=16,
                     shadow=dict(dy=18, blur=44, color=INK, alpha=0.16)),
        # PC3 ToolTip uses the Tooltip colour set (white text): Controls.dc.html light tooltip #1b2031
        pc3_tooltip=dict(fill=(27, 32, 49), a=1.0, edge=(WHITE, 0.0), radius=8),
        # MainLight.dc.html <header>: rgba(250,251,255,0.74), border-bottom rgba(20,24,39,0.06)
        topbar=dict(fill=(250, 251, 255), a=0.74, edge=(INK, 0.06)),
        # MainLight.dc.html dock: rgba(255,255,255,0.7), border rgba(20,24,39,0.1),
        # box-shadow 0 18px 44px rgba(20,24,39,0.14). Alpha 0.72, not 0.70: the active-app pill
        # (ButtonFocus #2f6fdf) keeps 3:1 over the darkest shipped light scene (Pine Fog's front
        # ridge: 2.95:1 at 0.70, 3.05:1 at 0.72; check_contrast.py --surfaces)
        dock=dict(fill=WHITE, a=0.72, edge=(INK, 0.10), radius=24,
                  shadow=dict(dy=18, blur=44, color=INK, alpha=0.14)),
        # MainLight.dc.html widget cards: rgba(255,255,255,0.62), border rgba(20,24,39,0.1)
        widget=dict(fill=WHITE, a=0.62, edge=(INK, 0.10), radius=18),
        widget_plain=dict(fill=WHITE, a=0.96, edge=(INK, 0.12)),
        hairline=(INK, 0.08),
        noblur_a=0.97,
        handle=WHITE, handle_edge=(INK, 0.14),
        ctl=dict(btn=0.10, btn_hover=0.05, btn_hover_edge=0.20, pressed=0.20, tb_hover=0.08, tb_pressed=0.16,
                 field=0.03, field_edge=0.16, field_hover_edge=0.32, halo=0.16,
                 item_hover=0.14, item_sel=0.22, item_sel_hover=0.28,
                 list_hover=0.06, list_pressed=0.16, track=0.14, scroll=0.30, scroll_hover=0.50,
                 frame=0.03, frame_edge=0.12, line=0.12, radio_edge=0.32, running=0.55,
                 shadow_color=INK, shadow_a=0.18),
    ),
}

# Geometry shared by both variants
POPUP_MARGINS = (14, 14, 14, 14)          # pop-up padding (Popups: 14-16); stock OSD becomes 32 + 2*14 = 60 px tall
TOOLTIP_MARGINS = (6, 6, 6, 6)            # + DefaultToolTip's own largeSpacing (8) = the board's 14 px padding
TOPBAR_MARGINS = (4, 4, 6, 6)             # 34 px top bar: 26 px applet row; containment caps l/r at 6
DOCK_THICKNESS = 88                       # shared contract with org.plasmafusion.dock
DOCK_HEADROOM = 16                        # transparent, unblurred band on top of the dock panel
DOCK_MARGINS = (DOCK_HEADROOM + 10, 14, 8, 8)  # board padding 10/12/14; +4 px row spacing on l/r
FLOATING_GAP = (0, 16, 8, 8)              # floating- hints (t, b, l, r): dock sits 16 px above the edge
PANEL_FALLBACK_R = 6                      # unprefixed panel frame: minimum drawing size 12 px (as Breeze)
# --south-frame plain (ADAPTIVE fix 12): a plain floating bar. Corner cells of 22 px keep the
# minimum drawing size at 44 px (a 44 px bottom panel is not raised) while the dock keeps the
# board's radius 24: the 24 px arc clipped to a 22 px cell is 0.08 px off the straight edge.
PLAIN_SOUTH_CELL = 22
PLAIN_SOUTH_MARGINS = (4, 4, 8, 8)        # (t, b, l, r): a 44 px panel gives its applets 36 px
FLOATING_GAP_PLAIN = (DOCK_HEADROOM, 16, 8, 8)  # the headroom becomes transparent window space above the frame
TOPBAR_SIDE_DEFAULT = TOPBAR_MARGINS[2]
WIDGET_MARGINS = (14, 14, 14, 14)         # widget cards: padding 14
CTRL_R = 10                               # Controls.dc.html: corners are 10 px on controls
FOCUS_GAP, FOCUS_W = 2, 2                 # 2 px accent ring with a 2 px gap


def rgba(pair, a=None):
    color, alpha = pair if isinstance(pair[0], tuple) else (pair, 1.0)
    return RGBA(*color, alpha if a is None else a)


def surface(fill, a):
    return RGBA(*fill, a)


TEXT = "ColorScheme-Text"
HL = "ColorScheme-Highlight"
HLTEXT = "ColorScheme-HighlightedText"
FOCUS = "ColorScheme-ButtonFocus"
NEUTRAL = "ColorScheme-NeutralText"


# ---------------------------------------------------------------------------
# surfaces
# ---------------------------------------------------------------------------

def surface_layers(fill, a, edge):
    """Frosted surface: fill under a 1 px edge (CSS background under border)."""
    layers = [Fill(0, surface(fill, a))]
    if edge and edge[1] > 0:
        layers.append(Ring(0, 1, rgba(edge)))
    return layers


def add_shadow_tiles(doc, pads, tiles):
    doc.newline()
    for name, img in tiles.items():
        add_image(doc, name, img)
    doc.newline()
    hint(doc, "shadow-hint-top-margin", 2, pads["top"])
    hint(doc, "shadow-hint-bottom-margin", 2, pads["bottom"])
    hint(doc, "shadow-hint-left-margin", pads["left"], 2)
    hint(doc, "shadow-hint-right-margin", pads["right"], 2)


def insets_hint(doc, prefix, m):
    """prefix-hint-{top,bottom,left,right}-inset; m = (top, bottom, left, right); 0 stays valid (0.001)."""
    p = f"{prefix}-" if prefix else ""
    t, b, l, r = m
    hint(doc, f"{p}hint-top-inset", 2, t)
    hint(doc, f"{p}hint-bottom-inset", 2, b)
    hint(doc, f"{p}hint-left-inset", l, 2)
    hint(doc, f"{p}hint-right-inset", r, 2)


def stretch_hint(doc):
    hint(doc, "hint-stretch-borders", 2, 2)


def dialog_background(v, a):
    """dialogs/background: every shell pop-up, notification, OSD, KRunner."""
    p = v["popup"]
    doc = Doc("dialogs/background")
    stretch_hint(doc)
    add_frame(doc, Frame("", p["radius"], surface_layers(p["fill"], a, p["edge"]), POPUP_MARGINS, mask=True,
                         note="pop-up surface"))
    # PlasmoidHeading/BackgroundMetrics read these insets; without them the heading falls back
    # to its own margins and QML reports a binding loop on leftInset (checked on the ThinkPad).
    insets_hint(doc, "", (0, 0, 0, 0))
    # Optional prefixes for shell pieces that draw their own surface with KSvg.FrameSvgItem
    # (imagePath "dialogs/background", prefix "launcher" / "osd" / "notification" /
    # "snaplayouts").
    for pfx, key, m in (("launcher", "launcher", (18, 18, 18, 18)), ("osd", "osd", (14, 14, 20, 20)),
                        ("notification", "notification", (14, 14, 14, 14)),
                        ("snaplayouts", "snaplayouts", (12, 12, 12, 12))):
        q = v[key]
        aa = q["a"] if a < 1 and a == p["a"] else a
        edge = (p["edge"][0], q["edge_a"]) if "edge_a" in q else p["edge"]
        add_frame(doc, Frame(pfx, q["radius"], surface_layers(p["fill"], aa, edge), m, mask=True,
                             note=f"{pfx} surface"))
    s = p["shadow"]
    # The launcher prefix (radius 26) shares these KWin shadow tiles (the Fusion launcher and
    # window switcher switch their Dialog frame to it): keep the shadow under its corners too.
    pads, tiles = window_shadow(p["radius"], s["dy"], s["blur"], s["alpha"], s["color"],
                                clear_r=v["launcher"]["radius"])
    add_shadow_tiles(doc, pads, tiles)
    return doc.render()


def tooltip(v, a, solid=False):
    """widgets/tooltip (ToolTipArea pop-ups, Window colours) or solid/ (PC3 ToolTip, Tooltip colours)."""
    doc = Doc("solid/widgets/tooltip" if solid else "widgets/tooltip")
    stretch_hint(doc)
    if solid:
        t = v["pc3_tooltip"]
        add_frame(doc, Frame("", t["radius"], surface_layers(t["fill"], t["a"], t["edge"]),
                             (5, 5, 10, 10), mask=True, note="PC3 tooltip, inverted colours"))
        # PC3 ToolTip draws a 'shadow' prefix frame around itself (margins = shadow reach)
        c = v["ctl"]
        pads, tiles = window_shadow(t["radius"], 3, 10, c["shadow_a"] * 0.8, c["shadow_color"], corner="frame")
        add_shadow_tiles(doc, pads, tiles)
        add_element(doc, "shadow-center", 1, 1, lambda x, y: "")
    else:
        t = v["tooltip"]
        add_frame(doc, Frame("", t["radius"], surface_layers(t["fill"], a if a < 1 else 1.0, t["edge"]),
                             TOOLTIP_MARGINS, mask=True, note="tooltip surface"))
        insets_hint(doc, "", (0, 0, 0, 0))
        s = t["shadow"]
        pads, tiles = window_shadow(t["radius"], s["dy"], s["blur"], s["alpha"], s["color"])
        add_shadow_tiles(doc, pads, tiles)
    return doc.render()


def panel_background(v, a, opts):
    """widgets/panel-background: north = top bar, south = dock (shared contract), others generic.

    opts["south"] == "headroom": the round-2 dock contract (16 px headroom inside the frame).
    opts["south"] == "plain": `south` is a plain floating bar and the headroom is the floating
    top margin (outside the frame, so outside the blur mask and the input region).
    """
    doc = Doc("widgets/panel-background")
    stretch_hint(doc)
    d, t = v["dock"], v["topbar"]
    fa_d = v["dock"]["a"] if a is None else a
    fa_t = v["topbar"]["a"] if a is None else a
    R = d["radius"]
    plain = opts["south"] == "plain"
    # Unprefixed: the frame Panel.qml draws before it knows the panel's edge. PanelView clamps
    # the thickness to this frame's minimum drawing size (top + bottom cells) when the panel
    # QML is ready, on every plasmashell start; with 24 px cells a 34 px top bar came back as
    # 48 px after a restart. Small cells keep any panel thickness >= 12 px intact.
    add_frame(doc, Frame("", PANEL_FALLBACK_R, surface_layers(d["fill"], fa_d, d["edge"]), (8, 8, 8, 8),
                         mask=True, note="panel without an edge (and before its edge is known)"))
    insets_hint(doc, "", (0, 0, 0, 0))
    # west/east (vertical panels): the dock look without headroom
    for pfx in ("west", "east"):
        add_frame(doc, Frame(pfx, R, surface_layers(d["fill"], fa_d, d["edge"]), (8, 8, 8, 8), mask=True,
                             note=f"{pfx} panel"))
    if plain:
        # south: a plain floating bar, the dock look without headroom; 22 px corner cells keep
        # a 44 px bottom panel at 44 px (its applets get 36 px rows)
        c = PLAIN_SOUTH_CELL
        add_frame(doc, Frame("south", R, surface_layers(d["fill"], fa_d, d["edge"]), PLAIN_SOUTH_MARGINS,
                             cells=(c, c, c, c), mask=True,
                             note=f"bottom panel: plain floating bar, radius {R} in {c} px cells"))
        insets_hint(doc, "south", (0, 0, 0, 0))
    else:
        # south: 16 px transparent headroom on top, then the 72 px frosted dock
        add_frame(doc, Frame("south", R, surface_layers(d["fill"], fa_d, d["edge"]), DOCK_MARGINS,
                             insets=(DOCK_HEADROOM, 0, 0, 0), mask=True,
                             note=f"dock: {DOCK_HEADROOM} px transparent headroom above a "
                                  f"{DOCK_THICKNESS - DOCK_HEADROOM} px, radius {R} surface ({DOCK_THICKNESS} px panel)"))
        # The dock reads this to learn where its frosted frame starts (0 with --south-frame plain).
        insets_hint(doc, "south", (DOCK_HEADROOM, 0, 0, 0))
    # north: square top bar, 1 px bottom edge (non-floating top panel draws only its bottom border)
    side = opts["north_side"]
    add_frame(doc, Frame("north", 0, surface_layers(t["fill"], fa_t, t["edge"]),
                         (TOPBAR_MARGINS[0], TOPBAR_MARGINS[1], side, side),
                         cells=(1, 1, 1, 1), mask=True, note=f"top bar (side margins {side})"))
    # floating gap (hint-only prefix; Panel.qml reads floating-hint-*-margin)
    doc.newline()
    add_element(doc, "floating-center", 4, 4, lambda x, y: "")
    g = FLOATING_GAP_PLAIN if plain else FLOATING_GAP
    margins_hint(doc, "floating", (g[0], g[1], g[2], g[3]))
    # one shadow set for every panel (PanelShadows is a singleton): drawn for the dock.
    # The top bar only ever gets the shadow-bottom tile (its other borders touch the screen
    # edges), so shadow-bottom is transparent and the dock's bottom shadow lives in two very
    # wide bottom corner tiles that KWin splits in the middle. With the plain south frame the
    # shadow belongs to the frame itself: PanelShadows subtracts the floating paddings.
    s = d["shadow"]
    pads, tiles = window_shadow(R, s["dy"], s["blur"], s["alpha"], s["color"], wide=1280,
                                headroom=0 if plain else DOCK_HEADROOM)
    tiles["shadow-bottom"] = tiles["shadow-bottom"].point(lambda v: 0)
    add_shadow_tiles(doc, pads, tiles)
    return doc.render()


def widget_background(v, blurred):
    """widgets/background: desktop widget cards (+ blurred-* for the wallpaper blur), PC3 menus."""
    doc = Doc("widgets/background")
    stretch_hint(doc)
    w, pl = v["widget"], v["widget_plain"]
    add_frame(doc, Frame("", w["radius"], surface_layers(pl["fill"], pl["a"], pl["edge"]), WIDGET_MARGINS,
                         note="plain widget / menu surface"))
    insets_hint(doc, "", (6, 6, 6, 6))  # PlasmoidHeading in desktop widgets reaches 8 px from the card edge
    if blurred:
        add_frame(doc, Frame("blurred", w["radius"], surface_layers(w["fill"], w["a"], w["edge"]), WIDGET_MARGINS,
                             note="desktop widget card over the wallpaper blur"))
        insets_hint(doc, "blurred", (6, 6, 6, 6))
        add_frame(doc, Frame("blurred-mask", w["radius"], [Fill(0, RGBA(0, 0, 0, 1.0))], WIDGET_MARGINS,
                             note="opaque shape: mask for the wallpaper blur"))
    return doc.render()


def translucent_background(v):
    doc = Doc("widgets/translucentbackground")
    stretch_hint(doc)
    w = v["widget"]
    add_frame(doc, Frame("", w["radius"], surface_layers(w["fill"], 0.30, w["edge"]), WIDGET_MARGINS,
                         note="translucent widget background / KWin outline"))
    insets_hint(doc, "", (0, 0, 0, 0))
    return doc.render()


def plasmoid_heading(v):
    """Transparent header and footer (tray panels keep one flat surface); footer keeps a hairline."""
    doc = Doc("widgets/plasmoidheading")
    stretch_hint(doc)
    clear = RGBA(0, 0, 0, 0.0)
    add_frame(doc, Frame("header", 6, [Fill(0, clear)], (6, 6, 6, 6), note="header: transparent"))
    hl = rgba(v["hairline"])
    # footer: a 1 px line along its top edge, kept 16 px away from the pop-up sides
    add_frame(doc, Frame("footer", 0, [Fill(0, clear)], (8, 6, 6, 6), cells=(1, 16, 1, 16),
                         note="footer: hairline on top"))
    doc.overlay("footer-top", lambda x, y, w, h:
                f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}" {doc.paint_attrs(hl)}/>')
    return doc.render()


# ---------------------------------------------------------------------------
# controls (Plasma Components 3 inside pop-ups)
# ---------------------------------------------------------------------------

def focus_ring_layers(width=FOCUS_W, paint=None):
    return [Ring(0, width, paint or Scheme(FOCUS, 1.0))]


def button(v):
    c = v["ctl"]
    doc = Doc("widgets/button")
    stretch_hint(doc)
    R = CTRL_R
    off = FOCUS_GAP + FOCUS_W
    # PC3 CheckIndicator draws these frames at 16 x 16 (checkbox), so the corner cells stay at
    # 8 px: the 10 px arc is clipped to the cell (a 0.2 px difference on real buttons) and the
    # cells never overlap on the small box.
    C8 = (8, 8, 8, 8)
    add_frame(doc, Frame("normal", R, [Fill(0, Scheme(TEXT, c["btn"]))], (6, 6, 10, 10), cells=C8, note="button"))
    add_frame(doc, Frame("pressed", R, [Fill(0, Scheme(HL, c["pressed"]))], (6, 6, 10, 10), cells=C8,
                         note="pressed or checked button"))
    add_frame(doc, Frame("hover", R, [Fill(0, Scheme(TEXT, c["btn_hover"])),
                                      Ring(0, 1, Scheme(TEXT, c["btn_hover_edge"]))], (0, 0, 0, 0), cells=C8,
                         note="hover overlay, drawn over normal"))
    add_frame(doc, Frame("focus", R + off, focus_ring_layers(), (off, off, off, off), cells=(12, 12, 12, 12),
                         note="focus: 2 px ring, 2 px gap (frame grows by its margins)"))
    add_frame(doc, Frame("toolbutton-hover", 8, [Fill(0, Scheme(TEXT, c["tb_hover"]))], (4, 4, 6, 6),
                         note="flat tool button hover"))
    add_frame(doc, Frame("toolbutton-pressed", 8, [Fill(0, Scheme(HL, c["tb_pressed"]))], (4, 4, 6, 6),
                         note="flat tool button pressed/checked"))
    add_frame(doc, Frame("toolbutton-focus", 8 + off, focus_ring_layers(), (off, off, off, off),
                         note="flat tool button focus"))
    # no drop shadow under buttons on the boards: keep the frame, fully transparent
    add_frame(doc, Frame("shadow", 2, [Fill(0, RGBA(0, 0, 0, 0.0))], (0, 0, 0, 0), note="no button shadow"))
    return doc.render()


def lineedit(v):
    c = v["ctl"]
    doc = Doc("widgets/lineedit")
    stretch_hint(doc)
    hint(doc, "hint-focus-over-base", 2, 2)
    R = CTRL_R
    add_frame(doc, Frame("base", R, [Fill(0, Scheme(TEXT, c["field"])), Ring(0, 1, Scheme(TEXT, c["field_edge"]))],
                         (6, 6, 10, 10), note="text field"))
    add_frame(doc, Frame("hover", R, [Ring(0, 1, Scheme(TEXT, c["field_hover_edge"]))], (0, 0, 0, 0),
                         note="hover: stronger edge"))
    # Controls.dc.html focused field: 1.5 px accent border + 3 px soft accent halo outside
    focus = [Ring(0, 3, Scheme(HL, c["halo"])), Ring(3, 1.5, Scheme(FOCUS, 1.0))]
    add_frame(doc, Frame("focus", R + 3, focus, (3, 3, 3, 3), note="focus: accent border and halo"))
    add_frame(doc, Frame("focusframe", R + 3, focus, (3, 3, 3, 3), note="keyboard focus"))
    return doc.render()


def viewitem(v):
    c = v["ctl"]
    doc = Doc("widgets/viewitem")
    stretch_hint(doc)
    R = 8
    m = (4, 4, 8, 8)
    add_frame(doc, Frame("normal", R, [Fill(0, RGBA(0, 0, 0, 0.0))], m, note="normal: nothing"))
    add_frame(doc, Frame("hover", R, [Fill(0, Scheme(HL, c["item_hover"]))], m, note="hover / current item"))
    add_frame(doc, Frame("selected", R, [Fill(0, Scheme(HL, c["item_sel"]))], m, note="selected"))
    add_frame(doc, Frame("selected+hover", R, [Fill(0, Scheme(HL, c["item_sel_hover"]))], m,
                         note="selected and hovered"))
    return doc.render()


def listitem(v):
    c = v["ctl"]
    doc = Doc("widgets/listitem")
    stretch_hint(doc)
    R = 8
    m = (6, 6, 8, 8)
    add_frame(doc, Frame("normal", R, [Fill(0, RGBA(0, 0, 0, 0.0))], m, note="normal"))
    add_frame(doc, Frame("hover", R, [Fill(0, Scheme(TEXT, c["list_hover"]))], m, note="hover"))
    add_frame(doc, Frame("pressed", R, [Fill(0, Scheme(HL, c["list_pressed"]))], m, note="pressed/highlighted"))
    add_frame(doc, Frame("section", R, [Fill(0, Scheme(TEXT, 0.04))], m, note="section header"))
    doc.newline()
    add_element(doc, "separator", 40, 1, lambda x, y: f'<rect x="{x}" y="{y}" width="40" height="1" '
                f'{doc.paint_attrs(Scheme(TEXT, c["line"]))}/>')
    return doc.render()


def tabbar(v):
    """Active tab = 3 px accent line on the content side; also the expanded-applet indicator in panels."""
    doc = Doc("widgets/tabbar")
    stretch_hint(doc)
    line = Scheme(HL, 1.0)
    clear = RGBA(0, 0, 0, 0.0)
    # (prefix, side of the line, cells t r b l, margins t b l r)
    for pfx, side, cells, m in (
        ("north-active-tab", "bottom", (1, 2, 3, 2), (8, 8, 10, 10)),
        ("south-active-tab", "bottom", (1, 14, 9, 14), (8, 8, 10, 10)),
        ("west-active-tab", "left", (2, 1, 2, 3), (8, 8, 10, 10)),
        ("east-active-tab", "right", (2, 3, 2, 1), (8, 8, 10, 10)),
    ):
        add_frame(doc, Frame(pfx, 0, [Fill(0, clear)], m, cells=cells, note=f"{pfx}: accent line ({side})"))
        doc.overlay(f"{pfx}-{side}", lambda x, y, w, h, pfx=pfx, side=side: _tab_line(doc, pfx, side, line, x, y, w, h))
    return doc.render()


def _tab_line(doc, pfx, side, paint, x, y, w, h):
    """Straight accent line inside a stretched side cell."""
    if side == "bottom":
        # south (dock): 4 px line with 5 px below it, the dock's running-indicator row
        ly, lh = (y, 4) if pfx.startswith("south") else (y + h - 3, 3)
        return f'<rect x="{fmt(x)}" y="{fmt(ly)}" width="{fmt(w)}" height="{lh}" {doc.paint_attrs(paint)}/>'
    lx = x if side == "left" else x + w - 3
    return f'<rect x="{fmt(lx)}" y="{fmt(y)}" width="3" height="{fmt(h)}" {doc.paint_attrs(paint)}/>'


def menubaritem(v):
    """Global menu titles in the top bar (stock appmenu MenuDelegate, window-list MenuButton).

    Main / MainLight header: titles have padding 4px 8px, radius 6 and 2 px between them, so the
    hover pill is 26 px tall inside the 34 px bar (y 4-29). The stock appmenu makes every title
    as tall as the panel (Layout.fillHeight, CanFillArea) and places titles without spacing, so
    the pill is drawn with 4 px of transparent space above and below it and 1 px at each side
    (together the board's 2 px gap); the margins are the padding (8 px inside the pill).

    Text: the delegates draw a hovered or open title in the colour scheme's Selection
    foreground (white in both Fusion schemes; with a custom accent KDE picks the readable colour
    for that accent). Dark: the board's white on a white .10 pill (about 14:1). Light: the
    board's grey pill would give white on light grey (1.3:1), so the light pill is the accent
    (Selection background), on which the Selection foreground is readable by definition,
    darkened by the light boards' ink at .10 (hover) and .18 (open menu): white on it is
    5.4:1 and 6.0:1.
    """
    doc = Doc("widgets/menubaritem")
    stretch_hint(doc)
    m = (4, 4, 9, 9)            # (t, b, l, r): 1 px side inset + the board's 8 px padding
    ins = (4, 1, 4, 1)          # (t, r, b, l) transparent space around the pill
    if v["id"].endswith("light"):
        # Accent darkened with the light boards' ink, so thin 13 px strokes stay above 4.5:1
        # after antialiasing too (white on #2f6fdf is 4.7:1 nominal, 4.3:1 measured).
        hover = [Fill(0, Scheme(HL, 1.0)), Fill(0, RGBA(*INK, 0.10))]
        pressed = [Fill(0, Scheme(HL, 1.0)), Fill(0, RGBA(*INK, 0.18))]
    else:
        c = v["ctl"]
        hover = [Fill(0, Scheme(TEXT, c["tb_hover"]))]
        pressed = [Fill(0, Scheme(TEXT, c["tb_hover"] + 0.04))]
    add_frame(doc, Frame("normal", 6, [Fill(0, RGBA(0, 0, 0, 0.0))], m, insets=ins, note="normal"))
    add_frame(doc, Frame("hover", 6, hover, m, insets=ins, note="hover"))
    add_frame(doc, Frame("pressed", 6, pressed, m, insets=ins, note="open menu"))
    return doc.render()


def tasks(v, opts):
    """Task manager items: running bar, active (focus) accent bar, hover tint (Main.dc.html dock)."""
    c = v["ctl"]
    doc = Doc("widgets/tasks")
    stretch_hint(doc)
    R = 13  # dock buttons: 48 px, radius 13
    run = Scheme(TEXT, c["running"])
    act = Scheme(FOCUS, 1.0)
    att = Scheme(NEUTRAL, 1.0)
    tint = Scheme(TEXT, 0.08)
    hov = Scheme(TEXT, 0.10)
    # Task.qml asks for "<state>-hover" first when hovered, then "hover"; pinned launchers use
    # the empty prefix (nothing drawn) and "launcher-hover".
    states = {
        "normal": (None, run),
        "hover": (hov, run),
        "focus": (tint, act),
        "focus-hover": (Scheme(TEXT, 0.14), act),
        "attention": (Scheme(NEUTRAL, 0.14), att),
        "attention-hover": (Scheme(NEUTRAL, 0.20), att),
        "minimized": (None, Scheme(TEXT, 0.30)),
        "minimized-hover": (hov, Scheme(TEXT, 0.30)),
        "launcher-hover": (hov, None),
    }
    for loc, side in (("", "bottom"), ("north-", "top"), ("west-", "left"), ("east-", "right")):
        for state, (bg, bar) in states.items():
            pfx = f"{loc}{state}"
            layers = [Fill(0, bg or RGBA(0, 0, 0, 0.0))]
            # wide corner cells keep the indicator bar short (it lives in the stretched side cell)
            cells = (13, 20, 13, 20) if side in ("top", "bottom") else (20, 13, 20, 13)
            add_frame(doc, Frame(pfx, R, layers, (4, 4, 4, 4), cells=cells, note=f"task {state} ({side})"))
            if bar is not None:
                doc.overlay(f"{pfx}-{side}", lambda x, y, w, h, side=side, bar=bar: _task_bar(doc, side, bar, x, y, w, h))
        add_frame(doc, Frame(f"{loc}progress", R, [Fill(0, Scheme(HL, 0.30))], (4, 4, 4, 4),
                             note="task progress"))
    if opts["south"] == "headroom":
        # plain south frame: bottom panels use the unprefixed (bottom bar) frames above
        _dock_tasks(doc, states, R)
    return doc.render()


# Bottom panels follow the dock contract (88 px panel, 16 px headroom). A task manager there
# fills the whole height (CanFillArea) and its slots are height + margins = 96 px wide, so the
# south- frames place a 48 px icon on the dock's button row (rows 26-74) with the hover tint
# as the board's 48 px, radius 13 square, and the running bar 6 px above the dock's bottom edge.
DOCK_TASK_MARGINS = (DOCK_MARGINS[0], DOCK_MARGINS[1], 4, 4)
DOCK_TASK_SLOT = DOCK_THICKNESS + DOCK_TASK_MARGINS[2] + DOCK_TASK_MARGINS[3]


def _dock_tasks(doc, states, R):
    side_inset = (DOCK_TASK_SLOT - 48) / 2
    insets = (DOCK_TASK_MARGINS[0], side_inset, DOCK_TASK_MARGINS[1], side_inset)  # t r b l
    for state, (bg, bar) in list(states.items()) + [("progress", (Scheme(HL, 0.30), None))]:
        # Main.dc.html running indicator: 5 px (active: 16 px) wide, 4 px tall
        bar_w = 16 if state.startswith("focus") else 6
        side = (DOCK_TASK_SLOT - bar_w) / 2
        cells = (DOCK_TASK_MARGINS[0] + R, side, DOCK_TASK_MARGINS[1] + R, side)
        pfx = f"south-{state}"
        add_frame(doc, Frame(pfx, R, [Fill(0, bg or RGBA(0, 0, 0, 0.0))], DOCK_TASK_MARGINS, insets=insets,
                             cells=cells, note=f"dock task {state}"))
        if bar is not None:
            doc.overlay(f"{pfx}-bottom", lambda x, y, w, h, bar=bar:
                        f'<rect x="{fmt(x)}" y="{fmt(y + h - 10)}" width="{fmt(w)}" height="4" {doc.paint_attrs(bar)}/>')


def _task_bar(doc, side, paint, x, y, w, h):
    """3 px indicator bar in the stretched side cell that faces the screen edge."""
    if side in ("bottom", "top"):
        yy = y + h - 4 if side == "bottom" else y + 1
        return f'<rect x="{fmt(x)}" y="{fmt(yy)}" width="{fmt(w)}" height="3" {doc.paint_attrs(paint)}/>'
    xx = x + 1 if side == "left" else x + w - 4
    return f'<rect x="{fmt(xx)}" y="{fmt(y)}" width="3" height="{fmt(h)}" {doc.paint_attrs(paint)}/>'


def scrollbar(v):
    c = v["ctl"]
    doc = Doc("widgets/scrollbar")
    stretch_hint(doc)
    hint(doc, "hint-scrollbar-size", 8, 8)
    # Controls.dc.html: 5 px thumb, radius 3, rgba(text, 0.3); inset 1.5 px in an 8 px track
    for pfx, a in (("slider", c["scroll"]), ("mouseover-slider", c["scroll_hover"])):
        add_frame(doc, Frame(pfx, 4, [Fill(1.5, Scheme(TEXT, a))], (0, 0, 0, 0), cells=(4, 4, 4, 4),
                             note=f"{pfx}"))
    for pfx in ("background-vertical", "background-horizontal"):
        add_frame(doc, Frame(pfx, 4, [Fill(0, Scheme(TEXT, 0.05))], (0, 0, 0, 0), cells=(4, 4, 4, 4),
                             note=f"{pfx}"))
    return doc.render()


def handle_markup(doc, v, x, y, size, knob, shadow=True):
    """White round knob with a soft shadow and a faint edge (Controls.dc.html slider/switch)."""
    cx, cy = x + size / 2, y + size / 2
    out = ""
    if shadow:
        c = v["ctl"]
        col = c["shadow_color"]
        for i, (grow, a) in enumerate(((2.0, 0.06), (1.2, 0.10), (0.5, 0.14))):
            out += f'<path {doc.paint_attrs(RGBA(*col, a))} d="{circle_path(cx, cy + 1, knob / 2 + grow)}"/>'
    out += f'<path {doc.paint_attrs(RGBA(*v["handle"], 1.0))} d="{circle_path(cx, cy, knob / 2)}"/>'
    e, ea = v["handle_edge"]
    out += (f'<path {doc.paint_attrs(RGBA(*e, ea))} fill-rule="evenodd" '
            f'd="{circle_path(cx, cy, knob / 2)}{circle_path(cx, cy, knob / 2 - 1)}"/>')
    return out


def ring_markup(doc, x, y, size, r_out, width, paint):
    cx, cy = x + size / 2, y + size / 2
    return (f'<path {doc.paint_attrs(paint)} fill-rule="evenodd" '
            f'd="{circle_path(cx, cy, r_out)}{circle_path(cx, cy, r_out - width)}"/>')


def slider(v):
    c = v["ctl"]
    doc = Doc("widgets/slider")
    stretch_hint(doc)
    hint(doc, "hint-handle-size", 20, 20)
    # groove 6 px (Controls.dc.html), radius 3
    add_frame(doc, Frame("groove", 3, [Fill(0, Scheme(TEXT, c["track"]))], (3, 3, 3, 3), cells=(3, 3, 3, 3),
                         note="groove"))
    add_frame(doc, Frame("groove-highlight", 3, [Fill(0, Scheme(HL, 1.0))], (3, 3, 3, 3), cells=(3, 3, 3, 3),
                         note="groove fill"))
    doc.newline()
    for o in ("horizontal", "vertical"):
        add_element(doc, f"{o}-slider-handle", 20, 20, lambda x, y: handle_markup(doc, v, x, y, 20, 20, False))
        add_element(doc, f"{o}-slider-shadow", 26, 26, lambda x, y: handle_markup(doc, v, x, y, 26, 20, True))
        add_element(doc, f"{o}-slider-hover", 20, 20,
                    lambda x, y: ring_markup(doc, x, y, 20, 10, 2, Scheme(HL, 0.55)))
        add_element(doc, f"{o}-slider-focus", 28, 28,
                    lambda x, y: ring_markup(doc, x, y, 28, 14, 2, Scheme(FOCUS, 1.0)))
    return doc.render()


def switch(v):
    c = v["ctl"]
    doc = Doc("widgets/switch")
    stretch_hint(doc)
    hint(doc, "hint-bar-size", 40, 22)   # Controls.dc.html: 40 x 22, radius 11
    add_frame(doc, Frame("inactive", 11, [Fill(0, Scheme(TEXT, c["track"]))], (0, 0, 0, 0), cells=(11, 11, 11, 11),
                         stretch=4, note="track off"))
    add_frame(doc, Frame("active", 11, [Fill(0, Scheme(HL, 1.0))], (0, 0, 0, 0), cells=(11, 11, 11, 11),
                         stretch=4, note="track on"))
    doc.newline()
    add_element(doc, "handle", 22, 22, lambda x, y: handle_markup(doc, v, x, y, 22, 18, False))
    add_element(doc, "handle-hover", 22, 22, lambda x, y: handle_markup(doc, v, x, y, 22, 18, False)
                + ring_markup(doc, x, y, 22, 9, 1, Scheme(HL, 0.6)))
    add_element(doc, "handle-pressed", 22, 22, lambda x, y: handle_markup(doc, v, x, y, 22, 18, False)
                + f'<path {doc.paint_attrs(Scheme(TEXT, 0.10))} d="{circle_path(x + 11, y + 11, 9)}"/>')
    add_element(doc, "handle-shadow", 24, 24, lambda x, y: handle_markup(doc, v, x, y, 24, 18, True))
    add_element(doc, "handle-focus", 26, 26, lambda x, y: ring_markup(doc, x, y, 26, 13, 2, Scheme(FOCUS, 1.0)))
    return doc.render()


def check_glyph(x, y, s):
    """Check mark as a filled polygon (stroke 1.8 at 24 px, scaled)."""
    k = s / 24.0
    pts = [(5, 12.5), (6.3, 11.2), (9.8, 14.7), (17.7, 6.8), (19, 8.1), (9.8, 17.3)]
    d = "M" + " L".join(f"{fmt(x + px * k)},{fmt(y + py * k)}" for px, py in pts) + "Z"
    return d


def checkmarks(v):
    doc = Doc("widgets/checkmarks")
    add_element(doc, "checkbox", 16, 16, lambda x, y:
                f'<path {doc.paint_attrs(Scheme(HL, 1.0))} d="{rr_full_path(x, y, x + 16, y + 16, 5)}"/>'
                f'<path {doc.paint_attrs(Scheme(HLTEXT, 1.0))} d="{check_glyph(x - 0.5, y - 0.5, 17)}"/>')
    add_element(doc, "radiobutton", 16, 16, lambda x, y:
                f'<path {doc.paint_attrs(Scheme(HL, 1.0))} d="{circle_path(x + 8, y + 8, 8)}"/>'
                f'<path {doc.paint_attrs(Scheme(HLTEXT, 1.0))} d="{circle_path(x + 8, y + 8, 3)}"/>')
    return doc.render()


def radiobutton(v):
    c = v["ctl"]
    doc = Doc("widgets/radiobutton")
    hint(doc, "hint-size", 16, 16)
    add_element(doc, "normal", 16, 16, lambda x, y:
                f'<path {doc.paint_attrs(Scheme(TEXT, c["field"]))} d="{circle_path(x + 8, y + 8, 8)}"/>'
                + ring_markup(doc, x, y, 16, 8, 1.5, Scheme(TEXT, c["radio_edge"])))
    add_element(doc, "checked", 16, 16, lambda x, y:
                f'<path {doc.paint_attrs(Scheme(HL, 1.0))} d="{circle_path(x + 8, y + 8, 8)}"/>')
    add_element(doc, "hover", 16, 16, lambda x, y: ring_markup(doc, x, y, 16, 8, 1.5, Scheme(HL, 0.8)))
    add_element(doc, "focus", 24, 24, lambda x, y: ring_markup(doc, x, y, 24, 12, 2, Scheme(FOCUS, 1.0)))
    add_element(doc, "symbol", 6, 6, lambda x, y:
                f'<path {doc.paint_attrs(Scheme(HLTEXT, 1.0))} d="{circle_path(x + 3, y + 3, 3)}"/>')
    add_element(doc, "shadow", 16, 16, lambda x, y: "")
    return doc.render()


def actionbutton(v):
    c = v["ctl"]
    doc = Doc("widgets/actionbutton")
    for size, pfx in ((32, ""), (16, "16-16-"), (22, "22-22-"), (24, "24-24-")):
        doc.newline()
        r = size / 2
        add_element(doc, f"{pfx}normal", size, size, lambda x, y, r=r:
                    f'<path {doc.paint_attrs(Scheme(TEXT, c["btn"]))} d="{circle_path(x + r, y + r, r)}"/>')
        add_element(doc, f"{pfx}hover", size, size, lambda x, y, r=r:
                    f'<path {doc.paint_attrs(Scheme(TEXT, c["btn"] + c["btn_hover"]))} d="{circle_path(x + r, y + r, r)}"/>')
        add_element(doc, f"{pfx}pressed", size, size, lambda x, y, r=r:
                    f'<path {doc.paint_attrs(Scheme(HL, c["pressed"]))} d="{circle_path(x + r, y + r, r)}"/>')
        add_element(doc, f"{pfx}focus", size, size, lambda x, y, r=r, s=size:
                    f'<path {doc.paint_attrs(Scheme(TEXT, c["btn"]))} d="{circle_path(x + r, y + r, r)}"/>'
                    + ring_markup(doc, x, y, s, r, 2, Scheme(FOCUS, 1.0)))
        add_element(doc, f"{pfx}shadow", size, size, lambda x, y: "")
    return doc.render()


def frame_svg(v):
    c = v["ctl"]
    doc = Doc("widgets/frame")
    stretch_hint(doc)
    for pfx in ("plain", "raised", "sunken"):
        add_frame(doc, Frame(pfx, CTRL_R, [Fill(0, Scheme(TEXT, c["frame"])), Ring(0, 1, Scheme(TEXT, c["frame_edge"]))],
                             (6, 6, 6, 6), note=pfx))
    return doc.render()


def bar_meter(v, orientation):
    c = v["ctl"]
    doc = Doc(f"widgets/bar_meter_{orientation}")
    stretch_hint(doc)
    hint(doc, "hint-bar-size", 6, 6)   # Controls.dc.html progress: 6 px, radius 3
    add_frame(doc, Frame("bar-inactive", 3, [Fill(0, Scheme(TEXT, c["track"]))], (3, 3, 3, 3), cells=(3, 3, 3, 3),
                         note="track"))
    add_frame(doc, Frame("bar-active", 3, [Fill(0, Scheme(HL, 1.0))], (3, 3, 3, 3), cells=(3, 3, 3, 3),
                         note="fill"))
    return doc.render()


def busywidget(v):
    doc = Doc("widgets/busywidget")
    hint(doc, "hint-rotation-angle", 2, 2)

    def spinner(x, y, s, w):
        cx, cy, r = x + s / 2, y + s / 2, s / 2 - w / 2 - 0.5
        # 270 degree arc as a filled band (no strokes: exact bounds)
        import math
        ro, ri = r + w / 2, r - w / 2
        a0, a1 = -90, 180
        p0o = (cx + ro * math.cos(math.radians(a0)), cy + ro * math.sin(math.radians(a0)))
        p1o = (cx + ro * math.cos(math.radians(a1)), cy + ro * math.sin(math.radians(a1)))
        p1i = (cx + ri * math.cos(math.radians(a1)), cy + ri * math.sin(math.radians(a1)))
        p0i = (cx + ri * math.cos(math.radians(a0)), cy + ri * math.sin(math.radians(a0)))
        d = (f"M{fmt(p0o[0])},{fmt(p0o[1])}A{fmt(ro)},{fmt(ro)} 0 1 1 {fmt(p1o[0])},{fmt(p1o[1])}"
             f"A{fmt(w / 2)},{fmt(w / 2)} 0 0 1 {fmt(p1i[0])},{fmt(p1i[1])}"
             f"A{fmt(ri)},{fmt(ri)} 0 1 0 {fmt(p0i[0])},{fmt(p0i[1])}"
             f"A{fmt(w / 2)},{fmt(w / 2)} 0 0 1 {fmt(p0o[0])},{fmt(p0o[1])}Z")
        track = ring_markup(doc, x, y, s, r + w / 2, w, Scheme(TEXT, 0.12))
        return track + f'<path {doc.paint_attrs(Scheme(HL, 1.0))} d="{d}"/>'

    add_element(doc, "busywidget", 36, 36, lambda x, y: spinner(x, y, 36, 3.5))
    add_element(doc, "22-22-busywidget", 22, 22, lambda x, y: spinner(x, y, 22, 2.5))
    add_element(doc, "16-16-busywidget", 16, 16, lambda x, y: spinner(x, y, 16, 2))
    add_element(doc, "stopped", 36, 36, lambda x, y: ring_markup(doc, x, y, 36, 16.5, 3.5, Scheme(TEXT, 0.20)))
    return doc.render()


def line_svg(v):
    c = v["ctl"]
    doc = Doc("widgets/line")
    p = Scheme(TEXT, c["line"])
    add_element(doc, "horizontal-line", 8, 1, lambda x, y: f'<rect x="{x}" y="{y}" width="8" height="1" {doc.paint_attrs(p)}/>')
    add_element(doc, "vertical-line", 1, 8, lambda x, y: f'<rect x="{x}" y="{y}" width="1" height="8" {doc.paint_attrs(p)}/>')
    return doc.render()


def arrows(v):
    doc = Doc("widgets/arrows")
    p = Scheme(TEXT, 1.0)

    def chevron(x, y, direction):
        # 1.8 px chevron in a 14 px box, as a filled polygon
        k = 14 / 24.0
        base = [(6, 9), (7.3, 7.7), (12, 12.4), (16.7, 7.7), (18, 9), (12, 15)]  # pointing down
        pts = []
        for px, py in base:
            if direction == "up":
                py = 24 - py
            elif direction == "left":
                px, py = 24 - py, px
            elif direction == "right":
                px, py = py, px
            pts.append((x + px * k, y + (py + 0.3) * k))
        return f'<path {doc.paint_attrs(p)} d="M' + " L".join(f"{fmt(a)},{fmt(b)}" for a, b in pts) + 'Z"/>'

    for d in ("down", "up", "left", "right"):
        add_element(doc, f"{d}-arrow", 14, 14, lambda x, y, d=d: chevron(x, y, d))
    return doc.render()


def toolbar(v):
    doc = Doc("widgets/toolbar")
    stretch_hint(doc)
    add_frame(doc, Frame("", 4, [Fill(0, RGBA(0, 0, 0, 0.0))], (4, 4, 4, 4), note="toolbar"))
    return doc.render()


def pager(v):
    c = v["ctl"]
    doc = Doc("widgets/pager")
    stretch_hint(doc)
    add_frame(doc, Frame("normal", 6, [Fill(0, Scheme(TEXT, 0.06)), Ring(0, 1, Scheme(TEXT, 0.14))], None, note="desktop"))
    add_frame(doc, Frame("hover", 6, [Fill(0, Scheme(TEXT, 0.12)), Ring(0, 1, Scheme(TEXT, 0.24))], None, note="hover"))
    add_frame(doc, Frame("active", 6, [Fill(0, Scheme(HL, 0.35)), Ring(0, 1, Scheme(HL, 1.0))], None, note="current"))
    return doc.render()


def _overlay_glyph(kind, x, y):
    """White glyph of a 16 px action overlay: plus, minus, or a chevron pointing right."""
    if kind == "add":
        return (f"M{fmt(x + 4.25)},{fmt(y + 7.25)}H{fmt(x + 7.25)}V{fmt(y + 4.25)}H{fmt(x + 8.75)}"
                f"V{fmt(y + 7.25)}H{fmt(x + 11.75)}V{fmt(y + 8.75)}H{fmt(x + 8.75)}V{fmt(y + 11.75)}"
                f"H{fmt(x + 7.25)}V{fmt(y + 8.75)}H{fmt(x + 4.25)}Z")
    if kind == "remove":
        return f"M{fmt(x + 4.25)},{fmt(y + 7.25)}H{fmt(x + 11.75)}V{fmt(y + 8.75)}H{fmt(x + 4.25)}Z"
    # open: 1.5 px chevron, 3.5 px deep
    pts = [(6.4, 4.4), (7.46, 3.34), (12.12, 8.0), (7.46, 12.66), (6.4, 11.6), (10.0, 8.0)]
    return "M" + " L".join(f"{fmt(x + px)},{fmt(y + py)}" for px, py in pts) + "Z"


def action_overlays(v):
    """widgets/action-overlays: Folder View's selection markers and folder pop-up button (BACKLOG S6).

    FolderItemActionButton draws `<add|remove|open>-<normal|hover|pressed>` at 16 x 16, scaled to
    the icon size's smallMedium (22 px for 48 px desktop icons), over the icon's top-left corner.
    A 16 px accent disc (ColorScheme-Highlight, so it follows the accent colour) with a white
    glyph and a 1 px white rim that separates it from the icon under it; hover lightens the
    accent, pressed darkens it with the light boards' ink.
    """
    doc = Doc("widgets/action-overlays")
    rim = Scheme(HLTEXT, 0.92)
    glyph = Scheme(HLTEXT, 1.0)
    states = {
        "normal": [],
        "hover": [RGBA(*WHITE, 0.18)],
        "pressed": [RGBA(*INK, 0.22)],
    }
    for kind in ("add", "remove", "open"):
        doc.newline()
        for state, tints in states.items():
            def draw(x, y, tints=tints, kind=kind):
                out = f'<path {doc.paint_attrs(rim)} d="{circle_path(x + 8, y + 8, 8)}"/>'
                out += f'<path {doc.paint_attrs(Scheme(HL, 1.0))} d="{circle_path(x + 8, y + 8, 7)}"/>'
                for t in tints:
                    out += f'<path {doc.paint_attrs(t)} d="{circle_path(x + 8, y + 8, 7)}"/>'
                return out + f'<path {doc.paint_attrs(glyph)} d="{_overlay_glyph(kind, x, y)}"/>'
            add_element(doc, f"{kind}-{state}", 16, 16, draw)
    return doc.render()


# ---------------------------------------------------------------------------
# package
# ---------------------------------------------------------------------------

def metadata(v):
    return {
        "KPlugin": {
            "Authors": [{"Email": "archledger236@gmail.com", "Name": "Wisbendji Fimerlus"}],
            "Category": "",
            "Description": v["description"],
            "EnabledByDefault": True,
            "Id": v["id"],
            "License": "CC-BY-SA-4.0",
            "Name": v["name"],
            "Version": VERSION,
            "Website": "",
        },
        "X-Plasma-API": "5.0",
    }


PLASMARC = """[ContrastEffect]
# KWin 6.7 has no background-contrast effect; these values only feed the wallpaper blur
# behind desktop widgets (MultiEffect contrast = contrast - 1, saturation = saturation - 1).
# Main.dc.html widget cards use a plain blur(24px): no contrast or saturation change.
enabled=false
contrast=1
intensity=1
saturation=1

[BlurBehindEffect]
enabled=true

[AdaptiveTransparency]
enabled=true
"""


DEFAULT_OPTS = {"south": "headroom", "north_side": TOPBAR_SIDE_DEFAULT}


def build(outdir, key, opts=None):
    opts = dict(DEFAULT_OPTS, **(opts or {}))
    v = VARIANTS[key]
    root = os.path.join(outdir, v["id"])
    if os.path.isdir(root):
        shutil.rmtree(root)
    nb = v["noblur_a"]
    files = {
        # translucent/: KWin blur available (ext_background_effect blur capability)
        "translucent/dialogs/background.svg": dialog_background(v, v["popup"]["a"]),
        "translucent/widgets/tooltip.svg": tooltip(v, v["tooltip"]["a"]),
        "translucent/widgets/panel-background.svg": panel_background(v, None, opts),
        "translucent/widgets/background.svg": widget_background(v, True),
        # root: no blur: nearly opaque surfaces
        "dialogs/background.svg": dialog_background(v, nb),
        "widgets/tooltip.svg": tooltip(v, nb),
        "widgets/panel-background.svg": panel_background(v, nb, opts),
        "widgets/background.svg": widget_background(v, False),
        # solid/: opaque requests (opaque/adaptive panels, SolidBackground dialogs, PC3 ToolTip)
        "solid/dialogs/background.svg": dialog_background(v, 1.0),
        "solid/widgets/tooltip.svg": tooltip(v, 1.0, solid=True),
        "solid/widgets/panel-background.svg": panel_background(v, 1.0, opts),
        "solid/widgets/background.svg": widget_background(v, False),
        # shared by all selectors
        "widgets/translucentbackground.svg": translucent_background(v),
        "widgets/plasmoidheading.svg": plasmoid_heading(v),
        "widgets/button.svg": button(v),
        "widgets/lineedit.svg": lineedit(v),
        "widgets/viewitem.svg": viewitem(v),
        "widgets/listitem.svg": listitem(v),
        "widgets/tabbar.svg": tabbar(v),
        "widgets/menubaritem.svg": menubaritem(v),
        "widgets/tasks.svg": tasks(v, opts),
        "widgets/action-overlays.svg": action_overlays(v),
        "widgets/scrollbar.svg": scrollbar(v),
        "widgets/slider.svg": slider(v),
        "widgets/switch.svg": switch(v),
        "widgets/checkmarks.svg": checkmarks(v),
        "widgets/radiobutton.svg": radiobutton(v),
        "widgets/actionbutton.svg": actionbutton(v),
        "widgets/frame.svg": frame_svg(v),
        "widgets/bar_meter_horizontal.svg": bar_meter(v, "horizontal"),
        "widgets/bar_meter_vertical.svg": bar_meter(v, "vertical"),
        "widgets/busywidget.svg": busywidget(v),
        "widgets/line.svg": line_svg(v),
        "widgets/arrows.svg": arrows(v),
        "widgets/toolbar.svg": toolbar(v),
        "widgets/pager.svg": pager(v),
    }
    for rel, text in files.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    with open(os.path.join(root, "metadata.json"), "w", encoding="utf-8") as f:
        json.dump(metadata(v), f, indent=4, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(root, "plasmarc"), "w", encoding="utf-8") as f:
        f.write(PLASMARC)
    return root


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("outdir", help="directory that receives plasma-fusion-dark/ and plasma-fusion-light/")
    ap.add_argument("--variant", choices=["dark", "light", "all"], default="all")
    ap.add_argument("--south-frame", choices=["headroom", "plain"], default=DEFAULT_OPTS["south"],
                    help="bottom panel frame: the dock contract with 16 px headroom (default) or a plain floating bar")
    ap.add_argument("--north-side-margin", type=int, choices=[TOPBAR_SIDE_DEFAULT, 0],
                    default=DEFAULT_OPTS["north_side"], help="left/right margin of the top bar frame")
    a = ap.parse_args()
    opts = {"south": a.south_frame, "north_side": a.north_side_margin}
    keys = ["dark", "light"] if a.variant == "all" else [a.variant]
    for k in keys:
        print(build(a.outdir, k, opts))


if __name__ == "__main__":
    main()
