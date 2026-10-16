// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Snap sizes from the keyboard (Rectangle's cycle): "Plasma Fusion: Snap Left/Right", which the
// setup gives Meta+Left/Right, step the window through 1/2, 1/3 and 2/3 of the screen on that side
// and then back to 1/2. When a screen lies on that side, the step after 2/3 moves the window there
// (to that screen's facing half), as KWin's own quick tile does on a second press. Pure logic,
// plain values in and out (packages/kwin/tests/snap-cycle.test.js); main.qml places the windows.

// The widths the steps give in a work area WIDTH wide, with the gap between snapped windows GAP
// and HALFGAP for the halves (KWin's quick tiles take the gap only with QuickTileGaps), as the
// script places them: the half and two thirds inset by half a gap at their inner edge, a third
// (thirdRect) a third of what the two gaps between three leave.
function stepWidths(width, gap, halfGap) {
    return { half: width / 2 - halfGap / 2, third: (width - 2 * gap) / 3, twoThirds: width * 2 / 3 - gap / 2 };
}

// Where a window is on SIDE ("left" or "right") of the work area AREA ({ x, y, width, height }):
// "half", "third", "twoThirds", or "" (none of them). Its edge on that side and its top must meet
// the area's (within 8 px) and it must be nearly the area's height (90 %: a terminal sizes itself
// in whole character cells, so its bottom may stop short); its width is measured against each
// step's width with the gaps (stepWidths), within 3 % of the area's width (the cells again).
function stepOf(rect, area, side, gap, halfGap) {
    if (!rect || !area || area.width <= 0) {
        return "";
    }
    const edge = side === "left" ? Math.abs(rect.x - area.x) : Math.abs(rect.x + rect.width - (area.x + area.width));
    if (edge > 8 || Math.abs(rect.y - area.y) > 8 || rect.height < area.height * 0.9) {
        return "";
    }
    const widths = stepWidths(area.width, gap || 0, halfGap === undefined ? gap || 0 : halfGap);
    const near = (want) => Math.abs(rect.width - want) <= area.width * 0.03;
    if (near(widths.half)) {
        return "half";
    }
    if (near(widths.third)) {
        return "third";
    }
    if (near(widths.twoThirds)) {
        return "twoThirds";
    }
    return "";
}

// The step a window is at, given the last step asked of it (PENDING: { side, step, at, from },
// FROM the window's rectangle when it was asked, or null) at NOW (ms), the window's rectangle being
// RECT: a client that has not drawn the new size yet still shows the rectangle it had, so for a
// second after a request on the same side the requested step counts while the window still has
// that rectangle. Any other rectangle (the step drawn, or the window moved or resized since, by the
// user or anything else) is measured: MEASURED, stepOf's answer.
function currentStep(measured, pending, side, now, rect) {
    if (pending && pending.side === side && now - pending.at < 1000 && sameRect(rect, pending.from)) {
        return pending.step;
    }
    return measured;
}
function sameRect(a, b) {
    return !!a && !!b && Math.abs(a.x - b.x) <= 1 && Math.abs(a.y - b.y) <= 1
        && Math.abs(a.width - b.width) <= 1 && Math.abs(a.height - b.height) <= 1;
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
