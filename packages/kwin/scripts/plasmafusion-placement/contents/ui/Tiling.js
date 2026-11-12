// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
.pragma library

// Plasma Fusion dynamic tiling: the master-and-stack layout's pure rules (the design:
// docs/NATIVE-TILING-SPEC.md; the first slice: Option A, fixed-anchor master).
//
// The master window rides the native transient ownership (the floating-A guarantee,
// the explicit restore, the placement-memory suppression); the stack windows are
// placed by direct frameGeometry writes with their pre-tiling floats saved for the
// untoggle. The tiler lives inside the placement package because the writer takes
// exactly one provider and the tiler IS that provider's policy consumer.

// ---------------------------------------------------------------- the layout

// The master's relative width within the output (0..1), clamped to the configured range.
function masterFraction(config) {
    return clamp(config.masterFraction, 0.25, 0.75);
}

function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v));
}

// The master tile's relative rect (normalized to the root tile).
function masterTileRect(fraction) {
    return { x: 0, y: 0, width: fraction, height: 1 };
}

// The stack column's absolute rects (endpoint-rounded, gap between cells, outer flush).
// area: the work area {x, y, width, height}; dividerX: the absolute divider x;
// gap: the pixel gap between stack cells; count: the number of stack windows.
function stackRects(area, dividerX, gap, count) {
    const out = [];
    if (count <= 0) {
        return out;
    }
    const x = dividerX + Math.ceil(gap / 2);
    const w = Math.max(1, area.x + area.width - x);
    const h = area.height;
    for (let i = 0; i < count; ++i) {
        const y0 = area.y + Math.round((h * i) / count);
        const y1 = (i === count - 1) ? area.y + h : area.y + Math.round((h * (i + 1)) / count);
        const g = (i === 0 ? 0 : Math.ceil(gap / 2)) + (i === count - 1 ? 0 : Math.ceil(gap / 2));
        out.push({ x: x, y: y0 + (i === 0 ? 0 : Math.ceil(gap / 2)), width: w,
                   height: Math.max(1, y1 - y0 - g) });
    }
    return out;
}

// Whether a window can be a stack cell (the eligibility snapshot is the caller's).
function feasibleInCell(minSize, cell) {
    return minSize.width <= cell.width && minSize.height <= cell.height;
}

// ---------------------------------------------------------------- the session

// The tiler's session state (one at a time; the controller holds one tree).
// { active: bool, generation: int, master: Window, masterKey: string,
//   stack: [Window], savedFloats: { internalId -> {x,y,width,height} },
//   dividerX: real, output: Output, desktop: VirtualDesktop }
function createSession() {
    return { active: false, generation: 0, master: null, masterKey: "",
             stack: [], savedFloats: {}, dividerX: 0, output: null, desktop: null };
}

// Toggle on: the eligibility checks, then the layout.
function eligibleForMaster(w) {
    return w && !w.deleted && w.normalWindow && !w.transient && !w.modal
        && w.moveable && w.resizeable && !w.fullScreen && !w.tile
        && !w.minimized && w.maximizeMode === 0;
}

function eligibleForStack(w) {
    return eligibleForMaster(w);
}

// The windows on the tiled desktop that are not the master (stacking order, top first).
function stackCandidates(windows, master, desktop) {
    const out = [];
    for (let i = 0; i < windows.length; ++i) {
        const w = windows[i];
        if (w === master || !eligibleForStack(w)) {
            continue;
        }
        // Same desktop only (the tiler is per-workspace).
        if (w.onAllDesktops || w.desktops.length !== 1
            || String(w.desktops[0]) !== String(desktop)) {
            continue;
        }
        out.push(w);
    }
    return out;
}

// Layout the stack: feasible windows get cells; infeasible windows float (the safe state).
function layoutStack(candidates, area, dividerX, gap) {
    const cells = stackRects(area, dividerX, gap, candidates.length);
    const placed = [];
    const floated = [];
    for (let i = 0; i < candidates.length; ++i) {
        const cell = cells[i];
        if (feasibleInCell(candidates[i].minSize, cell)) {
            placed.push({ window: candidates[i], rect: cell });
        } else {
            floated.push(candidates[i]);
        }
    }
    // Re-layout: only the placed windows get cells.
    if (floated.length > 0) {
        const rects = stackRects(area, dividerX, gap, placed.length);
        for (let i = 0; i < placed.length; ++i) {
            placed[i].rect = rects[i];
        }
    }
    return { placed: placed, floated: floated };
}

// ---------------------------------------------------------------- the focus order

// The focus cycle: master -> stack top-to-bottom -> master.
function focusOrder(session) {
    const out = [];
    if (session.master) {
        out.push(session.master);
    }
    for (let i = 0; i < session.stack.length; ++i) {
        out.push(session.stack[i]);
    }
    return out;
}

function nextInCycle(session, current) {
    const order = focusOrder(session);
    if (order.length === 0) {
        return null;
    }
    const idx = order.indexOf(current);
    if (idx < 0 || idx === order.length - 1) {
        return order[0];
    }
    return order[idx + 1];
}

function previousInCycle(session, current) {
    const order = focusOrder(session);
    if (order.length === 0) {
        return null;
    }
    const idx = order.indexOf(current);
    if (idx <= 0) {
        return order[order.length - 1];
    }
    return order[idx - 1];
}

// ---------------------------------------------------------------- the untoggle

// The saved floating geometries for the untoggle (the master's A is the native layer's;
// the stack's floats are the tiler's own memory).
function saveFloats(windows) {
    const out = {};
    for (let i = 0; i < windows.length; ++i) {
        const w = windows[i];
        const g = w.frameGeometry;
        out[String(w.internalId)] = { x: g.x, y: g.y, width: g.width, height: g.height };
    }
    return out;
}
