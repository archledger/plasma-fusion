// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#pragma once

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

} // namespace KWin
