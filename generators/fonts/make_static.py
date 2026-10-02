#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later

"""Cut static weight instances from the variable Manrope and Space Grotesk fonts.

Qt synthesises bold on top of variable fonts for heavy weights, and Space Grotesk's variable
font has no 600 instance, so Plasma Fusion installs one static file per weight instead.

Maintainer tool (needs fontTools):
    python3 -m venv build/venv-fonts && build/venv-fonts/bin/pip install fonttools
    build/venv-fonts/bin/python generators/fonts/make_static.py
The output under fonts/<family>/static/ is committed; the build only copies it.
"""
import os
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

FAMILIES = [
    ("Manrope", "fonts/manrope/Manrope[wght].ttf", "fonts/manrope/static",
     [(200, "ExtraLight"), (300, "Light"), (400, "Regular"), (500, "Medium"),
      (600, "SemiBold"), (700, "Bold"), (800, "ExtraBold")]),
    ("Space Grotesk", "fonts/spacegrotesk/SpaceGrotesk[wght].ttf", "fonts/spacegrotesk/static",
     [(300, "Light"), (400, "Regular"), (500, "Medium"), (600, "SemiBold"), (700, "Bold")]),
]


def set_names(font, family, style, weight):
    """Write the name table the way static families from Google Fonts do."""
    name = font["name"]
    ribbi = style in ("Regular", "Bold")
    legacy_family = family if ribbi else f"{family} {style}"
    legacy_style = style if ribbi else "Regular"
    ps_name = f"{family.replace(' ', '')}-{style}"
    version = name.getDebugName(5) or "Version 1.000"
    for record_id in (1, 2, 3, 4, 6, 16, 17, 25):
        name.removeNames(nameID=record_id)
    name.setName(legacy_family, 1, 3, 1, 0x409)
    name.setName(legacy_style, 2, 3, 1, 0x409)
    name.setName(f"{version.split(';')[0]};{ps_name}", 3, 3, 1, 0x409)
    name.setName(f"{family} {style}", 4, 3, 1, 0x409)
    name.setName(ps_name, 6, 3, 1, 0x409)
    if not ribbi:
        name.setName(family, 16, 3, 1, 0x409)
        name.setName(style, 17, 3, 1, 0x409)

    os2 = font["OS/2"]
    os2.usWeightClass = weight
    # fsSelection: bit 0 italic, bit 5 bold, bit 6 regular.
    os2.fsSelection &= ~((1 << 0) | (1 << 5) | (1 << 6))
    os2.fsSelection |= (1 << 5) if style == "Bold" else (1 << 6) if style == "Regular" else 0
    font["head"].macStyle = 1 if style == "Bold" else 0


def main():
    for family, source, out_dir, weights in FAMILIES:
        out = os.path.join(ROOT, out_dir)
        os.makedirs(out, exist_ok=True)
        for weight, style in weights:
            font = TTFont(os.path.join(ROOT, source))
            static = instancer.instantiateVariableFont(font, {"wght": weight})
            for table in ("STAT", "fvar", "avar", "gvar", "HVAR", "MVAR"):
                if table in static:
                    del static[table]
            set_names(static, family, style, weight)
            path = os.path.join(out, f"{family.replace(' ', '')}-{style}.ttf")
            static.save(path)
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
