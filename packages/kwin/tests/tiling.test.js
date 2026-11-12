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
        eligibleForMaster, stackCandidates, layoutStack, focusOrder, nextInCycle,
        previousInCycle, saveFloats } = globalThis;

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

console.log("tiling.test.js: ok");
