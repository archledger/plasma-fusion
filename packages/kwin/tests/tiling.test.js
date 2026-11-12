// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Plasma Fusion dynamic tiling: the node tests for Tiling.js.
// Run with: node packages/kwin/tests/tiling.test.js
// The assertions run inline (the placement suite's pattern): node exits non-zero on the
// first failure, and 80-kwin.sh runs this file with the other KWin node suites.

"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-placement", "contents", "ui", "Tiling.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { masterFraction, masterTileRect, stackRects, feasibleInCell, createSession,
        eligibleForMaster, stackCandidates, dormantCandidates, eligibleDormant, layoutStack,
        focusOrder, nextInCycle, previousInCycle, saveFloats, onWorkspace, desktopMatches,
        floatRestores, isOwnCell } = globalThis;

const rect = (x, y, width, height) => ({ x, y, width, height });
const windowWith = (over) => Object.assign({
    deleted: false, normalWindow: true, transient: false, modal: false,
    moveable: true, resizeable: true, fullScreen: false, tile: null,
    minimized: false, maximizeMode: 0, onAllDesktops: false,
    desktops: ["1"], activities: [], minSize: { width: 1, height: 1 }
}, over);

// ---------------------------------------------------------------- the layout

assert.strictEqual(masterFraction({ masterFraction: 0.5 }), 0.5);
assert.strictEqual(masterFraction({ masterFraction: 0.1 }), 0.25, "below the floor");
assert.strictEqual(masterFraction({ masterFraction: 0.9 }), 0.75, "above the ceiling");

const tile = masterTileRect(0.5);
assert.strictEqual(tile.x, 0);
assert.strictEqual(tile.y, 0);
assert.strictEqual(tile.width, 0.5);
assert.strictEqual(tile.height, 1);

{
    const area = rect(0, 0, 1000, 901);
    const rects = stackRects(area, 500, 8, 3);
    assert.strictEqual(rects.length, 3);
    // The cells fill the column (endpoint-rounded, last flush).
    assert.strictEqual(rects[0].y, 0);
    assert.strictEqual(rects[2].y + rects[2].height, 901);
    // Each cell is at least 1px.
    for (const r of rects) {
        assert.ok(r.height >= 1, "cell height >= 1");
        assert.ok(r.width >= 1, "cell width >= 1");
    }
}
assert.strictEqual(stackRects(rect(0, 0, 100, 100), 50, 8, 0).length, 0);
{
    const rects = stackRects(rect(0, 0, 1000, 800), 500, 8, 1);
    assert.strictEqual(rects.length, 1);
    assert.strictEqual(rects[0].height, 800);
}

// ---------------------------------------------------------------- feasibility

assert.ok(feasibleInCell({ width: 100, height: 50 }, { width: 200, height: 100 }));
assert.ok(!feasibleInCell({ width: 300, height: 50 }, { width: 200, height: 100 }));
assert.ok(!feasibleInCell({ width: 100, height: 150 }, { width: 200, height: 100 }));

// ---------------------------------------------------------------- the session

{
    const s = createSession();
    assert.strictEqual(s.active, false);
    assert.strictEqual(s.generation, 0);
    assert.strictEqual(s.master, null);
    assert.strictEqual(s.stack.length, 0);
    assert.strictEqual(s.activity, "", "the session records its activity");
}

assert.ok(eligibleForMaster(windowWith()));
assert.ok(!eligibleForMaster(windowWith({ fullScreen: true })), "fullscreen refused");
assert.ok(!eligibleForMaster(windowWith({ tile: { some: "tile" } })), "tiled refused");
assert.ok(!eligibleForMaster(windowWith({ resizeable: false })), "not resizable refused");

// ---------------------------------------------------------------- the candidates

{
    const master = windowWith({});
    const same = windowWith({});
    const otherDesktop = windowWith({ desktops: ["2"] });
    const allDesktops = windowWith({ onAllDesktops: true });
    const otherActivity = windowWith({ activities: ["act-b"] });
    const thisActivity = windowWith({ activities: ["act-a"] });
    const candidates = stackCandidates([master, same, otherDesktop, allDesktops,
                                        otherActivity, thisActivity], master, "1", "act-a");
    assert.ok(candidates.indexOf(same) >= 0, "the same desktop and activity");
    assert.ok(candidates.indexOf(thisActivity) >= 0, "the window's own activity");
    assert.ok(candidates.indexOf(otherDesktop) < 0, "another desktop is not a candidate");
    assert.ok(candidates.indexOf(allDesktops) < 0, "an all-desktops window is not a candidate");
    assert.ok(candidates.indexOf(otherActivity) < 0,
        "a window of another activity is not on this workspace's view");
    assert.strictEqual(candidates.length, 2);
}

{
    // An empty activity (no activity constraint recorded) takes every desktop match.
    const w = windowWith({ activities: ["act-z"] });
    const candidates = stackCandidates([w], null, "1", "");
    assert.strictEqual(candidates.length, 1);
}

// ---------------------------------------------------------------- the layout stack

{
    const candidates = [
        windowWith({ minSize: { width: 100, height: 50 } }),
        windowWith({ minSize: { width: 5000, height: 50 } }),  // too wide
        windowWith({ minSize: { width: 100, height: 50 } }),
    ];
    const area = rect(0, 0, 1000, 800);
    const result = layoutStack(candidates, area, 500, 8);
    assert.strictEqual(result.placed.length, 2, "two feasible");
    assert.strictEqual(result.floated.length, 1, "one floated");
    // The floated window is reported so the caller can unmanage it.
    assert.strictEqual(result.floated[0], candidates[1]);
    // The placed cells fill the column between just the feasible two.
    assert.strictEqual(result.placed[0].rect.height + result.placed[1].rect.height + 8, 800,
        "two cells + gap = area height");
}

// Feasibility is against the cells as they would be for the set being placed: the worst fit
// goes first and the rest are re-tried in the larger cells. A 300 px column with minimum
// heights 100, 100 and 200 has no three-way cells (92-96 px each), but removing the 200 px
// window gives the two that fit ~146 px cells: they place, and only the tall one floats -
// where a single pass against the three-way cells would float all three.
{
    const tall = windowWith({ internalId: "tall", minSize: { width: 1, height: 200 } });
    const two = [
        windowWith({ internalId: "a", minSize: { width: 1, height: 100 } }),
        windowWith({ internalId: "b", minSize: { width: 1, height: 100 } }),
    ];
    const area = rect(0, 0, 1000, 300);
    const result = layoutStack([two[0], tall, two[1]], area, 500, 8);
    assert.strictEqual(result.placed.length, 2, "the two that fit place");
    assert.strictEqual(result.floated.length, 1, "only the tall window floats");
    assert.strictEqual(result.floated[0], tall);
    assert.ok(result.placed[0].rect.height >= 100 && result.placed[1].rect.height >= 100,
        "in cells enlarged by the removal");
    // A window too wide for the column can never fit at any count: it floats first.
    const wide = windowWith({ internalId: "wide", minSize: { width: 900, height: 50 } });
    const r2 = layoutStack([wide, two[0]], area, 500, 8);
    assert.strictEqual(r2.placed.length, 1, "the other one still places");
    assert.strictEqual(r2.floated[0], wide, "the hopeless one floats");
}

// ---------------------------------------------------------------- the focus cycle

assert.deepStrictEqual(focusOrder({ master: "M", stack: ["S1", "S2"] }), ["M", "S1", "S2"]);
{
    const session = { master: "M", stack: ["S1", "S2"] };
    assert.strictEqual(nextInCycle(session, "M"), "S1");
    assert.strictEqual(nextInCycle(session, "S1"), "S2");
    assert.strictEqual(nextInCycle(session, "S2"), "M", "wraps to master");
    assert.strictEqual(previousInCycle(session, "M"), "S2", "wraps to last");
    assert.strictEqual(previousInCycle(session, "S1"), "M");
}

// ---------------------------------------------------------------- the untoggle

{
    const floats = saveFloats([
        { internalId: "a", frameGeometry: rect(10, 20, 100, 50) },
        { internalId: "b", frameGeometry: rect(30, 40, 200, 100) },
    ]);
    assert.strictEqual(floats.a.x, 10);
    assert.strictEqual(floats.a.width, 100);
    assert.strictEqual(floats.b.y, 40);
}

// ---------------------------------------------------------------- the membership decisions

// The workspace filter: one place decides what "on this session's workspace" means for the
// candidates, the managed windows and the leavers (a member that moves away is nobody's).
{
    const on = (desktops, activities, output) => ({ onAllDesktops: false, desktops: desktops, activities: activities, output: output });
    assert.ok(onWorkspace(on(["2"], []), "2", ""), "the session's desktop");
    assert.ok(!onWorkspace(on(["2"], []), "3", ""), "another desktop");
    assert.ok(onWorkspace(on(["2"], []), 2, ""), "a desktop given as a number still matches its string form");
    assert.ok(onWorkspace(on(["2"], []), "2", "a"), "an empty activity list is on every activity");
    assert.ok(onWorkspace(on(["2"], ["a"]), "2", "a"), "the session's activity");
    assert.ok(!onWorkspace(on(["2"], ["a"]), "2", "b"), "another activity");
    assert.ok(!onWorkspace({ onAllDesktops: true, desktops: [], activities: [] }, "2", ""), "all desktops is no single desktop");
    assert.ok(onWorkspace(on(["2"], ["a"]), "2", ""), "a window of every activity is on the session's");
    // VirtualDesktop objects, not strings: KWin hands the scripting API wrappers, and two
    // wrappers of one desktop must compare as one desktop (identity or their id), or tiling
    // on one desktop pulls another one's windows in
    const desk1a = { id: "d-1" };
    const desk1b = { id: "d-1" };
    const desk2 = { id: "d-2" };
    assert.ok(desktopMatches(desk1a, desk1a), "the same wrapper");
    assert.ok(desktopMatches(desk1a, desk1b), "two wrappers of one desktop, by id");
    assert.ok(!desktopMatches(desk1a, desk2), "another desktop's wrapper");
    assert.ok(onWorkspace(on([desk1b], []), desk1a, ""), "the workspace rule reads the wrappers");
    assert.ok(!onWorkspace(on([desk2], []), desk1a, ""), "another desktop's window is not on the session's");
    // the session's output scopes the workspace: the session tiles its own screen
    const outA = { name: "eDP" };
    assert.ok(onWorkspace(on(["2"], [], outA), "2", "", outA), "the session's output");
    assert.ok(!onWorkspace(on(["2"], [], outA), "2", "", { name: "HDMI" }), "another output's window");
    assert.ok(onWorkspace(on(["2"], [], outA), "2", ""), "no output given: every screen's windows");
}

// The stack candidates: stacking order TOP FIRST (KWin's stackingOrder lists the bottom-most
// first, and the stack's first cell and the focus cycle are the top-most window's), this
// output only - a same-desktop window on another screen is not this session's to place.
{
    const out = { name: "eDP" };
    const win = (id, over) => Object.assign({ internalId: id, normalWindow: true, transient: false, modal: false,
        minimized: false, maximizeMode: 0, moveable: true, resizeable: true, onAllDesktops: false,
        desktops: ["2"], activities: [], output: out }, over);
    const master = win("M");
    const top = win("top");
    const bottom = win("bottom");
    const otherScreen = win("hdmi", { output: { name: "HDMI" } });
    const thisScreen = win("edp");
    const c = stackCandidates([bottom, otherScreen, master, top, thisScreen], master, "2", "", out);
    assert.deepStrictEqual(c.map(w => w.internalId), ["edp", "top", "bottom"],
        "top first, this output only: not the master, not the other screen's, down to the bottom-most");
    assert.deepStrictEqual(stackCandidates([bottom, top], master, "2", "").map(w => w.internalId),
        ["top", "bottom"], "without an output, every screen's windows");
}

// The dormant candidates: this workspace's minimized windows at session start. They are not
// stack candidates (they are out of the view), but each rejoins the layout when it is restored
// during the session - so its float is saved and it is watched from the start, not first when
// a restore finds no listener (windowAdded does not fire for it: it was there all along).
{
    const win = (over) => Object.assign({ internalId: "x", normalWindow: true, transient: false, modal: false,
        minimized: false, maximizeMode: 0, moveable: true, resizeable: true, onAllDesktops: false,
        desktops: ["2"], activities: [] }, over);
    const minimized = win({ internalId: "m1", minimized: true, caption: "m1" });
    const otherDesk = win({ internalId: "m2", minimized: true, desktops: ["3"] });
    const visible = win({ internalId: "v1" });
    const master = win({ internalId: "M" });
    const dormant = dormantCandidates([minimized, otherDesk, visible, master], master, "2", "");
    assert.deepStrictEqual(dormant.map(w => w.internalId), ["m1"],
        "this workspace's minimized windows only: not the visible ones, not the master, not another desktop's");
    // a full-screen or manually tiled window keeps that state through a restore: the layout
    // must never overwrite it
    const fullscreen = win({ internalId: "fs", minimized: true, fullScreen: true });
    const tiled = win({ internalId: "tiled", minimized: true, tile: {} });
    assert.deepStrictEqual(dormantCandidates([fullscreen, tiled, minimized], master, "2", "").map(w => w.internalId),
        ["m1"], "full-screen and manually tiled minimized windows are strangers");
}

// A window that arrives already minimized while the session is live is the same member-to-be
// the toggle-on scan watches: for it too, a later restore emits no windowAdded (it was there
// all along), so the live add path must recognize it by the same rule and watch it on arrival
// - or its restore floats over the managed column with no relayout ever coming for it.
{
    assert.ok(eligibleDormant(windowWith({ minimized: true })),
        "a minimized normal window is a member-to-be");
    assert.ok(!eligibleDormant(windowWith({})),
        "a visible window is a stack candidate, not a dormant one");
    assert.ok(!eligibleDormant(windowWith({ minimized: true, fullScreen: true })),
        "full-screen keeps its state through a restore: a relayout must never overwrite it");
    assert.ok(!eligibleDormant(windowWith({ minimized: true, tile: {} })),
        "a manual tile keeps its state through a restore too");
    assert.ok(!eligibleDormant(windowWith({ minimized: true, transient: true })),
        "a transient is a stranger");
    assert.ok(!eligibleDormant(windowWith({ minimized: true, resizeable: false })),
        "not resizable: no cell could hold it");
    assert.ok(!eligibleDormant(windowWith({ minimized: true, deleted: true })),
        "a deleted window is not admitted");
    // the toggle-on scan and the live add read one rule: with the workspace matched, the
    // scan admits a window exactly when the predicate says member-to-be (the workspace
    // filter itself is the scan's own, on top of the shared rule)
    const ref = (over) => windowWith(Object.assign({ desktops: ["2"] }, over));
    const refs = [ref({ internalId: "r1", minimized: true }),
                  ref({ internalId: "r2", minimized: true, desktops: ["3"] }),
                  ref({ internalId: "r3" })];
    for (const w of refs) {
        assert.strictEqual(eligibleDormant(w),
            dormantCandidates([w], null, w.desktops[0], "").length === 1,
            "dormantCandidates and eligibleDormant agree on " + w.internalId);
    }
}

// What a reflow takes away: a member the layout had placed gets its saved float back before it
// is detached, because it sits at a cell no untoggle can undo; one the layout never placed
// already sits at its own float, and restoring it to itself is a no-op either way.
{
    const placed = { internalId: "p" };
    const neverPlaced = { internalId: "n" };
    const floats = { p: rect(10, 20, 300, 200), n: rect(40, 60, 320, 240) };
    const cells = { p: rect(600, 0, 400, 300) };
    const restores = floatRestores([placed, neverPlaced], floats, cells);
    assert.deepStrictEqual(restores, [{ window: placed, rect: rect(10, 20, 300, 200) }],
        "the placed member's float, and nothing for the never-placed one");
    assert.deepStrictEqual(floatRestores([neverPlaced], floats, {}), [],
        "no cell, no restore: the window keeps its own geometry");
    assert.deepStrictEqual(floatRestores([placed], {}, cells), [],
        "no float saved (a window that joined and was never placed is not drifted either)");
}

// Whether a frame is the tiler's own placement: a member's geometry change that lands exactly
// on its assigned cell is the tiler's own write arriving (the synchronous one or the client's
// late commit of it); anything else is the user's hand.
assert.ok(isOwnCell(rect(600, 0, 400, 300), rect(600, 0, 400, 300)), "the assigned cell");
assert.ok(!isOwnCell(rect(600, 0, 400, 300), rect(601, 0, 400, 300)), "a moved frame");
assert.ok(!isOwnCell(rect(600, 0, 400, 300), rect(600, 0, 399, 300)), "a resized frame");
assert.ok(!isOwnCell(null, rect(600, 0, 400, 300)), "no cell assigned");

console.log("tiling.test.js: ok");
