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
//   masterFloat: {x,y,width,height} (the master's frame before the admission),
//   masterTile: {x,y,width,height} (the native tile's rectangle at the last layout),
//   stack: [Window], savedFloats: { internalId -> {x,y,width,height} },
//   dividerX: real, output: Output, desktop: VirtualDesktop, activity: string }
function createSession() {
    return { active: false, generation: 0, master: null, masterKey: "",
             masterFloat: null, masterTile: null,
             stack: [], savedFloats: {}, dividerX: 0, output: null, desktop: null,
             activity: "" };
}

// A window that keeps itself out of the taskbar or the window switcher is not one the user
// arranges, and the tiler leaves it alone as the tablet and snap scripts do. The XWayland
// Video Bridge keeps an invisible normal window mapped on the desktop (skip-taskbar,
// skip-switcher, opacity 0): as a stack member it took a cell, and the whole column once the
// others had left.
function userWindow(w) {
    return !w.skipTaskbar && !w.skipSwitcher;
}

// Toggle on: the eligibility checks, then the layout.
function eligibleForMaster(w) {
    return w && !w.deleted && w.normalWindow && !w.transient && !w.modal
        && w.moveable && w.resizeable && !w.fullScreen && !w.tile
        && !w.minimized && w.maximizeMode === 0 && userWindow(w);
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

// Whether the current view is the session's own: the desktop AND the activity AND the output.
// The toggle reads this to decide untoggle-versus-retile, and it must read the same scoping
// the whole session does (onWorkspace): another screen is another workspace even where the
// desktop and activity are shared, so a toggle there lays out that screen instead of silently
// untoggling the old one and leaving the invoked screen untiled. The output compares by
// identity and the desktop by desktopMatches - the one rule onWorkspace reads for both.
function sameView(session, desktop, activity, output) {
    return desktopMatches(session.desktop, desktop)
            && (session.activity === "" || session.activity === activity)
            && session.output === output;
}

// A dormant window: minimized, but otherwise a stack candidate - a member-to-be. This is the
// one rule both dormant paths read: the toggle-on scan below, and the live add (a window can
// first appear while the session is up, already minimized - for it too, a later restore emits
// no windowAdded). A window that is full-screen or manually tiled keeps that state through a
// restore, and a relayout must never overwrite it, so those are strangers too.
function eligibleDormant(w) {
    return w && !w.deleted && w.normalWindow && !w.transient && !w.modal && w.moveable
        && w.resizeable && w.minimized && !w.fullScreen && !w.tile && userWindow(w);
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

// How far the frame KWin lands can be from the whole-pixel rectangle the tiler asked for, on
// each of x, y, width and height, for a pixel grid of the given scale. On a scale of 1 it is the
// rectangle. On any other, KWin snaps the frame to device pixels (half a device pixel), gives
// the client a whole logical size under its decoration (half a logical pixel) and snaps what the
// client commits again: a 718 px cell is a 717.75 px frame at 133%, a 280 px one 280.5 px under
// a 50.25 px title bar, a 718 px one 718.67 px at 75%.
function cellSlack(scale) {
    const s = Number(scale);
    return s > 0 && s !== 1 ? 0.5 + 1 / s : 0;
}

// Whether a frame is the tiler's own placement landing on the cell it assigned: the
// synchronous write or the client's late commit of it, within the slack the pixel grids in use
// allow (cellSlack; none by default). Anything else is the user's hand.
function isOwnCell(cell, frame, slack) {
    if (!cell || !frame) {
        return false;
    }
    const allowed = (Number(slack) || 0) + 1e-6;
    return Math.abs(frame.x - cell.x) <= allowed && Math.abs(frame.y - cell.y) <= allowed
        && Math.abs(frame.width - cell.width) <= allowed && Math.abs(frame.height - cell.height) <= allowed;
}

// How far inside its tile the master's frame can be, on width and on height, for a pixel grid
// of the given scale. On a whole scale every whole-pixel rectangle is on the output's pixels
// and the frame is the tile's rectangle. On a fractional one the native layer gives the window
// the tile's corner and the largest size it reaches inside the tile (the fork's
// transientTileFrame): short of the tile by less than a step of the client's own grid (a
// logical pixel at most) and two device pixels.
function tileFitShort(scale) {
    const s = Number(scale);
    return s > 0 && !Number.isInteger(s) ? 1 + 2 / s : 0;
}

// Whether the master still stands where the native layer put it: at its tile's corner, at the
// tile's size or the fit inside it (tileFitShort). The tiler reads it while the release's own
// configure is still unanswered, to return the master at once; once the window's geometry has
// settled the native layer's answer decides (settleAgain).
function onMasterTile(tile, frame, scale) {
    if (!tile || !frame) {
        return false;
    }
    const short = tileFitShort(scale) + 1e-6;
    const fits = function (size, extent) {
        return size <= extent + 1e-6 && extent - size <= short;
    };
    return Math.abs(frame.x - tile.x) <= 1e-6 && Math.abs(frame.y - tile.y) <= 1e-6
        && fits(frame.width, tile.width) && fits(frame.height, tile.height);
}

// What the tiler does with the native layer's answer to settleWindow (the fork's
// Window::TransientSettleResult): 0 settled, 1 nothing to settle (a live restoration completes
// by itself), 2 another provider's and 5 refused end the matter; 3 (the window's geometry is
// not settled, or it is maximized, full screen or tiled) and 4 (it stands neither on its
// floating frame nor where the user's own move left it) are asked again.
function settleAgain(result) {
    return result === 3 || result === 4;
}

// Whether a rectangle shows on a screen the session has: the frame a released master is
// returned to is where it floated, half off an edge included, but never on a display that is
// gone.
function touchesScreen(rect, screens) {
    if (!rect) {
        return false;
    }
    for (let i = 0; i < screens.length; ++i) {
        const s = screens[i];
        if (rect.x < s.x + s.width && rect.x + rect.width > s.x
                && rect.y < s.y + s.height && rect.y + rect.height > s.y) {
            return true;
        }
    }
    return false;
}

// Whether a window reference can still be used. KWin marks a closing window deleted and
// destroys it a moment later; a script's reference to the destroyed window is neither null
// nor falsy, every property of it reads undefined (deleted too, so "not deleted" is true of
// it), and handing it to the compositor throws. A live window's deleted is the boolean false.
function alive(w) {
    return !!w && w.deleted === false;
}

// The same rectangle, to the last bits of a frame's arithmetic.
function sameRect(a, b) {
    return !!a && !!b && Math.abs(a.x - b.x) < 1e-3 && Math.abs(a.y - b.y) < 1e-3
        && Math.abs(a.width - b.width) < 1e-3 && Math.abs(a.height - b.height) < 1e-3;
}

// An admission refusal that passes: 3 (busy: the window's released record is being settled)
// and 7 (ineligible: a configure the client has not answered yet, as right after an
// activation or the previous session's restore). Every other refusal is final.
function admitAgain(result) {
    return result === 3 || result === 7;
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
