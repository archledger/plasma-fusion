// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Keep the perpendicular axis, replace the requested axis. Roles match SnapGeometry.quickRole:
// left, right, top, bottom, top-left, top-right, bottom-left, bottom-right; -1 means untiled.
function directionalRole(role, direction) {
    let x = [-1, 1, 0, 0, -1, 1, -1, 1][role] || 0;
    let y = [0, 0, -1, 1, -1, -1, 1, 1][role] || 0;
    switch (direction) {
    case "left": x = -1; break;
    case "right": x = 1; break;
    case "up": y = -1; break;
    case "down": y = 1; break;
    default: return role;
    }
    if (x === 0) return y < 0 ? 2 : 3;
    if (y === 0) return x < 0 ? 0 : 1;
    return (y < 0 ? 4 : 6) + (x > 0 ? 1 : 0);
}

// Only screens wholly on that side and sharing a span are adjacent. Choose the nearest facing
// edge, then the closest perpendicular center; connector order cannot turn an arrow sideways.
function directionalNeighbour(screens, current, direction) {
    const horizontal = direction === "left" || direction === "right";
    const backwards = direction === "left" || direction === "up";
    if (!horizontal && direction !== "up" && direction !== "down") return -1;
    const a = horizontal ? current.x : current.y;
    const length = horizontal ? current.width : current.height;
    const b = horizontal ? current.y : current.x;
    const span = horizontal ? current.height : current.width;
    let best = -1, distance = Infinity, alignment = Infinity;
    for (let i = 0; i < screens.length; ++i) {
        const screen = screens[i];
        const sa = horizontal ? screen.x : screen.y;
        const size = horizontal ? screen.width : screen.height;
        const sb = horizontal ? screen.y : screen.x;
        const cross = horizontal ? screen.height : screen.width;
        if (Math.min(b + span, sb + cross) <= Math.max(b, sb)) continue;
        const gap = backwards ? a - (sa + size) : sa - (a + length);
        if (gap < 0) continue;
        const offset = Math.abs(sb + cross / 2 - b - span / 2);
        if (gap < distance || (gap === distance && offset < alignment)) {
            best = i;
            distance = gap;
            alignment = offset;
        }
    }
    return best;
}
