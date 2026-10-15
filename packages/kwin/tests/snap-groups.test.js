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
const { groupOf, leave, join, partners, fillOrder, inZone, zoneOccupied, prune, joined, left, sameRect, sharedActivity, holds, fillValid } = globalThis;

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

// ---- membership and zones change together (no stale zone survives a transfer)
const key = (w) => w.n;
let s = joined({ groups: [], zones: {} }, a, b, "a@left", "b@right", key);
assert.deepStrictEqual(shape(s.groups), [["a", "b"]]);
assert.deepStrictEqual(s.zones, { a: "a@left", b: "b@right" });
s = joined(s, c, b, "c@q0", "b@q1", key);
assert.deepStrictEqual(shape(s.groups), [["c", "b"]], "b picked for c's arrangement: a's pair ended");
assert.deepStrictEqual(s.zones, { c: "c@q0", b: "b@q1" }, "a, left alone, is forgotten with its zone");
s = joined(s, a, d, "a@third0", "d@third1", key);
assert.strictEqual(s.zones.a, "a@third0", "a starts a new arrangement with the zone it holds now, never the stale one");
s = joined(s, a, e, "a@elsewhere", "e@third2", key);
assert.strictEqual(s.zones.a, "a@third0", "an anchor already in a group keeps the zone it was placed in");
assert.deepStrictEqual(shape(s.groups), [["c", "b"], ["a", "d", "e"]]);
s = left(s, d, key);
assert.deepStrictEqual(Object.keys(s.zones).sort(), ["a", "b", "c", "e"], "d's zone goes with it");
s = left(s, e, key);
assert.deepStrictEqual(Object.keys(s.zones).sort(), ["b", "c"], "a, left alone again, is forgotten");
assert.deepStrictEqual(prune([[a, b]], { a: 1, b: 2, x: 3 }, key), { a: 1, b: 2 }, "prune keeps group members only");

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
assert.ok(!inZone({ x: 0, y: 32, width: 300, height: 600 }, zone), "starting at the zone's corner, much smaller: not filling it");
assert.ok(!inZone({ x: 0, y: 32, width: 440, height: 868 }, zone), "36 px narrower: beyond rounding");
assert.ok(inZone({ x: 0, y: 32, width: 446, height: 840 }, zone), "within 32 px (two terminal cells or lines)");

// ---- occupancy of a plain-geometry zone: any window filling it, tiled or not
assert.ok(zoneOccupied(zone, [{ x: 600, y: 32, width: 400, height: 400 }, { x: 0, y: 32, width: 476, height: 868 }]), "a window in a matching custom tile counts");
assert.ok(!zoneOccupied(zone, []), "nothing there");
assert.ok(!zoneOccupied(zone, [{ x: 0, y: 32, width: 238, height: 434 }]), "a small window at its corner does not fill it");

// ---- asked at use: does a window still hold its zone, does a sequence still stand
const third = { x: 482, y: 34, width: 476, height: 866 };
const geoZone = { tile: null, rect: third, place: "eDP-1|1|*" };
const tileA = { n: "tileA" };
const quickZone = { tile: tileA, rect: null, place: "eDP-1|1|*" };
const snap = (o) => Object.assign({ tile: null, frame: third, place: "eDP-1|1|*", maximized: false, fullScreen: false, settled: true }, o);
assert.ok(holds(geoZone, snap({})), "in its third");
assert.ok(!holds(geoZone, snap({ frame: { x: 380, y: 220, width: 620, height: 420 } })), "moved out by an app or a script, settled");
assert.ok(holds(geoZone, snap({ frame: { x: 160, y: 110, width: 640, height: 420 }, settled: false })), "not settled yet: the old geometry may still show");
assert.ok(!holds(geoZone, snap({ tile: tileA })), "tiled since");
assert.ok(!holds(geoZone, snap({ place: "eDP-1|2|*" })), "another desktop");
assert.ok(!holds(geoZone, snap({ place: "eDP-1|1|act-b" })), "another activity");
assert.ok(!holds(geoZone, snap({ maximized: true })), "maximized");
assert.ok(holds(quickZone, snap({ tile: tileA, frame: { x: 0, y: 0, width: 1, height: 1 } })), "a quick tile is its tile, whatever the geometry");
assert.ok(!holds(quickZone, snap({ tile: { n: "tileB" } })), "another tile");
assert.ok(!holds(undefined, snap({})), "no zone");

const area = { x: 0, y: 34, width: 1440, height: 866 };
const rec = { zone: geoZone, desktop: "1", activity: "act-a", area: area, family: "columns" };
const now = (o) => Object.assign(snap({}), { desktop: "1", activity: "act-a", area: { x: 0, y: 34, width: 1440, height: 866 }, family: "columns" }, o);
assert.ok(fillValid(rec, now({})), "the sequence stands");
assert.ok(!fillValid(rec, now({ activity: "act-b" })), "another activity became current (a switch in the settle)");
assert.ok(!fillValid(rec, now({ desktop: "2" })), "another desktop became current");
assert.ok(!fillValid(rec, now({ family: "rows", area: { x: 0, y: 34, width: 900, height: 1406 } })), "a rotation: rows now");
assert.ok(!fillValid(rec, now({ area: { x: 0, y: 34, width: 1440, height: 836 } })), "the work area changed");
assert.ok(!fillValid(rec, now({ frame: { x: 300, y: 200, width: 700, height: 450 } })), "the first window moved by a script, settled");
assert.ok(!fillValid(rec, now({ place: "HDMI-1|1|*" })), "the first window on another screen");
assert.ok(sameRect(area, { x: 0, y: 34, width: 1440, height: 866 }) && !sameRect(area, null));

// ---- a window of another activity is not there to see; empty lists mean all activities
assert.ok(sharedActivity([], ["a"]) && sharedActivity(["a"], []), "on all activities");
assert.ok(sharedActivity(["a", "b"], ["b"]));
assert.ok(!sharedActivity(["a"], ["b"]), "only another activity");

console.log("snap-groups.test.js: ok");
