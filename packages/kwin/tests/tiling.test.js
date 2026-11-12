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
        eligibleForMaster, stackCandidates, dormantCandidates, layoutStack, focusOrder, nextInCycle,
        previousInCycle, saveFloats, onWorkspace, floatRestores, isOwnCell } = globalThis;

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
    const on = (desktops, activities) => ({ onAllDesktops: false, desktops: desktops, activities: activities });
    assert.ok(onWorkspace(on(["2"], []), "2", ""), "the session's desktop");
    assert.ok(!onWorkspace(on(["2"], []), "3", ""), "another desktop");
    assert.ok(onWorkspace(on(["2"], []), 2, ""), "a desktop given as a number still matches its string form");
    assert.ok(onWorkspace(on(["2"], []), "2", "a"), "an empty activity list is on every activity");
    assert.ok(onWorkspace(on(["2"], ["a"]), "2", "a"), "the session's activity");
    assert.ok(!onWorkspace(on(["2"], ["a"]), "2", "b"), "another activity");
    assert.ok(!onWorkspace({ onAllDesktops: true, desktops: [], activities: [] }, "2", ""), "all desktops is no single desktop");
    assert.ok(onWorkspace(on(["2"], ["a"]), "2", ""), "a window of every activity is on the session's");
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
