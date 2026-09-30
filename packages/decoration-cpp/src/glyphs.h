/*
    SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/
#pragma once

#include <QPainterPath>
#include <QString>

namespace PlasmaFusion
{

enum class Glyph {
    None,
    Minimize,
    Maximize,
    Restore,
    Close,
    KeepAbove,
    KeepBelow,
    OnAllDesktops,
    Shade,
    Unshade,
    ContextHelp,
    ApplicationMenu,
    ExcludeFromCapture,
};

// Symbolic glyph in the boards' 24-unit grid (Icons.dc.html set: stroke 1.8, round caps and joins).
const QPainterPath &glyphPath(Glyph glyph);

// Parser for the SVG path subset the glyphs use (M L H V C A Z, absolute and relative).
QPainterPath parseSvgPath(const QString &data);

} // namespace PlasmaFusion
