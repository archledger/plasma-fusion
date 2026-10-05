#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Reference palette kits from the shipped colour schemes.

  packages/color-schemes/export-kits.py

Writes packages/color-schemes/reference-kits/ from PlasmaFusion{Dark,Light}.colors: CSS custom
properties (fusion-{dark,light}.css), Dear ImGui colour assignments (imgui_fusion.cpp), Flutter
ColorScheme constants (flutter_fusion.dart) and wxWidgets colour roles (wx_fusion.md). The values
are the schemes' own; tests/check-kits.py catches a kit that stops matching them.

A scheme's accent is its Colors:Selection BackgroundNormal (the value the XDG settings portal
reports as accent-color); the schemes carry no separate AccentColor key.
"""
import configparser
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
OUT = ROOT / "reference-kits"
SCHEMES = (("PlasmaFusionDark.colors", "dark", "Brightness.dark", "ApplyFusionDark"),
           ("PlasmaFusionLight.colors", "light", "Brightness.light", "ApplyFusionLight"))

COPYRIGHT = "SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>"
LICENSE = "SPDX-License-Identifier: GPL-2.0-or-later"


def load(name):
    """The scheme as (rgb(group, key), files own name)."""
    parser = configparser.ConfigParser()
    parser.optionxform = lambda optionstr: optionstr  # keep the keys' case (BackgroundNormal)
    parser.read(ROOT / name, encoding="utf-8")

    def rgb(group, key):
        value = parser[group][key].strip()
        r, g, b = (int(v) for v in value.split(","))
        return r, g, b

    return rgb


def hexv(color):
    return "#%02x%02x%02x" % color


def imvec(color, alpha=1.0):
    return "ImVec4(%.3ff, %.3ff, %.3ff, %.3ff)" % (color[0] / 255, color[1] / 255, color[2] / 255, alpha)


def dart(color):
    return "Color(0xFF%02X%02X%02X)" % color


# CSS custom properties, group.key of the scheme.
CSS_MAP = (
    ("--fusion-accent", "Colors:Selection", "BackgroundNormal"),
    ("--fusion-on-accent", "Colors:Selection", "ForegroundNormal"),
    ("--fusion-bg", "Colors:View", "BackgroundNormal"),
    ("--fusion-bg-alt", "Colors:View", "BackgroundAlternate"),
    ("--fusion-surface", "Colors:Window", "BackgroundNormal"),
    ("--fusion-surface-alt", "Colors:Window", "BackgroundAlternate"),
    ("--fusion-elevated", "Colors:Button", "BackgroundNormal"),
    ("--fusion-fg", "Colors:View", "ForegroundNormal"),
    ("--fusion-fg-muted", "Colors:View", "ForegroundInactive"),
    ("--fusion-link", "Colors:View", "ForegroundLink"),
    ("--fusion-positive", "Colors:View", "ForegroundPositive"),
    ("--fusion-negative", "Colors:View", "ForegroundNegative"),
    ("--fusion-neutral", "Colors:View", "ForegroundNeutral"),
)

# Dear ImGui colours, name -> (group, key, alpha).
IMGUI_MAP = (
    ("Text", "Colors:View", "ForegroundNormal", 1.0),
    ("TextDisabled", "Colors:View", "ForegroundInactive", 1.0),
    ("WindowBg", "Colors:Window", "BackgroundNormal", 1.0),
    ("ChildBg", "Colors:View", "BackgroundNormal", 1.0),
    ("PopupBg", "Colors:Window", "BackgroundAlternate", 1.0),
    ("Border", "Colors:View", "BackgroundAlternate", 1.0),
    ("FrameBg", "Colors:Button", "BackgroundNormal", 1.0),
    ("FrameBgHovered", "Colors:Button", "DecorationHover", 1.0),
    ("FrameBgActive", "Colors:Button", "DecorationFocus", 1.0),
    ("TitleBg", "Colors:Window", "BackgroundAlternate", 1.0),
    ("TitleBgActive", "Colors:Window", "BackgroundNormal", 1.0),
    ("Button", "Colors:Button", "BackgroundNormal", 1.0),
    ("ButtonHovered", "Colors:Button", "DecorationHover", 1.0),
    ("ButtonActive", "Colors:Button", "DecorationFocus", 1.0),
    ("Header", "Colors:Selection", "BackgroundNormal", 1.0),
    ("HeaderHovered", "Colors:Selection", "DecorationHover", 1.0),
    ("HeaderActive", "Colors:Selection", "DecorationFocus", 1.0),
    ("CheckMark", "Colors:Selection", "BackgroundNormal", 1.0),
    ("SliderGrab", "Colors:Selection", "BackgroundNormal", 1.0),
    ("SliderGrabHovered", "Colors:Selection", "DecorationHover", 1.0),
    ("SliderGrabActive", "Colors:Selection", "DecorationFocus", 1.0),
    ("TextSelectedBg", "Colors:Selection", "BackgroundNormal", 0.35),
)

# Flutter ColorScheme, constructor name -> (group, key).
DART_MAP = (
    ("primary", "Colors:Selection", "BackgroundNormal"),
    ("onPrimary", "Colors:Selection", "ForegroundNormal"),
    ("secondary", "Colors:View", "ForegroundLink"),
    ("onSecondary", "Colors:Selection", "ForegroundNormal"),
    ("surface", "Colors:Window", "BackgroundNormal"),
    ("onSurface", "Colors:View", "ForegroundNormal"),
    ("error", "Colors:View", "ForegroundNegative"),
    ("onError", "Colors:Selection", "ForegroundNormal"),
    ("outline", "Colors:View", "ForegroundInactive"),
)

# wxWidgets colour roles, name -> (group, key, description).
WX_MAP = (
    ("wxSYS_COLOUR_WINDOW", "Colors:View", "BackgroundNormal", "text areas"),
    ("wxSYS_COLOUR_WINDOWTEXT", "Colors:View", "ForegroundNormal", "text on window"),
    ("wxSYS_COLOUR_BACKGROUND", "Colors:Window", "BackgroundNormal", "desktop background"),
    ("wxSYS_COLOUR_BTNFACE", "Colors:Button", "BackgroundNormal", "button faces"),
    ("wxSYS_COLOUR_BTNTEXT", "Colors:Button", "ForegroundNormal", "button labels"),
    ("wxSYS_COLOUR_HIGHLIGHT", "Colors:Selection", "BackgroundNormal", "selection and the accent"),
    ("wxSYS_COLOUR_HIGHLIGHTTEXT", "Colors:Selection", "ForegroundNormal", "text on selection"),
    ("wxSYS_COLOUR_GRAYTEXT", "Colors:View", "ForegroundInactive", "disabled text"),
)


def css_kit(rgb, variant, scheme_name):
    lines = [f"/* {COPYRIGHT} */", f"/* {LICENSE} */",
             f"/* Generated by packages/color-schemes/export-kits.py from {scheme_name}. Do not edit. */",
             ":root {"]
    for name, group, key in CSS_MAP:
        lines.append(f"  {name}: {hexv(rgb(group, key))};")
    lines.append("}")
    return "\n".join(lines) + "\n"


def imgui_kit(dark, light):
    lines = [f"// {COPYRIGHT}", f"// {LICENSE}",
             "// Generated by packages/color-schemes/export-kits.py from the Plasma Fusion colour",
             "// schemes. Do not edit; run the generator and packages/color-schemes/tests/check-kits.py.",
             "#include <imgui.h>",
             ""]
    for rgb, variant, scheme_name, func in ((dark, "dark", "PlasmaFusionDark.colors", "ApplyFusionDark"),
                                            (light, "light", "PlasmaFusionLight.colors", "ApplyFusionLight")):
        accent = rgb("Colors:Selection", "BackgroundNormal")
        lines.append(f"// {scheme_name}: the accent is its Colors:Selection BackgroundNormal ({hexv(accent)}).")
        lines.append(f"void {func}(ImGuiStyle &style)")
        lines.append("{")
        for name, group, key, alpha in IMGUI_MAP:
            lines.append(f"    style.Colors[ImGuiCol_{name}] = {imvec(rgb(group, key), alpha)};")
        lines.append("}")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def dart_kit(dark, light):
    lines = [f"// {COPYRIGHT}", f"// {LICENSE}",
             "// Generated by packages/color-schemes/export-kits.py from the Plasma Fusion colour",
             "// schemes. Do not edit; run the generator and packages/color-schemes/tests/check-kits.py.",
             "import 'package:flutter/material.dart';",
             ""]
    for rgb, variant, brightness, unused in ((dark, "dark", "Brightness.dark", None),
                                             (light, "light", "Brightness.light", None)):
        lines.append(f"const ColorScheme fusion{variant.capitalize()} = ColorScheme(")
        lines.append(f"  brightness: {brightness},")
        for name, group, key in DART_MAP:
            lines.append(f"  {name}: {dart(rgb(group, key))},")
        lines.append(");")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def wx_kit(dark, light):
    lines = ["<!--", COPYRIGHT, LICENSE, "-->", "",
             "# wxWidgets colour roles from the Plasma Fusion schemes", "",
             "Generated by `packages/color-schemes/export-kits.py`; do not edit. Apply with",
             "`wxSystemSettings::GetColour` values overridden in the app, or draw from these tables",
             "in a custom style. A scheme's accent is its Colors:Selection BackgroundNormal.", "",
             "| wxSystemColour | Plasma Fusion Dark | Plasma Fusion Light | Use | Source |",
             "|---|---|---|---|---|"]
    for name, group, key, use in WX_MAP:
        lines.append(f"| `{name}` | `{hexv(dark(group, key))}` | `{hexv(light(group, key))}` | {use} | "
                     f"{group} {key} |")
    lines.append("")
    return "\n".join(lines)


def main():
    OUT.mkdir(exist_ok=True)
    rgbs = {}
    for name, variant, _, _ in SCHEMES:
        rgbs[variant] = load(name)
    (OUT / "fusion-dark.css").write_text(css_kit(rgbs["dark"], "dark", "PlasmaFusionDark.colors"), encoding="utf-8")
    (OUT / "fusion-light.css").write_text(css_kit(rgbs["light"], "light", "PlasmaFusionLight.colors"), encoding="utf-8")
    (OUT / "imgui_fusion.cpp").write_text(imgui_kit(rgbs["dark"], rgbs["light"]), encoding="utf-8")
    (OUT / "flutter_fusion.dart").write_text(dart_kit(rgbs["dark"], rgbs["light"]), encoding="utf-8")
    (OUT / "wx_fusion.md").write_text(wx_kit(rgbs["dark"], rgbs["light"]), encoding="utf-8")
    print(f"export-kits: wrote 5 files to {OUT}")


if __name__ == "__main__":
    main()
