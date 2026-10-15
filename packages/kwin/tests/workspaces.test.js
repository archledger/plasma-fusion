// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the dynamic workspaces script's contents/ui/Workspaces.js (which desktops come and go,
// when, and what they are called).
// Run: node packages/kwin/tests/workspaces.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-workspaces", "contents", "ui", "Workspaces.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { candidate, counts, occupancy, keepCount, plan, canAdd, decide, numberOf, nameFor, renames } = globalThis;

// A counted window on the given desktops; overrides switch single properties.
const win = (desktops, overrides) => ({ managed: true, deleted: false, allDesktops: false, skipPager: false, special: false, popup: false, desktops, ...overrides });
const ids = (n) => Array.from({ length: n }, (_, i) => "d" + i);
// plan() over occupancy given as a string: "x" occupied, "." empty.
const planOf = (pattern, current, keepFirst) => {
    const desktops = ids(pattern.length);
    return plan(desktops, pattern.split("").map(c => c === "x"), current, keepFirst || 0);
};

// ---- which windows hold their desktops
assert.ok(counts(win(["d0"])));
assert.ok(counts(win(["d0"], { minimized: true })), "a minimized window still holds its desktop");
assert.ok(!counts(win([], { allDesktops: true })), "on every desktop (KWin's own internal windows are)");
assert.ok(!counts(win(["d0"], { skipPager: true })), "kept out of the pager");
assert.ok(!counts(win(["d0"], { special: true })), "a panel, notification, OSD, applet popup or tooltip");
assert.ok(!counts(win(["d0"], { popup: true })), "a popup menu");
assert.ok(!counts(win(["d0"], { deleted: true })), "a window that is closing");
assert.ok(!counts(win(["d0"], { managed: false })), "an unmanaged (override-redirect) window");
assert.ok(!counts(null));
assert.ok(candidate(win([], { allDesktops: true, skipPager: true, deleted: true })), "the kind of window is what is watched: its desktops and pager flag can change");
assert.ok(!candidate(win(["d0"], { special: true })) && !candidate(win(["d0"], { popup: true })) && !candidate(win(["d0"], { managed: false })));

// ---- KeepFirst as a count
assert.strictEqual(keepCount(3), 3);
assert.strictEqual(keepCount("4"), 4, "KWin.readConfig may answer a string");
assert.strictEqual(keepCount(2.7), 2);
assert.strictEqual(keepCount(99), 24, "KWin's ceiling less the empty one at the end");
assert.strictEqual(keepCount(-1), 0);
assert.strictEqual(keepCount("nonsense"), 0);
assert.strictEqual(keepCount(undefined), 0);

// ---- occupancy: one boolean per desktop, in KWin's order
assert.deepStrictEqual(occupancy(ids(4), [win(["d1"]), win(["d3"], { skipPager: true })]), [false, true, false, false]);
assert.deepStrictEqual(occupancy(ids(3), [win(["d0", "d2"])]), [true, false, true], "a window on two desktops holds both");
assert.deepStrictEqual(occupancy(ids(2), [win(["gone"])]), [false, false], "a desktop id KWin no longer has is ignored");
assert.deepStrictEqual(occupancy(ids(2), []), [false, false]);
assert.deepStrictEqual(occupancy(ids(2), [win(undefined)]), [false, false], "a window without a desktop list");

// ---- plan: one empty desktop at the end, other empty ones go (GNOME's WorkspaceTracker)
assert.deepStrictEqual(planOf("x", ["d0"]), { append: true, remove: [] }, "the last desktop filled: one is added");
assert.deepStrictEqual(planOf("x.", ["d0"]), { append: false, remove: [] }, "steady state");
assert.deepStrictEqual(planOf("x..", ["d0"]), { append: false, remove: ["d2"] }, "a second empty one at the end goes");
assert.deepStrictEqual(planOf("x.x.", ["d0"]), { append: false, remove: ["d1"] }, "an empty one in the middle goes");
assert.deepStrictEqual(planOf("x.x.", ["d1"]), { append: false, remove: [] }, "...but not while it is shown");
assert.deepStrictEqual(planOf(".x.", ["d1"]), { append: false, remove: ["d0"] }, "the first one goes too when empty (KeepFirst 0)");
assert.deepStrictEqual(planOf(".x.", ["d1"], 1), { append: false, remove: [] }, "KeepFirst 1 keeps it");
assert.deepStrictEqual(planOf("x....", ["d0"], 3), { append: false, remove: ["d4", "d3"] }, "KeepFirst 3: the first three stay");
assert.deepStrictEqual(planOf("x...", ["d0"]).remove, ["d3", "d2"], "removals come last first");
assert.deepStrictEqual(planOf("...", ["d2"]), { append: false, remove: ["d1"] }, "no windows: the first desktop and the shown one stay");
assert.deepStrictEqual(planOf("...", ["d0"]), { append: false, remove: ["d2", "d1"] }, "no windows on the first desktop: it alone stays");
assert.deepStrictEqual(planOf("x.x", ["d0"]), { append: true, remove: ["d1"] }, "both at once");
assert.deepStrictEqual(planOf("x..", ["d2"]), { append: false, remove: [] }, "shown at the end: the two empty ones stay until it is left");
assert.deepStrictEqual(planOf("x.x..", ["d0", "d3"]), { append: false, remove: ["d4", "d1"] }, "each screen's shown desktop stays (per-screen desktops)");
assert.deepStrictEqual(planOf("x".repeat(25), ["d0"]), { append: false, remove: [] }, "KWin's ceiling: no 26th desktop");
assert.deepStrictEqual(planOf("x".repeat(24), ["d0"]), { append: true, remove: [] }, "the 25th can still come");
assert.deepStrictEqual(planOf("x.x" + "x".repeat(22), ["d0"]), { append: true, remove: ["d1"] }, "at the ceiling, a removal in the same pass makes room");
assert.ok(canAdd(24) && !canAdd(25), "KWin takes 25 desktops");
assert.deepStrictEqual(planOf("x....", ["d0"], 99).remove, [], "KeepFirst is capped at 24");
assert.deepStrictEqual(planOf("x....", ["d0"], -3).remove, ["d4", "d3", "d2"], "a negative KeepFirst is 0");
assert.deepStrictEqual(planOf("x....", ["d0"], "3").remove, ["d4", "d3"], "KWin.readConfig may answer a string");
assert.deepStrictEqual(planOf("x....", ["d0"], "nonsense").remove, ["d4", "d3", "d2"], "an unreadable KeepFirst is 0");

// ---- the rules hold for every state (random states, a fixed seed)
let seed = 20261015;
const rand = (n) => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed % n; };
for (let round = 0; round < 5000; ++round) {
    const n = 1 + rand(25);
    const desktops = ids(n);
    const occupied = desktops.map(() => rand(3) === 0);
    const current = [desktops[rand(n)]];
    if (rand(4) === 0) {
        current.push(desktops[rand(n)]);
    }
    const keepFirst = rand(6);
    const p = plan(desktops, occupied, current, keepFirst);
    const removed = new Set(p.remove);
    const lastOccupied = occupied.lastIndexOf(true);
    desktops.forEach((id, i) => {
        if (!removed.has(id)) {
            return;
        }
        assert.ok(!occupied[i], `round ${round}: an occupied desktop is never removed`);
        assert.ok(current.indexOf(id) < 0, `round ${round}: a shown desktop is never removed`);
        assert.ok(i >= Math.min(keepFirst, 24), `round ${round}: KeepFirst desktops stay`);
        assert.notStrictEqual(i, lastOccupied + 1, `round ${round}: the empty one after the last occupied stays`);
    });
    assert.ok(removed.size < n, `round ${round}: a desktop always stays`);
    assert.strictEqual(p.append, occupied[n - 1] && n - removed.size < 25, `round ${round}: added exactly when the last one is occupied and there is room`);
    // A second pass over the result changes nothing: the rules are a fixed point.
    const after = desktops.filter(id => !removed.has(id));
    const afterOccupied = after.map(id => occupied[desktops.indexOf(id)]);
    if (p.append) {
        after.push("new");
        afterOccupied.push(false);
    }
    const again = plan(after, afterOccupied, current, keepFirst);
    assert.deepStrictEqual(again, { append: false, remove: [] }, `round ${round}: a second pass is a no-op`);
}

// ---- timing: nothing during a desktop switch, removals after a close and after the start
const never = -Infinity;
const at = (now, lastSwitch, lastClose, started) => ({ now, lastSwitch, lastClose, started });
const both = { append: true, remove: ["d3"] };
assert.deepStrictEqual(decide(both, at(20000, never, never, 0)), { append: true, remove: ["d3"], retryIn: -1 }, "a quiet desktop: everything now");
assert.deepStrictEqual(decide(both, at(20000, 19600, never, 0)), { append: false, remove: [], retryIn: 600 }, "a switch 400 ms ago: wait out the slide");
assert.deepStrictEqual(decide(both, at(20000, 19000, never, 0)), { append: true, remove: ["d3"], retryIn: -1 }, "exactly a second after the switch");
assert.deepStrictEqual(decide(both, at(20000, never, 19800, 0)), { append: true, remove: [], retryIn: 800 }, "a window just closed: adds go on, removals wait");
assert.deepStrictEqual(decide(both, at(4000, never, never, 0)), { append: true, remove: [], retryIn: 6000 }, "just started: no removal for ten seconds");
assert.deepStrictEqual(decide(both, at(10000, never, never, 0)), { append: true, remove: ["d3"], retryIn: -1 }, "ten seconds after the start");
assert.deepStrictEqual(decide({ append: false, remove: [] }, at(5, 5, 5, 5)), { append: false, remove: [], retryIn: -1 }, "nothing wanted, nothing to wait for");
assert.deepStrictEqual(decide({ append: false, remove: ["d1"] }, at(20000, 19900, 19950, 0)), { append: false, remove: [], retryIn: 950 }, "the later gate decides");
assert.strictEqual(decide({ append: true, remove: [] }, at(20000, 19000.5, never, 0)).retryIn, 1, "whole milliseconds, never 0 while waiting");
const copy = decide(both, at(20000, never, never, 0)).remove;
copy.push("x");
assert.deepStrictEqual(both.remove, ["d3"], "the plan is not changed through the answer");

// ---- names: the script's own numbered names follow their positions; every other name stays
const numbered = Array.from({ length: 25 }, (_, i) => `Workspace ${i + 1}`);
assert.strictEqual(numberOf("Workspace 3", numbered), 3);
assert.strictEqual(numberOf("Work", numbered), 0);
assert.strictEqual(numberOf("Desktop 3", numbered), 0, "KWin's default names are not the script's");
assert.strictEqual(numberOf("Workspace 26", numbered), 0, "beyond KWin's ceiling");
assert.strictEqual(nameFor(2, numbered), "Workspace 3");
assert.strictEqual(nameFor(25, numbered), "");
const named = (...names) => names.map((name, i) => ({ id: "d" + i, name }));
assert.deepStrictEqual(renames(named("Work", "Workspace 3", "Workspace 4"), numbered),
    [{ id: "d1", name: "Workspace 2" }, { id: "d2", name: "Workspace 3" }], "after the second desktop went");
assert.deepStrictEqual(renames(named("Work", "Design", "Workspace 3"), numbered), [], "in step: nothing");
assert.deepStrictEqual(renames(named("Workspace 2", "Desktop 5", "Notes"), numbered), [{ id: "d0", name: "Workspace 1" }], "only the script's own names move");
assert.deepStrictEqual(renames([], numbered), []);

console.log("workspaces.test.js: ok");
