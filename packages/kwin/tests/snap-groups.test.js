// SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
// SPDX-License-Identifier: GPL-2.0-or-later
//
// Tests of the snap script's contents/ui/Groups.js (snap groups and filling a layout's zones).
// Run: node packages/kwin/tests/snap-groups.test.js (80-kwin.sh runs it).
"use strict";
const fs = require("fs");
const path = require("path");
const assert = require("assert");
const vm = require("vm");
const { pathToFileURL } = require("url");

const file = path.join(__dirname, "..", "scripts", "plasmafusion-snap", "contents", "ui", "Groups.js");
vm.runInThisContext(fs.readFileSync(file, "utf8").replace(/^\.pragma library$/m, (l) => " ".repeat(l.length)), { filename: pathToFileURL(file).href });
const { groupOf, leave, join, partners, fillOrder, inZone } = globalThis;

// Windows are opaque objects compared by identity.
const a = { n: "a" };
const b = { n: "b" };
const c = { n: "c" };
const d = { n: "d" };
const names = (list) => list.map((w) => w.n);
const shape = (groups) => groups.map(names);

// ---- forming groups: the anchor and every window picked for its layout
let groups = join([], a, b);
assert.deepStrictEqual(shape(groups), [["a", "b"]], "a pair");
groups = join(groups, a, c);
groups = join(groups, a, d);
assert.deepStrictEqual(shape(groups), [["a", "b", "c", "d"]], "four quarters, one group");
assert.strictEqual(groupOf(groups, c), 0);
assert.strictEqual(groupOf(groups, { n: "x" }), -1, "a window outside every group");
assert.deepStrictEqual(names(partners(groups, b)), ["a", "c", "d"]);
assert.deepStrictEqual(partners(groups, { n: "x" }), [], "no group, no partners");
assert.strictEqual(join(groups, a, a), groups, "a window does not join itself");

// ---- a window is in one group at most: joining another arrangement moves it
const e = { n: "e" };
let two = join(join([], a, b), c, d);
assert.deepStrictEqual(shape(two), [["a", "b"], ["c", "d"]]);
two = join(two, e, b);
assert.deepStrictEqual(shape(two), [["c", "d"], ["e", "b"]], "b left a's group (which ended) for e's");

// ---- leaving: the group shrinks, and a group of one ends
groups = leave(groups, c);
assert.deepStrictEqual(shape(groups), [["a", "b", "d"]], "a member that left its zone");
groups = leave(groups, b);
groups = leave(groups, d);
assert.deepStrictEqual(groups, [], "the last partner of a group of two is alone: the group ended");
const before = join([], a, b);
const after = leave(before, c);
assert.notStrictEqual(after, before, "a new list every time (QML sees the assignment)");
assert.deepStrictEqual(shape(after), [["a", "b"]], "leaving without a group changes nothing");

// ---- the order the picker offers a layout's other zones
assert.deepStrictEqual(fillOrder(4, 0, []), [1, 2, 3], "quarters from the top-left");
assert.deepStrictEqual(fillOrder(4, 2, []), [3, 0, 1], "after the chosen zone, wrapping");
assert.deepStrictEqual(fillOrder(3, 1, [false, false, false]), [2, 0], "thirds from the middle");
assert.deepStrictEqual(fillOrder(4, 0, [false, true, false, false]), [2, 3], "a zone that holds a window is skipped");
assert.deepStrictEqual(fillOrder(2, 1, []), [0], "halves: the other half");
assert.deepStrictEqual(fillOrder(2, 0, [false, true]), [], "nothing left to fill");
assert.deepStrictEqual(fillOrder(1, 0, []), []);

// ---- a window in a plain-geometry zone (thirds)
const zone = { x: 0, y: 32, width: 476, height: 868 };
assert.ok(inZone({ x: 0, y: 32, width: 476, height: 868 }, zone), "exactly the zone");
assert.ok(inZone({ x: 2, y: 30, width: 468, height: 860 }, zone), "a terminal a few px smaller (cell rounding)");
assert.ok(!inZone({ x: 40, y: 32, width: 476, height: 868 }, zone), "moved away");
assert.ok(!inZone({ x: 0, y: 32, width: 900, height: 868 }, zone), "wider than its zone");
assert.ok(!inZone({ x: 0, y: 32, width: 200, height: 400 }, zone), "far smaller: not the zone's window any more");
assert.ok(inZone({ x: 6, y: 32, width: 476, height: 868 }, zone, 8), "a custom tolerance");

console.log("snap-groups.test.js: ok");
