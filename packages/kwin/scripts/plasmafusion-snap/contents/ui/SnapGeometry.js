// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Tile.absoluteGeometry rounds origin and size separately. Use work-area endpoints for outer
// edges so an odd-sized trailing tile cannot extend under a panel. Native padding remains on
// shared edges, including while KWin's interactive resize controller moves them.
function tileRect(a, r, padding, area, flushOuter) {
    const outerLeft = r.x <= 0.001;
    const outerTop = r.y <= 0.001;
    const outerRight = r.x + r.width >= 0.999;
    const outerBottom = r.y + r.height >= 0.999;
    const left = Math.max(area.x, flushOuter && outerLeft ? area.x : a.x + (outerLeft ? padding : padding / 2));
    const top = Math.max(area.y, flushOuter && outerTop ? area.y : a.y + (outerTop ? padding : padding / 2));
    const right = Math.min(area.x + area.width, flushOuter && outerRight ? area.x + area.width : a.x + a.width - (outerRight ? padding : padding / 2));
    const bottom = Math.min(area.y + area.height, flushOuter && outerBottom ? area.y + area.height : a.y + a.height - (outerBottom ? padding : padding / 2));
    return { x: left, y: top, width: Math.max(0, right - left), height: Math.max(0, bottom - top) };
}

// ---------------------------------------------------------------- KWin's quick tiles
//
// KWin keeps one quick-tile root per screen and desktop (QuickRootTile, src/tiles/quicktile.cpp,
// unchanged from Plasma 6.7 to 6.8) beside the custom (Meta+T) root that Workspace.rootTile()
// returns. Scripts can reach it only as a window tile's parent, and it is not a QML type: Plasma
// 6.8 registers Tile and CustomTile, not QuickRootTile. Its children are the left and right
// halves, the top and bottom halves and the four quarters, in that order today. Both are read here
// without relying on the number or the order of the children, which KWin does not document.

// The role of a quick tile from its shape: 0 left, 1 right, 2 top, 3 bottom, 4 top-left,
// 5 top-right, 6 bottom-left, 7 bottom-right; -1 for anything else. Halves span the whole
// height (left/right) or width (top/bottom); splits move the shared edge only.
function quickRole(tile) {
    const r = tile ? tile.relativeGeometry : null;
    if (!r || r.width === undefined) {
        return -1;
    }
    const eps = 0.001;
    const atLeft = r.x <= eps;
    const atTop = r.y <= eps;
    const fullWidth = atLeft && r.x + r.width >= 1 - eps;
    const fullHeight = atTop && r.y + r.height >= 1 - eps;
    if (fullWidth && fullHeight) {
        return -1;
    }
    if (fullHeight) {
        return atLeft ? 0 : 1;
    }
    if (fullWidth) {
        return atTop ? 2 : 3;
    }
    return (atLeft ? 0 : 1) + (atTop ? 4 : 6);
}

// The quick tile with the given role, or null.
function quickTileFor(quickRoot, role) {
    const tiles = quickRoot ? quickRoot.tiles : null;
    if (!tiles) {
        return null;
    }
    for (let i = 0; i < tiles.length; ++i) {
        if (quickRole(tiles[i]) === role) {
            return tiles[i];
        }
    }
    return null;
}

// Whether a root tile is KWin's quick-tile root. Qt names an object's class in its string
// ("KWin::QuickRootTile(0x…)" in Plasma 6.7 and 6.8); should that name change, the shape decides:
// all eight roles present, which a custom layout cannot have, since its tiles never overlap.
function isQuickRoot(rootTile, customRoot) {
    if (!rootTile || rootTile.parent || rootTile === customRoot || !rootTile.tiles) {
        return false;
    }
    const name = String(rootTile);
    if (name.indexOf("QuickRootTile") >= 0) {
        return true;
    }
    if (name.indexOf("CustomTile") >= 0 || name.indexOf("RootTile") >= 0) {
        return false;
    }
    for (let role = 0; role < 8; ++role) {
        if (!quickTileFor(rootTile, role)) {
            return false;
        }
    }
    return true;
}
