// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later

#include "splitside.h"

#include <core/rect.h>
#include <window.h>

namespace KWin
{

FusionSplitSide fusionSplitSide(Window *window)
{
    if (!window || window->isDeleted()) {
        return FusionSplitSide::None;
    }
    // The window's tile (Window::requestedTile, the QML "tile"), read through its properties:
    // KWin does not install the Tile header.
    const QObject *tile = window->property("tile").value<QObject *>();
    if (!tile) {
        return FusionSplitSide::None;
    }
    const RectF g = tile->property("relativeGeometry").value<RectF>();
    if (g.height() <= 0.99) {
        return FusionSplitSide::None;
    }
    if (g.x() < 0.01 && g.width() < 0.99) {
        return FusionSplitSide::Left;
    }
    if (g.x() > 0.01 && g.x() + g.width() > 0.99) {
        return FusionSplitSide::Right;
    }
    return FusionSplitSide::None;
}

bool fusionSideBySide(Window *window, Window *other)
{
    if (!window || !other || window == other || window->output() != other->output()) {
        return false;
    }
    const FusionSplitSide side = fusionSplitSide(window);
    const FusionSplitSide otherSide = fusionSplitSide(other);
    return side != FusionSplitSide::None && otherSide != FusionSplitSide::None && side != otherSide;
}

Window *fusionVisiblePartner(Window *window, const QList<Window *> &below)
{
    const FusionSplitSide side = fusionSplitSide(window);
    if (side == FusionSplitSide::None) {
        return nullptr;
    }
    for (int i = 0; i < below.size(); ++i) {
        const FusionSplitSide otherSide = fusionSplitSide(below[i]);
        if (otherSide == FusionSplitSide::None || otherSide == side) {
            continue;
        }
        const QPointF middle = below[i]->frameGeometry().center();
        for (int j = 0; j < i; ++j) {
            if (below[j]->frameGeometry().contains(middle)) {
                return nullptr;
            }
        }
        return below[i];
    }
    return nullptr;
}

} // namespace KWin
