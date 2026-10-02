#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Contact sheet of the wallpaper packages and startup backgrounds (test only)."""
from PIL import Image, ImageDraw, ImageFont
import glob, json
import os
import sys
F=os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../fonts/manrope/Manrope[wght].ttf')
f=ImageFont.truetype(F,16); f.set_variation_by_axes([700])
# usage: sheet.py STAGE_HOME OUT.png
STAGE=sys.argv[1].rstrip('/')
base=STAGE+'/.local/share/wallpapers/'
im=lambda p: Image.open(p).convert('RGB')
S=Image.new('RGB',(1900,1300),(24,24,28)); d=ImageDraw.Draw(S)
x,y=12,34
d.text((12,8),'PlasmaFusion (Dusk Ridge): images_dark/ and images/ at 1920x1200, 1920x1080, 1200x1920',font=f,fill=(235,238,245))
for sub in ('images_dark','images'):
    for sz,(w,h) in (('1920x1200',(384,240)),('1920x1080',(384,216)),('1200x1920',(150,240))):
        S.paste(im(base+'PlasmaFusion/contents/%s/%s.png'%(sub,sz)).resize((w,h),Image.LANCZOS),(x,y)); x+=w+10
y=34+240+40; d.text((12,y-26),'PlasmaFusion-<Name>: the other palettes of Main.dc.html (1920x1200 and portrait)',font=f,fill=(235,238,245))
for i,p in enumerate(sorted(glob.glob(base+'PlasmaFusion-*'))):
    name=json.load(open(p+'/metadata.json'))['KPlugin']['Name'].replace('Plasma Fusion ','')
    X=12+(i%4)*470; Y=y+(i//4)*215
    S.paste(im(p+'/contents/images/1920x1200.png').resize((256,160),Image.LANCZOS),(X,Y))
    S.paste(im(p+'/contents/images/1200x1920.png').resize((100,160),Image.LANCZOS),(X+262,Y))
    d.text((X,Y+166),name,font=f,fill=(205,211,228))
y2=y+3*215+30
d.text((12,y2-4),'Startup backgrounds (.local/share/plasma-fusion/backgrounds/, 1920x1200): dimmed (lock), blurred, login, splash',font=f,fill=(235,238,245))
x=12
for n in ('dimmed','blurred','login','splash'):
    S.paste(im(STAGE+'/.local/share/plasma-fusion/backgrounds/dusk-ridge-dark-%s.png'%n).resize((448,280),Image.LANCZOS),(x,y2+22)); x+=466
S.crop((0,0,1900,y2+22+292)).save(sys.argv[2],optimize=True)
