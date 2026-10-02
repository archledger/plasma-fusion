// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

#include <QList>

namespace KWin
{
class Window;

// Plasma Fusion: which side of a split a window is on (SPLIT.md item 4). Left: its tile spans the
// full height from the left edge but not the full width; right: its tile reaches the right edge from
// further in. The test of the tablet script's split divider (SplitDivider.qml isLeft/isRight).
// Minimized windows keep their tile.
enum class FusionSplitSide {
    None,
    Left,
    Right,
};

FusionSplitSide fusionSplitSide(Window *window);

// Plasma Fusion: whether two windows are tiled on opposite sides of the same screen.
bool fusionSideBySide(Window *window, Window *other);

// Plasma Fusion: the app seen in the other half of the window's split. Of the apps under it
// (topmost first), the topmost one tiled on the other side, unless an app above that one covers
// its middle (a maximized app, say); or null.
Window *fusionVisiblePartner(Window *window, const QList<Window *> &below);

} // namespace KWin
