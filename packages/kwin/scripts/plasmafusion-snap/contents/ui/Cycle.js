// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Snap sizes from the keyboard (Rectangle's cycle): "Plasma Fusion: Snap Left/Right", which the
// setup gives Meta+Left/Right, step the window through 1/2, 1/3 and 2/3 of the screen on that side
// and then back to 1/2. When a screen lies on that side, the step after 2/3 moves the window there
// (to that screen's facing half), as KWin's own quick tile does on a second press. Pure logic,
// plain values in and out (packages/kwin/tests/snap-cycle.test.js); main.qml places the windows.

// Where a window is on SIDE ("left" or "right") of the work area AREA ({ x, y, width, height }):
// "half", "third", "twoThirds", or "" (none of them). The edge on that side must touch the area's
// edge (within 8 px) and the window span the area's height; its width is measured as a share of
// the area, within 3 % (a terminal sizes itself in whole character cells).
function stepOf(rect, area, side) {
    if (!rect || !area || area.width <= 0) {
        return "";
    }
    const edge = side === "left" ? Math.abs(rect.x - area.x) : Math.abs(rect.x + rect.width - (area.x + area.width));
    if (edge > 8 || rect.height < area.height * 0.9) {
        return "";
    }
    const share = rect.width / area.width;
    const near = (want) => Math.abs(share - want) <= 0.03;
    if (near(1 / 2)) {
        return "half";
    }
    if (near(1 / 3)) {
        return "third";
    }
    if (near(2 / 3)) {
        return "twoThirds";
    }
    return "";
}

// The step after CURRENT: 1/2, 1/3, 2/3, then "screen" when a screen lies on that side
// (HASNEIGHBOUR), else 1/2 again.
function nextStep(current, hasNeighbour) {
    switch (current) {
    case "half":
        return "third";
    case "third":
        return "twoThirds";
    case "twoThirds":
        return hasNeighbour ? "screen" : "half";
    default:
        return "half";
    }
}

// The screen next to CURRENT on SIDE among SCREENS (each { x, y, width, height }): the nearest one
// lying wholly on that side that shares some height with it, or -1.
function neighbourOf(screens, current, side) {
    let best = -1;
    let bestGap = Infinity;
    for (let i = 0; i < screens.length; ++i) {
        const s = screens[i];
        const overlap = Math.min(s.y + s.height, current.y + current.height) - Math.max(s.y, current.y);
        if (overlap <= 0) {
            continue;
        }
        const gap = side === "left" ? current.x - (s.x + s.width) : s.x - (current.x + current.width);
        if (gap >= 0 && gap < bestGap) {
            best = i;
            bestGap = gap;
        }
    }
    return best;
}
