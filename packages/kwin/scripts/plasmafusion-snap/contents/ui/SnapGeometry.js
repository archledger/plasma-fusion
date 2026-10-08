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
