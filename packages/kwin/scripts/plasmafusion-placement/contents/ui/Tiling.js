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
//   dividerX: real, output: Output, desktop: VirtualDesktop, activity: string }
function createSession() {
    return { active: false, generation: 0, master: null, masterKey: "",
             stack: [], savedFloats: {}, dividerX: 0, output: null, desktop: null,
             activity: "" };
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

// The windows on the tiled workspace that are not the master (stacking order, TOP FIRST:
// KWin's stackingOrder lists the bottom-most first, and the stack's first cell and the focus
// cycle are the top-most window's). The workspace is the desktop AND the activity AND the
// session's output: activities are orthogonal to desktops, and a window of another activity
// or another screen is not this session's to place - an empty activity list is a window on
// all of them.
function stackCandidates(windows, master, desktop, activity, output) {
    const out = [];
    for (let i = windows.length - 1; i >= 0; --i) {
        const w = windows[i];
        if (w === master || !eligibleForStack(w)) {
            continue;
        }
        if (!onWorkspace(w, desktop, activity, output)) {
            continue;
        }
        out.push(w);
    }
    return out;
}

// Whether a window is on this session's workspace: its desktop and its activity. Activities
// are orthogonal to desktops, and a window of another activity is not on this workspace's view
// even where the desktop number is shared; an empty activity list is a window on all of them.
// The candidates, the managed windows and the leavers all read the one rule. The output scopes
// it further: the session tiles its own screen, and a same-desktop window on another output is
// not the session's to place.
function onWorkspace(w, desktop, activity, output) {
    if (!w || w.onAllDesktops || !w.desktops || w.desktops.length !== 1
            || !desktopMatches(w.desktops[0], desktop)) {
        return false;
    }
    if (output !== undefined && w.output !== output) {
        return false;
    }
    const activities = w.activities || [];
    return activities.length === 0 || activity === "" || activities.indexOf(activity) >= 0;
}

// Whether two desktop references are the same desktop: KWin hands the scripting API
// VirtualDesktop objects (identity, or their id when the references differ), and tests hand
// plain numbers and strings. Stringifying the wrappers would compare representations, not
// desktops - two wrappers of one desktop would differ, and tiling on one desktop could pull
// another one's windows in.
function desktopMatches(a, b) {
    if (a === b) {
        return true;
    }
    if (!a || !b) {
        return false;
    }
    if (a.id !== undefined && b.id !== undefined) {
        return String(a.id) === String(b.id);
    }
    return String(a) === String(b);
}

// A dormant window: minimized, but otherwise a stack candidate - a member-to-be. This is the
// one rule both dormant paths read: the toggle-on scan below, and the live add (a window can
// first appear while the session is up, already minimized - for it too, a later restore emits
// no windowAdded). A window that is full-screen or manually tiled keeps that state through a
// restore, and a relayout must never overwrite it, so those are strangers too.
function eligibleDormant(w) {
    return w && !w.deleted && w.normalWindow && !w.transient && !w.modal && w.moveable
        && w.resizeable && w.minimized && !w.fullScreen && !w.tile;
}

// The workspace's minimized windows at session start: not stack candidates (they are out of
// the view), but each is a member-to-be. Its float is saved and it is watched from the start,
// because restoring it during the session emits no windowAdded - it was there all along.
function dormantCandidates(windows, master, desktop, activity, output) {
    const out = [];
    for (let i = 0; i < windows.length; ++i) {
        const w = windows[i];
        if (w === master || !eligibleDormant(w)) {
            continue;
        }
        if (!onWorkspace(w, desktop, activity, output)) {
            continue;
        }
        out.push(w);
    }
    return out;
}

// What a reflow must restore before it detaches: a member the layout had placed sits at a cell
// no untoggle can undo, so its saved float goes back; one the layout never placed already sits
// at its own float. A member with no float saved (or no cell it was placed at) is left alone.
function floatRestores(floated, savedFloats, cellRects) {
    const out = [];
    for (let i = 0; i < floated.length; ++i) {
        const id = String(floated[i].internalId);
        if (cellRects[id] && savedFloats[id]) {
            out.push({ window: floated[i], rect: savedFloats[id] });
        }
    }
    return out;
}

// Whether a frame is the tiler's own placement landing on the cell it assigned: the
// synchronous write or the client's late commit of it. Anything else is the user's hand.
function isOwnCell(cell, frame) {
    return !!cell && !!frame
        && frame.x === cell.x && frame.y === cell.y
        && frame.width === cell.width && frame.height === cell.height;
}

// Layout the stack: feasible windows get cells; infeasible windows float (the safe state).
// Feasibility is against the cells as they would be for the set being placed, so the worst
// fit goes first and the rest are re-tried in the larger cells: a 300 px column with minimum
// heights 100, 100 and 200 has no three-way cells (~95 px each), but removing the 200 px
// window gives the two that fit ~146 px cells - they place, and only the tall one floats,
// where a single pass against the three-way cells would float all three.
function layoutStack(candidates, area, dividerX, gap) {
    const pending = candidates.slice();
    const floated = [];
    while (pending.length > 0) {
        const cells = stackRects(area, dividerX, gap, pending.length);
        // The worst fit leaves first: the tallest minimum (the column constrains height; a
        // window too wide for the column is never feasible and leaves as soon as it is the
        // worst - or the only - misfit, which it always eventually is).
        let worst = -1;
        for (let i = 0; i < pending.length; ++i) {
            if (feasibleInCell(pending[i].minSize, cells[i])) {
                continue;
            }
            if (worst < 0 || pending[i].minSize.height > pending[worst].minSize.height) {
                worst = i;
            }
        }
        if (worst < 0) {
            const placed = [];
            for (let i = 0; i < pending.length; ++i) {
                placed.push({ window: pending[i], rect: cells[i] });
            }
            return { placed: placed, floated: floated };
        }
        floated.push(pending.splice(worst, 1)[0]);
    }
    return { placed: [], floated: floated };
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
