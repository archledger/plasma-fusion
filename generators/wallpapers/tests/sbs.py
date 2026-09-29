#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Side-by-side comparisons of the board renders and the virtual-session screenshots (test only)."""
from PIL import Image, ImageDraw, ImageFont
import os
R=os.environ.get('PF_RENDERS', '/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-design-source/renders').rstrip('/')+'/'
import os
F=os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../fonts/manrope/Manrope[wght].ttf')
import sys
# usage: sbs.py DARK_OUT_DIR LIGHT_OUT_DIR EVIDENCE_DIR  (vsession-out/<name>/ of the dark and light runs)
V6=sys.argv[1].rstrip('/')+'/'; V7=sys.argv[2].rstrip('/')+'/'; E=sys.argv[3].rstrip('/')+'/'
BG=(24,24,28); CAP=34
def font(sz):
    f=ImageFont.truetype(F, sz); f.set_variation_by_axes([700]); return f
im=lambda p: Image.open(p).convert('RGB')
def grid(cols, out):
    """cols: list of (caption, [images stacked])"""
    colimgs=[]
    for cap, imgs in cols:
        w=max(i.width for i in imgs); h=CAP+sum(i.height for i in imgs)+8*(len(imgs)-1)
        c=Image.new('RGB',(w,h),BG); d=ImageDraw.Draw(c); d.text((6,6),cap,font=font(18),fill=(235,238,245))
        y=CAP
        for i in imgs: c.paste(i,(0,y)); y+=i.height+8
        colimgs.append(c)
    W=sum(c.width for c in colimgs)+16*(len(colimgs)-1); H=max(c.height for c in colimgs)
    s=Image.new('RGB',(W,H),BG); x=0
    for c in colimgs: s.paste(c,(x,0)); x+=c.width+16
    s.save(out, optimize=True)
grid([('Board: Main (desktop-dark-1)',[im(R+'desktop-dark-1.png')]),('Built: PlasmaFusion wallpaper + Plasma Fusion Dark, Manrope (virtual session)',[im(V6+'dark-02-colors.png')])],E+'sbs-desktop-dark.png')
grid([('Board: MainLight (desktop-light-1)',[im(R+'desktop-light-1.png')]),('Built: same, Plasma Fusion Light (wallpaper follows the scheme)',[im(V7+'light-02-colors.png')])],E+'sbs-desktop-light.png')
grid([('Board: TabsSnap terminal',[im(R+'theme-parts-4.png').crop((762,282,1357,475))]),('Built: Konsole, profile "Plasma Fusion"',[im(V6+'dark-04-konsole.png').crop((196,142,800,420))])],E+'sbs-konsole.png')
grid([('Board: Overview code window',[im(R+'desktop-dark-3.png').crop((640,630,1080,758)).resize((660,192))]),('Built: KWrite, theme "Plasma Fusion Dark"',[im(V6+'dark-05-kwrite.png').crop((400,276,1040,520))])],E+'sbs-kwrite.png')
for v,V,col in (('dark',V6,(57,210,709,1338)),('light',V7,(733,210,1385,1338))):
    b=im(R+'theme-parts-2.png').crop(col)
    g=im(V+'%s-06-gtk3.png'%v).crop((410,132,1031,722)); m=im(V+'%s-07-gtk3-menu.png'%v).crop((595,205,775,465))
    a=im(V+'%s-08-adw.png'%v).crop((400,117,1041,737)); am=im(V+'%s-09-adw-menu.png'%v).crop((835,160,970,350))
    grid([('Board: Controls, %s'%v,[b]),('Built: GTK 3 app (Breeze + plasma-fusion.css), menu',[g,m]),('Built: libadwaita app, pop-over menu',[a,am])],E+'sbs-controls-gtk-%s.png'%v)
print('ok')
